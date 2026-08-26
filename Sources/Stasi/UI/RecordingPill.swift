import AppKit

// MARK: - Aufnahme-Pill (AppKit, unten mittig)
// ✕ · roter Pulsdot · 14 Pegelbalken · Timer/Modellstatus · ✓
// Bei Live-Text wächst sie auf 320 px und zeigt die letzten zwei Zeilen.
// Bewusst KOMPLETT in AppKit: SwiftUI-Interaktion in manuell verwalteten
// NSPanels crasht unter macOS 26.6 (Button-Gesture/Executor-Bug).

// MARK: - Panel

final class PillPanel: NSPanel {
    // KEIN canBecomeKey-Override! Borderless-Panels sind default nicht
    // key-fähig – genau richtig (Panel darf dem Hauptfenster nie den Fokus
    // klauen). Und: Ein Swift-Override wird von AppKit über einen @objc-Thunk
    // mit MainActor-Executor-Check aufgerufen – das crashte unter macOS 26.6.

    init(content: NSView, size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = true
        worksWhenModal = true
        becomesKeyOnlyIfNeeded = true
        contentView = content
        positionBottomCenter()
    }

    func positionBottomCenter() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: screen.midX - frame.width / 2,
                               y: screen.minY + 28))
    }

    /// Breite wechseln (✕/✓ ein-/ausblenden) und horizontal neu zentrieren.
    func resize(to size: NSSize) {
        setContentSize(size)
        if let screen = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: screen.midX - size.width / 2,
                                   y: frame.minY))
        }
    }
}

// MARK: - Controller

@MainActor
final class PillController {
    static let shared = PillController()
    var app: AppState?
    private var pillPanel: PillPanel?
    private var pillView: RecordingPillView?
    private var toastPanel: PillPanel?
    private var toastTimer: Timer?
    private var statusPanel: PillPanel?

    private var lastPhase: AppState.Phase = .idle
    private var lastSource: RecordingSource = .pushToTalk
    private var lastHadPartialText = false
    private var lastModelReady = true
    private var recordingPillVisible = false

    func sync(phase: AppState.Phase, partialText: String, elapsed: TimeInterval,
              level: Double, source: RecordingSource, modelReady: Bool) {
        guard let app else { return }
        let phaseChanged = phase != lastPhase
        let entered = phase == .recording && lastPhase != .recording
        let exited = phase != .recording && lastPhase == .recording
        let sourceChanged = phase == .recording && lastSource != source
        let hasPartialText = !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let layoutChanged = hasPartialText != lastHadPartialText || modelReady != lastModelReady
        lastPhase = phase
        lastSource = source
        lastHadPartialText = hasPartialText
        lastModelReady = modelReady

        if phaseChanged {
            switch phase {
            case .transcribing: showStatus(Copy.pillTranscribing)
            case .polishing: showStatus(Copy.pillPolishing)
            case .injecting: showStatus(Copy.pillInjecting)
            case .idle, .recording: hideStatus()
            }
        }

        switch phase {
        case .recording:
            guard PillChrome.shouldShowRecording(source: source, elapsed: elapsed) else {
                return
            }
            let view = ensurePill(app: app)
            view.applyChrome(for: source)
            view.update(level: level, secs: elapsed,
                        partialText: partialText, modelReady: modelReady)
            let newlyVisible = !recordingPillVisible
            if newlyVisible || entered || sourceChanged || layoutChanged {
                if newlyVisible {
                    recordingPillVisible = true
                    view.resetWaveform()
                    pillPanel?.positionBottomCenter()
                    startAnimation()
                }
                pillPanel?.resize(to: NSSize(
                    width: PillChrome.pillWidth(for: source,
                                                hasPartialText: hasPartialText,
                                                modelReady: modelReady),
                    height: PillChrome.pillHeight(hasPartialText: hasPartialText)
                ))
                pillPanel?.orderFront(nil)
            }
        default:
            if exited || recordingPillVisible {
                pillPanel?.orderOut(nil)
                stopAnimation()
                recordingPillVisible = false
            }
        }
    }

