import Foundation

enum DurationFormatter {
    static func minutesAndSeconds(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

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

private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct HistoryFile: Codable {
    let version: Int
    let records: [TranscriptionRecord]
    let skippedRecords: Int

    init(version: Int = 1, records: [TranscriptionRecord]) {
        self.version = version
        self.records = records
        skippedRecords = 0
    }

    private enum CodingKeys: String, CodingKey {
        case version, records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let elements = try container.decode(
            [FailableDecodable<TranscriptionRecord>].self,
            forKey: .records
        )
        records = elements.compactMap(\.value)
        skippedRecords = elements.count - records.count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(records, forKey: .records)
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
    private let audioDirectory: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var hasBackedUpUnreadableFile = false

    /// `directory` ist für Tests injizierbar; default = Application Support.
    init(directory: URL? = nil) {
        let dir = directory ?? DictionaryStore.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        audioDirectory = dir.appendingPathComponent("audio", isDirectory: true)
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
            let declaredAudioPaths = audioPathsDeclaredInFile(data)
            let decoded: (records: [TranscriptionRecord], skipped: Int)
            if let file = try? decoder.decode(HistoryFile.self, from: data) {
                decoded = (file.records, file.skippedRecords)
            } else {
                let elements = try decoder.decode(
                    [FailableDecodable<TranscriptionRecord>].self,
                    from: data
                )
                decoded = (
                    elements.compactMap(\.value),
                    elements.filter { $0.value == nil }.count
                )
            }
            records = decoded.records.sorted { $0.date > $1.date }
            state = .loaded
            if decoded.skipped > 0 {
                let message = decoded.skipped == 1
                    ? "1 beschädigtes Protokoll wurde übersprungen."
                    : "\(decoded.skipped) beschädigte Protokolle wurden übersprungen."
                lastError = message
                DebugLog.log("STASI-HISTORY: \(message)")
                // Übersprungene Records fehlen beim nächsten Schreiben; Original sichern.
                backupUnreadableFileOnce()
            } else {
                lastError = nil
            }
            sweepOrphanedAudio(protecting: declaredAudioPaths)
        } catch {
            records = []
            let message = error.localizedDescription
            backupInvalidJSONIfNeeded()
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
        sweepOrphanedAudio()
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
        sweepOrphanedAudio()
    }

    /// Entfernt Protokolle (und deren Audio), die älter als `days` Tage sind.
    /// Liefert die Anzahl der entfernten Einträge.
    @discardableResult
    func purge(olderThan days: Int, now: Date = Date()) throws -> Int {
        try ensureWritable()
        guard days > 0 else { return 0 }
        let cutoff = RetentionCutoff.date(daysBack: days, calendar: .current, now: now)
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
        sweepOrphanedAudio()
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
            data = try encoder.encode(HistoryFile(records: records))
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

    private func backupInvalidJSONIfNeeded() {
        guard let data = try? Data(contentsOf: fileURL),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) == nil
        else { return }
        backupUnreadableFileOnce()
    }

    private func backupUnreadableFileOnce() {
        guard !hasBackedUpUnreadableFile,
              FileManager.default.fileExists(atPath: fileURL.path) else { return }
        hasBackedUpUnreadableFile = true
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("history.corrupt-\(timestamp).json")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        } catch {
            DebugLog.log("STASI-HISTORY: Sicherung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func audioPathsDeclaredInFile(_ data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) else { return [] }
        let rawRecords: [[String: Any]]
        if let legacy = root as? [[String: Any]] {
            rawRecords = legacy
        } else if let envelope = root as? [String: Any],
                  let records = envelope["records"] as? [[String: Any]] {
            rawRecords = records
        } else {
            return []
        }
        return Set(rawRecords.compactMap { record in
            (record["audioPath"] as? String).map {
                URL(fileURLWithPath: $0).standardizedFileURL.path
            }
        })
    }

    private func sweepOrphanedAudio(protecting additionalPaths: Set<String> = []) {
        guard state == .loaded,
              FileManager.default.fileExists(atPath: audioDirectory.path) else { return }
        let referencedPaths = Set(records.compactMap { record in
            record.audioPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        }).union(additionalPaths)
        do {
            let candidates = try FileManager.default.contentsOfDirectory(
                at: audioDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for candidate in candidates {
                let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true,
                      !referencedPaths.contains(candidate.standardizedFileURL.path) else {
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: candidate)
                } catch {
                    DebugLog.log(
                        "STASI-HISTORY: Verwaiste Audiodatei konnte nicht gelöscht werden: "
                        + error.localizedDescription
                    )
                }
            }
        } catch {
            DebugLog.log("STASI-HISTORY: Audio-Sweep fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
