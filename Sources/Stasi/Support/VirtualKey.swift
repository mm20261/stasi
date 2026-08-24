import Foundation

enum VirtualKey {
    static func name(for code: Int) -> String {
        switch code {
        case 54: return "Rechte ⌘ halten"
        case 55: return "Linke ⌘ halten"
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
}
