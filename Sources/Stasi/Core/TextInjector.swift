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
    static func inject(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let scalars = Array(text.utf16)

        // In Häppchen posten – sehr lange Strings in einem Event können
        // von manchen Apps verschluckt werden.
        var offset = 0
        while offset < scalars.count {
            let end = min(offset + 24, scalars.count)
            let chunk = Array(scalars[offset..<end])
            let length = chunk.count

            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                // Abbrechen statt continue: continue ohne offset-Vorschub war
                // eine Endlosschleife (100% CPU), wenn CGEvent-Erzeugung
                // fehlschlägt (z. B. Accessibility-Recht entzogen).
                NSLog("STASI-INJECT: CGEvent-Erzeugung fehlgeschlagen – Abbruch bei Offset %d", offset)
                break
            }

            down.keyboardSetUnicodeString(stringLength: length, unicodeString: chunk)
            up.keyboardSetUnicodeString(stringLength: length, unicodeString: chunk)

            down.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.002)
            up.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.006)

            offset = end
        }
    }

    /// Prüft via Accessibility-API, ob das fokussierte UI-Element der
    /// vordersten App ein bearbeitbares Textfeld ist. Bei false würde
    /// `inject()` einen System-Beep auslösen (kein Textfeld im Fokus).
    static func isFocusedElementEditable() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
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

    /// Reine Rollen-Prüfung, testbar ohne AX-Abhängigkeit.
    static func isEditableRole(_ role: String, valueSettable: Bool) -> Bool {
        switch role {
        case "AXTextField", "AXTextArea", "AXComboBox": true
        case "AXWebArea": valueSettable
        default: false
        }
    }
}
