import Foundation

// MARK: - Dictionary-Datenmodell
// Plain-File unter ~/Library/Application Support/Stasi/dictionary.json

enum EntryType: String, Codable {
    /// Wort/Phrase, die die Engine kennen soll ("Anthropic", "Vercel")
    case word
    /// Korrekturpaar: gehört X → schreibe Y ("cloud code" → "Claude Code")
    case correction
    /// Auto-gelernt (vom System vorgeschlagen, noch nicht bestätigt)
    case learned
}

struct DictionaryEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var type: EntryType
    /// Nur bei .word
    var value: String = ""
    /// Nur bei .correction: Quellmuster (gehörte Form)
    var from: String? = nil
    /// Nur bei .correction: Zielschreibweise
    var to: String? = nil
    /// Freitext-Kommentar (erspart JSON-Kommentare beim Hand-Editieren)
    var note: String? = nil
    /// Vom System berechnete Warnungen (z. B. Kollision mit gebräuchlichem Wort)
    var warns: [String]? = nil

    /// Das Muster, gegen das transkribierter Text gematcht wird.
    var matchSource: String {
        switch type {
        case .word: return value
        case .correction: return from ?? ""
        case .learned: return value
        }
    }

    var replacementTarget: String {
        switch type {
        case .word: return value
        case .correction: return to ?? ""
        case .learned: return value
        }
    }
}

struct DictionaryFile: Codable {
    var entries: [DictionaryEntry] = []
}

// MARK: - Gebräuchliche Wörter (Warnungs-Heuristik)

enum CommonWords {
    /// Statische Blocklist häufiger Wörter – Korrekturquellen, die allein schon
    /// eines davon sind, bekommen eine UI-Warnung (Gefahr von Fehlkorrekturen).
    static let set: Set<String> = [
        // Englisch
        "cloud", "code", "word", "mail", "team", "note", "voice", "text",
        "time", "work", "home", "life", "love", "people", "project", "meeting",
        "apple", "google", "amazon", "server", "client", "date", "line",
        "file", "link", "site", "store", "stream", "sheet", "doc", "page",
        "post", "story", "key", "board", "book", "call", "chat", "slack",
        "notion", "linear", "base", "hub", "lab", "labs", "ai",
        // Deutsch
        "und", "oder", "die", "der", "das", "ist", "nicht", "mit", "für",
        "auch", "wort", "zeit", "arbeit", "haus", "leben", "leute", "brief",
        "seite", "datei", "ort", "gut", "neu", "sehr", "bitte", "danke",
    ]

    /// Prüft einen Eintrag und liefert Warnungen für riskante Quellen.
    static func warnings(for entry: DictionaryEntry) -> [String] {
        let source = entry.matchSource.lowercased()
        guard !source.isEmpty else { return [] }
        var warns: [String] = []
        for token in source.split(whereSeparator: { $0 == " " || $0 == "-" }) {
            if set.contains(String(token)) {
                warns.append("Quelle „\(token)“ ist ein gebräuchliches Wort – Korrektur könnte normale Texte verändern.")
            }
        }
        return warns
    }
}
