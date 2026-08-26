import Foundation
import CoreGraphics

enum VirtualKey {
    /// Hands-free darf nur Modifier verwenden: Ein Doppeltipp schreibt dann
    /// kein normales Zeichen in die gerade fokussierte App.
    nonisolated static let handsFreeModifierKeyCodes: [UInt64] = [
        63, 55, 54, 58, 61, 59, 62, 56, 60,
    ]

    nonisolated static func isHandsFreeModifier(_ code: UInt64) -> Bool {
        handsFreeModifierKeyCodes.contains(code)
    }

    static func name(for code: Int) -> String {
        switch code {
        case 54: return "Rechte ⌘ halten"
        case 55: return "Linke ⌘ halten"
        case 56: return "Linke ⇧ halten"
        case 60: return "Rechte ⇧ halten"
        case 58: return "Linke ⌥ halten"
        case 61: return "Rechte ⌥ halten"
        case 59: return "Linke ⌃ halten"
        case 62: return "Rechte ⌃ halten"
        case 63: return "Fn halten"
        case 49: return "Space halten"
        default:
            let fKeys: [Int: String] = [
                96: "F5 halten", 97: "F6 halten", 98: "F7 halten",
                100: "F8 halten", 101: "F9 halten", 109: "F10 halten",
                103: "F11 halten", 111: "F12 halten",
            ]
            if let fk = fKeys[code] { return fk }
            let letters: [Int: String] = [
                0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
                34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
                35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
                13: "W", 7: "X", 16: "Y", 6: "Z",
            ]
            if let letter = letters[code] { return "\(letter)" }
            return "Taste \(code)"
        }
    }

    /// Kurzes Symbol für eine Taste (ohne „halten"-Suffix).
    static func keySymbol(_ code: Int) -> String {
        switch code {
        case 54: return "⌘ Rechts"
        case 55: return "⌘ Links"
        case 56: return "⇧ Links"
        case 60: return "⇧ Rechts"
        case 58: return "⌥ Links"
        case 61: return "⌥ Rechts"
        case 59: return "⌃ Links"
        case 62: return "⌃ Rechts"
        case 63: return "fn"
        case 57: return "⇪"
        case 49: return "Leertaste"
        case 36: return "↩"
        case 51: return "⌫"
        case 53: return "esc"
        case 48: return "⇥"
        default:
            if code >= 96 && code <= 123 { return "F\(code - 95)" }
            let letters: [Int: String] = [
                0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
                34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
                35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
                13: "W", 7: "X", 16: "Y", 6: "Z",
            ]
            if let letter = letters[code] { return letter }
            return "Taste \(code)"
        }
    }

    /// Modifier-Symbole in macOS-Reihenfolge (⌃ ⌥ ⇧ ⌘).
    static func modifierSymbols(_ flags: UInt64) -> String {
        var s = ""
        if flags & CGEventFlags.maskControl.rawValue != 0 { s += "⌃" }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if flags & CGEventFlags.maskShift.rawValue != 0 { s += "⇧" }
        if flags & CGEventFlags.maskCommand.rawValue != 0 { s += "⌘" }
        return s
    }

    /// Anzeige-String für einen Hotkey (z. B. „⌘ Rechts", „⌥ Leertaste").
    static func display(_ combo: HotkeyEngine.Combo) -> String {
        let mods = modifierSymbols(combo.flags)
        let key = keySymbol(Int(combo.keyCode))
        return mods.isEmpty ? key : "\(mods) \(key)"
    }
}
