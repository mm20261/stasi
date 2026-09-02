import Foundation

// MARK: - DictionaryStore
// Lädt/speichert dictionary.json, beobachtet die Datei (Hand-Edits erscheinen live).

enum DictionaryStoreState: Equatable {
    case loading
    case loaded
    case unreadable(String)
}

private enum DictionaryLoadResult: Sendable {
    case missing
    case loaded(entries: [DictionaryEntry], ignoredLearned: [String])
    case unreadable(String)
}

private enum DictionaryWatcherResult: Sendable {
    case ownWrite
    case disk(DictionaryLoadResult)
}

/// Thread-sichere Brücke aus dem Dispatch-Source-Callback. Der Callback darf
/// keinen MainActor-isolierten Store-Zustand berühren und erzeugt keine Task.
private final class DictionaryWatcherMailbox: @unchecked Sendable {
    let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func signal() {
        continuation.yield(())
    }

    func finish() {
        continuation.finish()
    }

    func makeEventHandler() -> @Sendable () -> Void {
        { [weak self] in self?.signal() }
    }

    static func makeCancelHandler(fileDescriptor: Int32) -> @Sendable () -> Void {
        {
            if fileDescriptor >= 0 { close(fileDescriptor) }
        }
    }
}

@MainActor
@Observable
final class DictionaryStore {
    private(set) var entries: [DictionaryEntry] = []
    private(set) var ignoredLearned: [String] = []
    private(set) var lastError: String?
    private(set) var state: DictionaryStoreState = .loading

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
    @ObservationIgnored
    private var loadTask: Task<DictionaryLoadResult, Never>?
    @ObservationIgnored
    private var watcherTask: Task<Void, Never>?
    @ObservationIgnored
    private let watcherMailbox = DictionaryWatcherMailbox()
    private nonisolated let watcherQueue = DispatchQueue(
        label: "app.stasi.dictionary-watcher",
        qos: .utility
    )

    /// `directory` ist für Tests injizierbar; default = Application Support.
    /// `loadImmediately` ist ausschließlich der synchrone Kompatibilitätspfad
    /// für Store-Tests; die App lädt im Bootstrap asynchron.
    init(directory: URL? = nil, loadImmediately: Bool = false) {
        let dir = directory ?? Self.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dictionary.json")
        if loadImmediately {
            loadSynchronously(initial: true)
        }
    }

    // MARK: Laden / Speichern

    func load() {
        loadSynchronously(initial: false)
    }

    func loadAsync() async {
        guard state == .loading else { return }
        let task: Task<DictionaryLoadResult, Never>
        if let loadTask {
            task = loadTask
        } else {
            let url = fileURL
            let created = Task.detached(priority: .userInitiated) {
                Self.readDictionary(from: url)
            }
            loadTask = created
            task = created
        }
        let result = await task.value
        guard state == .loading else { return }
        loadTask = nil
        applyInitial(result)
    }

    private func loadSynchronously(initial: Bool) {
        let result = Self.readDictionary(from: fileURL)
        if initial {
            applyInitial(result)
        } else {
            applyReload(result)
        }
    }

    private nonisolated static func readDictionary(from fileURL: URL) -> DictionaryLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: fileURL)
            return decodeDictionary(data)
        } catch {
            return .unreadable("dictionary.json unlesbar: \(error.localizedDescription)")
        }
    }

    private nonisolated static func decodeDictionary(_ data: Data) -> DictionaryLoadResult {
        do {
            let file = try JSONDecoder().decode(DictionaryFile.self, from: data)
            return .loaded(
                entries: file.entries.sorted(by: DictionaryEntryOrdering.precedes),
                ignoredLearned: file.ignoredLearned ?? []
            )
        } catch {
            return .unreadable("dictionary.json unlesbar: \(error.localizedDescription)")
        }
    }

    private func applyInitial(_ result: DictionaryLoadResult) {
        switch result {
        case .missing:
            entries = seedEntries()
            ignoredLearned = []
            state = .loaded
            lastError = nil
            save()
            startWatcherLoop()
        case let .loaded(loadedEntries, loadedIgnored):
            applyLoaded(entries: loadedEntries, ignoredLearned: loadedIgnored)
            restartWatcher()
            startWatcherLoop()
        case .unreadable(let message):
            applyUnreadable(message)
        }
    }

    private func applyReload(_ result: DictionaryLoadResult) {
        switch result {
        case .missing:
            // Ein temporäres Delete/Rename beim atomaren Editor-Speichern darf
            // den bereits geladenen In-Memory-Stand nicht leeren oder neu seeden.
            break
        case let .loaded(loadedEntries, loadedIgnored):
            applyLoaded(entries: loadedEntries, ignoredLearned: loadedIgnored)
        case .unreadable(let message):
            applyUnreadable(message)
        }
        // Auch nach einem externen ungültigen Rename weiter beobachten, damit
        // eine anschließende Reparatur der Datei wieder übernommen wird.
        restartWatcher()
        if state == .loaded {
            startWatcherLoop()
        }
    }

    private func applyLoaded(entries loadedEntries: [DictionaryEntry],
                             ignoredLearned loadedIgnored: [String]) {
        entries = loadedEntries
        ignoredLearned = stableUnique(loadedIgnored)
        state = .loaded
        lastError = nil
    }

    private func applyUnreadable(_ message: String) {
        backupUnreadableFileIfNeeded()
        state = .unreadable(message)
        lastError = message
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
        entries.sort(by: DictionaryEntryOrdering.precedes)
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
        state == .loaded
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
            queue: watcherQueue
        )
        let mailbox = watcherMailbox
        // Beide Closures entstehen außerhalb der MainActor-isolierten Methode.
        // Der Event-Callback signalisiert nur und erzeugt keine Task.
        source.setEventHandler(handler: mailbox.makeEventHandler())
        source.setCancelHandler(
            handler: DictionaryWatcherMailbox.makeCancelHandler(fileDescriptor: watchFD)
        )
        source.resume()
        watcher = source
    }

    private func startWatcherLoop() {
        guard watcherTask == nil else { return }
        let events = watcherMailbox.stream
        watcherTask = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { return }
                // Kleine Verzögerung – Editoren schreiben in mehreren Schritten.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                await self.handleWatcherEvent()
            }
        }
    }

    private func handleWatcherEvent() async {
        let url = fileURL
        let ownData = lastWrittenData
        let result = await Task.detached(priority: .utility) {
            guard let currentData = try? Data(contentsOf: url) else {
                return DictionaryWatcherResult.disk(.missing)
            }
            if let ownData, currentData == ownData {
                return .ownWrite
            }
            return .disk(Self.decodeDictionary(currentData))
        }.value

        switch result {
        case .ownWrite:
            lastWrittenData = nil
            restartWatcher()
        case .disk(let diskResult):
            lastWrittenData = nil
            applyReload(diskResult)
        }
    }

    deinit {
        watcherTask?.cancel()
        watcherMailbox.finish()
        watcher?.cancel()
    }
}

enum DictionaryEntryOrdering {
    static func precedes(_ lhs: DictionaryEntry, _ rhs: DictionaryEntry) -> Bool {
        let lhsSource = lhs.matchSource.precomposedStringWithCanonicalMapping
        let rhsSource = rhs.matchSource.precomposedStringWithCanonicalMapping
        if lhsSource.count != rhsSource.count { return lhsSource.count > rhsSource.count }

        let lhsIsCorrection = lhs.type == .correction
        let rhsIsCorrection = rhs.type == .correction
        if lhsIsCorrection != rhsIsCorrection { return lhsIsCorrection }
        if lhsSource != rhsSource { return lhsSource < rhsSource }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
