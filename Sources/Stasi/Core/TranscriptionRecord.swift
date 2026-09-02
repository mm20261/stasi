import Foundation

enum DurationFormatter {
    static func minutesAndSeconds(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - TranscriptionRecord
// Ein abgeschlossener Diktat-Vorgang inkl. Korrektur-Nachweis, Metadaten & Audio.

struct TranscriptionRecord: Identifiable, Codable, Equatable, Sendable {
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
    /// Beim Erzeugen einmal berechnet; alte Dateien erhalten beim Dekodieren
    /// denselben Wert als Fallback und werden beim nächsten Speichern migriert.
    let wordCount: Int

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
        self.wordCount = Self.countWords(in: correctedText)
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, localeID, rawText, correctedText, corrections
        case durationSecs, targetApp, audioPath, polish, wordCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        localeID = try container.decode(String.self, forKey: .localeID)
        rawText = try container.decode(String.self, forKey: .rawText)
        correctedText = try container.decode(String.self, forKey: .correctedText)
        corrections = try container.decodeIfPresent(
            [AppliedCorrection].self,
            forKey: .corrections
        ) ?? []
        durationSecs = try container.decodeIfPresent(Double.self, forKey: .durationSecs) ?? 0
        targetApp = try container.decodeIfPresent(String.self, forKey: .targetApp) ?? ""
        audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath)
        polish = try container.decodeIfPresent(PolishSummary.self, forKey: .polish)
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount)
            ?? Self.countWords(in: correctedText)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(localeID, forKey: .localeID)
        try container.encode(rawText, forKey: .rawText)
        try container.encode(correctedText, forKey: .correctedText)
        try container.encode(corrections, forKey: .corrections)
        try container.encode(durationSecs, forKey: .durationSecs)
        try container.encode(targetApp, forKey: .targetApp)
        try container.encodeIfPresent(audioPath, forKey: .audioPath)
        try container.encodeIfPresent(polish, forKey: .polish)
        try container.encode(wordCount, forKey: .wordCount)
    }

    private static func countWords(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
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
    case loading
    case missing
    case loaded
    case unreadable(String)
}

enum HistoryStoreError: LocalizedError, Sendable {
    case stillLoading
    case writeBlockedByUnreadableHistory(URL)
    case encodingFailed(String)
    case writeFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .stillLoading:
            return L10n.text("history.error.notLoaded")
        case .writeBlockedByUnreadableHistory(let url):
            return L10n.text("history.error.unreadable", url.path)
        case .encodingFailed(let message):
            return L10n.text("history.error.encoding", message)
        case .writeFailed(let url, let message):
            return L10n.text("history.error.write", url.path, message)
        }
    }
}

private enum HistoryLoadResult: Sendable {
    case missing
    case loaded(
        records: [TranscriptionRecord],
        skipped: Int,
        declaredAudioPaths: Set<String>
    )
    case unreadable(message: String, invalidJSON: Bool)
}

/// Serialisiert komplette Mutationen über Actor-Reentranz hinweg. Dadurch
/// sieht jeder schnelle Folgeaufruf den bereits geschriebenen MainActor-Stand.
private actor HistoryPersistenceCoordinator {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            locked = false
            return
        }
        waiters.removeFirst().resume()
    }

    func persist(_ records: [TranscriptionRecord], to fileURL: URL) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(HistoryFile(records: records))
        } catch {
            throw HistoryStoreError.encodingFailed(error.localizedDescription)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw HistoryStoreError.writeFailed(fileURL, error.localizedDescription)
        }
    }
}

@MainActor
protocol HistoryStoring: AnyObject {
    var records: [TranscriptionRecord] { get }
    var state: HistoryStoreState { get }
    var lastError: String? { get }

    func loadAsync() async
    func save() async throws
    func insert(_ record: TranscriptionRecord, at position: Int) async throws
    func delete(_ record: TranscriptionRecord) async throws
    func deleteAll() async throws
    func purge(olderThan days: Int, now: Date) async throws -> Int
}

extension HistoryStoring {
    func insert(_ record: TranscriptionRecord) async throws {
        try await insert(record, at: 0)
    }

    func purge(olderThan days: Int) async throws -> Int {
        try await purge(olderThan: days, now: Date())
    }
}

@MainActor
@Observable
final class HistoryStore: HistoryStoring {
    private(set) var records: [TranscriptionRecord] = []
    private(set) var state: HistoryStoreState = .loading
    private(set) var lastError: String?

    private let fileURL: URL
    private let audioDirectory: URL
    private let persistence = HistoryPersistenceCoordinator()
    private var hasBackedUpUnreadableFile = false
    @ObservationIgnored private var loadTask: Task<HistoryLoadResult, Never>?

    /// `directory` ist für Tests injizierbar; default = Application Support.
    /// `loadImmediately` hält synchrone Store-Tests kompakt; die App nutzt den
    /// nicht-blockierenden Standardwert und startet das Laden im Bootstrap.
    init(directory: URL? = nil, loadImmediately: Bool = false) {
        let dir = directory ?? DictionaryStore.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        audioDirectory = dir.appendingPathComponent("audio", isDirectory: true)
        if loadImmediately {
            loadSynchronously()
        }
    }

    /// Expliziter synchroner Reload für bestehende Store-Tests und Diagnosepfade.
    func load() {
        loadSynchronously()
    }

