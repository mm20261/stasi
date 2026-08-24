import Foundation

// MARK: - DictionaryStore
// Lädt/speichert dictionary.json, beobachtet die Datei (Hand-Edits erscheinen live).

@MainActor
@Observable
final class DictionaryStore {
    private(set) var entries: [DictionaryEntry] = []
    private(set) var lastError: String?

    static let appSupportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Stasi", isDirectory: true)

    let fileURL: URL
    private nonisolated(unsafe) var watcher: DispatchSourceFileSystemObject?
    private nonisolated(unsafe) var watchFD: Int32 = -1

    /// `directory` ist für Tests injizierbar; default = Application Support.
    init(directory: URL? = nil) {
        let dir = directory ?? Self.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dictionary.json")
        load()
    }

    // MARK: Laden / Speichern

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = seedEntries()
            save()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try JSONDecoder().decode(DictionaryFile.self, from: data)
            entries = file.entries.sorted { $0.matchSource.count > $1.matchSource.count }
            lastError = nil
        } catch {
            lastError = "dictionary.json unlesbar: \(error.localizedDescription)"
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(DictionaryFile(entries: entries))
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
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
        entries.insert(entry, at: 0)
        resort()
        save()
    }

    func update(_ entry: DictionaryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        resort()
        save()
    }

    func delete(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Auto-gelernt → Begriffe übernehmen
    func promote(_ entry: DictionaryEntry) {
        guard entry.type == .learned else { return }
        var word = DictionaryEntry(type: .word, value: entry.value)
        word.note = entry.note
        entries.removeAll { $0.id == entry.id }
        entries.insert(word, at: 0)
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

    // MARK: File-Watching

    private func restartWatcher() {
        watcher?.cancel()
        if watchFD >= 0 { close(watchFD); watchFD = -1 }
        watchFD = open(fileURL.path, O_EVTONLY)
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
                self?.load()
                self?.restartWatcher()
            }
        }
        source.setCancelHandler { [watchFD] in
            if watchFD >= 0 { close(watchFD) }
        }
        source.resume()
        watcher = source
    }

    deinit {
        watcher?.cancel()
        if watchFD >= 0 { close(watchFD) }
    }
}
