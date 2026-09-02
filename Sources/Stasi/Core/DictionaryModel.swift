import Foundation

// MARK: - Dictionary-Datenmodell
// Plain-File unter ~/Library/Application Support/Stasi/dictionary.json

enum EntryType: String, Codable, Sendable {
    /// Wort/Phrase, die die Engine kennen soll ("Anthropic", "Vercel")
    case word
    /// Korrekturpaar: gehört X → schreibe Y ("cloud code" → "Claude Code")
    case correction
    /// Auto-gelernt (vom System vorgeschlagen, noch nicht bestätigt)
    case learned
}

struct DictionaryEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
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

    init(id: UUID = UUID(), type: EntryType, value: String = "",
         from: String? = nil, to: String? = nil, note: String? = nil,
         warns: [String]? = nil) {
        self.id = id
        self.type = type
        self.value = value
        self.from = from
        self.to = to
        self.note = note
        self.warns = warns
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, value, from, to, note, warns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(EntryType.self, forKey: .type)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        from = try container.decodeIfPresent(String.self, forKey: .from)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        warns = try container.decodeIfPresent([String].self, forKey: .warns)
    }

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
    var version: Int = 1
    var entries: [DictionaryEntry] = []
    /// Optional für Rückwärtskompatibilität mit bestehenden dictionary.json-Dateien.
    var ignoredLearned: [String]? = nil

    init(version: Int = 1, entries: [DictionaryEntry] = [],
         ignoredLearned: [String]? = nil) {
        self.version = version
        self.entries = entries
        self.ignoredLearned = ignoredLearned
    }

    private enum CodingKeys: String, CodingKey {
        case version, entries, ignoredLearned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let tolerantEntries = try container.decodeIfPresent(
            [TolerantDictionaryEntry].self,
            forKey: .entries
        ) ?? []
        entries = tolerantEntries.compactMap(\.value)
        ignoredLearned = try container.decodeIfPresent([String].self, forKey: .ignoredLearned)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encodeIfPresent(ignoredLearned, forKey: .ignoredLearned)
    }
}

private struct TolerantDictionaryEntry: Decodable {
    let value: DictionaryEntry?

    init(from decoder: Decoder) throws {
        value = try? DictionaryEntry(from: decoder)
    }
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