    /// Generischer Phasenstatus. Block 3A ergänzt im Phase-Switch nur „Poliere…".
    func showStatus(_ text: String) {
        let view = StatusViewNS(text: text)
        if statusPanel == nil {
            statusPanel = PillPanel(content: view, size: NSSize(width: 190, height: 36))
        } else {
            statusPanel?.contentView = view
        }
        statusPanel?.resize(to: NSSize(width: 190, height: 36))
        statusPanel?.positionBottomCenter()
        statusPanel?.orderFront(nil)
    }

    func hideStatus() {
        statusPanel?.orderOut(nil)
    }

    /// Toast-Pill nach Abschluss/Verwerfen (v3: 36 px hoch)
    func showToast(_ message: String, success: Bool) {
        let view = ToastViewNS(text: message, success: success)
        if toastPanel == nil {
            toastPanel = PillPanel(content: view, size: NSSize(width: 260, height: 36))
        } else {
            toastPanel?.contentView = view
        }
        toastPanel?.resize(to: NSSize(width: 260, height: 36))
        toastPanel?.positionBottomCenter()
        toastPanel?.orderFront(nil)

        toastTimer?.invalidate()
        let timer = Timer(timeInterval: 2.6,
                          target: self,
                          selector: #selector(toastTimerFired(_:)),
                          userInfo: nil,
                          repeats: false)
        toastTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func toastTimerFired(_ timer: Timer) {
        toastPanel?.orderOut(nil)
        if toastTimer === timer { toastTimer = nil }
    }

    // MARK: Intern

    private func ensurePill(app: AppState) -> RecordingPillView {
        if let view = pillView { return view }
        let view = RecordingPillView(
            onDiscard: { [weak app] in app?.enqueue(.discard) },
            onCommit: { [weak app] in app?.enqueue(.commit) }
        )
        pillView = view
        pillPanel = PillPanel(content: view, size: NSSize(width: 140, height: 24))
        return view
    }

    private var animationTimer: Timer?

    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / 30,
                          target: self,
                          selector: #selector(animationTimerFired(_:)),
                          userInfo: nil,
                          repeats: true)
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func animationTimerFired(_ timer: Timer) {
        pillView?.tick()
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Pill-View (AppKit, v2 Mini-Format)

@MainActor
final class RecordingPillView: NSView {
    nonisolated(unsafe) var onDiscard: (() -> Void)?
    nonisolated(unsafe) var onCommit: (() -> Void)?

    private let discardButton = PillCircleButton(symbol: "xmark", dark: false)
    private let commitButton = PillCircleButton(symbol: "checkmark", dark: true)
    private let dotView = NSView()
    private let timerLabel = NSTextField(labelWithString: "0:00")
    private let transcriptLabel = NSTextField(labelWithString: "")
    private let waveformView = PillWaveformView()
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var t: Double = 0
    private var currentLevel: Double = 0

    init(onDiscard: @escaping () -> Void, onCommit: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        self.onDiscard = onDiscard
        self.onCommit = onCommit

        wantsLayer = true
        applyBackground()

        discardButton.target = self
        discardButton.action = #selector(discardTapped)
        discardButton.setAccessibilityLabel("Aufnahme verwerfen")
        commitButton.target = self
        commitButton.action = #selector(commitTapped)
        commitButton.setAccessibilityLabel("Aufnahme abschließen")

        // Roter Pulsdot
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor(red: 1.0, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1).cgColor
        dotView.layer?.cornerRadius = 2.5
        dotView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 5),
            dotView.heightAnchor.constraint(equalToConstant: 5),
        ])
        if !reduceMotion {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.35
            pulse.duration = 1.1
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            dotView.layer?.add(pulse, forKey: "pulse")
        }

        // Timer
        timerLabel.font = NSFont(name: "Geist Mono", size: 9) ?? .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        timerLabel.textColor = NSColor(white: 1, alpha: 0.65)
        timerLabel.isBezeled = false
        timerLabel.drawsBackground = false
        timerLabel.alignment = .right

