import AppKit
import SwiftUI

// MARK: - Aufnahme-Pill (v2 Mini-Pill, unten mittig, 26px hoch)
// ✕ · roter Pulsdot · 14 Pegelbalken · Timer · ✓
// Bewusst KOMPLETT in AppKit: SwiftUI-Interaktion in manuell verwalteten
// NSPanels crasht unter macOS 26.6 (Button-Gesture/Executor-Bug).

// MARK: - Modell (einfache Felder, vom Controller gesetzt)

@MainActor
final class PillModel {
    var level: Double = 0
    var secs: TimeInterval = 0
}

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
    let model = PillModel()
    var app: AppState?
    private var pillPanel: PillPanel?
    private var pillView: RecordingPillView?
    private var toastPanel: PillPanel?
    private var toastTimer: Timer?

    private var lastPhase: AppState.Phase = .idle
    private var lastSource: RecordingSource = .pushToTalk

    func sync(phase: AppState.Phase, partialText: String, elapsed: TimeInterval,
              level: Double, source: RecordingSource) {
        guard let app else { return }
        let entered = phase == .recording && lastPhase != .recording
        let exited = phase != .recording && lastPhase == .recording
        let sourceChanged = phase == .recording && lastSource != source
        lastPhase = phase
        lastSource = source
        switch phase {
        case .recording:
            let view = ensurePill(app: app)
            model.level = level
            model.secs = elapsed
            view.applyChrome(for: source)
            view.update(level: level, secs: elapsed)
            if entered || sourceChanged {
                if entered {
                    pillPanel?.positionBottomCenter()
                    startAnimation()
                }
                pillPanel?.resize(to: NSSize(width: PillChrome.pillWidth(for: source),
                                             height: 26))
                pillPanel?.orderFront(nil)
            }
        default:
            if exited {
                pillPanel?.orderOut(nil)
                stopAnimation()
            }
        }
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
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
            self?.toastPanel?.orderOut(nil)
        }
    }

    // MARK: Intern

    private func ensurePill(app: AppState) -> RecordingPillView {
        if let view = pillView { return view }
        let view = RecordingPillView(
            onDiscard: { [weak app] in app?.enqueue(.discard) },
            onCommit: { [weak app] in app?.enqueue(.commit) }
        )
        pillView = view
        pillPanel = PillPanel(content: view, size: NSSize(width: 160, height: 26))
        startAnimation()
        return view
    }

    private var animationTimer: Timer?

    private func startAnimation() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            self?.pillView?.tick()
        }
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
    private var bars: [BarView] = []

    private var t: Double = 0
    private var currentLevel: Double = 0

    init(onDiscard: @escaping () -> Void, onCommit: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 26))
        self.onDiscard = onDiscard
        self.onCommit = onCommit

        wantsLayer = true
        applyBackground()

        discardButton.target = self
        discardButton.action = #selector(discardTapped)
        commitButton.target = self
        commitButton.action = #selector(commitTapped)

        // Roter Pulsdot
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor(red: 1.0, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1).cgColor
        dotView.layer?.cornerRadius = 2.5
        dotView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 5),
            dotView.heightAnchor.constraint(equalToConstant: 5),
        ])
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dotView.layer?.add(pulse, forKey: "pulse")

        // Timer
        timerLabel.font = NSFont(name: "Geist Mono", size: 9) ?? .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        timerLabel.textColor = NSColor(white: 1, alpha: 0.65)
        timerLabel.isBezeled = false
        timerLabel.drawsBackground = false
        timerLabel.alignment = .right

        // Mini-Waveform: 14 Pegelbalken (2px breit)
        let barsStack = NSStackView(views: [])
        barsStack.orientation = .horizontal
        barsStack.spacing = 2
        for _ in 0..<14 {
            let bar = BarView()
            bars.append(bar)
            barsStack.addArrangedSubview(bar)
        }
        barsStack.alignment = .centerY

        let main = NSStackView(views: [discardButton, dotView, barsStack, timerLabel, commitButton])
        main.orientation = .horizontal
        main.spacing = 6
        main.alignment = .centerY
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 160),
            heightAnchor.constraint(equalToConstant: 26),
            main.centerXAnchor.constraint(equalTo: centerXAnchor),
            main.centerYAnchor.constraint(equalTo: centerYAnchor),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
        ])
        pillWidthConstraint = constraints.first { $0.firstAttribute == .width }

        // Leichtes Schweben (translateY −3px, 3 s) – reine Core Animation,
        // kein Timer, kein Executor-Kontakt.
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = 0
        float.toValue = -3
        float.duration = 3
        float.autoreverses = true
        float.repeatCount = .infinity
        layer?.add(float, forKey: "float")
    }

    private var pillWidthConstraint: NSLayoutConstraint?

    /// v4: ✕ und ✓ nur bei gehaltener Push-to-talk-Taste (Hands-free ohne).
    func applyChrome(for source: RecordingSource) {
        let show = PillChrome.showsButtons(for: source)
        discardButton.isHidden = !show
        commitButton.isHidden = !show
        applyBackground()
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// v3: Pill-Hintergrund = Akzent gemischt 88 % (color-mix mit Schwarz 12 %).
    private func applyBackground() {
        let hex = Theme.sharedSettings?.accentHex ?? 0x1A1917
        let r = CGFloat((hex >> 16) & 0xFF)
        let g = CGFloat((hex >> 8) & 0xFF)
        let b = CGFloat(hex & 0xFF)
        let mixed = NSColor(srgbRed: (r * 0.88) / 255,
                            green: (g * 0.88) / 255,
                            blue: (b * 0.88) / 255, alpha: 1)
        layer?.backgroundColor = mixed.cgColor
        layer?.cornerRadius = 13
        commitButton.contentTintColor = mixed
    }

    @objc nonisolated private func discardTapped() {
        onDiscard?()
    }

    @objc nonisolated private func commitTapped() {
        onCommit?()
    }

    func update(level: Double, secs: TimeInterval) {
        currentLevel = level
        let total = Int(secs)
        timerLabel.stringValue = String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 30 Hz: Waveform-Ballistik. Silenz = komplett flach (2 px, statisch),
    /// Lautstärke spreizt die Balken deutlich bis ~16 px – man sieht klar,
    /// dass wirklich aufgenommen wird.
    func tick() {
        t += 1.0 / 30.0
        let l = currentLevel
        for (i, bar) in bars.enumerated() {
            let p = t * (2.4 + Double(i % 4) * 0.55) + Double(i) * 0.9
            // Mehrkomponenten-Sinus → unregelmäßigere, „echtere" Waveform.
            let jagged = abs(sin(p) * 0.6 + sin(p * 2.1) * 0.4)
            bar.setLevel(l * (0.15 + 0.85 * jagged))
        }
    }
}

// MARK: - Bauteile

@MainActor
final class BarView: NSView {
    private var heightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 2, height: 6))
        wantsLayer = true
        // v3: Pegelbalken weiß 95 % auf Akzent-Pill
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.95).cgColor
        layer?.cornerRadius = 1
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 2).isActive = true
        heightConstraint = heightAnchor.constraint(equalToConstant: 6)
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Höhe 2…16px; `l` ist der 0…1-Spitzenpegel.
    func setLevel(_ l: CGFloat) {
        let clamped = max(0, min(l, 1))
        heightConstraint.constant = 2 + clamped * 14
    }
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
            // ✓-Button v3: weißer Kreis, akzentfarbenes Häkchen (via applyBackground).
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
