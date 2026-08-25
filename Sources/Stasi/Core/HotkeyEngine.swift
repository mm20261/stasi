import AppKit
import CoreGraphics

// MARK: - Tap-Reaktivierungsrichtlinie

/// Reine Zähl-/Aufgabe-Logik. Der Aufrufer injiziert die Abfrage des echten
/// Tap-Zustands; nur `HotkeyEngine.ensureEnabled()` führt die Reaktivierung aus.
struct HotkeyReenablePolicy {
    enum Action: Equatable {
        case none
        case reenable(attempt: Int)
        case giveUp
    }

    let maxReenableAttempts: Int
    private(set) var reenableCount = 0
    private(set) var gaveUp = false

    init(maxReenableAttempts: Int = 3) {
        self.maxReenableAttempts = maxReenableAttempts
    }

    mutating func evaluate(isTapEnabled: () -> Bool) -> Action {
        guard !gaveUp else { return .none }
        guard !isTapEnabled() else {
            reenableCount = 0
            return .none
        }

        reenableCount += 1
        guard reenableCount <= maxReenableAttempts else {
            gaveUp = true
            return .giveUp
        }
        return .reenable(attempt: reenableCount)
    }
}

// MARK: - HotkeyEngine
// Globaler Push-to-Talk-Hotkey via CGEventTap (listen-only).
// Standard: Rechte Command-Taste HALTEN = aufnehmen, loslassen = stoppen.

final class HotkeyEngine: @unchecked Sendable {
    struct Combo: Codable, Equatable, Sendable {
        var keyCode: UInt64      // CGEvent-KeyCode
        var flags: UInt64        // erforderliche Modifier-Maske (CGEventFlags.rawValue)

        /// Rechte Command-Taste, ohne zusätzliche Modifier.
        static let defaultPTT = Combo(keyCode: 54, flags: 0)
    }
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onChord: ((Combo) -> Void)?
    var onHandsFree: (() -> Void)?
    var onTapStopped: (() -> Void)?

    private let combo: Combo
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isDown = false
    private(set) var isOperational = false
    private var tapWasDisabled = false
    private var shortcut = ShortcutDetector()
    private var reenablePolicy: HotkeyReenablePolicy

    init(combo: Combo, chords: [Combo] = [], handsFreeEnabled: Bool = false,
         reenablePolicy: HotkeyReenablePolicy = HotkeyReenablePolicy()) {
        self.combo = combo
        self.reenablePolicy = reenablePolicy
        self.shortcut.chords = chords
        self.shortcut.handsFreeEnabled = handsFreeEnabled
    }

