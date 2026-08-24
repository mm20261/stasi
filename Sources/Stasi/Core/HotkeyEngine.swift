import AppKit
import CoreGraphics

// MARK: - HotkeyEngine
// Globaler Push-to-Talk-Hotkey via CGEventTap (listen-only).
// Standard: Rechte Command-Taste HALTEN = aufnehmen, loslassen = stoppen.

final class HotkeyEngine: @unchecked Sendable {
    struct Combo: Codable, Equatable {
        var keyCode: UInt64      // CGEvent-KeyCode
        var flags: UInt64        // erforderliche Modifier-Maske (CGEventFlags.rawValue)

        /// Rechte Command-Taste, ohne zusätzliche Modifier.
        static let defaultPTT = Combo(keyCode: 54, flags: 0)
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private let combo: Combo
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isDown = false

    init(combo: Combo) {
        self.combo = combo
    }

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
        // · tapDisabled-Events werden direkt im Callback re-armed.
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
                    if let tap = engine.tap {
                        NSLog("STASI-HK: Tap deaktiviert (%d) – re-arm im Callback", type.rawValue)
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
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

        // KEIN NSEvent-Global-Monitor mehr: Der braucht Eingabe-Überwachung
        // (die wir nicht mehr anfordern) – ein unberechtigter Keyboard-Monitor
        // löst dieselbe Maus-Event-Sperre aus wie ein unberechtigter Tap.
        // Der Session-Tap ist zuverlässig genug, ein Fallback ist unnötig.

        DebugLog.log("STASI-HK: Session-Tap installiert (keyCode \(combo.keyCode))")
        return true
    }

    private var reenableCount = 0
    /// System deaktiviert den Tap wiederholt (TCC greift erst nach Neustart) –
    /// dann NICHT weiterkämpfen, sonst entzieht macOS dem Prozess alle Maus-Events.
    private(set) var gaveUp = false

    /// Reaktiviert den Tap, falls macOS ihn wegen Timeout deaktiviert hat.
    /// Nach 3 Deaktivierungen: aufgeben und Tap stoppen (App-Neustart nötig).
    func ensureEnabled() {
        guard let tap, !gaveUp else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            reenableCount += 1
            if reenableCount > 3 {
                DebugLog.log("STASI-HK: Tap wird wiederholt vom System deaktiviert – gebe auf. App-Neustart nötig, damit die Freigabe greift.")
                gaveUp = true
                stop()
                return
            }
            DebugLog.log("STASI-HK: Tap war deaktiviert – reaktiviere (\(reenableCount)/3)")
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            reenableCount = 0
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
        }
        tap = nil
        runLoopSource = nil
        isDown = false
    }

    deinit { stop() }

    // MARK: Event-Auswertung

    private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let matchesKey = UInt64(bitPattern: Int64(keyCode)) == combo.keyCode

        switch type {
        case .flagsChanged where matchesKey:
            // Modifier-Taste (z. B. rechte Command): Down/Up aus Flags ableiten.
            let commandDown = event.flags.contains(.maskCommand)
            transition(to: commandDown)
        case .keyDown where matchesKey && combo.flags != 0:
            transition(to: event.flags.contains(CGEventFlags(rawValue: combo.flags)))
        case .keyDown where matchesKey && combo.flags == 0:
            transition(to: true)
        case .keyUp where matchesKey && combo.flags == 0:
            transition(to: false)
        default:
            break
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
