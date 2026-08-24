import AppKit
import SwiftUI

// MARK: - Aufnahme-Pill (Overlay, unten mittig)
// Wispr-Stil: kompakt – nur ✕ · Waveform · ✓
// Bewusst KOMPLETT in AppKit: SwiftUI-Interaktion in manuell verwalteten
// NSPanels crasht unter macOS 26.6 (Button-Gesture/Executor-Bug).

// MARK: - Modell (einfache Felder, vom Controller gesetzt)

@MainActor
final class PillModel {
    var level: Double = 0
}

// MARK: - Panel

final class PillPanel: NSPanel {
    // KEIN canBecomeKey-Override! Borderless-Panels sind default nicht
    // key-fähig – genau richtig (Panel darf dem Hauptfenster nie den Fokus
    // klauen). Und: Ein Swift-Override wird von AppKit über einen @objc-Thunk
    // mit MainActor-Executor-Check aufgerufen – das crashte unter macOS 26.6
    // mitten in _handleMouseDownEvent (EXC_BAD_ACCESS in swift_task_
    // isMainExecutorImpl). Buttons funktionieren ohne Key-Status, weil
    // PillCircleButton acceptsFirstMouse/needsPanelToBecomeKey überschreibt.

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

    func sync(phase: AppState.Phase, partialText: String, elapsed: TimeInterval, level: Double) {
        guard let app else { return }
        // orderFront/orderOut NUR bei Phasenwechsel – 20 Hz Window-Ordering-
        // Churn hat den WindowServer beschäftigt und Klicks geschluckt.
        let entered = phase == .recording && lastPhase != .recording
        let exited = phase != .recording && lastPhase == .recording
        lastPhase = phase
        switch phase {
        case .recording:
            let view = ensurePill(app: app)
            model.level = level
            view.update(level: level)
            if entered {
                pillPanel?.positionBottomCenter()
                pillPanel?.orderFront(nil)
                startAnimation()
            }
        default:
            if exited {
                pillPanel?.orderOut(nil)
                stopAnimation()
            }
        }
    }

    /// Toast-Pill nach Abschluss/Verwerfen
    func showToast(_ message: String, success: Bool) {
        let view = ToastViewNS(text: message, success: success)
        if toastPanel == nil {
            toastPanel = PillPanel(content: view, size: NSSize(width: 320, height: 48))
        } else {
            toastPanel?.contentView = view
        }
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
            // Kein Task aus dem Button-Thunk: enqueue ist thread-sicher und
            // der Command-Loop (AppState) verarbeitet auf dem MainActor.
            onDiscard: { [weak app] in app?.enqueue(.discard) },
            onCommit: { [weak app] in app?.enqueue(.commit) }
        )
        pillView = view
        pillPanel = PillPanel(content: view, size: NSSize(width: 190, height: 48))
        startAnimation()
        return view
    }

    private var animationTimer: Timer?

    private func startAnimation() {
        guard animationTimer == nil else { return }
        // Statisch MainActor-isoliert (Timer auf Main-RunLoop) → direkter Aufruf
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            self?.pillView?.tick()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Pill-View (AppKit, Wispr-Kompaktformat)

@MainActor
final class RecordingPillView: NSView {
    // Bewusst nonisolated(unsafe): wird nur vom @objc-Thunk auf dem
    // Main-Thread gelesen; die Closures rufen ausschließlich das
    // thread-sichere AppState.enqueue – kein Executor-Check, kein Task.
    nonisolated(unsafe) var onDiscard: (() -> Void)?
    nonisolated(unsafe) var onCommit: (() -> Void)?

    private let discardButton = PillCircleButton(symbol: "xmark", dark: false)
    private let commitButton = PillCircleButton(symbol: "checkmark", dark: true)
    private var bars: [BarView] = []

    private var t: Double = 0
    private var currentLevel: Double = 0

    init(onDiscard: @escaping () -> Void, onCommit: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 48))
        self.onDiscard = onDiscard
        self.onCommit = onCommit

        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0x1A / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1).cgColor
        layer?.cornerRadius = 24
        layer?.masksToBounds = false

        discardButton.target = self
        discardButton.action = #selector(discardTapped)
        commitButton.target = self
        commitButton.action = #selector(commitTapped)

        // Mini-Waveform: 12 kleine helle Balken
        let barsStack = NSStackView(views: [])
        barsStack.orientation = .horizontal
        barsStack.spacing = 3
        for _ in 0..<12 {
            let bar = BarView()
            bars.append(bar)
            barsStack.addArrangedSubview(bar)
        }
        barsStack.alignment = .centerY

        let main = NSStackView(views: [discardButton, barsStack, commitButton])
        main.orientation = .horizontal
        main.spacing = 14
        main.alignment = .centerY
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 190),
            heightAnchor.constraint(equalToConstant: 48),
            main.centerXAnchor.constraint(equalTo: centerXAnchor),
            main.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// nonisolated, KEIN Task, KEIN Executor-Check: Der @objc-Thunk ruft nur
    /// die plain Closure, die per enqueue in den Command-Stream yieldet.
    /// (Task { @MainActor } aus diesem Frame war der crashende Pfad.)
    @objc nonisolated private func discardTapped() {
        NSLog("STASI-PILL: ✕ gedrückt")
        onDiscard?()
    }

    @objc nonisolated private func commitTapped() {
        NSLog("STASI-PILL: ✓ gedrückt")
        onCommit?()
    }

    func update(level: Double) {
        currentLevel = level
    }

    /// 30 Hz: Waveform-Ballistik
    func tick() {
        t += 1.0 / 30.0
        let base = 0.3 + currentLevel * 0.7
        for (i, bar) in bars.enumerated() {
            let phase = t * (2.2 + Double(i % 5) * 0.35) + Double(i) * 0.7
            let variation = 0.5 + 0.5 * abs(sin(phase))
            bar.setScaleY(base * variation)
        }
    }
}

// MARK: - Bauteile

@MainActor
final class BarView: NSView {
    private var heightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 3, height: 11))
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xED / 255, alpha: 0.95).cgColor
        layer?.cornerRadius = 1.5
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 3).isActive = true
        heightConstraint = heightAnchor.constraint(equalToConstant: 11)
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setScaleY(_ value: CGFloat) {
        let clamped = max(0.2, min(value, 1.3))
        heightConstraint.constant = 11 * clamped
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
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.backgroundColor = dark
            ? NSColor(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xED / 255, alpha: 1).cgColor
            : NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.cornerRadius = 12
        contentTintColor = dark
            ? NSColor(red: 0x1A / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1)
            : NSColor(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xED / 255, alpha: 0.85)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    // Klicks auch ohne Key-Panel annehmen (Panel darf nie key werden).
    // nonisolated: Diese Getter ruft AppKit mitten im Maus-Event-Routing –
    // ein MainActor-Executor-Check im @objc-Thunk crasht dort (macOS 26.6).
    override nonisolated func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override nonisolated var needsPanelToBecomeKey: Bool { false }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }
}

// MARK: - Toast (AppKit)

@MainActor
final class ToastViewNS: NSView {
    init(text: String, success: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 48))
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0x1A / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1).cgColor
        layer?.cornerRadius = 24
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: success ? "checkmark" : "xmark",
                             accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        icon.contentTintColor = success
            ? NSColor(red: 0x30 / 255, green: 0xA4 / 255, blue: 0x6C / 255, alpha: 1)
            : NSColor(red: 1.0, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

        let label = NSTextField(labelWithString: text)
        label.font = NSFont(name: "Geist", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xED / 255, alpha: 1)

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 320),
            heightAnchor.constraint(equalToConstant: 48),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }
}
