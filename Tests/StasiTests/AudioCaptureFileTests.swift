import AVFoundation
import XCTest
@testable import Stasi

@MainActor
final class AudioCaptureFileTests: XCTestCase {
    private enum StartError: Error { case failed }

    private func makeDirectory() -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-artifacts", isDirectory: true)
            .appendingPathComponent("audio-capture-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func format() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16,
                      sampleRate: 16_000,
                      channels: 1,
                      interleaved: false)!
    }

    private func hooks(format: AVAudioFormat,
                       beforeTap: (() -> Void)? = nil,
                       start: @escaping () throws -> Void = {},
                       stop: @escaping () -> Void = {},
                       removeTap: @escaping () -> Void = {}) -> AudioCapture.EngineHooks {
        AudioCapture.EngineHooks(
            prepareInput: { _, _ in
                beforeTap?()
                return format
            },
            prepareEngine: {},
            startEngine: start,
            stopEngine: stop,
            removeTap: removeTap
        )
    }

    func testWAVExistsBeforeTapInstallation() throws {
        let url = makeDirectory().appendingPathComponent("before-tap.wav")
        var existedBeforeTap = false
        let outputFormat = format()
        let capture = AudioCapture(engineHooks: hooks(format: outputFormat) {
            existedBeforeTap = FileManager.default.fileExists(atPath: url.path)
        })

        try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }

        XCTAssertTrue(existedBeforeTap)
        _ = capture.stop()
    }

    func testWAVIsOpenAfterStart() throws {
        let url = makeDirectory().appendingPathComponent("open.wav")
        let outputFormat = format()
        let capture = AudioCapture(engineHooks: hooks(format: outputFormat))

        try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(capture.hasOpenOutputFile)
        XCTAssertTrue(capture.isRunning)
        _ = capture.stop()
    }

    func testStopClosesFileAndRemovesTap() throws {
        let url = makeDirectory().appendingPathComponent("closed.wav")
        let outputFormat = format()
        var stopCount = 0
        var removeTapCount = 0
        let capture = AudioCapture(engineHooks: hooks(
            format: outputFormat,
            stop: { stopCount += 1 },
            removeTap: { removeTapCount += 1 }
        ))
        try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }

        let returnedURL = capture.stop()

        XCTAssertEqual(returnedURL, url)
        XCTAssertFalse(capture.hasOpenOutputFile)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(removeTapCount, 1)
    }

    func testEngineStartFailureRemovesTapAndClosesFile() {
        let url = makeDirectory().appendingPathComponent("failed.wav")
        let outputFormat = format()
        var stopCount = 0
        var removeTapCount = 0
        let capture = AudioCapture(engineHooks: hooks(
            format: outputFormat,
            start: { throw StartError.failed },
            stop: { stopCount += 1 },
            removeTap: { removeTapCount += 1 }
        ))

        XCTAssertThrowsError(
            try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }
        )
        XCTAssertFalse(capture.hasOpenOutputFile)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(removeTapCount, 1)
        XCTAssertEqual(stopCount, 1)
    }
}
