import XCTest
@testable import Stasi

// MARK: - DictionaryStore (CRUD, Persistenz, Auto-gelernt)

@MainActor
final class DictionaryStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: DictionaryStore!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-artifacts", isDirectory: true)
            .appendingPathComponent("StoreTests-\(UUID().uuidString)", isDirectory: true)
        store = DictionaryStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSeedEntriesOnFirstLaunch() {
        // Erster Start legt Beispieleinträge an
        XCTAssertFalse(store.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testAddAndPersistRoundtrip() throws {
        let entry = DictionaryEntry(type: .word, value: "Supabase", note: "Datenbank")
        store.add(entry)

        // Frische Instanz auf demselben Verzeichnis = Persistenz-Check
        let reloaded = DictionaryStore(directory: tempDir)
        XCTAssertTrue(reloaded.entries.contains { $0.value == "Supabase" && $0.note == "Datenbank" })
    }

    func testDelete() {
        let entry = DictionaryEntry(type: .word, value: "Testwort")
        store.add(entry)
        store.delete(entry)
        XCTAssertFalse(store.entries.contains { $0.id == entry.id })

        let reloaded = DictionaryStore(directory: tempDir)
        XCTAssertFalse(reloaded.entries.contains { $0.value == "Testwort" })
    }

    func testUpdate() {
        let entry = DictionaryEntry(type: .word, value: "Alter Begriff")
        store.add(entry)
        var updated = entry
        updated.value = "Neuer Begriff"
        store.update(updated)

        XCTAssertTrue(store.entries.contains { $0.value == "Neuer Begriff" })
        XCTAssertFalse(store.entries.contains { $0.value == "Alter Begriff" })
    }

    func testPromoteLearnedToWord() {
        let learned = DictionaryEntry(type: .learned, value: "Kubernetes", note: "3× DIKTIERT")
        store.add(learned)
        store.promote(learned)

        XCTAssertFalse(store.entries.contains { $0.id == learned.id })
        XCTAssertTrue(store.entries.contains { $0.type == .word && $0.value == "Kubernetes" })
    }

    func testPromoteNonLearnedIsNoOp() {
        let word = DictionaryEntry(type: .word, value: "Schon da")
        store.add(word)
        store.promote(word)
        XCTAssertTrue(store.entries.contains { $0.id == word.id })
    }

    func testJSONFileIsHandEditable() throws {
        store.add(DictionaryEntry(type: .word, value: "Handedit"))
        let data = try Data(contentsOf: store.fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let entries = json?["entries"] as? [[String: Any]]
        XCTAssertNotNil(entries)
        XCTAssertTrue(entries?.contains { ($0["value"] as? String) == "Handedit" } ?? false)
    }

    func testMergeLearnedDeduplicatesAndUpdatesNote() {
        let existing = DictionaryEntry(type: .learned, value: "Frobulator", note: "2× diktiert")
        store.add(existing)

        store.mergeLearned([
            DictionaryEntry(type: .learned, value: "frobulator", note: "3× diktiert"),
            DictionaryEntry(type: .learned, value: "Anthropic", note: "4× diktiert"),
            DictionaryEntry(type: .learned, value: "Neologismus", note: "2× diktiert"),
            DictionaryEntry(type: .learned, value: "NEOLOGISMUS", note: "2× diktiert"),
        ])

        let frobulator = store.entries.filter {
            $0.matchSource.caseInsensitiveCompare("Frobulator") == .orderedSame
        }
        XCTAssertEqual(frobulator.count, 1)
        XCTAssertEqual(frobulator.first?.note, "3× diktiert")
        XCTAssertEqual(store.entries.filter {
            $0.matchSource.caseInsensitiveCompare("Neologismus") == .orderedSame
        }.count, 1)
        XCTAssertEqual(store.entries.filter {
            $0.type == .learned && $0.matchSource.caseInsensitiveCompare("Anthropic") == .orderedSame
        }.count, 0)
    }

    func testIgnoreLearnedPersists() {
        let learned = DictionaryEntry(type: .learned, value: "Frobulator", note: "2× diktiert")
        store.add(learned)

        store.ignoreLearned(learned)

        XCTAssertFalse(store.entries.contains { $0.id == learned.id })
        XCTAssertEqual(store.ignoredLearned, ["frobulator"])
        store.mergeLearned([
            DictionaryEntry(type: .learned, value: "FROBULATOR", note: "3× diktiert"),
        ])
        XCTAssertFalse(store.entries.contains {
            $0.matchSource.caseInsensitiveCompare("Frobulator") == .orderedSame
        })
        let reloaded = DictionaryStore(directory: tempDir)
        XCTAssertFalse(reloaded.entries.contains { $0.id == learned.id })
        XCTAssertEqual(reloaded.ignoredLearned, ["frobulator"])
    }

    func testOldDictionaryWithoutIgnoredLearnedLoads() throws {
        let legacyDirectory = tempDir.appendingPathComponent("legacy-dictionary", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let entry = DictionaryEntry(type: .word, value: "Legacy")
        let encodedEntry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry))
        let legacyData = try JSONSerialization.data(withJSONObject: ["entries": [encodedEntry]])
        try legacyData.write(to: legacyDirectory.appendingPathComponent("dictionary.json"))

        let reloaded = DictionaryStore(directory: legacyDirectory)

        XCTAssertEqual(reloaded.entries.map(\.value), ["Legacy"])
        XCTAssertTrue(reloaded.ignoredLearned.isEmpty)
    }
}

// MARK: - HistoryStore

@MainActor
final class HistoryStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: HistoryStore!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-artifacts", isDirectory: true)
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = HistoryStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeRecord(text: String = "Hallo Welt", date: Date = Date()) -> TranscriptionRecord {
        TranscriptionRecord(
            date: date,
            localeID: "de_DE",
            rawText: text,
            correctedText: text,
            corrections: [],
            durationSecs: 3.5,
            targetApp: "Notizen"
        )
    }

    func testMissingHistoryIsNotAnError() {
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(store.state, .missing)
        XCTAssertNil(store.lastError)
    }

    func testValidHistoryIsLoaded() throws {
        let record = makeRecord(text: "Gültiger Verlauf")
        let data = try JSONEncoder().encode([record])
        try data.write(to: tempDir.appendingPathComponent("history.json"))

        let reloaded = HistoryStore(directory: tempDir)

        XCTAssertEqual(reloaded.records.map(\.correctedText), ["Gültiger Verlauf"])
        XCTAssertEqual(reloaded.state, .loaded)
        XCTAssertNil(reloaded.lastError)
    }

    func testMalformedHistoryIsUnreadableAndPreserved() throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)

        let reloaded = HistoryStore(directory: tempDir)

        guard case .unreadable = reloaded.state else {
            return XCTFail("Beschädigte Historie muss als unlesbar markiert werden")
        }
        XCTAssertNotNil(reloaded.lastError)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInsertCannotOverwriteUnreadableHistory() throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let reloaded = HistoryStore(directory: tempDir)

        XCTAssertThrowsError(try reloaded.insert(makeRecord())) { error in
            XCTAssertTrue(error is HistoryStoreError)
        }
        XCTAssertTrue(reloaded.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSaveCannotOverwriteUnreadableHistory() throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let reloaded = HistoryStore(directory: tempDir)

        XCTAssertThrowsError(try reloaded.save())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDeleteCannotMutateUnreadableHistoryOrRemoveAudio() throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let audioURL = tempDir.appendingPathComponent("preserve.wav")
        try Data("audio".utf8).write(to: audioURL)
        var record = makeRecord()
        record.audioPath = audioURL.path
        let reloaded = HistoryStore(directory: tempDir)

        XCTAssertThrowsError(try reloaded.delete(record))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDeleteAllCannotOverwriteUnreadableHistory() throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let reloaded = HistoryStore(directory: tempDir)

        XCTAssertThrowsError(try reloaded.deleteAll())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testPurgeCannotOverwriteUnreadableHistory() throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let reloaded = HistoryStore(directory: tempDir)

        XCTAssertThrowsError(try reloaded.purge(olderThan: 7))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInsertAndPersistRoundtrip() throws {
        let record = makeRecord(text: "Persistenz-Test")
        try store.insert(record)

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertEqual(reloaded.records.first?.correctedText, "Persistenz-Test")
        XCTAssertEqual(reloaded.records.first?.durationSecs ?? 0, 3.5, accuracy: 0.001)
        XCTAssertEqual(reloaded.records.first?.targetApp, "Notizen")
    }

    func testOldHistoryWithoutPolishSummaryStillLoads() throws {
        let historyDirectory = tempDir.appendingPathComponent("legacy-history", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory,
                                                withIntermediateDirectories: true)
        let record = makeRecord(text: "Altes Protokoll")
        let encoded = try JSONEncoder().encode([record])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        XCTAssertNil(json.first?["polish"])
        try encoded.write(to: historyDirectory.appendingPathComponent("history.json"))

        let reloaded = HistoryStore(directory: historyDirectory)

        XCTAssertEqual(reloaded.records.first?.correctedText, "Altes Protokoll")
        XCTAssertNil(reloaded.records.first?.polish)
    }

    func testInsertAtTop() throws {
        let first = makeRecord(text: "erster")
        let second = makeRecord(text: "zweiter")
        try store.insert(first)
        try store.insert(second)

        XCTAssertEqual(store.records.first?.correctedText, "zweiter")
        XCTAssertEqual(store.records.count, 2)
    }

    func testDeleteRemovesAudioFile() throws {
        let audioFile = tempDir.appendingPathComponent("test.wav")
        try Data([0x00]).write(to: audioFile)
        var record = makeRecord()
        record.audioPath = audioFile.path
        try store.insert(record)
        try store.delete(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertTrue(store.records.isEmpty)
    }

    func testWordCount() {
        let record = makeRecord(text: "eins zwei drei vier\nfünf")
        XCTAssertEqual(record.wordCount, 5)
    }

    // MARK: Retention (Aufbewahrungsdauer)

    func testDeleteAllRemovesRecordsAndAudio() throws {
        let audioFile = tempDir.appendingPathComponent("a.wav")
        try Data([0x00]).write(to: audioFile)
        var r = makeRecord(text: "mit Audio")
        r.audioPath = audioFile.path
        try store.insert(r)
        try store.insert(makeRecord(text: "ohne Audio"))

        try store.deleteAll()

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertTrue(reloaded.records.isEmpty)
    }

    func testPurgeRemovesOnlyOldRecords() throws {
        let now = Date()
        let old = makeRecord(text: "alt", date: now.addingTimeInterval(-20 * 86_400))
        let recent = makeRecord(text: "neu", date: now)
        try store.insert(old)
        try store.insert(recent)

        let purged = try store.purge(olderThan: 7, now: now)

        XCTAssertEqual(purged, 1)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.correctedText, "neu")
    }

    func testPurgeRemovesAudioFilesOfPurgedRecords() throws {
        let now = Date()
        let audioFile = tempDir.appendingPathComponent("old.wav")
        try Data([0x00]).write(to: audioFile)
        var old = makeRecord(text: "alt", date: now.addingTimeInterval(-10 * 86_400))
        old.audioPath = audioFile.path
        try store.insert(old)

        try store.purge(olderThan: 7, now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
    }

    func testPurgeKeepsEverythingWhenWithinRetention() throws {
        let now = Date()
        try store.insert(makeRecord(text: "frisch", date: now.addingTimeInterval(-3 * 86_400)))
        let purged = try store.purge(olderThan: 7, now: now)
        XCTAssertEqual(purged, 0)
        XCTAssertEqual(store.records.count, 1)
    }
}
