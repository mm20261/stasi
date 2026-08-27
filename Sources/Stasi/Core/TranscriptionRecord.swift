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
    /// Optionale Zusammenfassung der regelbasierten Nachbearbeitung.
    /// Optional hält bestehende history.json-Dateien rückwärtskompatibel.
    let polish: PolishSummary?

    var wordCount: Int {
        correctedText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    init(date: Date, localeID: String, rawText: String, correctedText: String,
         corrections: [AppliedCorrection], durationSecs: Double = 0,
         targetApp: String = "", audioPath: String? = nil,
         polish: PolishSummary? = nil) {
        self.id = UUID()
        self.date = date
        self.localeID = localeID
        self.rawText = rawText
        self.correctedText = correctedText
        self.corrections = corrections
        self.durationSecs = durationSecs
        self.targetApp = targetApp
        self.audioPath = audioPath
        self.polish = polish
    }
}

// MARK: - HistoryStore
// Persistiert Protokolle nach ~/Library/Application Support/Stasi/history.json.

enum HistoryStoreState: Equatable {
    case missing
    case loaded
    case unreadable(String)
}

enum HistoryStoreError: LocalizedError {
    case writeBlockedByUnreadableHistory(URL)
    case encodingFailed(String)
    case writeFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .writeBlockedByUnreadableHistory(let url):
            return "Die unlesbare Verlaufsdatei \(url.path) wurde nicht verändert."
        case .encodingFailed(let message):
            return "Der Verlauf konnte nicht kodiert werden: \(message)"
        case .writeFailed(let url, let message):
            return "Der Verlauf konnte nicht nach \(url.path) geschrieben werden: \(message)"
        }
    }
}

@MainActor
protocol HistoryStoring: AnyObject {
    var records: [TranscriptionRecord] { get }
    var state: HistoryStoreState { get }
    var lastError: String? { get }

    func save() throws
    func insert(_ record: TranscriptionRecord, at position: Int) throws
    func delete(_ record: TranscriptionRecord) throws
    func deleteAll() throws
    func purge(olderThan days: Int, now: Date) throws -> Int
}

extension HistoryStoring {
    func insert(_ record: TranscriptionRecord) throws {
        try insert(record, at: 0)
    }

    func purge(olderThan days: Int) throws -> Int {
        try purge(olderThan: days, now: Date())
    }
}

@MainActor
@Observable
final class HistoryStore: HistoryStoring {
    private(set) var records: [TranscriptionRecord] = []
    private(set) var state: HistoryStoreState = .missing
    private(set) var lastError: String?

    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// `directory` ist für Tests injizierbar; default = Application Support.
    init(directory: URL? = nil) {
        let dir = directory ?? DictionaryStore.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            state = .missing
            lastError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            records = try decoder.decode([TranscriptionRecord].self, from: data)
                .sorted { $0.date > $1.date }
            state = .loaded
            lastError = nil
        } catch {
            records = []
            let message = error.localizedDescription
            state = .unreadable(message)
            lastError = message
        }
    }

    func save() throws {
        try ensureWritable()
        try persist(records)
    }

    func insert(_ record: TranscriptionRecord, at position: Int = 0) throws {
        try ensureWritable()
        var updated = records
        updated.insert(record, at: min(position, updated.count))
        try persist(updated)
        records = updated
    }

    func delete(_ record: TranscriptionRecord) throws {
        try ensureWritable()
        let updated = records.filter { $0.id != record.id }
        try persist(updated)
        records = updated
        if let audioPath = record.audioPath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }

    /// Löscht sämtliche Protokolle inkl. Audio-Dateien.
    func deleteAll() throws {
        try ensureWritable()
        let removed = records
        try persist([])
        records = []
        for record in removed {
            if let audioPath = record.audioPath {
                try? FileManager.default.removeItem(atPath: audioPath)
            }
        }
    }

    /// Entfernt Protokolle (und deren Audio), die älter als `days` Tage sind.
    /// Liefert die Anzahl der entfernten Einträge.
    @discardableResult
    func purge(olderThan days: Int, now: Date = Date()) throws -> Int {
        try ensureWritable()
        guard days > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let stale = records.filter { $0.date < cutoff }
        guard !stale.isEmpty else { return 0 }
        let updated = records.filter { $0.date >= cutoff }
        try persist(updated)
        records = updated
        for record in stale {
            if let audioPath = record.audioPath {
                try? FileManager.default.removeItem(atPath: audioPath)
            }
        }
        return stale.count
    }

    private func ensureWritable() throws {
        if case .unreadable = state {
            throw HistoryStoreError.writeBlockedByUnreadableHistory(fileURL)
        }
    }

    private func persist(_ records: [TranscriptionRecord]) throws {
        let data: Data
        do {
            data = try encoder.encode(records)
        } catch {
            let message = error.localizedDescription
            lastError = message
            throw HistoryStoreError.encodingFailed(message)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            state = .loaded
            lastError = nil
        } catch {
            let message = error.localizedDescription
            lastError = message
            throw HistoryStoreError.writeFailed(fileURL, message)
        }
    }
}
