import Foundation
import XCTest
@testable import Stasi

final class AudioRecoveryStoreTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-artifacts", isDirectory: true)
            .appendingPathComponent("audio-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testRegisterMovesFinishedWAVIntoDedicatedRecoveryDirectory() throws {
        let root = try makeDirectory()
        let source = root.appendingPathComponent("session.wav")
        try Data("audio".utf8).write(to: source)
        let recoveryDirectory = root.appendingPathComponent("Recovery", isDirectory: true)
        let store = AudioRecoveryStore(directory: recoveryDirectory)

        let recovered = try store.register(source, now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(recovered.deletingLastPathComponent(), recoveryDirectory)
        XCTAssertEqual(recovered.pathExtension, "wav")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.path))
    }

    func testCleanupDeletesOnlyExpiredRecoveryWAVsAndNeverHistoryAudio() throws {
        let root = try makeDirectory()
        let recoveryDirectory = root.appendingPathComponent("Recovery", isDirectory: true)
        let historyDirectory = root.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let oldRecovery = recoveryDirectory.appendingPathComponent("old.wav")
        let recentRecovery = recoveryDirectory.appendingPathComponent("recent.wav")
        let nonWAVRecovery = recoveryDirectory.appendingPathComponent("keep.txt")
        let historyWAV = historyDirectory.appendingPathComponent("history.wav")
        for url in [oldRecovery, recentRecovery, nonWAVRecovery, historyWAV] {
            try Data("audio".utf8).write(to: url)
        }
        let now = Date(timeIntervalSince1970: 10_000)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-101)],
            ofItemAtPath: oldRecovery.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-99)],
            ofItemAtPath: recentRecovery.path
        )
        let store = AudioRecoveryStore(
            directory: recoveryDirectory,
            policy: .init(maxAge: 100, maxFiles: 20, maxBytes: 1_000_000)
        )

        try store.cleanup(now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldRecovery.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentRecovery.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonWAVRecovery.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyWAV.path))
    }

    func testCleanupEnforcesFileAndByteLimitsOldestFirst() throws {
        let root = try makeDirectory()
        let recoveryDirectory = root.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 10_000)
        var urls: [URL] = []
        for index in 0..<4 {
            let url = recoveryDirectory.appendingPathComponent("\(index).wav")
            try Data(repeating: UInt8(index), count: 10).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(Double(index - 10))],
                ofItemAtPath: url.path
            )
            urls.append(url)
        }
        let store = AudioRecoveryStore(
            directory: recoveryDirectory,
            policy: .init(maxAge: 1_000, maxFiles: 3, maxBytes: 20)
        )

        try store.cleanup(now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[1].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[2].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[3].path))
    }
}
