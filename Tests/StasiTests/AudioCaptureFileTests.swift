import AudioToolbox
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

    private final class ErrorSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AudioCaptureRuntimeError] = []

        var values: [AudioCaptureRuntimeError] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func record(_ error: AudioCaptureRuntimeError) {
            lock.lock()
            storage.append(error)
            lock.unlock()
        }
    }

    private final class FloatSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Float] = []

        var values: [Float] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func record(_ value: Float) {
            lock.lock()
            storage.append(value)
            lock.unlock()
        }
    }

    private final class ConfigurationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var configuration: AudioCapture.IOConfiguration?

        func store(_ configuration: AudioCapture.IOConfiguration) {
            lock.lock()
            self.configuration = configuration
            lock.unlock()
        }

        func load() -> AudioCapture.IOConfiguration? {
            lock.lock()
            defer { lock.unlock() }
            return configuration
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
                       beforeInput: (@Sendable () -> Void)? = nil,
                       configure: @escaping @Sendable (AudioCapture.IOConfiguration) -> Void = { _ in },
                       initialize: @escaping () throws -> Void = {},
                       start: @escaping () throws -> Void = {},
                       stop: @escaping () -> Void = {},
                       uninitialize: @escaping () -> Void = {},
                       dispose: @escaping () -> Void = {}) -> AudioCapture.AudioUnitHooks {
        AudioCapture.AudioUnitHooks(
            configureInput: { configuration, _, _ in
                configure(configuration)
                beforeInput?()
                return format
            },
            initialize: initialize,
            start: start,
            stop: stop,
            uninitialize: uninitialize,
            dispose: dispose
        )
    }

    func testWAVExistsBeforeInputConfiguration() throws {
        let url = makeDirectory().appendingPathComponent("before-input.wav")
        let existedBeforeInput = LockedFlag()
        let outputFormat = format()
        let capture = AudioCapture(audioUnitHooks: hooks(format: outputFormat) {
            existedBeforeInput.set(FileManager.default.fileExists(atPath: url.path))
        })

        try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }

        XCTAssertTrue(existedBeforeInput.get())
        _ = capture.stop()
    }

    func testConfiguresInputOnlyIO() throws {
        let outputFormat = format()
        let configurationBox = ConfigurationBox()
        let capture = AudioCapture(audioUnitHooks: hooks(
            format: outputFormat,
            configure: { configurationBox.store($0) }
        ))

        try capture.start(outputFormat: outputFormat, recordTo: nil) { _ in }

        XCTAssertEqual(configurationBox.load(), .inputOnly)
        XCTAssertTrue(configurationBox.load()?.inputEnabled == true)
        XCTAssertTrue(configurationBox.load()?.outputEnabled == false)
        _ = capture.stop()
    }

    func testWAVIsOpenAfterStart() throws {
        let url = makeDirectory().appendingPathComponent("open.wav")
        let outputFormat = format()
        let capture = AudioCapture(audioUnitHooks: hooks(format: outputFormat))

        try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(capture.hasOpenOutputFile)
        XCTAssertTrue(capture.isRunning)
        _ = capture.stop()
    }

    func testStopClosesFileAndDisposesAudioUnit() throws {
        let url = makeDirectory().appendingPathComponent("closed.wav")
        let outputFormat = format()
        var teardownOrder: [String] = []
        let capture = AudioCapture(audioUnitHooks: hooks(
            format: outputFormat,
            stop: { teardownOrder.append("stop") },
            uninitialize: { teardownOrder.append("uninitialize") },
            dispose: { teardownOrder.append("dispose") }
        ))
        try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }

        let returnedURL = capture.stop()

        XCTAssertEqual(returnedURL, url)
        XCTAssertFalse(capture.hasOpenOutputFile)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(teardownOrder, ["stop", "uninitialize", "dispose"])
    }

    func testAudioUnitStartFailureUninitializesDisposesAndClosesFile() {
        let url = makeDirectory().appendingPathComponent("failed.wav")
        let outputFormat = format()
        var teardownOrder: [String] = []
        let capture = AudioCapture(audioUnitHooks: hooks(
            format: outputFormat,
            start: { throw StartError.failed },
            stop: { teardownOrder.append("stop") },
            uninitialize: { teardownOrder.append("uninitialize") },
            dispose: { teardownOrder.append("dispose") }
        ))

        XCTAssertThrowsError(
            try capture.start(outputFormat: outputFormat, recordTo: url) { _ in }
        )
        XCTAssertFalse(capture.hasOpenOutputFile)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(teardownOrder, ["uninitialize", "dispose"])
    }

    func testSecondStartWhileRunningThrowsAlreadyRunning() throws {
        let outputFormat = format()
        let capture = AudioCapture(audioUnitHooks: hooks(format: outputFormat))
        try capture.start(outputFormat: outputFormat, recordTo: nil) { _ in }

        XCTAssertThrowsError(
            try capture.start(outputFormat: outputFormat, recordTo: nil) { _ in }
        ) { error in
            guard case AudioCaptureError.alreadyRunning = error else {
                return XCTFail("Erwartet alreadyRunning, erhalten: \(error)")
            }
        }
        _ = capture.stop()
    }

    func testSecondStartAfterStopCreatesFreshAudioUnitLifecycle() throws {
        let outputFormat = format()
        var startCount = 0
        var disposeCount = 0
        let capture = AudioCapture(audioUnitHooks: hooks(
            format: outputFormat,
            start: { startCount += 1 },
            dispose: { disposeCount += 1 }
        ))

        try capture.start(outputFormat: outputFormat, recordTo: nil) { _ in }
        _ = capture.stop()
        try capture.start(outputFormat: outputFormat, recordTo: nil) { _ in }
        _ = capture.stop()

        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(disposeCount, 2)
        XCTAssertFalse(capture.isRunning)
    }

    func testNativeFormatDifferentFromTargetCreatesConverter() throws {
        let targetFormat = format()
        let nativeFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let capture = AudioCapture(audioUnitHooks: hooks(format: nativeFormat))

        try capture.start(outputFormat: targetFormat, recordTo: nil) { _ in }

        XCTAssertTrue(capture.hasConverter)
        _ = capture.stop()
    }

    func testDifferentFormatsWithUnavailableConverterTearDownAudioUnitAndCloseFile() throws {
        let url = makeDirectory().appendingPathComponent("converter-unavailable.wav")
        let targetFormat = format()
        let nativeFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        var teardownOrder: [String] = []
        let capture = AudioCapture(
            audioUnitHooks: hooks(
                format: nativeFormat,
                stop: { teardownOrder.append("stop") },
                uninitialize: { teardownOrder.append("uninitialize") },
                dispose: { teardownOrder.append("dispose") }
            ),
            converterFactory: { _, _ in nil }
        )

        XCTAssertThrowsError(
            try capture.start(outputFormat: targetFormat, recordTo: url) { _ in }
        ) { error in
            guard case let AudioCaptureError.converterUnavailable(input, output) = error else {
                return XCTFail("Erwartet converterUnavailable, erhalten: \(error)")
            }
            XCTAssertEqual(input, nativeFormat)
            XCTAssertEqual(output, targetFormat)
        }
        XCTAssertEqual(teardownOrder, ["dispose"])
        XCTAssertFalse(capture.hasOpenOutputFile)
        XCTAssertFalse(capture.hasConverter)
        XCTAssertFalse(capture.isRunning)
    }

    func testClientInputFormatLimitsSixChannelHardwareToMono() throws {
        var nativeDescription = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 24,
            mFramesPerPacket: 1,
            mBytesPerFrame: 24,
            mChannelsPerFrame: 6,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let layout = try XCTUnwrap(AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 6
        ))
        let nativeFormat = try XCTUnwrap(AVAudioFormat(streamDescription: &nativeDescription,
                                                       channelLayout: layout))

        let clientFormat = try AudioCapture.clientInputFormat(for: nativeFormat)

        XCTAssertEqual(clientFormat.sampleRate, 48_000)
        XCTAssertEqual(clientFormat.channelCount, 1)
        XCTAssertEqual(clientFormat.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(clientFormat.isInterleaved)
    }

    func testInputFormatConfigurationAcceptsSixChannelHardwareDescription() throws {
        let hardwareDescription = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 24,
            mFramesPerPacket: 1,
            mBytesPerFrame: 24,
            mChannelsPerFrame: 6,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        let formats = try AudioCapture.configureInputFormats(
            readHardwareFormat: { _, _ in (noErr, hardwareDescription) },
            setClientFormat: { _, _, _ in noErr }
        )

        XCTAssertEqual(formats.hardware.channelCount, 6)
        XCTAssertEqual(formats.client.channelCount, 1)
    }

    func testInputFormatConfigurationReadsHardwareSideAndWritesSupportedMonoClientSide() throws {
        let hardwareFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        ))
        let hardwareDescription = hardwareFormat.streamDescription.pointee
        var readScope: AudioUnitScope?
        var readElement: AudioUnitElement?
        var writeScope: AudioUnitScope?
        var writeElement: AudioUnitElement?
        var writtenDescription: AudioStreamBasicDescription?

        let formats = try AudioCapture.configureInputFormats(
            readHardwareFormat: { scope, element in
                readScope = scope
                readElement = element
                return (noErr, hardwareDescription)
            },
            setClientFormat: { description, scope, element in
                writtenDescription = description
                writeScope = scope
                writeElement = element
                return noErr
            }
        )

        XCTAssertEqual(readScope, kAudioUnitScope_Input)
        XCTAssertEqual(readElement, 1)
        XCTAssertEqual(writeScope, kAudioUnitScope_Output)
        XCTAssertEqual(writeElement, 1)
        XCTAssertEqual(formats.hardware.sampleRate, 48_000)
        XCTAssertEqual(formats.hardware.channelCount, 2)
        XCTAssertEqual(formats.client.sampleRate, 48_000)
        XCTAssertEqual(formats.client.channelCount, 1)
        XCTAssertEqual(formats.client.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(formats.client.isInterleaved)

        var written = try XCTUnwrap(writtenDescription)
        let writtenFormat = AVAudioFormat(streamDescription: &written)
        XCTAssertEqual(writtenFormat?.sampleRate, 48_000)
        XCTAssertEqual(writtenFormat?.channelCount, 1)
        XCTAssertEqual(writtenFormat?.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(writtenFormat?.isInterleaved, false)
    }

    func testInputFormatConfigurationPropagatesHardwareReadFailure() {
        let expectedStatus = OSStatus(-50)

        XCTAssertThrowsError(try AudioCapture.configureInputFormats(
            readHardwareFormat: { _, _ in
                (expectedStatus, AudioStreamBasicDescription())
            },
            setClientFormat: { _, _, _ in
                XCTFail("Clientformat darf nach Lesefehler nicht gesetzt werden")
                return noErr
            }
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("Natives Hardwareformat lesen"))
            XCTAssertTrue(error.localizedDescription.contains("\(expectedStatus)"))
        }
    }

    func testInputFormatConfigurationPropagatesClientFormatSetFailure() throws {
        let hardwareFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let hardwareDescription = hardwareFormat.streamDescription.pointee
        let expectedStatus = OSStatus(-10868)

        XCTAssertThrowsError(try AudioCapture.configureInputFormats(
            readHardwareFormat: { _, _ in (noErr, hardwareDescription) },
            setClientFormat: { _, _, _ in expectedStatus }
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("Float32-Clientformat setzen"))
            XCTAssertTrue(error.localizedDescription.contains("\(expectedStatus)"))
        }
    }

    func testMaximumFramesConfigurationSetsRequestedValueBeforeReadingEffectiveValue() throws {
        var operations: [String] = []

        let capacity = try AudioCapture.configureMaximumFrames(
            requested: 4_096,
            set: { value in
                operations.append("set:\(value)")
                return noErr
            },
            get: {
                operations.append("get")
                return (noErr, 8_192)
            }
        )

        XCTAssertEqual(operations, ["set:4096", "get"])
        XCTAssertEqual(capacity, 8_192)
    }

    func testMaximumFramesConfigurationRejectsSetFailure() {
        let expectedStatus = OSStatus(-50)

        XCTAssertThrowsError(try AudioCapture.configureMaximumFrames(
            requested: 4_096,
            set: { _ in expectedStatus },
            get: { XCTFail("Get darf nach Set-Fehler nicht laufen"); return (noErr, 4_096) }
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("\(expectedStatus)"))
        }
    }

    func testMaximumFramesCapacityNeverFallsBelowRequestedValue() throws {
        let capacity = try AudioCapture.configureMaximumFrames(
            requested: 4_096,
            set: { _ in noErr },
            get: { (noErr, 512) }
        )

        XCTAssertEqual(capacity, 4_096)
    }

    func testRenderBufferPreparationSetsNonInterleavedTopologyAndByteSizes() throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 2,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: 4_096
        ))

        let status = AudioCapture.prepareRenderBuffer(buffer, frameCount: 2_048)
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)

        XCTAssertEqual(status, noErr)
        XCTAssertEqual(buffer.frameLength, 2_048)
        XCTAssertEqual(buffer.mutableAudioBufferList.pointee.mNumberBuffers, 2)
        XCTAssertEqual(buffers.count, 2)
        XCTAssertTrue(buffers.allSatisfy { $0.mNumberChannels == 1 })
        XCTAssertTrue(buffers.allSatisfy { $0.mDataByteSize == 2_048 * 4 })
        XCTAssertTrue(buffers.allSatisfy { $0.mData != nil })
    }

    func testRenderBufferPreparationRejectsOversizedSliceWithoutMutatingLength() throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: 4_096
        ))

        let status = AudioCapture.prepareRenderBuffer(buffer, frameCount: 4_097)

        XCTAssertEqual(status, kAudio_ParamError)
        XCTAssertEqual(buffer.frameLength, 0)
    }

    func testInputCallbackDeliversBufferFromBackgroundThread() async throws {
        let outputFormat = format()
        let sinkBox = SinkBox()
        let received = expectation(description: "Puffer erreicht onBuffer")
        let hooks = AudioCapture.AudioUnitHooks(
            configureInput: { _, _, sink in
                sinkBox.store(sink)
                return outputFormat
            },
            initialize: {},
            start: {},
            stop: {},
            uninitialize: {},
            dispose: {}
        )
        let capture = AudioCapture(audioUnitHooks: hooks)
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

    func testProcessingOwnsRenderBufferBeforeAsynchronousWorkBegins() throws {
        let outputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let sinkBox = SinkBox()
        let processingEntered = DispatchSemaphore(value: 0)
        let allowProcessing = DispatchSemaphore(value: 0)
        let received = expectation(description: "Eigene Pufferkopie verarbeitet")
        let samples = FloatSpy()
        let capture = AudioCapture(
            audioUnitHooks: AudioCapture.AudioUnitHooks(
                configureInput: { _, _, sink in
                    sinkBox.store(sink)
                    return outputFormat
                },
                initialize: {}, start: {}, stop: {}, uninitialize: {}, dispose: {}
            ),
            beforeProcessing: {
                processingEntered.signal()
                allowProcessing.wait()
            }
        )
        try capture.start(
            outputFormat: outputFormat,
            recordTo: nil,
            onRuntimeError: { _ in XCTFail("Kein Runtimefehler erwartet") }
        ) { chunk in
            samples.record(chunk.buffer.floatChannelData?[0][0] ?? -1)
            received.fulfill()
        }
        let renderBuffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: 16
        ))
        renderBuffer.frameLength = 16
        renderBuffer.floatChannelData?[0][0] = 0.25

        try XCTUnwrap(sinkBox.load())(renderBuffer)
        XCTAssertEqual(processingEntered.wait(timeout: .now() + 1), .success)
        renderBuffer.floatChannelData?[0][0] = 0.75
        allowProcessing.signal()

        wait(for: [received], timeout: 1)
        XCTAssertEqual(samples.values, [0.25])
        _ = capture.stop()
    }

    func testDefaultProcessingBacklogCapacityIsExactly64Chunks() {
        XCTAssertEqual(AudioCapture.defaultBacklogCapacity, 64)
    }

    func testFullProcessingBacklogReportsExactlyOnce() throws {
        let outputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let sinkBox = SinkBox()
        let processingEntered = DispatchSemaphore(value: 0)
        let allowProcessing = DispatchSemaphore(value: 0)
        let didBlockProcessing = LockedFlag()
        let errorReported = expectation(description: "Backlog gemeldet")
        let errorSpy = ErrorSpy()
        let capture = AudioCapture(
            audioUnitHooks: AudioCapture.AudioUnitHooks(
                configureInput: { _, _, sink in
                    sinkBox.store(sink)
                    return outputFormat
                },
                initialize: {}, start: {}, stop: {}, uninitialize: {}, dispose: {}
            ),
            backlogCapacity: 1,
            beforeProcessing: {
                guard !didBlockProcessing.get() else { return }
                didBlockProcessing.set(true)
                processingEntered.signal()
                allowProcessing.wait()
            }
        )
        try capture.start(
            outputFormat: outputFormat,
            recordTo: nil,
            onRuntimeError: { error in
                errorSpy.record(error)
                errorReported.fulfill()
            }
        ) { _ in }
        let renderBuffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: 16
        ))
        renderBuffer.frameLength = 16
        let sink = try XCTUnwrap(sinkBox.load())

        sink(renderBuffer)
        XCTAssertEqual(processingEntered.wait(timeout: .now() + 1), .success)
        sink(renderBuffer)
        sink(renderBuffer)
        sink(renderBuffer)

        wait(for: [errorReported], timeout: 1)
        XCTAssertEqual(errorSpy.values, [.processingBacklog])
        allowProcessing.signal()
        _ = capture.stop()
    }

    func testProcessingFailureReportsExactlyOnce() throws {
        let outputFormat = format()
        let sinkBox = SinkBox()
        let errorReported = expectation(description: "Verarbeitungsfehler gemeldet")
        let errorSpy = ErrorSpy()
        let capture = AudioCapture(
            audioUnitHooks: AudioCapture.AudioUnitHooks(
                configureInput: { _, _, sink in
                    sinkBox.store(sink)
                    return outputFormat
                },
                initialize: {}, start: {}, stop: {}, uninitialize: {}, dispose: {}
            ),
            processingFailure: { _ in .conversionFailed("test") }
        )
        try capture.start(
            outputFormat: outputFormat,
            recordTo: nil,
            onRuntimeError: { error in
                errorSpy.record(error)
                errorReported.fulfill()
            }
        ) { _ in }
        let renderBuffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: 16
        ))
        renderBuffer.frameLength = 16
        let sink = try XCTUnwrap(sinkBox.load())

        sink(renderBuffer)
        sink(renderBuffer)

        wait(for: [errorReported], timeout: 1)
        XCTAssertEqual(errorSpy.values, [.conversionFailed("test")])
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
