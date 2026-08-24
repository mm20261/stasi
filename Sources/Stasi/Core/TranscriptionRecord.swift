import Foundation

// MARK: - TranscriptionRecord
// Ein abgeschlossener Diktat-Vorgang inkl. Korrektur-Nachweis, Metadaten & Audio.

struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let localeID: String
    let rawText: String
    let correctedText: String
    let corrections: [AppliedCorrection]
    /// Dauer der Aufnahme in Sekunden
    var durationSecs: Double
    /// Name der Ziel-App, in die eingefügt wurde
    var targetApp: String
    /// Pfad zur WAV-Aufnahme (optional)
    var audioPath: String?

    var wordCount: Int {
        correctedText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    init(date: Date, localeID: String, rawText: String, correctedText: String,
         corrections: [AppliedCorrection], durationSecs: Double = 0,
         targetApp: String = "", audioPath: String? = nil) {
        self.id = UUID()
        self.date = date
        self.localeID = localeID
        self.rawText = rawText
        self.correctedText = correctedText
        self.corrections = corrections
        self.durationSecs = durationSecs
        self.targetApp = targetApp
        self.audioPath = audioPath
    }
}

// MARK: - HistoryStore
// Persistiert Protokolle nach ~/Library/Application Support/Stasi/history.json.

@MainActor
@Observable
final class HistoryStore {
    private(set) var records: [TranscriptionRecord] = []

    private var fileURL: URL

    /// `directory` ist für Tests injizierbar; default = Application Support.
    init(directory: URL? = nil) {
        let dir = directory ?? DictionaryStore.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data)
        else { return }
        records = decoded.sorted { $0.date > $1.date }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func insert(_ record: TranscriptionRecord, at position: Int = 0) {
        records.insert(record, at: min(position, records.count))
        save()
    }

    func delete(_ record: TranscriptionRecord) {
        records.removeAll { $0.id == record.id }
        if let audioPath = record.audioPath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
        save()
    }
}