    func loadAsync() async {
        guard state == .loading else { return }
        let task: Task<HistoryLoadResult, Never>
        if let loadTask {
            task = loadTask
        } else {
            let url = fileURL
            let created = Task.detached(priority: .userInitiated) {
                Self.readHistory(from: url)
            }
            loadTask = created
            task = created
        }
        let result = await task.value
        guard state == .loading else { return }
        loadTask = nil
        apply(result)
    }

    private func loadSynchronously() {
        state = .loading
        apply(Self.readHistory(from: fileURL))
    }

    private nonisolated static func readHistory(from fileURL: URL) -> HistoryLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let declaredAudioPaths = audioPathsDeclaredInFile(data)
            let decoded: (records: [TranscriptionRecord], skipped: Int)
            let decoder = JSONDecoder()
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
            return .loaded(
                records: decoded.records.sorted { $0.date > $1.date },
                skipped: decoded.skipped,
                declaredAudioPaths: declaredAudioPaths
            )
        } catch {
            let invalidJSON = ((try? Data(contentsOf: fileURL)).flatMap { data in
                try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            }) == nil
            return .unreadable(message: error.localizedDescription, invalidJSON: invalidJSON)
        }
    }

    private func apply(_ result: HistoryLoadResult) {
        switch result {
        case .missing:
            records = []
            state = .missing
            lastError = nil
        case let .loaded(loadedRecords, skipped, declaredAudioPaths):
            records = loadedRecords
            state = .loaded
            if skipped > 0 {
                let message = L10n.text(
                    skipped == 1 ? "history.warning.skipped.one" : "history.warning.skipped.many",
                    skipped
                )
                lastError = message
                DebugLog.log("STASI-HISTORY: \(message)")
                // Übersprungene Records fehlen beim nächsten Schreiben; Original sichern.
                backupUnreadableFileOnce()
            } else {
                lastError = nil
            }
            sweepOrphanedAudio(protecting: declaredAudioPaths)
        case let .unreadable(message, invalidJSON):
            records = []
            if invalidJSON { backupUnreadableFileOnce() }
            state = .unreadable(message)
            lastError = message
        }
    }

    func save() async throws {
        await persistence.acquire()
        do {
            try ensureWritable()
            try await persistLocked(records)
            await persistence.release()
        } catch {
            await persistence.release()
            throw error
        }
    }

    func insert(_ record: TranscriptionRecord, at position: Int = 0) async throws {
        await persistence.acquire()
        do {
            try ensureWritable()
            var updated = records
            updated.insert(record, at: min(position, updated.count))
            try await persistLocked(updated)
            records = updated
            await persistence.release()
        } catch {
            await persistence.release()
            throw error
        }
    }

    func delete(_ record: TranscriptionRecord) async throws {
        await persistence.acquire()
        do {
            try ensureWritable()
            let updated = records.filter { $0.id != record.id }
            try await persistLocked(updated)
            records = updated
            if let audioPath = record.audioPath {
                try? FileManager.default.removeItem(atPath: audioPath)
            }
            sweepOrphanedAudio()
            await persistence.release()
        } catch {
            await persistence.release()
            throw error
        }
    }

    /// Löscht sämtliche Protokolle inkl. Audio-Dateien.
    func deleteAll() async throws {
        await persistence.acquire()
        do {
            try ensureWritable()
            let removed = records
            try await persistLocked([])
            records = []
            for record in removed {
                if let audioPath = record.audioPath {
                    try? FileManager.default.removeItem(atPath: audioPath)
                }
            }
            sweepOrphanedAudio()
            await persistence.release()
        } catch {
            await persistence.release()
            throw error
        }
    }

    /// Entfernt Protokolle (und deren Audio), die älter als `days` Tage sind.
    /// Liefert die Anzahl der entfernten Einträge.
    @discardableResult
    func purge(olderThan days: Int, now: Date = Date()) async throws -> Int {
        await persistence.acquire()
        do {
            try ensureWritable()
            guard days > 0 else {
                await persistence.release()
                return 0
            }
            let cutoff = RetentionCutoff.date(daysBack: days, calendar: .current, now: now)
            let stale = records.filter { $0.date < cutoff }
            guard !stale.isEmpty else {
                await persistence.release()
                return 0
            }
            let updated = records.filter { $0.date >= cutoff }
            try await persistLocked(updated)
            records = updated
            for record in stale {
                if let audioPath = record.audioPath {
                    try? FileManager.default.removeItem(atPath: audioPath)
                }
            }
            sweepOrphanedAudio()
            await persistence.release()
            return stale.count
        } catch {
            await persistence.release()
            throw error
        }
    }

    private func ensureWritable() throws {
        if state == .loading {
            throw HistoryStoreError.stillLoading
        }
        if case .unreadable = state {
            throw HistoryStoreError.writeBlockedByUnreadableHistory(fileURL)
        }
    }

    private func persistLocked(_ records: [TranscriptionRecord]) async throws {
        do {
            try await persistence.persist(records, to: fileURL)
            state = .loaded
            lastError = nil
        } catch let error as HistoryStoreError {
            let message = error.localizedDescription
            lastError = message
            throw error
        } catch {
            let message = error.localizedDescription
            lastError = message
            throw HistoryStoreError.writeFailed(fileURL, message)
        }
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

    private nonisolated static func audioPathsDeclaredInFile(_ data: Data) -> Set<String> {
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