    var gaveUp: Bool { reenablePolicy.gaveUp }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        // Session-Tap statt HID-Tap:
        // · .cgSessionEventTap + .defaultTap braucht NUR Bedienungshilfen,
        //   nicht die zickige Eingabe-Überwachung (deren Grant nach jedem
        //   Re-Sign kaputt war und deren Tauziehen Maus-Events schluckte).
        // · tapDisabled-Events markieren nur den Zustand. Reaktivierung
        //   passiert ausschließlich gezählt in ensureEnabled().
        // Events werden IMMER unverändert durchgereicht (kein Konsumieren).
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<HotkeyEngine>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    engine.tapWasDisabled = true
                    engine.isOperational = false
                    NSLog("STASI-HK: Tap deaktiviert (%d) – Reaktivierung nur im Poll", type.rawValue)
                    return Unmanaged.passUnretained(event)
                }
                engine.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else {
            DebugLog.log("STASI-HK: tapCreate fehlgeschlagen – Bedienungshilfen fehlt (oder greift erst nach Neustart)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        runLoopSource = source
        isOperational = CGEvent.tapIsEnabled(tap: port)
        tapWasDisabled = !isOperational

        // KEIN NSEvent-Global-Monitor mehr: Der braucht Eingabe-Überwachung
        // (die wir nicht mehr anfordern) – ein unberechtigter Keyboard-Monitor
        // löst dieselbe Maus-Event-Sperre aus wie ein unberechtigter Tap.
        // Der Session-Tap ist zuverlässig genug, ein Fallback ist unnötig.

        DebugLog.log("STASI-HK: Session-Tap installiert (keyCode \(combo.keyCode))")
        return true
    }

    /// Reaktiviert den Tap, falls macOS ihn wegen Timeout deaktiviert hat.
    /// Nach 3 Deaktivierungen: aufgeben und Tap stoppen (App-Neustart nötig).
    func ensureEnabled() {
        guard let tap, !reenablePolicy.gaveUp else { return }
        switch reenablePolicy.evaluate(isTapEnabled: { CGEvent.tapIsEnabled(tap: tap) }) {
        case .none:
            isOperational = true
            tapWasDisabled = false
        case .reenable(let attempt):
            DebugLog.log("STASI-HK: Tap war deaktiviert – reaktiviere (\(attempt)/\(reenablePolicy.maxReenableAttempts))")
            CGEvent.tapEnable(tap: tap, enable: true)
            isOperational = CGEvent.tapIsEnabled(tap: tap)
            tapWasDisabled = !isOperational
        case .giveUp:
            DebugLog.log("STASI-HK: Tap wird wiederholt vom System deaktiviert – gebe auf. App-Neustart nötig, damit die Freigabe greift.")
            isOperational = false
            tapWasDisabled = true
            stop()
            onTapStopped?()
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isDown = false
        isOperational = false
    }

    deinit { stop() }

    // MARK: Event-Auswertung

    private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let keyCodeU = UInt64(bitPattern: Int64(keyCode))
        let matchesKey = keyCodeU == combo.keyCode
        let isModifier = Self.modifierFlag(for: keyCodeU) != nil

        // PTT
        switch type {
        case .flagsChanged where matchesKey && isModifier:
            // Modifier-Taste (z. B. rechte Command): Down/Up aus Flags ableiten.
            // Ist bei Command gleichzeitig Control gedrückt, ist es ein Chord,
            // kein Diktat-Start.
            var down = event.flags.contains(Self.modifierFlag(for: keyCodeU)!)
            if Self.modifierFlag(for: keyCodeU) == .maskCommand,
               event.flags.contains(.maskControl) { down = false }
            transition(to: down)
        case .keyDown where matchesKey && !isModifier:
            // Normale Taste: Down, wenn geforderte Modifier gehalten werden.
            let down = combo.flags == 0 || (event.flags.rawValue & combo.flags) == combo.flags
            transition(to: down)
        case .keyUp where matchesKey && !isModifier:
            transition(to: false)
        default:
            break
        }

        // Zusatz-Shortcuts (Fn-Doppeltipp)
        let kind: ShortcutDetector.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: kind = .flagsChanged
        }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let events = shortcut.process(kind: kind, keyCode: keyCodeU,
                                      flags: event.flags.rawValue, isRepeat: isRepeat)
        for e in events {
            switch e {
            case .chord(let c): onChord?(c)
            case .handsFreeTap: onHandsFree?()
            }
        }
    }

    /// Bildet eine Modifier-Taste auf ihr CGEventFlag ab; nil für normale Tasten.
    private static func modifierFlag(for keyCode: UInt64) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59: return .maskControl
        case 63: return .maskSecondaryFn
        case 57: return .maskAlphaShift
        default: return nil
        }
    }

    private func transition(to down: Bool) {
        guard down != isDown else { return }
        isDown = down
        DebugLog.log("STASI-HK: \(down ? "PRESS" : "RELEASE")")
        // Der Tap-Callback läuft auf dem Main-RunLoop → direkter Aufruf ist sicher.
        down ? onPress?() : onRelease?()
    }
}

// MARK: - ShortcutDetector
// Reiner, zustandsbehafteter Detektor für Zusatz-Shortcuts: Chord-Aktionen
// und Fn-Doppeltipp (Hands-free). Kein CGEvent nötig → testbar.

struct ShortcutDetector {
    enum Kind: Equatable {
        case keyDown, keyUp, flagsChanged
    }

    enum Event: Equatable {
        case chord(HotkeyEngine.Combo)
        case handsFreeTap
    }

    static let fnKeyCode: UInt64 = 63
    static let secondaryFn: UInt64 = CGEventFlags.maskSecondaryFn.rawValue

    var chords: [HotkeyEngine.Combo] = []
    var handsFreeEnabled = false
    var doubleTapWindow: TimeInterval = 0.35

    private var fnWasDown = false
    private var lastFnDownAt: Date?

    mutating func process(kind: Kind, keyCode: UInt64, flags: UInt64,
                          isRepeat: Bool = false, now: Date = Date()) -> [Event] {
        var events: [Event] = []

        if kind == .keyDown && !isRepeat {
            for chord in chords where chord.keyCode == keyCode
                && (flags & chord.flags) == chord.flags {
                events.append(.chord(chord))
            }
        }

        if handsFreeEnabled, kind == .flagsChanged, keyCode == Self.fnKeyCode {
            let down = (flags & Self.secondaryFn) != 0
            if down && !fnWasDown {
                if let last = lastFnDownAt, now.timeIntervalSince(last) <= doubleTapWindow {
                    events.append(.handsFreeTap)
                    lastFnDownAt = nil
                } else {
                    lastFnDownAt = now
                }
            }
            fnWasDown = down
        }

        return events
    }
}
