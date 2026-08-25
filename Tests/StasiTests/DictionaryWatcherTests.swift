import XCTest
@testable import Stasi

@MainActor
final class DictionaryWatcherTests: XCTestCase {
    private func makeDirectory() -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-artifacts", isDirectory: true)
            .appendingPathComponent("dictionary-watcher-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testRepeatedSavesRestartWatcherWithoutCrash() {
        let directory = makeDirectory()
        var store: DictionaryStore? = DictionaryStore(directory: directory)

        for index in 0..<25 {
            store?.add(DictionaryEntry(type: .word, value: "Watcher \(index)"))
        }

        XCTAssertEqual(store?.entries.filter { $0.value.hasPrefix("Watcher ") }.count, 25)
        store = nil
    }

    func testStoreCanBeRecreatedAfterWatcherCancellation() {
        let directory = makeDirectory()
        var store: DictionaryStore? = DictionaryStore(directory: directory)
        store?.add(DictionaryEntry(type: .word, value: "Vor Neustart"))
        store = nil

        let recreated = DictionaryStore(directory: directory)

        XCTAssertTrue(recreated.entries.contains { $0.value == "Vor Neustart" })
    }
}