        transcriptLabel.font = NSFont(name: "Geist", size: 11)
            ?? .systemFont(ofSize: 11, weight: .regular)
        transcriptLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        transcriptLabel.isBezeled = false
        transcriptLabel.drawsBackground = false
        transcriptLabel.maximumNumberOfLines = 2
        transcriptLabel.lineBreakMode = .byTruncatingHead
        transcriptLabel.cell?.truncatesLastVisibleLine = true
        transcriptLabel.alignment = .left
        transcriptLabel.isHidden = true
        transcriptLabel.translatesAutoresizingMaskIntoConstraints = false

        // Mini-Waveform: eine Zeichenfläche statt 14 Layout-Constraints.
        // Der 30-Hz-Tick invalidiert nur den kleinen Zeichenbereich.
        waveformView.translatesAutoresizingMaskIntoConstraints = false

        let main = NSStackView(views: [discardButton, dotView, waveformView, timerLabel, commitButton])
        main.orientation = .horizontal
        main.spacing = 5
        main.alignment = .centerY
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)
        addSubview(transcriptLabel)

        widthConstraint = widthAnchor.constraint(equalToConstant: 140)
        heightConstraint = heightAnchor.constraint(equalToConstant: 24)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            main.centerXAnchor.constraint(equalTo: centerXAnchor),
            main.topAnchor.constraint(equalTo: topAnchor, constant: 2.5),
            waveformView.widthAnchor.constraint(equalToConstant: 54),
            waveformView.heightAnchor.constraint(equalToConstant: MicLevelBars.maxHeight),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            transcriptLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            transcriptLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            transcriptLabel.topAnchor.constraint(equalTo: main.bottomAnchor, constant: 2),
            transcriptLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -3),
        ])
        // Leichtes Schweben (translateY −3px, 3 s) – reine Core Animation,
        // kein Timer, kein Executor-Kontakt.
        if !reduceMotion {
            let float = CABasicAnimation(keyPath: "transform.translation.y")
            float.fromValue = 0
            float.toValue = -3
            float.duration = 3
            float.autoreverses = true
            float.repeatCount = .infinity
            layer?.add(float, forKey: "float")
        }
    }

    /// ✕ und ✓ sind in beiden Aufnahmemodi sichtbar.
    func applyChrome(for source: RecordingSource) {
        let show = PillChrome.showsButtons(for: source)
        discardButton.isHidden = !show
        commitButton.isHidden = !show
        applyBackground()
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// Aufnahme bleibt unabhängig vom gewählten Akzent auf dem dunklen Ink-Token.
    private func applyBackground() {
        let ink = NSColor(Theme.Palette.ink)
        layer?.backgroundColor = ink.cgColor
        layer?.cornerRadius = 12
        commitButton.contentTintColor = ink
    }

    @objc nonisolated private func discardTapped() {
        onDiscard?()
    }

    @objc nonisolated private func commitTapped() {
        onCommit?()
    }

    func update(level: Double, secs: TimeInterval, partialText: String, modelReady: Bool) {
        currentLevel = level
        let total = Int(secs)
        timerLabel.stringValue = modelReady
            ? String(format: "%d:%02d", total / 60, total % 60)
            : Copy.pillModelLoading
        let trimmed = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPartialText = !trimmed.isEmpty
        if transcriptLabel.stringValue != trimmed {
            transcriptLabel.stringValue = trimmed
        }
        transcriptLabel.isHidden = !hasPartialText
        widthConstraint.constant = PillChrome.pillWidth(
            for: .pushToTalk,
            hasPartialText: hasPartialText,
            modelReady: modelReady
        )
        heightConstraint.constant = PillChrome.pillHeight(hasPartialText: hasPartialText)
    }

    /// 30 Hz: Waveform-Ballistik. Stille = flach (4 px, statisch),
    /// Lautstärke spreizt die Balken symmetrisch bis 20 px – man sieht klar,
    /// dass wirklich aufgenommen wird.
    func tick() {
        t += 1.0 / 30.0
        waveformView.update(level: currentLevel, time: t, reduceMotion: reduceMotion)
    }

    /// Test-Naht: exakt die Höhen, die `PillWaveformView.draw(_:)` verwendet.
    var waveformHeightsForTesting: [CGFloat] { waveformView.barHeights }

    func resetWaveform() {
        t = 0
        waveformView.reset()
    }
}

