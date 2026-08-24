import AppKit
import CoreGraphics

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
}
