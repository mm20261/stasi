import AppKit
import CoreGraphics
import ApplicationServices

struct TargetApplication: Equatable, Sendable {
    let localizedName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
}

enum TargetApplicationMatcher {
    static func matches(captured: TargetApplication, current: TargetApplication?) -> Bool {
        guard let current,
              captured.processIdentifier == current.processIdentifier else { return false }
        guard let bundleIdentifier = captured.bundleIdentifier else { return true }
        return current.bundleIdentifier == bundleIdentifier
    }
}

// MARK: - TextInjector
// Tippt fertigen Text per synthetisierter Keyboard-Events in die fokussierte App.
// Benötigt Bedienungshilfen-Berechtigung (Accessibility).

enum TextInjector {
    static let injectionQueue = DispatchQueue(
        label: "stasi.inject",
        qos: .userInteractive
    )

    @discardableResult
    static func inject(_ text: String, targetPID: pid_t) async -> Bool {
        await onInjectionQueue {
            guard targetPID > 0,
                  let source = CGEventSource(stateID: .combinedSessionState) else { return false }
            return routeChunks(text, targetPID: targetPID) { chunk, pid in
                let length = chunk.count
                guard let down = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: true
                ) else {
                    NSLog("STASI-INJECT: Key-down-Erzeugung fehlgeschlagen – Route abgebrochen")
                    return false
                }
                // Beide Events entstehen vor dem ersten Post. Scheitert key-up nach
                // erfolgreichem key-down-Aufbau, bleibt kein down-ohne-up im System.
                guard let up = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: false
                ) else {
                    NSLog("STASI-INJECT: Key-up-Erzeugung fehlgeschlagen – Route abgebrochen")
                    return false
                }
                down.keyboardSetUnicodeString(stringLength: length, unicodeString: chunk)
                up.keyboardSetUnicodeString(stringLength: length, unicodeString: chunk)
                down.postToPid(pid)
                Thread.sleep(forTimeInterval: 0.002)
                up.postToPid(pid)
                Thread.sleep(forTimeInterval: 0.006)
                return true
            }
        }
    }

    /// Testnaht für Queue-Bindung und Timing ohne globale Tastaturereignisse.
    @discardableResult
    static func inject(
        _ text: String,
        targetPID: pid_t,
        deliver: @escaping @Sendable (_ chunk: [UniChar], _ targetPID: pid_t) -> Bool
    ) async -> Bool {
        await onInjectionQueue {
            routeChunks(text, targetPID: targetPID, deliver: deliver)
        }
    }

    private static func onInjectionQueue(
        _ operation: @escaping @Sendable () -> Bool
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            injectionQueue.async {
                continuation.resume(returning: operation())
            }
        }
    }

    /// Zerlegt Text deterministisch und bindet jeden Chunk an denselben Prozess.
    /// Die Testnaht erzeugt weder globale Events noch Pasteboard-/App-Zugriffe.
    @discardableResult
    static func routeChunks(
        _ text: String,
        targetPID: pid_t,
        deliver: (_ chunk: [UniChar], _ targetPID: pid_t) -> Bool
    ) -> Bool {
        var chunk: [UniChar] = []
        chunk.reserveCapacity(24)

        for scalar in text.unicodeScalars {
            let scalarUnits = Array(String(scalar).utf16)
            if !chunk.isEmpty, chunk.count + scalarUnits.count > 24 {
                guard deliver(chunk, targetPID) else { return false }
                chunk.removeAll(keepingCapacity: true)
            }
            chunk.append(contentsOf: scalarUnits)
        }

        if !chunk.isEmpty {
            guard deliver(chunk, targetPID) else { return false }
        }
        return true
    }

    /// Prüft via Accessibility-API, ob das fokussierte UI-Element der
    /// vordersten App ein bearbeitbares Textfeld ist. Bei false würde
    /// `inject()` einen System-Beep auslösen (kein Textfeld im Fokus).
    static func isFocusedElementEditable() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        _ = messagingTimeoutConfigured
        var app: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedApplicationAttribute as CFString,
                                            &app) == .success,
              let app,
              CFGetTypeID(app) == AXUIElementGetTypeID() else { return false }
        let appElement = unsafeDowncast(app, to: AXUIElement.self)
        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &element) == .success,
              let element,
              CFGetTypeID(element) == AXUIElementGetTypeID() else { return false }
        let focusedElement = unsafeDowncast(element, to: AXUIElement.self)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement,
                                            kAXRoleAttribute as CFString,
                                            &role) == .success,
              let roleString = role as? String else { return false }
        var settable = DarwinBoolean(false)
        let valueSettable = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &settable
        ) == .success && settable.boolValue
        return isEditableRole(roleString, valueSettable: valueSettable)
    }

    /// Der AX-Systemknoten ist pro Prozess konfiguriert; 500 ms verhindern,
    /// dass eine nicht antwortende Ziel-App die Injection unbegrenzt festhält.
    private static let messagingTimeoutConfigured: Void = {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.5)
    }()

    /// Reine Rollen-Prüfung, testbar ohne AX-Abhängigkeit.
    static func isEditableRole(_ role: String, valueSettable: Bool) -> Bool {
        switch role {
        case "AXTextField", "AXTextArea", "AXComboBox": true
        case "AXWebArea": valueSettable
        default: false
        }
    }
}