// MARK: - Generischer Phasenstatus (AppKit)

@MainActor
final class StatusViewNS: NSView {
    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 36))
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            red: 0x1A / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1
        ).cgColor
        layer?.cornerRadius = 18

        let label = NSTextField(labelWithString: text)
        label.font = NSFont(name: "Geist", size: 12.5)
            ?? .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = NSColor(
            red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xED / 255, alpha: 1
        )
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 190),
            heightAnchor.constraint(equalToConstant: 36),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }
}

// MARK: - Bauteile

@MainActor
final class PillWaveformView: NSView {
    static let barCount = 14
    static let barWidth: CGFloat = 2
    static let spacing: CGFloat = 2

    private(set) var barHeights = Array(
        repeating: MicLevelBars.minHeight,
        count: barCount
    )
    private var peakHoldUntil = Array(repeating: TimeInterval.zero, count: barCount)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    func update(level: Double, time: Double, reduceMotion: Bool) {
        for index in 0..<Self.barCount {
            let modulatedLevel: Double
            if reduceMotion {
                modulatedLevel = level
            } else {
                let phase = time * (2.4 + Double(index % 4) * 0.55) + Double(index) * 0.9
                let jagged = abs(sin(phase) * 0.6 + sin(phase * 2.1) * 0.4)
                modulatedLevel = level * (0.55 + 0.45 * jagged)
            }
            let target = MicLevelBars.height(level: modulatedLevel, jitter: 0)
            let peak = MicLevelBars.nextPeak(
                current: barHeights[index],
                target: target,
                holdUntil: peakHoldUntil[index],
                now: time
            )
            barHeights[index] = peak.height
            peakHoldUntil[index] = peak.holdUntil
        }
        needsDisplay = true
    }

    func reset() {
        barHeights = Array(repeating: MicLevelBars.minHeight, count: Self.barCount)
        peakHoldUntil = Array(repeating: 0, count: Self.barCount)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (index, height) in barHeights.enumerated() {
            let x = CGFloat(index) * (Self.barWidth + Self.spacing)
            // Mittelpunkt bleibt fest: der Ausschlag wächst symmetrisch nach
            // oben und unten, ohne die 24-px-Pill zu vergrößern.
            let rect = NSRect(x: x, y: bounds.midY - height / 2,
                              width: Self.barWidth, height: height)
            NSColor(white: 1, alpha: MicLevelBars.opacity(forHeight: height)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
final class PillCircleButton: NSButton {
    let dark: Bool

    init(symbol: String, dark: Bool) {
        self.dark = dark
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        let pointSize: CGFloat = dark ? 10 : 9
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        imagePosition = .imageOnly
        wantsLayer = true
        let size: CGFloat = dark ? 17 : 16
        if dark {
            // ✓-Button: weißer Kreis, Häkchen im festen Ink-Ton.
            layer?.backgroundColor = NSColor.white.cgColor
            contentTintColor = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            contentTintColor = NSColor.white.withAlphaComponent(0.85)
        }
        layer?.cornerRadius = size / 2
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    // Klicks auch ohne Key-Panel annehmen (Panel darf nie key werden).
    override nonisolated func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override nonisolated var needsPanelToBecomeKey: Bool { false }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }
}

// MARK: - Toast (AppKit, v3: 36 px, dunkle Pill, grüner Haken / rotes ✕)

@MainActor
final class ToastViewNS: NSView {
    init(text: String, success: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0x1A / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1).cgColor
        layer?.cornerRadius = 18

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: success ? "checkmark" : "xmark",
                             accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
        icon.contentTintColor = success
            ? NSColor(red: 0x30 / 255, green: 0xA4 / 255, blue: 0x6C / 255, alpha: 1)
            : NSColor(red: 1.0, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

        let label = NSTextField(labelWithString: text)
        label.font = NSFont(name: "Geist", size: 12.5) ?? .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = NSColor(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xED / 255, alpha: 1)

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 260),
            heightAnchor.constraint(equalToConstant: 36),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }
}
