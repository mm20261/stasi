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
        store = DictionaryStore(directory: tempDir, loadImmediately: true)
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
        let reloaded = DictionaryStore(directory: tempDir, loadImmediately: true)
        XCTAssertTrue(reloaded.entries.contains { $0.value == "Supabase" && $0.note == "Datenbank" })
    }

    func testGleichlangeEintraegeBleibenDeterministischSortiert() {
        store.add(DictionaryEntry(type: .word, value: "Zulu"))
        store.add(DictionaryEntry(type: .correction, from: "Bravo", to: "B"))
        store.add(DictionaryEntry(type: .correction, from: "Alpha", to: "A"))

        let erwarteteReihenfolge = ["Alpha", "Bravo", "Zulu"]
        for _ in 0..<5 {
            store.load()
            let gleichlange = store.entries
                .filter { ["Alpha", "Bravo", "Zulu"].contains($0.matchSource) }
                .map(\.matchSource)
            XCTAssertEqual(gleichlange, erwarteteReihenfolge)
        }
    }

    func testDelete() {
        let entry = DictionaryEntry(type: .word, value: "Testwort")
        store.add(entry)
        store.delete(entry)
        XCTAssertFalse(store.entries.contains { $0.id == entry.id })

        let reloaded = DictionaryStore(directory: tempDir, loadImmediately: true)
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
        let reloaded = DictionaryStore(directory: tempDir, loadImmediately: true)
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

        let reloaded = DictionaryStore(directory: legacyDirectory, loadImmediately: true)

        XCTAssertEqual(reloaded.entries.map(\.value), ["Legacy"])
        XCTAssertTrue(reloaded.ignoredLearned.isEmpty)
    }

    func testKaputteDateiWirdGesichertUndNichtUeberschrieben() throws {
        let original = Data("{kaputt".utf8)
        try original.write(to: store.fileURL)

        store.load()
        store.save()
        store.add(DictionaryEntry(type: .word, value: "Darf nicht hinein"))

        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        guard case .unreadable = store.state else {
            return XCTFail("Die kaputte Wörterbuchdatei muss schreibgeschützt bleiben")
        }
        XCTAssertNotNil(store.lastError)
        let backups = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("dictionary.corrupt-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backups.first)), original)
    }

    func testFehlendeDateiBeimNachladenBehaeltBestehendeEintraege() throws {
        store.add(DictionaryEntry(type: .word, value: "Vercel"))
        store.add(DictionaryEntry(type: .word, value: "Supabase"))
        store.add(DictionaryEntry(type: .word, value: "PostHog"))
        XCTAssertEqual(store.entries.count, 5)

        try FileManager.default.removeItem(at: store.fileURL)
        store.load()

        XCTAssertEqual(store.entries.count, 5)
        XCTAssertTrue(store.entries.contains { $0.value == "Vercel" })
    }

    func testHandeintragOhneIDWirdGeladen() throws {
        let data = Data(#"{"entries":[{"type":"word","value":"Vercel"}]}"#.utf8)
        try data.write(to: store.fileURL)

        store.load()

        XCTAssertEqual(store.entries.map(\.value), ["Vercel"])
        XCTAssertNotNil(store.entries.first?.id)
    }

    func testUnbekannterTypUeberspringtNurBetroffenenEintrag() throws {
        let data = Data(#"{"entries":[{"type":"word","value":"Vercel"},{"type":"spaeter","value":"Zukunft"},{"type":"word","value":"Supabase"}]}"#.utf8)
        try data.write(to: store.fileURL)

        store.load()

        XCTAssertEqual(Set(store.entries.map(\.value)), ["Vercel", "Supabase"])
        XCTAssertEqual(store.state, .loaded)
    }

    func testWoerterbuchSchreibtSchemaVersionEins() throws {
        store.save()

        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: store.fileURL)
        ) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
    }

    func testMutationVorLadenIstNoOpUndDanachNormal() async throws {
        let directory = tempDir.appendingPathComponent("asynchron", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("dictionary.json")
        let existing = DictionaryEntry(type: .word, value: "Bestehend")
        let original = try JSONEncoder().encode(DictionaryFile(entries: [existing]))
        try original.write(to: url)

        let loading = DictionaryStore(directory: directory)
        loading.add(DictionaryEntry(type: .word, value: "Zu früh"))

        XCTAssertEqual(loading.state, .loading)
        XCTAssertTrue(loading.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)

        await loading.loadAsync()
        loading.add(DictionaryEntry(type: .word, value: "Nach Laden"))

        XCTAssertEqual(loading.state, .loaded)
        XCTAssertTrue(loading.entries.contains { $0.value == "Bestehend" })
        XCTAssertTrue(loading.entries.contains { $0.value == "Nach Laden" })
    }

    func testSeedingPassiertNurBeiFehlenderDateiNachErstemLaden() async throws {
        let missingDirectory = tempDir.appendingPathComponent("fehlend", isDirectory: true)
        let missing = DictionaryStore(directory: missingDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.fileURL.path))
        await missing.loadAsync()

        XCTAssertEqual(missing.state, .loaded)
        XCTAssertFalse(missing.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: missing.fileURL.path))

        let existingDirectory = tempDir.appendingPathComponent("vorhanden", isDirectory: true)
        try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
        let custom = DictionaryEntry(type: .word, value: "Nur dieser Eintrag")
        try JSONEncoder().encode(DictionaryFile(entries: [custom])).write(
            to: existingDirectory.appendingPathComponent("dictionary.json")
        )
        let existing = DictionaryStore(directory: existingDirectory)

        await existing.loadAsync()

        XCTAssertEqual(existing.entries.map(\.value), ["Nur dieser Eintrag"])
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
        store = HistoryStore(directory: tempDir, loadImmediately: true)
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

    func testInitBlockiertNichtUndLoadAsyncLiefertGrossenVerlauf() async throws {
        let records = (0..<20_000).map { index in
            makeRecord(text: "Protokoll \(index)", date: Date(timeIntervalSince1970: Double(index)))
        }
        try JSONEncoder().encode(records)
            .write(to: tempDir.appendingPathComponent("history.json"), options: .atomic)

        let start = ContinuousClock.now
        let loading = HistoryStore(directory: tempDir)
        let elapsed = start.duration(to: .now)

        XCTAssertLessThan(elapsed, .milliseconds(500))
        XCTAssertEqual(loading.state, .loading)
        XCTAssertTrue(loading.records.isEmpty)

        await loading.loadAsync()

        XCTAssertEqual(loading.state, .loaded)
        XCTAssertEqual(loading.records.count, 20_000)
    }

    func testInsertVorLadenWirftStillLoadingUndBewahrtDatei() async throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = try JSONEncoder().encode([makeRecord(text: "Vorhanden")])
        try original.write(to: url)
        let loading = HistoryStore(directory: tempDir)

        do {
            try await loading.insert(makeRecord(text: "Zu früh"))
            XCTFail("Einfügen muss während des Ladens fehlschlagen")
        } catch let error as HistoryStoreError {
            guard case .stillLoading = error else {
                return XCTFail("Erwartet stillLoading, erhalten: \(error)")
            }
        }

        XCTAssertTrue(loading.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testValidHistoryIsLoaded() throws {
        let record = makeRecord(text: "Gültiger Verlauf")
        let data = try JSONEncoder().encode([record])
        try data.write(to: tempDir.appendingPathComponent("history.json"))

        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        XCTAssertEqual(reloaded.records.map(\.correctedText), ["Gültiger Verlauf"])
        XCTAssertEqual(reloaded.state, .loaded)
        XCTAssertNil(reloaded.lastError)
    }

    func testMalformedHistoryIsUnreadableAndPreserved() throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)

        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        guard case .unreadable = reloaded.state else {
            return XCTFail("Beschädigte Historie muss als unlesbar markiert werden")
        }
        XCTAssertNotNil(reloaded.lastError)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testVollstaendigKaputteHistorieWirdGesichert() throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{nicht-json".utf8)
        try original.write(to: url)

        _ = HistoryStore(directory: tempDir, loadImmediately: true)

        let backups = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("history.corrupt-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backups.first)), original)
    }

    func testInsertCannotOverwriteUnreadableHistory() async throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        do {
            try await reloaded.insert(makeRecord())
            XCTFail("Einfügen muss bei unlesbarem Verlauf fehlschlagen")
        } catch {
            XCTAssertTrue(error is HistoryStoreError)
        }
        XCTAssertTrue(reloaded.records.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSaveCannotOverwriteUnreadableHistory() async throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        do {
            try await reloaded.save()
            XCTFail("Speichern muss bei unlesbarem Verlauf fehlschlagen")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDeleteCannotMutateUnreadableHistoryOrRemoveAudio() async throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let audioURL = tempDir.appendingPathComponent("preserve.wav")
        try Data("audio".utf8).write(to: audioURL)
        var record = makeRecord()
        record.audioPath = audioURL.path
        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        do {
            try await reloaded.delete(record)
            XCTFail("Löschen muss bei unlesbarem Verlauf fehlschlagen")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDeleteAllCannotOverwriteUnreadableHistory() async throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        do {
            try await reloaded.deleteAll()
            XCTFail("Alles löschen muss bei unlesbarem Verlauf fehlschlagen")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testPurgeCannotOverwriteUnreadableHistory() async throws {
        let url = tempDir.appendingPathComponent("history.json")
        let original = Data("{not-json".utf8)
        try original.write(to: url)
        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        do {
            _ = try await reloaded.purge(olderThan: 7)
            XCTFail("Retention muss bei unlesbarem Verlauf fehlschlagen")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInsertAndPersistRoundtrip() async throws {
        let record = makeRecord(text: "Persistenz-Test")
        try await store.insert(record)

        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)
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

        let reloaded = HistoryStore(directory: historyDirectory, loadImmediately: true)

        XCTAssertEqual(reloaded.records.first?.correctedText, "Altes Protokoll")
        XCTAssertNil(reloaded.records.first?.polish)
    }

    func testEinKaputtesProtokollVerwirftNichtDenRest() async throws {
        let records = [
            makeRecord(text: "Eins", date: Date(timeIntervalSince1970: 100)),
            makeRecord(text: "Kaputt", date: Date(timeIntervalSince1970: 200)),
            makeRecord(text: "Drei", date: Date(timeIntervalSince1970: 300)),
        ]
        let encoded = try JSONEncoder().encode(records)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[1]["date"] = "kein Datum"
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: tempDir.appendingPathComponent("history.json"))

        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        XCTAssertEqual(Set(reloaded.records.map(\.correctedText)), ["Eins", "Drei"])
        XCTAssertEqual(reloaded.state, .loaded)
        XCTAssertTrue(reloaded.lastError?.contains("1") == true)
        try await reloaded.insert(makeRecord(text: "Neu"))
        let backups = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { $0.hasPrefix("history.corrupt-") }
        XCTAssertEqual(backups.count, 1, "Original mit defektem Record muss gesichert sein")
    }

    func testAudioEinesUebersprungenenProtokollsBleibtErhalten() throws {
        let audioDirectory = tempDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audio = audioDirectory.appendingPathComponent("teilweise-lesbar.wav")
        try Data("audio".utf8).write(to: audio)
        var damaged = makeRecord(text: "Kaputtes Datum")
        damaged.audioPath = audio.path
        let encoded = try JSONEncoder().encode([damaged])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        json[0]["date"] = "kein Datum"
        try JSONSerialization.data(withJSONObject: json)
            .write(to: tempDir.appendingPathComponent("history.json"))

        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        XCTAssertEqual(reloaded.state, .loaded)
        XCTAssertTrue(reloaded.records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    func testUnbekanntePolishArtBleibtAlsFallbackLesbar() throws {
        let change = PolishChange(kind: .hesitation, count: 1, removed: "äh")
        let summary = PolishSummary(level: .standard, changes: [change])
        let record = TranscriptionRecord(
            date: Date(), localeID: "de_DE", rawText: "äh Hallo", correctedText: "Hallo",
            corrections: [], polish: summary
        )
        let encoded = try JSONEncoder().encode([record])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        var polish = try XCTUnwrap(json[0]["polish"] as? [String: Any])
        var changes = try XCTUnwrap(polish["changes"] as? [[String: Any]])
        changes[0]["kind"] = "zukuenftigeArt"
        polish["changes"] = changes
        json[0]["polish"] = polish
        try JSONSerialization.data(withJSONObject: json)
            .write(to: tempDir.appendingPathComponent("history.json"))

        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        XCTAssertEqual(reloaded.records.first?.polish?.changes.first?.kind, .unknown)
    }

    func testAltesArrayWirdBeimNaechstenSchreibenAufSchemaEinsMigriert() async throws {
        let legacy = try JSONEncoder().encode([makeRecord(text: "Alt")])
        let url = tempDir.appendingPathComponent("history.json")
        try legacy.write(to: url)
        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)

        try await reloaded.save()

        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual((json["records"] as? [[String: Any]])?.count, 1)
    }

    func testVerwaisteAudiodateiWirdNachGeladenemVerlaufEntfernt() throws {
        let audioDirectory = tempDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let referenced = audioDirectory.appendingPathComponent("referenziert.wav")
        let orphaned = audioDirectory.appendingPathComponent("verwaist.wav")
        let orphanedOtherFormat = audioDirectory.appendingPathComponent("verwaist.m4a")
        try Data("audio".utf8).write(to: referenced)
        try Data("audio".utf8).write(to: orphaned)
        try Data("audio".utf8).write(to: orphanedOtherFormat)
        var record = makeRecord(text: "Mit Audio")
        record.audioPath = referenced.path
        try JSONEncoder().encode([record])
            .write(to: tempDir.appendingPathComponent("history.json"))

        _ = HistoryStore(directory: tempDir, loadImmediately: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphaned.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanedOtherFormat.path))
    }

    func testUnlesbarerVerlaufLoeschtKeineVerwaisteAudiodatei() throws {
        let audioDirectory = tempDir.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let orphaned = audioDirectory.appendingPathComponent("verwaist.wav")
        try Data("audio".utf8).write(to: orphaned)
        try Data("{kaputt".utf8).write(to: tempDir.appendingPathComponent("history.json"))

        _ = HistoryStore(directory: tempDir, loadImmediately: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: orphaned.path))
    }

    func testAudioSweepLaesstRecoveryOrdnerUnberuehrt() throws {
        let recoveryDirectory = tempDir.appendingPathComponent(
            "Audio Recovery",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )
        let recovery = recoveryDirectory.appendingPathComponent("recovery.wav")
        try Data("audio".utf8).write(to: recovery)
        try JSONEncoder().encode([makeRecord()])
            .write(to: tempDir.appendingPathComponent("history.json"))

        _ = HistoryStore(directory: tempDir, loadImmediately: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path))
    }

    func testInsertAtTop() async throws {
        let first = makeRecord(text: "erster")
        let second = makeRecord(text: "zweiter")
        try await store.insert(first)
        try await store.insert(second)

        XCTAssertEqual(store.records.first?.correctedText, "zweiter")
        XCTAssertEqual(store.records.count, 2)

        let data = try Data(contentsOf: tempDir.appendingPathComponent("history.json"))
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let persisted = try XCTUnwrap(envelope["records"] as? [[String: Any]])
        XCTAssertEqual(persisted.compactMap { $0["correctedText"] as? String }, ["zweiter", "erster"])

        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)
        XCTAssertEqual(reloaded.records.map(\.correctedText), ["zweiter", "erster"])
    }

    func testDeleteRemovesAudioFile() async throws {
        let audioFile = tempDir.appendingPathComponent("test.wav")
        try Data([0x00]).write(to: audioFile)
        var record = makeRecord()
        record.audioPath = audioFile.path
        try await store.insert(record)
        try await store.delete(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertTrue(store.records.isEmpty)
    }

    func testWordCount() {
        let record = makeRecord(text: "eins zwei drei vier\nfünf")
        XCTAssertEqual(record.wordCount, 5)
    }

    func testLegacyRecordOhneWordCountWirdBeimKodierenErgaenzt() throws {
        let record = makeRecord(text: "eins zwei drei")
        let encoded = try JSONEncoder().encode(record)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "wordCount")

        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(TranscriptionRecord.self, from: legacyData)
        XCTAssertEqual(decoded.wordCount, 3)

        let migratedData = try JSONEncoder().encode(decoded)
        let migrated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        XCTAssertEqual(migrated["wordCount"] as? Int, 3)
    }

    // MARK: Retention (Aufbewahrungsdauer)

    func testDeleteAllRemovesRecordsAndAudio() async throws {
        let audioFile = tempDir.appendingPathComponent("a.wav")
        try Data([0x00]).write(to: audioFile)
        var r = makeRecord(text: "mit Audio")
        r.audioPath = audioFile.path
        try await store.insert(r)
        try await store.insert(makeRecord(text: "ohne Audio"))

        try await store.deleteAll()

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))

        let reloaded = HistoryStore(directory: tempDir, loadImmediately: true)
        XCTAssertTrue(reloaded.records.isEmpty)
    }

    func testPurgeRemovesOnlyOldRecords() async throws {
        let now = Date()
        let old = makeRecord(text: "alt", date: now.addingTimeInterval(-20 * 86_400))
        let recent = makeRecord(text: "neu", date: now)
        try await store.insert(old)
        try await store.insert(recent)

        let purged = try await store.purge(olderThan: 7, now: now)

        XCTAssertEqual(purged, 1)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.correctedText, "neu")
    }

    func testPurgeRemovesAudioFilesOfPurgedRecords() async throws {
        let now = Date()
        let audioFile = tempDir.appendingPathComponent("old.wav")
        try Data([0x00]).write(to: audioFile)
        var old = makeRecord(text: "alt", date: now.addingTimeInterval(-10 * 86_400))
        old.audioPath = audioFile.path
        try await store.insert(old)

        try await store.purge(olderThan: 7, now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
    }

    func testPurgeKeepsEverythingWhenWithinRetention() async throws {
        let now = Date()
        try await store.insert(makeRecord(text: "frisch", date: now.addingTimeInterval(-3 * 86_400)))
        let purged = try await store.purge(olderThan: 7, now: now)
        XCTAssertEqual(purged, 0)
        XCTAssertEqual(store.records.count, 1)
    }
}
