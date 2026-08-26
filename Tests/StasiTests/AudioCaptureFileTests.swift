import AVFoundation
import XCTest
@testable import Stasi

@MainActor
final class AudioCaptureFileTests: XCTestCase {
    private enum StartError: Error { case failed }

    private final class SinkBox: @unchecked Sendable {
        private let lock = NSLock()
        private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?

        func store(_ sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
            lock.lock()
            self.sink = sink
            lock.unlock()
        }

        func load() -> (@Sendable (AVAudioPCMBuffer) -> Void)? {
            lock.lock()
            defer { lock.unlock() }
            return sink
        }
    }

    private final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set(_ value: Bool) {
            lock.lock()
            self.value = value
            lock.unlock()
        }

        func get() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

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
                       beforeTap: (@Sendable () -> Void)? = nil,
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
        let existedBeforeTap = LockedFlag()
        let outputFormat = format()
        let capture = AudioCapture(engineHooks: hooks(format: outputFormat) {
            existedBeforeTap.set(FileManager.default.fileExists(atPath: url.path))
        })

        try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }

        XCTAssertTrue(existedBeforeTap.get())
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

    func testTapSinkDeliversBufferFromBackgroundThread() async throws {
        let outputFormat = format()
        let sinkBox = SinkBox()
        let received = expectation(description: "Puffer erreicht onBuffer")
        let hooks = AudioCapture.EngineHooks(
            prepareInput: { _, sink in
                sinkBox.store(sink)
                return outputFormat
            },
            prepareEngine: {},
            startEngine: {},
            stopEngine: {},
            removeTap: {}
        )
        let capture = AudioCapture(engineHooks: hooks)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: 16
        ))
        buffer.frameLength = 16
        nonisolated(unsafe) let backgroundBuffer = buffer
        let startTask = Task.detached {
            try capture.start(outputFormat: outputFormat,
                              recordTo: nil) { chunk in
                XCTAssertEqual(chunk.buffer.frameLength, 16)
                received.fulfill()
            }
        }
        try await startTask.value
        let sink = try XCTUnwrap(sinkBox.load())

        DispatchQueue.global(qos: .userInitiated).async {
            sink(backgroundBuffer)
        }

        await fulfillment(of: [received], timeout: 1)
        _ = capture.stop()
    }

    func testComputeLevelAndCopyFromBackgroundThread() throws {
        let floatFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: floatFormat,
            frameCapacity: 16
        ))
        buffer.frameLength = 16
        for index in 0..<16 {
            buffer.floatChannelData?[0][index] = 0.25
        }
        nonisolated(unsafe) let backgroundBuffer = buffer
        let completed = expectation(description: "Pegel und Kopie auf Hintergrund-Thread")

        DispatchQueue.global(qos: .userInitiated).async {
            let level = AudioCapture.computeLevel(of: backgroundBuffer)
            let copied = AudioCapture.copy(backgroundBuffer)
            backgroundBuffer.floatChannelData?[0][0] = 0

            XCTAssertGreaterThan(level, 0)
            XCTAssertEqual(copied?.frameLength, 16)
            XCTAssertEqual(copied?.floatChannelData?[0][0], 0.25)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }
}
