import XCTest
@testable import Stasi

// MARK: - DictionaryStore (CRUD, Persistenz, Auto-gelernt)

@MainActor
final class DictionaryStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: DictionaryStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stasi-tests-\(UUID().uuidString)", isDirectory: true)
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
}

// MARK: - HistoryStore

@MainActor
final class HistoryStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: HistoryStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stasi-tests-\(UUID().uuidString)", isDirectory: true)
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

    func testInsertAndPersistRoundtrip() {
        let record = makeRecord(text: "Persistenz-Test")
        store.insert(record)

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertEqual(reloaded.records.first?.correctedText, "Persistenz-Test")
        XCTAssertEqual(reloaded.records.first?.durationSecs ?? 0, 3.5, accuracy: 0.001)
        XCTAssertEqual(reloaded.records.first?.targetApp, "Notizen")
    }

    func testInsertAtTop() {
        let first = makeRecord(text: "erster")
        let second = makeRecord(text: "zweiter")
        store.insert(first)
        store.insert(second)

        XCTAssertEqual(store.records.first?.correctedText, "zweiter")
        XCTAssertEqual(store.records.count, 2)
    }

    func testDeleteRemovesAudioFile() throws {
        let audioFile = tempDir.appendingPathComponent("test.wav")
        try Data([0x00]).write(to: audioFile)
        var record = makeRecord()
        record.audioPath = audioFile.path
        store.insert(record)
        store.delete(record)

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
        store.insert(r)
        store.insert(makeRecord(text: "ohne Audio"))

        store.deleteAll()

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertTrue(reloaded.records.isEmpty)
    }

    func testPurgeRemovesOnlyOldRecords() {
        let now = Date()
        let old = makeRecord(text: "alt", date: now.addingTimeInterval(-20 * 86_400))
        let recent = makeRecord(text: "neu", date: now)
        store.insert(old)
        store.insert(recent)

        let purged = store.purge(olderThan: 7, now: now)

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
        store.insert(old)

        store.purge(olderThan: 7, now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
    }

    func testPurgeKeepsEverythingWhenWithinRetention() {
        let now = Date()
        store.insert(makeRecord(text: "frisch", date: now.addingTimeInterval(-3 * 86_400)))
        let purged = store.purge(olderThan: 7, now: now)
        XCTAssertEqual(purged, 0)
        XCTAssertEqual(store.records.count, 1)
    }
}
