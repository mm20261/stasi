import Foundation

// MARK: - DictionaryStore
// Lädt/speichert dictionary.json, beobachtet die Datei (Hand-Edits erscheinen live).

enum DictionaryStoreState: Equatable {
    case loaded
    case unreadable(String)
}

@MainActor
@Observable
final class DictionaryStore {
    private(set) var entries: [DictionaryEntry] = []
    private(set) var ignoredLearned: [String] = []
    private(set) var lastError: String?
    private(set) var state: DictionaryStoreState = .loaded

    static let appSupportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Stasi", isDirectory: true)

    let fileURL: URL
    @ObservationIgnored
    private nonisolated(unsafe) var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored
    private var lastWrittenData: Data?
    @ObservationIgnored
    private var hasBackedUpUnreadableFile = false

    /// `directory` ist für Tests injizierbar; default = Application Support.
    init(directory: URL? = nil) {
        let dir = directory ?? Self.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dictionary.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            load()
        } else if entries.isEmpty {
            entries = seedEntries()
            save()
        }
        restartWatcher()
    }

    // MARK: Laden / Speichern

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try JSONDecoder().decode(DictionaryFile.self, from: data)
            entries = file.entries.sorted { $0.matchSource.count > $1.matchSource.count }
            ignoredLearned = stableUnique(file.ignoredLearned ?? [])
            state = .loaded
            lastError = nil
        } catch {
            let message = "dictionary.json unlesbar: \(error.localizedDescription)"
            backupUnreadableFileIfNeeded()
            state = .unreadable(message)
            lastError = message
        }
    }

    func save() {
        guard ensureWritable() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(DictionaryFile(
                entries: entries,
                ignoredLearned: ignoredLearned
            ))
            lastWrittenData = data
            try data.write(to: fileURL, options: .atomic)
            state = .loaded
            lastError = nil
        } catch {
            lastWrittenData = nil
            lastError = "Schreiben fehlgeschlagen: \(error.localizedDescription)"
        }
        restartWatcher()
    }

    /// Beispiel-Einträge für den ersten Start.
    private func seedEntries() -> [DictionaryEntry] {
        [
            DictionaryEntry(type: .word, value: "Anthropic", note: "Firmenname"),
            DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code",
                            note: "CLI-Tool von Anthropic"),
        ]
    }

    // MARK: CRUD

    func add(_ entry: DictionaryEntry) {
        guard ensureWritable() else { return }
        entries.insert(entry, at: 0)
        resort()
        save()
    }

    func update(_ entry: DictionaryEntry) {
        guard ensureWritable() else { return }
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        resort()
        save()
    }

    func delete(_ entry: DictionaryEntry) {
        guard ensureWritable() else { return }
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Auto-gelernt → Begriffe übernehmen
    func promote(_ entry: DictionaryEntry) {
        guard ensureWritable() else { return }
        guard entry.type == .learned else { return }
        var word = DictionaryEntry(type: .word, value: entry.value)
        word.note = entry.note
        entries.removeAll { $0.id == entry.id }
        entries.insert(word, at: 0)
        save()
    }

    /// Führt einen Scout-Lauf zusammen und schreibt höchstens einmal auf die Platte.
    func mergeLearned(_ candidates: [DictionaryEntry]) {
        guard ensureWritable() else { return }
        let ignored = Set(ignoredLearned.map(normalized))
        var occupied = Set(entries.flatMap {
            [normalized($0.matchSource), normalized($0.replacementTarget)]
        }.filter { !$0.isEmpty })
        var changed = false

        for candidate in candidates where candidate.type == .learned {
            let key = normalized(candidate.value)
            guard !key.isEmpty, !ignored.contains(key) else { continue }

            if let index = entries.firstIndex(where: {
                $0.type == .learned && normalized($0.value) == key
            }) {
                if entries[index].note != candidate.note {
                    entries[index].note = candidate.note
                    changed = true
                }
                continue
            }

            guard !occupied.contains(key) else { continue }
            var learned = candidate
            learned.type = .learned
            entries.append(learned)
            occupied.insert(key)
            changed = true
        }

        guard changed else { return }
        resort()
        save()
    }

    /// Verwirft einen Vorschlag dauerhaft, damit der Scout ihn nicht erneut anlegt.
    func ignoreLearned(_ entry: DictionaryEntry) {
        guard ensureWritable() else { return }
        guard entry.type == .learned else { return }
        let key = normalized(entry.value)
        let oldCount = entries.count
        entries.removeAll { $0.id == entry.id }
        let removed = entries.count != oldCount
        let addedToIgnoreList: Bool
        if !key.isEmpty && !ignoredLearned.contains(where: { normalized($0) == key }) {
            ignoredLearned.append(key)
            addedToIgnoreList = true
        } else {
            addedToIgnoreList = false
        }
        guard removed || addedToIgnoreList else { return }
        save()
    }

    /// Längste Quellen zuerst (Match-Priorität).
    private func resort() {
        entries.sort {
            ($0.type == .correction ? 1 : 0, $0.matchSource) >
            ($1.type == .correction ? 1 : 0, $1.matchSource)
        }
        entries.sort { $0.matchSource.count > $1.matchSource.count }
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let key = normalized(value)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return key
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func ensureWritable() -> Bool {
        if case .unreadable = state { return false }
        return true
    }

    private func backupUnreadableFileIfNeeded() {
        guard !hasBackedUpUnreadableFile else { return }
        hasBackedUpUnreadableFile = true
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("dictionary.corrupt-\(timestamp).json")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        } catch {
            DebugLog.log("STASI-DICTIONARY: Sicherung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: File-Watching

    private func restartWatcher() {
        watcher?.cancel()
        watcher = nil
        let watchFD = open(fileURL.path, O_EVTONLY)
        guard watchFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchFD,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Kleine Verzögerung – Editoren schreiben in mehreren Schritten.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.handleWatcherEvent()
            }
        }
        source.setCancelHandler { [watchFD] in
            if watchFD >= 0 { close(watchFD) }
        }
        source.resume()
        watcher = source
    }

    private func handleWatcherEvent() {
        if let ownData = lastWrittenData,
           let currentData = try? Data(contentsOf: fileURL),
           currentData == ownData {
            lastWrittenData = nil
            restartWatcher()
            return
        }
        lastWrittenData = nil
        load()
        restartWatcher()
    }

    deinit {
        watcher?.cancel()
    }
}
