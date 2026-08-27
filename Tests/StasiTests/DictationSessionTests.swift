import AppKit
import AVFoundation
import XCTest
@testable import Stasi

@MainActor
final class DictationSessionTests: XCTestCase {
    private enum FakeError: Error { case setup, audio, history }

    private final class FakeHistoryStore: HistoryStoring {
        var records: [TranscriptionRecord] = []
        var state: HistoryStoreState = .missing
        var lastError: String?
        private(set) var insertCount = 0
        var insertError: Error?

        func save() throws {}

        func insert(_ record: TranscriptionRecord, at position: Int) throws {
            insertCount += 1
            if let insertError { throw insertError }
            records.insert(record, at: min(position, records.count))
        }

        func delete(_ record: TranscriptionRecord) throws {
            records.removeAll { $0.id == record.id }
        }

        func deleteAll() throws {
            records.removeAll()
        }

        func purge(olderThan days: Int, now: Date) throws -> Int { 0 }
    }

    private final class FakeAudioCapture: AudioCapturing, @unchecked Sendable {
        var latestLevel: Double = 0
        private(set) var isRunning = false
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var activateCount = 0
        private(set) var openCount = 0
        private(set) var isCaptureActive = false
        private var activationReserved = false
        private var runtimeFailed = false
        var activationShouldFail = false
        var startError: Error?
        var stoppedURL: URL?
        private(set) var startedURL: URL?
        private var onBuffer: (@Sendable (AudioChunk) -> Void)?
        private var onRuntimeErrorAccepted: (@Sendable (AudioCaptureRuntimeError) -> Void)?
        private var onRuntimeError: (@Sendable (AudioCaptureRuntimeError) -> Void)?
        var delaysRuntimeErrorDelivery = false
        private var pendingRuntimeError: AudioCaptureRuntimeError?
        var onStart: (() -> Void)?
        var onActivate: (() -> Void)?
        var onOpen: (() -> Void)?
        var onStop: (() -> Void)?
        var suspendFirstStop = false
        private var firstStopContinuation: CheckedContinuation<URL?, Never>?

        func ingestNativeBuffer(_ buffer: AVAudioPCMBuffer) {
            latestLevel = AudioCapture.computeLevel(of: buffer)
        }

        func start(outputFormat: AVAudioFormat,
                   recordTo url: URL?,
                   preferredMicUID: String?,
                   captureInitiallyActive: Bool,
                   onRuntimeErrorAccepted: @escaping @Sendable (AudioCaptureRuntimeError) -> Void,
                   onRuntimeError: @escaping @Sendable (AudioCaptureRuntimeError) -> Void,
                   onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws {
            startCount += 1
            startedURL = url
            self.onRuntimeErrorAccepted = onRuntimeErrorAccepted
            self.onRuntimeError = onRuntimeError
            self.onBuffer = onBuffer
            activationReserved = captureInitiallyActive
            isCaptureActive = captureInitiallyActive
            runtimeFailed = false
            onStart?()
            if let startError {
                activationReserved = false
                isCaptureActive = false
                throw startError
            }
            isRunning = true
        }

        func activateCapture() -> Bool {
            activateCount += 1
            onActivate?()
            guard isRunning, !runtimeFailed, !activationShouldFail else { return false }
            activationReserved = true
            return true
        }

        func openCapture() -> Bool {
            guard isRunning, activationReserved, !runtimeFailed else { return false }
            openCount += 1
            isCaptureActive = true
            onOpen?()
            return true
        }

        func emit(_ chunk: AudioChunk) {
            guard isCaptureActive else { return }
            onBuffer?(chunk)
        }

        func fail(_ error: AudioCaptureRuntimeError) {
            runtimeFailed = true
            isCaptureActive = false
            onRuntimeErrorAccepted?(error)
            if delaysRuntimeErrorDelivery {
                pendingRuntimeError = error
            } else {
                onRuntimeError?(error)
            }
        }

        func deliverPendingRuntimeError() {
            guard let error = pendingRuntimeError else { return }
            pendingRuntimeError = nil
            onRuntimeError?(error)
        }

        func stop() async -> URL? {
            stopCount += 1
            onStop?()
            isRunning = false
            activationReserved = false
            isCaptureActive = false
            guard stopCount == 1 else { return nil }
            guard suspendFirstStop else { return stoppedURL }
            return await withCheckedContinuation { firstStopContinuation = $0 }
        }

        func finishFirstStop() {
            firstStopContinuation?.resume(returning: stoppedURL)
            firstStopContinuation = nil
        }
    }

    @MainActor
    private final class AudioFactorySpy {
        private(set) var captures: [FakeAudioCapture] = []
        var configureCapture: ((FakeAudioCapture, Int) -> Void)?

        func make() -> any AudioCapturing {
            let capture = FakeAudioCapture()
            configureCapture?(capture, captures.count)
            captures.append(capture)
            return capture
        }
    }

    private actor FakeSpeechEngine: SpeechEngining {
        struct Metrics: Sendable {
            let startCount: Int
            let feedCount: Int
            let finishCount: Int
            let streamCancellationCount: Int
            let finalizeStillRunning: Bool
        }

        private var continuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?
        private(set) var startCount = 0
        private(set) var feedCount = 0
        private(set) var finishCount = 0
        private(set) var streamCancellationCount = 0
        var startError: Error?
        var text = ""
        var localeToResolve: Locale?
        var finishDelayNanoseconds: UInt64 = 0
        var timeoutNanoseconds: UInt64?
        var finishEndsResultStream = true
        private(set) var finalizeStillRunning = false
        private var shouldBlockStart = false
        private var startEntered = false
        private var blockedStartContinuation: CheckedContinuation<Void, Never>?
        private var shouldBlockNextFeed = false
        private var blockedFeedContinuation: CheckedContinuation<Void, Never>?

        init(text: String = "",
             startError: Error? = nil,
             resolvedLocale: Locale? = nil) {
            self.text = text
            self.startError = startError
            localeToResolve = resolvedLocale
        }

        func resolvedLocale(for requested: Locale) async throws -> Locale {
            localeToResolve ?? requested
        }

        func configureFinish(delay: UInt64, timeout: UInt64?) {
            finishDelayNanoseconds = delay
            timeoutNanoseconds = timeout
        }

        func configureFinishEndsResultStream(_ value: Bool) {
            finishEndsResultStream = value
        }

        func blockStart() {
            shouldBlockStart = true
        }

        func hasEnteredStart() -> Bool { startEntered }

        func unblockStart() {
            blockedStartContinuation?.resume()
            blockedStartContinuation = nil
        }

        func blockNextFeed() {
            shouldBlockNextFeed = true
        }

        func unblockFeed() {
            blockedFeedContinuation?.resume()
            blockedFeedContinuation = nil
        }

        func metrics() -> Metrics {
            Metrics(startCount: startCount,
                    feedCount: feedCount,
                    finishCount: finishCount,
                    streamCancellationCount: streamCancellationCount,
                    finalizeStillRunning: finalizeStillRunning)
        }

        func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
            startCount += 1
            startEntered = true
            if shouldBlockStart {
                shouldBlockStart = false
                await withCheckedContinuation { blockedStartContinuation = $0 }
            }
            if let startError { throw startError }
            let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task { await self?.recordStreamCancellation() }
            }
            self.continuation = continuation
            if !text.isEmpty {
                continuation.yield(TranscriptionChunk(text: text, isFinal: false))
            }
            return stream
        }

        func preferredInputFormat() async -> AVAudioFormat? {
            AVAudioFormat(commonFormat: .pcmFormatInt16,
                          sampleRate: 16_000,
                          channels: 1,
                          interleaved: false)
        }

        func feed(_ chunk: AudioChunk) async {
            feedCount += 1
            guard shouldBlockNextFeed else { return }
            shouldBlockNextFeed = false
            await withCheckedContinuation { blockedFeedContinuation = $0 }
        }

        func finish() async {
            finishCount += 1
            let delay = finishDelayNanoseconds
            guard delay > 0 else {
                if finishEndsResultStream {
                    continuation?.finish()
                    continuation = nil
                }
                return
            }

            finalizeStillRunning = true
            let finalizeTask = Task {
                try? await Task.sleep(nanoseconds: delay)
            }
            if let timeoutNanoseconds {
                let completed = await TranscriptionEngine.waitForFinalize(
                    finalizeTask,
                    timeoutNanoseconds: timeoutNanoseconds
                )
                if !completed {
                    continuation?.yield(TranscriptionChunk(text: text, isFinal: true))
                    continuation?.finish()
                    continuation = nil
                    Task { [weak self] in
                        await finalizeTask.value
                        await self?.markFinalizeFinished()
                    }
                    return
                }
            } else {
                await finalizeTask.value
            }
            finalizeStillRunning = false
            if finishEndsResultStream {
                continuation?.finish()
                continuation = nil
            }
        }

        private func recordStreamCancellation() { streamCancellationCount += 1 }
        private func markFinalizeFinished() { finalizeStillRunning = false }
    }

    private actor PermissionGate {
        private var continuation: CheckedContinuation<Bool, Never>?
        private(set) var requested = false

        func request() async -> Bool {
            requested = true
            return await withCheckedContinuation { continuation = $0 }
        }

        func resolve(_ granted: Bool) { continuation?.resume(returning: granted) }
    }

    private actor ModelInstallerSpy {
        private var localeIDs: [String] = []

        func install(_ locale: Locale) {
            localeIDs.append(locale.identifier)
        }

        func installedLocaleIDs() -> [String] { localeIDs }
    }

    private final class AudioSinkBox: @unchecked Sendable {
        private let lock = NSLock()
        private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?

        func store(_ sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
            lock.withLock { self.sink = sink }
        }

        func load() -> (@Sendable (AVAudioPCMBuffer) -> Void)? {
            lock.withLock { sink }
        }
    }

    private final class TextInjectorSpy: @unchecked Sendable {
        private(set) var callCount = 0
        private(set) var texts: [String] = []
        private(set) var targetPIDs: [pid_t] = []
        var succeeds = true

        @discardableResult
        func inject(_ text: String, targetPID: pid_t) -> Bool {
            callCount += 1
            texts.append(text)
            targetPIDs.append(targetPID)
            return succeeds
        }
    }

    private final class ClipboardSpy {
        private(set) var strings: [String] = []

        func copy(_ string: String) {
            strings.append(string)
        }
    }

    private final class FrontmostApplicationStub {
        var current: TargetApplication?
        private(set) var callCount = 0

        init(_ current: TargetApplication?) {
            self.current = current
        }

        func application() -> TargetApplication? {
            callCount += 1
            return current
        }
    }

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        func call(returning value: Bool) -> Bool {
            lock.withLock { storage += 1 }
            return value
        }

        var count: Int { lock.withLock { storage } }
    }

    private final class FakeClock {
        var now: Date

        init(now: Date = Date(timeIntervalSince1970: 1_000)) {
            self.now = now
        }

        func advance(by interval: TimeInterval) {
            now = now.addingTimeInterval(interval)
        }
    }

    private final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ event: String) {
            lock.withLock { storage.append(event) }
        }

        var events: [String] {
            lock.withLock { storage }
        }
    }

    @MainActor
    private final class SoundFeedbackSpy: SoundFeedback, @unchecked Sendable {
        private(set) var events: [SoundEvent] = []
        private let timeline: EventLog?
        private let onPlay: ((SoundEvent) async -> Void)?

        init(timeline: EventLog? = nil,
             onPlay: ((SoundEvent) async -> Void)? = nil) {
            self.timeline = timeline
            self.onPlay = onPlay
        }

        func play(_ event: SoundEvent) async {
            await onPlay?(event)
            guard !Task.isCancelled else { return }
            events.append(event)
            timeline?.append("sound.\(event)")
        }
    }

    private final class FocusGateRaceStub: @unchecked Sendable {
        private let lock = NSLock()
        private var current: TargetApplication?
        private let target: TargetApplication

        init(current: TargetApplication?, target: TargetApplication) {
            self.current = current
            self.target = target
        }

        func application() -> TargetApplication? {
            lock.withLock { current }
        }

        func setCurrent(_ application: TargetApplication?) {
            lock.withLock { current = application }
        }

        func editableAndRestoreTarget() -> Bool {
            lock.withLock { current = target }
            return true
        }
    }

    private final class RevealSpy {
        private(set) var urls: [URL] = []

        func reveal(_ url: URL) {
            urls.append(url)
        }
    }

    private final class SpellCheckerSpy {
        private(set) var calls: [(word: String, language: String)] = []

        func isKnown(_ word: String, language: String) -> Bool {
            calls.append((word, language))
            return false
        }
    }

    private func makeAudioChunk() throws -> AudioChunk {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        buffer.frameLength = 1
        return AudioChunk(buffer: buffer)
    }

    private func makeTargetApplication(
        named name: String = "Test App",
        bundleIdentifier: String? = "com.example.test-app",
        processIdentifier: pid_t = 42
    ) -> TargetApplication {
        TargetApplication(
            localizedName: name,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier
        )
    }

    private func makeDirectory(_ name: String = #function) -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-artifacts", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSettings() -> SettingsStore {
        let suite = "DictationSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.soundOn = false
        return settings
    }

    private func makeApp(audio: FakeAudioCapture = FakeAudioCapture(),
                         audioFactory: AudioCaptureFactory? = nil,
                         engines: [FakeSpeechEngine],
                         permission: @escaping @MainActor () async -> Bool = { true },
                         modelInstaller: @escaping @Sendable (Locale) async throws -> Void = { _ in },
                         spellChecker: @escaping @MainActor (String, String) -> Bool = { _, _ in true },
                         consumeTimeoutNanoseconds: UInt64 = 2_000_000_000,
                         minimumPushToTalkDuration: TimeInterval = 0,
                         history: (any HistoryStoring)? = nil,
                         frontmostApplication: @escaping @MainActor () -> TargetApplication? = {
                             TargetApplication(
                                 localizedName: "Test App",
                                 bundleIdentifier: "com.example.test-app",
                                 processIdentifier: 42
                             )
                         },
                         isTextFieldEditable: @escaping @Sendable () -> Bool = { false },
                         injectText: @escaping @Sendable (String, pid_t) -> Bool = { _, _ in true },
                         copyToClipboard: @escaping @MainActor (String) -> Void = { _ in },
                         recoveryStore: AudioRecoveryStore? = nil,
                         revealRecoveryFile: @escaping @MainActor (URL) -> Void = { _ in },
                         directory: URL? = nil,
                         now: @escaping @MainActor () -> Date = { Date() },
                         soundFeedback: any SoundFeedback = SoundFeedbackSpy()) -> AppState {
        let root = directory ?? makeDirectory("makeApp")
        let dictionary = DictionaryStore(directory: root.appendingPathComponent("dictionary"))
        let history = history ?? HistoryStore(directory: root.appendingPathComponent("history"))
        var remaining = engines
        return AppState(
            settings: makeSettings(),
            dictionary: dictionary,
            history: history,
            audioFactory: audioFactory ?? { audio },
            speechFactory: { _, _ in remaining.removeFirst() },
            requestMicrophone: permission,
            modelInstaller: modelInstaller,
            spellChecker: spellChecker,
            consumeTimeoutNanoseconds: consumeTimeoutNanoseconds,
            minimumPushToTalkDuration: minimumPushToTalkDuration,
            installHotkey: false,
            audioDirectory: root.appendingPathComponent("audio"),
            audioRecoveryStore: recoveryStore,
            revealRecoveryFile: revealRecoveryFile,
            frontmostApplication: frontmostApplication,
            isTextFieldEditable: isTextFieldEditable,
            injectText: injectText,
            copyToClipboard: copyToClipboard,
            now: now,
            soundFeedback: soundFeedback
        )
    }

    func testUnreadableHistoryIsReportedWhenToastChannelIsInstalled() throws {
        let directory = makeDirectory()
        let historyDirectory = directory.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(
            to: historyDirectory.appendingPathComponent("history.json")
        )
        let history = HistoryStore(directory: historyDirectory)
        let app = makeApp(
            audio: FakeAudioCapture(),
            engines: [FakeSpeechEngine()],
            history: history,
            directory: directory
        )
        var toasts: [(String, Bool)] = []

        app.settings.retention = .oneDay
        app.onToast = { toasts.append(($0, $1)) }
        app.applyRetention()

        XCTAssertEqual(toasts.count, 2)
        XCTAssertEqual(
            toasts.map(\.0),
            Array(
                repeating: "Verlauf konnte nicht geladen werden. Die vorhandene Datei ist beschädigt und bleibt schreibgeschützt.",
                count: 2
            )
        )
        XCTAssertEqual(toasts.map(\.1), [false, false])
    }

    func testModelReadinessIsTrackedPerLocale() async {
        let spy = ModelInstallerSpy()
        let app = makeApp(
            audio: FakeAudioCapture(),
            engines: [FakeSpeechEngine()],
            modelInstaller: { locale in await spy.install(locale) }
        )
        let german = Locale(identifier: "de_DE")
        let english = Locale(identifier: "en_US")

        XCTAssertFalse(app.modelReady(for: german))
        XCTAssertFalse(app.modelReady(for: english))
        await app.prepareModel(for: german)

        XCTAssertTrue(app.modelReady(for: german))
        XCTAssertFalse(app.modelReady(for: english))
        let installedLocaleIDs = await spy.installedLocaleIDs()
        XCTAssertEqual(installedLocaleIDs, ["de_DE"])
    }

    func testLoudNativeBufferRaisesPolledDisplayLevel() async throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 480
        ))
        buffer.frameLength = 480
        for index in 0..<480 {
            buffer.floatChannelData?[0][index] = 0.5 * sin(Float(index) * 0.25)
        }
        let audio = FakeAudioCapture()
        audio.ingestNativeBuffer(buffer)
        let measured = audio.latestLevel
        let app = makeApp(audio: audio, engines: [FakeSpeechEngine()])
        app.startDictation()
        await waitUntil { audio.isRunning }

        app.ingestLevelFromPoll()

        XCTAssertGreaterThan(measured, 0.5)
        XCTAssertGreaterThan(app.displayLevel, 0.5)
        app.requestDiscard()
        await waitUntil { app.phase == .idle }
    }

    func testFinishedDictationMergesLearnedCandidateUsingInjectedSpellChecker() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Wir verwenden Frobulator heute")
        let spellChecker = SpellCheckerSpy()
        let app = makeApp(
            audio: audio,
            engines: [speech],
            spellChecker: { word, language in
                spellChecker.isKnown(word, language: language)
            },
            directory: directory
        )
        try app.history.insert(TranscriptionRecord(
            date: Date().addingTimeInterval(-60),
            localeID: "de_DE",
            rawText: "Der Frobulator hilft",
            correctedText: "Der Frobulator hilft",
            corrections: []
        ))

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        await waitUntil { app.dictionary.entries.contains { $0.type == .learned } }

        let learned = app.dictionary.entries.first { $0.type == .learned }
        XCTAssertEqual(learned?.value, "Frobulator")
        XCTAssertEqual(learned?.note, "2× diktiert")
        XCTAssertEqual(spellChecker.calls.count, 1)
        XCTAssertEqual(spellChecker.calls.first?.word, "Frobulator")
        XCTAssertEqual(spellChecker.calls.first?.language, "de")
    }

    private func waitUntil(timeout: TimeInterval = 1,
                           _ predicate: @escaping @MainActor () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Bedingung nicht innerhalb von \(timeout) s erfüllt")
    }

    func testFocusChangeDuringFinalizeKeepsTextAndSkipsInjection() async {
        let slack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42
        )
        let notes = TargetApplication(
            localizedName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 84
        )
        let frontmost = FrontmostApplicationStub(slack)
        let audio = FakeAudioCapture()
        let history = FakeHistoryStore()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Finaler Text")],
            history: history,
            frontmostApplication: { frontmost.current },
            isTextFieldEditable: { true },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) }
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        frontmost.current = notes
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(injector.callCount, 0)
        XCTAssertEqual(clipboard.strings, ["Finaler Text"])
        XCTAssertEqual(history.records.first?.targetApp, "Slack")
        XCTAssertTrue(toasts.contains { $0.contains("Slack") })
    }

    func testFocusChangeBetweenEditableAndApplicationChecksSkipsInjection() async {
        let slack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42
        )
        let notes = TargetApplication(
            localizedName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 84
        )
        let focus = FocusGateRaceStub(current: slack, target: slack)
        let audio = FakeAudioCapture()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Finaler Text")],
            frontmostApplication: { focus.application() },
            isTextFieldEditable: { focus.editableAndRestoreTarget() },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) }
        )

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        focus.setCurrent(notes)
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(injector.callCount, 0)
        XCTAssertEqual(clipboard.strings, ["Finaler Text"])
    }

    func testRelaunchedTargetWithSameBundleSkipsInjection() async {
        let capturedSlack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42
        )
        let frontmost = FrontmostApplicationStub(capturedSlack)
        let audio = FakeAudioCapture()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Finaler Text")],
            frontmostApplication: { frontmost.current },
            isTextFieldEditable: { true },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) }
        )

        app.startDictation()
        await waitUntil { audio.isRunning }
        frontmost.current = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 43
        )
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(injector.callCount, 0)
        XCTAssertEqual(clipboard.strings, ["Finaler Text"])
    }

    func testMissingCurrentApplicationSkipsInjection() async {
        let slack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42
        )
        let frontmost = FrontmostApplicationStub(slack)
        let audio = FakeAudioCapture()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let editability = CallCounter()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Finaler Text")],
            frontmostApplication: { frontmost.application() },
            isTextFieldEditable: { editability.call(returning: true) },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) }
        )

        app.startDictation()
        await waitUntil { audio.isRunning }
        frontmost.current = nil
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(injector.callCount, 0)
        XCTAssertEqual(clipboard.strings, ["Finaler Text"])
        XCTAssertEqual(frontmost.callCount, 2)
        XCTAssertEqual(editability.count, 0)
    }

    func testSameEditableTargetInjectsFinalText() async {
        let slack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42
        )
        let audio = FakeAudioCapture()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Finaler Text")],
            frontmostApplication: { slack },
            isTextFieldEditable: { true },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) }
        )

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(injector.texts, ["Finaler Text"])
        XCTAssertEqual(injector.targetPIDs, [slack.processIdentifier])
        XCTAssertEqual(clipboard.strings, ["Finaler Text"])
    }

    func testInjectionFailureKeepsHistoryAndClipboardAndReportsRetainedText() async {
        let slack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42
        )
        let audio = FakeAudioCapture()
        let history = FakeHistoryStore()
        let injector = TextInjectorSpy()
        injector.succeeds = false
        let clipboard = ClipboardSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Vollständiger Text")],
            history: history,
            frontmostApplication: { slack },
            isTextFieldEditable: { true },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) }
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(injector.callCount, 1)
        XCTAssertEqual(history.records.first?.correctedText, "Vollständiger Text")
        XCTAssertEqual(clipboard.strings, ["Vollständiger Text"])
        XCTAssertTrue(toasts.contains { $0.contains("Zwischenablage") })
    }

    func testSameTargetWithoutEditableElementSkipsInjection() async {
        let slack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42
        )
        let frontmost = FrontmostApplicationStub(slack)
        let audio = FakeAudioCapture()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let editability = CallCounter()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Finaler Text")],
            frontmostApplication: { frontmost.application() },
            isTextFieldEditable: { editability.call(returning: false) },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) }
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(injector.callCount, 0)
        XCTAssertEqual(clipboard.strings, ["Finaler Text"])
        XCTAssertTrue(toasts.contains { $0.contains("Slack") })
        XCTAssertEqual(frontmost.callCount, 2)
        XCTAssertEqual(editability.count, 1)
    }

    func testSessionSnapshotsAreImmutable() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine()
        let locale = Locale(identifier: "de_DE")
        let entry = DictionaryEntry(type: .word, value: "Stasi")
        let url = makeDirectory().appendingPathComponent("snapshot.wav")
        let targetApplication = TargetApplication(
            localizedName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            processIdentifier: 42
        )
        let session = DictationSession(locale: locale,
                                       dictionaryEntries: [entry],
                                       audioURL: url,
                                       speech: speech,
                                       audio: audio)
        XCTAssertNil(session.targetApplication)
        XCTAssertTrue(session.assignTargetApplication(targetApplication))

        XCTAssertEqual(session.locale.identifier, "de_DE")
        XCTAssertEqual(session.dictionaryEntries, [entry])
        XCTAssertEqual(session.targetApplication, targetApplication)
        XCTAssertEqual(session.audioURL, url)
    }

    func testNewSessionStartsInSettingUpState() {
        let session = DictationSession(locale: Locale(identifier: "de_DE"),
                                       dictionaryEntries: [],
                                       audioURL: nil,
                                       speech: FakeSpeechEngine(), audio: FakeAudioCapture())
        XCTAssertEqual(session.state, .settingUp)
    }

    func testSessionPublishesRecordingOnlyFromSetup() {
        let session = DictationSession(locale: Locale(identifier: "de_DE"),
                                       dictionaryEntries: [],
                                       audioURL: nil,
                                       speech: FakeSpeechEngine(), audio: FakeAudioCapture())

        XCTAssertTrue(session.beginRecording())
        XCTAssertEqual(session.state, .recording)
        XCTAssertFalse(session.beginRecording())
    }

    func testSessionsHaveDistinctIDs() {
        let first = DictationSession(locale: .current, dictionaryEntries: [],
                                     audioURL: nil, speech: FakeSpeechEngine(), audio: FakeAudioCapture())
        let second = DictationSession(locale: .current, dictionaryEntries: [],
                                      audioURL: nil, speech: FakeSpeechEngine(), audio: FakeAudioCapture())
        XCTAssertNotEqual(first.id, second.id)
    }

    func testTeardownIsIdempotent() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine()
        let session = DictationSession(locale: .current, dictionaryEntries: [],
                                       audioURL: nil, speech: speech, audio: audio)

        await session.teardown()
        await session.teardown()

        let metrics = await speech.metrics()
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(metrics.finishCount, 1)
        XCTAssertEqual(session.state, .finished)
    }

    func testTeardownDeletesAudioFile() async throws {
        let url = makeDirectory().appendingPathComponent("delete-me.wav")
        try Data("audio".utf8).write(to: url)
        let session = DictationSession(locale: .current, dictionaryEntries: [],
                                       audioURL: url, speech: FakeSpeechEngine(), audio: FakeAudioCapture())

        await session.teardown()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testShortTapBeforeEngineStartIsCompletelySilent() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine()
        let gate = PermissionGate()
        let app = makeApp(
            audio: audio,
            engines: [speech],
            permission: { await gate.request() },
            minimumPushToTalkDuration: PillChrome.presentationDelay
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { await gate.requested }
        app.stopDictation()
        await gate.resolve(true)
        await waitUntil { app.phase == .idle }
        await waitUntil { (await speech.metrics()).finishCount == 1 }

        let metrics = await speech.metrics()
        XCTAssertFalse(audio.isRunning)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(metrics.startCount, 0)
        XCTAssertTrue(toasts.isEmpty)
        XCTAssertTrue(app.history.records.isEmpty)
    }

    func testShortTapStaysVisiblyBusyAndDoesNotLoseSecondPressBehindIdle() async {
        let factory = AudioFactorySpy()
        let stopEntered = DispatchSemaphore(value: 0)
        let allowStopToFinish = DispatchSemaphore(value: 0)
        factory.configureCapture = { capture, index in
            guard index == 0 else { return }
            capture.onStop = {
                stopEntered.signal()
                allowStopToFinish.wait()
            }
        }
        let app = makeApp(
            audioFactory: { factory.make() },
            engines: [FakeSpeechEngine(), FakeSpeechEngine()],
            minimumPushToTalkDuration: 60
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { factory.captures.first?.isRunning == true }
        DispatchQueue.global(qos: .userInitiated).async {
            stopEntered.wait()
            Thread.sleep(forTimeInterval: 0.1)
            allowStopToFinish.signal()
        }

        app.stopDictation()
        XCTAssertEqual(app.phase, .transcribing)
        app.startDictation()
        XCTAssertEqual(factory.captures.count, 1)
        XCTAssertEqual(app.phase, .transcribing)
        XCTAssertEqual(toasts, ["Vorherige Aufnahme wird noch beendet."])

        await waitUntil { app.phase == .idle }
        XCTAssertEqual(factory.captures.count, 1)
    }

    func testSpeechBufferOverflowFailsSessionWithoutHistoryClipboardOrInjection() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Darf nicht gespeichert werden")
        await speech.blockNextFeed()
        let history = FakeHistoryStore()
        let textInjector = TextInjectorSpy()
        let reveal = RevealSpy()
        let recoveryDirectory = directory.appendingPathComponent("recovery", isDirectory: true)
        let recoveryStore = AudioRecoveryStore(directory: recoveryDirectory)
        let app = makeApp(
            audio: audio,
            engines: [speech],
            history: history,
            isTextFieldEditable: { true },
            injectText: { text, pid in textInjector.inject(text, targetPID: pid) },
            recoveryStore: recoveryStore,
            revealRecoveryFile: { reveal.reveal($0) },
            directory: directory
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }
        let pasteboard = NSPasteboard.general
        let previousClipboard = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousClipboard {
                pasteboard.setString(previousClipboard, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("vorheriger Inhalt", forType: .string)

        app.startDictation()
        await waitUntil { audio.isRunning && app.partialText == "Darf nicht gespeichert werden" }
        let finishedWAV = try XCTUnwrap(audio.startedURL)
        try Data("finished audio".utf8).write(to: finishedWAV)
        audio.stoppedURL = finishedWAV
        let chunk = try makeAudioChunk()
        audio.emit(chunk)
        await waitUntil { await speech.metrics().feedCount == 1 }
        for _ in 0..<65 {
            audio.emit(chunk)
        }

        await waitUntil { await speech.metrics().feedCount == 1 }
        let feedCountAfterOverflow = await speech.metrics().feedCount
        app.stopDictation()
        await speech.unblockFeed()
        await waitUntil { app.phase == .idle }

        let finalFeedCount = await speech.metrics().feedCount
        XCTAssertEqual(feedCountAfterOverflow, 1)
        XCTAssertEqual(finalFeedCount, 1)
        XCTAssertTrue(history.records.isEmpty)
        XCTAssertEqual(history.insertCount, 0)
        XCTAssertEqual(textInjector.callCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "vorheriger Inhalt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: finishedWAV.path))
        let recoveredURL = try XCTUnwrap(reveal.urls.first)
        XCTAssertEqual(recoveredURL.deletingLastPathComponent(), recoveryDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredURL.path))
        XCTAssertTrue(toasts.contains { $0.localizedCaseInsensitiveContains("finder") })
        XCTAssertNil(app.currentSession)
    }

    func testAudioRuntimeErrorFailsSessionWithoutHistoryClipboardOrInjection() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Darf nicht gespeichert werden")
        let history = FakeHistoryStore()
        let textInjector = TextInjectorSpy()
        let reveal = RevealSpy()
        let recoveryDirectory = directory.appendingPathComponent("recovery", isDirectory: true)
        let app = makeApp(
            audio: audio,
            engines: [speech],
            history: history,
            isTextFieldEditable: { true },
            injectText: { text, pid in textInjector.inject(text, targetPID: pid) },
            recoveryStore: AudioRecoveryStore(directory: recoveryDirectory),
            revealRecoveryFile: { reveal.reveal($0) },
            directory: directory
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }
        let pasteboard = NSPasteboard.general
        let previousClipboard = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousClipboard {
                pasteboard.setString(previousClipboard, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("vorheriger Inhalt", forType: .string)

        app.startDictation()
        await waitUntil { audio.isRunning && app.partialText == "Darf nicht gespeichert werden" }
        let finishedWAV = try XCTUnwrap(audio.startedURL)
        try Data("finished audio".utf8).write(to: finishedWAV)
        audio.stoppedURL = finishedWAV

        audio.fail(.conversionFailed("test"))
        audio.fail(.processingBacklog)
        await waitUntil { app.phase == .idle }

        XCTAssertTrue(history.records.isEmpty)
        XCTAssertEqual(history.insertCount, 0)
        XCTAssertEqual(textInjector.callCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "vorheriger Inhalt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: finishedWAV.path))
        let recoveredURL = try XCTUnwrap(reveal.urls.first)
        XCTAssertEqual(recoveredURL.deletingLastPathComponent(), recoveryDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredURL.path))
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(toasts.count, 1)
        XCTAssertTrue(toasts[0].localizedCaseInsensitiveContains("finder"))
        XCTAssertNil(app.currentSession)
    }

    func testRuntimeErrorDuringDiscardDoesNotRecoverOrToast() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let reveal = RevealSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Verwerfen")],
            recoveryStore: AudioRecoveryStore(
                directory: directory.appendingPathComponent("recovery", isDirectory: true)
            ),
            revealRecoveryFile: { reveal.reveal($0) },
            directory: directory
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        let wav = try XCTUnwrap(audio.startedURL)
        try Data("discard audio".utf8).write(to: wav)
        audio.stoppedURL = wav
        audio.onStop = { audio.fail(.conversionFailed("late discard failure")) }

        app.requestDiscard()
        await waitUntil { app.phase == .idle }

        XCTAssertTrue(toasts.isEmpty)
        XCTAssertTrue(reveal.urls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wav.path))
        XCTAssertTrue(app.history.records.isEmpty)
    }

    func testRuntimeErrorDuringShortTapDoesNotRecoverOrToast() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let reveal = RevealSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine()],
            minimumPushToTalkDuration: 60,
            recoveryStore: AudioRecoveryStore(
                directory: directory.appendingPathComponent("recovery", isDirectory: true)
            ),
            revealRecoveryFile: { reveal.reveal($0) },
            directory: directory
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        let wav = try XCTUnwrap(audio.startedURL)
        try Data("short tap audio".utf8).write(to: wav)
        audio.stoppedURL = wav
        audio.onStop = { audio.fail(.processingBacklog) }

        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertTrue(toasts.isEmpty)
        XCTAssertTrue(reveal.urls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wav.path))
        XCTAssertTrue(app.history.records.isEmpty)
    }

    func testRuntimeErrorDuringCommitDrainRemainsFatalAndRecoverable() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let reveal = RevealSpy()
        let recoveryDirectory = directory.appendingPathComponent("recovery", isDirectory: true)
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Nicht als Erfolg speichern")],
            recoveryStore: AudioRecoveryStore(directory: recoveryDirectory),
            revealRecoveryFile: { reveal.reveal($0) },
            directory: directory
        )
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        let wav = try XCTUnwrap(audio.startedURL)
        try Data("commit drain audio".utf8).write(to: wav)
        audio.stoppedURL = wav
        audio.onStop = { audio.fail(.wavWriteFailed("late commit failure")) }

        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertTrue(app.history.records.isEmpty)
        XCTAssertEqual(reveal.urls.count, 1)
        XCTAssertEqual(reveal.urls.first?.deletingLastPathComponent(), recoveryDirectory)
        XCTAssertTrue(toasts.contains { $0.localizedCaseInsensitiveContains("finder") })
    }

    func testRuntimeErrorDuringSuspendedCommitStopReusesResultAndRegistersRecovery() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        audio.suspendFirstStop = true
        audio.delaysRuntimeErrorDelivery = true
        let history = FakeHistoryStore()
        let textInjector = TextInjectorSpy()
        let reveal = RevealSpy()
        let sound = SoundFeedbackSpy()
        let recoveryDirectory = directory.appendingPathComponent("recovery", isDirectory: true)
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Nicht als Erfolg speichern")],
            history: history,
            isTextFieldEditable: { true },
            injectText: { text, pid in textInjector.inject(text, targetPID: pid) },
            recoveryStore: AudioRecoveryStore(directory: recoveryDirectory),
            revealRecoveryFile: { reveal.reveal($0) },
            directory: directory,
            soundFeedback: sound
        )
        app.settings.soundOn = true
        let pasteboard = NSPasteboard.general
        let previousClipboard = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousClipboard {
                pasteboard.setString(previousClipboard, forType: .string)
            }
        }
        pasteboard.clearContents()
        pasteboard.setString("vorheriger Inhalt", forType: .string)

        app.startDictation()
        await waitUntil { audio.isRunning }
        let wav = try XCTUnwrap(audio.startedURL)
        try Data("suspended commit audio".utf8).write(to: wav)
        audio.stoppedURL = wav

        app.stopDictation()
        await waitUntil { audio.stopCount == 1 }
        audio.fail(.wavWriteFailed("failure during first stop"))
        await Task.yield()
        audio.finishFirstStop()
        await waitUntil { app.phase == .idle }
        audio.deliverPendingRuntimeError()
        await Task.yield()

        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(sound.events, [.recordingStarted, .recordingStopped, .failed])
        XCTAssertTrue(history.records.isEmpty)
        XCTAssertEqual(history.insertCount, 0)
        XCTAssertEqual(textInjector.callCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "vorheriger Inhalt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: wav.path))
        let recoveredURL = try XCTUnwrap(reveal.urls.first)
        XCTAssertEqual(recoveredURL.deletingLastPathComponent(), recoveryDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredURL.path))
    }

    func testRealAudioStopFlushBlocksCommitUntilAcceptedWorkerErrorMarksHealth() async throws {
        let directory = makeDirectory()
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let sinkBox = AudioSinkBox()
        let deliveryStarted = expectation(description: "off-RT health delivery started")
        let deliveryGate = DispatchSemaphore(value: 0)
        let capture = AudioCapture(
            audioUnitHooks: AudioCapture.AudioUnitHooks(
                configureInput: { _, _, sink in
                    sinkBox.store(sink)
                    return format
                },
                initialize: {}, start: {}, stop: {}, uninitialize: {}, dispose: {}
            ),
            beforeRuntimeErrorDelivery: {
                deliveryStarted.fulfill()
                deliveryGate.wait()
            },
            processingFailure: { _ in .wavWriteFailed("blocked worker delivery") }
        )
        let history = FakeHistoryStore()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let app = makeApp(
            audioFactory: { capture },
            engines: [FakeSpeechEngine(text: "Darf nie committed werden")],
            history: history,
            isTextFieldEditable: { true },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) },
            directory: directory
        )

        app.startDictation()
        await waitUntil { app.phase == .recording }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        buffer.frameLength = 16
        try XCTUnwrap(sinkBox.load())(buffer)
        await fulfillment(of: [deliveryStarted], timeout: 1)

        app.stopDictation()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(app.phase, .transcribing)
        XCTAssertEqual(history.insertCount, 0)
        XCTAssertEqual(injector.callCount, 0)
        XCTAssertTrue(clipboard.strings.isEmpty)

        deliveryGate.signal()
        await waitUntil { app.phase == .idle }
        XCTAssertEqual(history.insertCount, 0)
        XCTAssertEqual(injector.callCount, 0)
        XCTAssertTrue(clipboard.strings.isEmpty)
    }

    func testAcceptedRuntimeErrorBlocksCommitBeforeDelayedDelivery() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        audio.delaysRuntimeErrorDelivery = true
        let history = FakeHistoryStore()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let reveal = RevealSpy()
        let sound = SoundFeedbackSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Darf nie committed werden")],
            history: history,
            isTextFieldEditable: { true },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) },
            recoveryStore: AudioRecoveryStore(
                directory: directory.appendingPathComponent("recovery", isDirectory: true)
            ),
            revealRecoveryFile: { reveal.reveal($0) },
            directory: directory,
            soundFeedback: sound
        )
        app.settings.soundOn = true
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        let wav = try XCTUnwrap(audio.startedURL)
        try Data("valid frames".utf8).write(to: wav)
        audio.stoppedURL = wav
        audio.onStop = { audio.fail(.wavWriteFailed("delayed UI delivery")) }

        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(history.insertCount, 0)
        XCTAssertEqual(injector.callCount, 0)
        XCTAssertTrue(clipboard.strings.isEmpty)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(reveal.urls.count, 1)
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(sound.events, [.recordingStarted, .recordingStopped, .failed])

        audio.deliverPendingRuntimeError()
        await Task.yield()
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(reveal.urls.count, 1)
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(sound.events, [.recordingStarted, .recordingStopped, .failed])
    }

    func testOverflowThenLateRuntimeErrorHasOneTerminalOwner() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        audio.delaysRuntimeErrorDelivery = true
        let speech = FakeSpeechEngine(text: "Unvollständig")
        await speech.blockNextFeed()
        let history = FakeHistoryStore()
        let injector = TextInjectorSpy()
        let clipboard = ClipboardSpy()
        let reveal = RevealSpy()
        let sound = SoundFeedbackSpy()
        let app = makeApp(
            audio: audio,
            engines: [speech],
            history: history,
            isTextFieldEditable: { true },
            injectText: { text, pid in injector.inject(text, targetPID: pid) },
            copyToClipboard: { clipboard.copy($0) },
            recoveryStore: AudioRecoveryStore(
                directory: directory.appendingPathComponent("recovery", isDirectory: true)
            ),
            revealRecoveryFile: { reveal.reveal($0) },
            directory: directory,
            soundFeedback: sound
        )
        app.settings.soundOn = true
        var toasts: [String] = []
        app.onToast = { message, _ in toasts.append(message) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        let wav = try XCTUnwrap(audio.startedURL)
        try Data("recoverable frames".utf8).write(to: wav)
        audio.stoppedURL = wav
        let chunk = try makeAudioChunk()
        audio.emit(chunk)
        await waitUntil { await speech.metrics().feedCount == 1 }
        for _ in 0..<65 { audio.emit(chunk) }
        audio.onStop = { audio.fail(.wavWriteFailed("late after overflow")) }

        app.stopDictation()
        await speech.unblockFeed()
        await waitUntil { app.phase == .idle }
        audio.deliverPendingRuntimeError()
        await Task.yield()

        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(history.insertCount, 0)
        XCTAssertEqual(injector.callCount, 0)
        XCTAssertTrue(clipboard.strings.isEmpty)
        XCTAssertEqual(reveal.urls.count, 1)
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(sound.events, [.recordingStarted, .recordingStopped, .failed])
    }

    func testAudioRuntimeErrorDeletesUnclosedRecording() async throws {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let app = makeApp(audio: audio, engines: [FakeSpeechEngine()], directory: directory)

        app.startDictation()
        await waitUntil { audio.isRunning }
        let unfinishedWAV = try XCTUnwrap(audio.startedURL)
        try Data("unfinished audio".utf8).write(to: unfinishedWAV)
        audio.stoppedURL = nil

        audio.fail(.wavWriteFailed("test"))
        await waitUntil { app.phase == .idle }

        XCTAssertFalse(FileManager.default.fileExists(atPath: unfinishedWAV.path))
        XCTAssertTrue(app.history.records.isEmpty)
    }

    func testEmptyTranscriptPerformsCompleteIdleReset() async {
        let audio = FakeAudioCapture()
        let app = makeApp(audio: audio, engines: [FakeSpeechEngine()])

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.updateElapsedFromPoll(now: Date().addingTimeInterval(5))
        XCTAssertGreaterThan(app.elapsed, 4)

        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(app.elapsed, 0)
        XCTAssertEqual(app.displayLevel, 0)
        app.updateElapsedFromPoll(now: Date().addingTimeInterval(30))
        XCTAssertEqual(app.elapsed, 0)
    }

    func testHistoryInsertFailurePreservesFinishedAudioAndSkipsInjection() async throws {
        let directory = makeDirectory()
        let finishedWAV = directory.appendingPathComponent("finished.wav")
        try Data("finished audio".utf8).write(to: finishedWAV)
        let audio = FakeAudioCapture()
        audio.stoppedURL = finishedWAV
        let history = FakeHistoryStore()
        history.insertError = FakeError.history
        let textInjector = TextInjectorSpy()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Nicht verlieren")],
            history: history,
            isTextFieldEditable: { true },
            injectText: { text, pid in textInjector.inject(text, targetPID: pid) },
            directory: directory
        )

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.updateElapsedFromPoll(now: Date().addingTimeInterval(5))
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(history.insertCount, 1)
        XCTAssertEqual(app.elapsed, 0)
        app.updateElapsedFromPoll(now: Date().addingTimeInterval(30))
        XCTAssertEqual(app.elapsed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finishedWAV.path))
        XCTAssertEqual(textInjector.callCount, 0)
        XCTAssertEqual(app.phase, .idle)
    }

    func testCompletionAndDiscardStaySilentWhileErrorsStillToast() async {
        let factory = AudioFactorySpy()
        let app = makeApp(
            audioFactory: { factory.make() },
            engines: [
                FakeSpeechEngine(text: "Erfolgreiches Diktat"),
                FakeSpeechEngine(text: "Wird verworfen"),
                FakeSpeechEngine(),
            ],
            isTextFieldEditable: { true }
        )
        var toasts: [(String, Bool)] = []
        app.onToast = { toasts.append(($0, $1)) }

        app.startDictation()
        await waitUntil { factory.captures.first?.isRunning == true }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        app.startDictation()
        await waitUntil { factory.captures.count == 2 && factory.captures[1].isRunning }
        app.requestDiscard()
        await waitUntil { app.phase == .idle }

        app.startDictation()
        await waitUntil { factory.captures.count == 3 && factory.captures[2].isRunning }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(toasts.first?.0, Copy.toastNothingHeard)
        XCTAssertEqual(toasts.first?.1, false)
    }

    func testPreparingIsVisibleAndSecondHandsFreeActivationJoinsSetupBeforeTeardown() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine()
        await speech.blockStart()
        let app = makeApp(audio: audio, engines: [speech])
        app.startCommandLoop()

        app.handsFreeToggle()
        await waitUntil { await speech.hasEnteredStart() }

        XCTAssertEqual(app.phase, .preparing)
        XCTAssertNil(app.recordStart)

        app.handsFreeToggle()
        XCTAssertEqual(app.phase, .preparing)
        XCTAssertEqual(audio.startCount, 0)
        XCTAssertEqual(audio.stopCount, 0)
        let metricsBeforeTimeout = await speech.metrics()
        XCTAssertEqual(metricsBeforeTimeout.finishCount, 0)

        app.checkPhaseWatchdog(now: Date().addingTimeInterval(16))
        await waitUntil { app.phase == .setupTimedOut }
        XCTAssertEqual(audio.stopCount, 0)
        let metricsWhileBlocked = await speech.metrics()
        XCTAssertEqual(metricsWhileBlocked.finishCount, 0)

        await speech.unblockStart()
        await waitUntil { app.phase == .idle && app.currentSession == nil }

        let metrics = await speech.metrics()
        XCTAssertEqual(audio.startCount, 0)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(metrics.finishCount, 1)
    }

    func testPreparingWatchdogShowsRestartStateUntilSetupReturns() async {
        let speech = FakeSpeechEngine()
        await speech.blockStart()
        let app = makeApp(audio: FakeAudioCapture(), engines: [speech])
        app.startCommandLoop()

        app.startDictation()
        await waitUntil { await speech.hasEnteredStart() }
        app.checkPhaseWatchdog(now: Date().addingTimeInterval(16))
        await waitUntil { app.phase == .setupTimedOut }

        XCTAssertNotNil(app.currentSession)
        await speech.unblockStart()
        await waitUntil { app.phase == .idle && app.currentSession == nil }
    }

    func testCaptureBoundaryDiscardsHardwareAndCueBuffersAndStartsDurationAtActivation() async throws {
        let audio = FakeAudioCapture()
        let clock = FakeClock()
        let history = FakeHistoryStore()
        let speech = FakeSpeechEngine(text: "Grenzaufnahme")
        let chunk = try makeAudioChunk()
        audio.onStart = {
            clock.advance(by: 0.2)
            audio.emit(chunk)
        }
        let app = makeApp(
            audio: audio,
            engines: [speech],
            minimumPushToTalkDuration: 0,
            history: history,
            now: { clock.now },
            soundFeedback: SoundFeedbackSpy(onPlay: { event in
                guard event == .recordingStarted else { return }
                audio.emit(chunk)
            })
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { app.phase == .recording }
        let expectedStart = clock.now
        audio.emit(chunk)
        await waitUntil { await speech.metrics().feedCount == 1 }

        XCTAssertEqual(app.recordStart, expectedStart)
        let metrics = await speech.metrics()
        XCTAssertEqual(metrics.feedCount, 1)
        clock.advance(by: 0.05)
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(history.records.first?.durationSecs ?? -1, 0.05, accuracy: 0.001)
    }

    func testSetupStopCancelsOnlyActiveStartCueAndEmitsNoRecordingEvents() async {
        let audio = FakeAudioCapture()
        let cue = EventLog()
        let sound = SoundFeedbackSpy(onPlay: { event in
            guard event == .recordingStarted else { return }
            cue.append("started")
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                cue.append("cancelled")
            }
        })
        let speech = FakeSpeechEngine()
        let app = makeApp(audio: audio, engines: [speech], soundFeedback: sound)
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { cue.events.contains("started") }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(cue.events, ["started", "cancelled"])
        XCTAssertTrue(sound.events.isEmpty)
        XCTAssertEqual(audio.stopCount, 1)
        let metrics = await speech.metrics()
        XCTAssertEqual(metrics.streamCancellationCount, 0)
    }

    func testActivationWinningBeforeCueMakesCueRuntimeFailurePostStart() async {
        let audio = FakeAudioCapture()
        let cueGate = PermissionGate()
        let sound = SoundFeedbackSpy(onPlay: { event in
            guard event == .recordingStarted else { return }
            _ = await cueGate.request()
        })
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine()],
            soundFeedback: sound
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { await cueGate.requested }
        XCTAssertTrue(audio.isRunning)
        XCTAssertEqual(audio.activateCount, 1)
        XCTAssertFalse(audio.isCaptureActive)

        audio.fail(.processingBacklog)
        await Task.yield()
        await cueGate.resolve(true)
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(audio.openCount, 0)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(sound.events, [.failed])
    }

    func testRuntimeErrorWinningActivationCrossingPlaysFailedOnly() async {
        let audio = FakeAudioCapture()
        let sound = SoundFeedbackSpy()
        audio.onActivate = { audio.fail(.processingBacklog) }
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine()],
            soundFeedback: sound
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { app.phase == .idle && app.currentSession == nil }

        XCTAssertEqual(audio.activateCount, 1)
        XCTAssertEqual(audio.openCount, 0)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(sound.events, [.failed])
    }

    func testRuntimeFailureBeforeCaptureActivationPlaysFailedOnlyAndNeverPublishesRecording() async {
        let audio = FakeAudioCapture()
        let observedPhases = EventLog()
        let sound = SoundFeedbackSpy()
        weak var appReference: AppState?
        audio.onStart = {
            Task { @MainActor in
                if let phase = appReference?.phase {
                    observedPhases.append(phase.rawValue)
                }
            }
            audio.fail(.processingBacklog)
        }
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine()],
            soundFeedback: sound
        )
        appReference = app
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { !observedPhases.events.isEmpty && app.currentSession == nil }

        XCTAssertFalse(observedPhases.events.contains(AppState.Phase.recording.rawValue))
        XCTAssertEqual(app.phase, .idle)
        XCTAssertNil(app.recordStart)
        XCTAssertEqual(audio.activateCount, 0)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(sound.events, [.failed])
    }

    func testTargetApplicationRefreshesAtActualAudioBoundary() async {
        let before = makeTargetApplication(named: "Before", processIdentifier: 1)
        let actual = makeTargetApplication(named: "Actual", processIdentifier: 2)
        let frontmost = FrontmostApplicationStub(before)
        let cueGate = PermissionGate()
        let audio = FakeAudioCapture()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine()],
            frontmostApplication: { frontmost.application() },
            soundFeedback: SoundFeedbackSpy(onPlay: { event in
                guard event == .recordingStarted else { return }
                _ = await cueGate.request()
            })
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { await cueGate.requested }
        XCTAssertEqual(audio.startCount, 1)
        XCTAssertFalse(audio.isCaptureActive)
        frontmost.current = actual
        await cueGate.resolve(true)
        await waitUntil { app.phase == .recording }

        XCTAssertEqual(app.currentSession?.targetApplication, actual)
        XCTAssertEqual(frontmost.callCount, 1)
        XCTAssertFalse(app.currentSession?.assignTargetApplication(before) ?? true)
        XCTAssertEqual(app.currentSession?.targetApplication, actual)
        app.requestDiscard()
        await waitUntil { app.phase == .idle }
    }

    func testInjectedClockDrivesDefaultPollAndMonotonicShortTapDuration() async {
        let audio = FakeAudioCapture()
        let clock = FakeClock()
        let history = FakeHistoryStore()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Bleibt kurz")],
            minimumPushToTalkDuration: PillChrome.presentationDelay,
            history: history,
            now: { clock.now }
        )

        app.startDictation()
        await waitUntil { audio.isRunning }
        clock.advance(by: 0.2)
        app.updateElapsedFromPoll()
        XCTAssertEqual(app.elapsed, 0.2, accuracy: 0.001)

        clock.advance(by: -0.15)
        app.updateElapsedFromPoll()
        XCTAssertEqual(app.elapsed, 0.2, accuracy: 0.001)

        app.stopDictation()
        await waitUntil { app.phase == .idle }
        XCTAssertTrue(history.records.isEmpty)
    }

    func testProductionPollUsesAppStatesInjectedRecordingClock() async {
        let audio = FakeAudioCapture()
        let clock = FakeClock()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine()],
            now: { clock.now }
        )

        app.startDictation()
        await waitUntil { audio.isRunning }
        clock.advance(by: 0.4)

        AppDelegate.updateRecordingElapsed(app)

        XCTAssertEqual(app.elapsed, 0.4, accuracy: 0.001)
        app.requestDiscard()
        await waitUntil { app.phase == .idle }
    }

    func testHardwareStartsThenActivationWinsThenCueFinishesThenCaptureOpens() async {
        let audio = FakeAudioCapture()
        let events = EventLog()
        weak var appReference: AppState?
        audio.onStart = { events.append("hardware.start") }
        audio.onActivate = {
            XCTAssertEqual(appReference?.phase, .preparing)
            XCTAssertNil(appReference?.recordStart)
            events.append("capture.activate")
        }
        audio.onOpen = {
            XCTAssertEqual(appReference?.phase, .preparing)
            XCTAssertNil(appReference?.recordStart)
            events.append("capture.open")
        }
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine()],
            soundFeedback: SoundFeedbackSpy(onPlay: { event in
                guard event == .recordingStarted else { return }
                XCTAssertEqual(appReference?.phase, .preparing)
                XCTAssertNil(appReference?.recordStart)
                events.append("cue.complete")
            })
        )
        appReference = app
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { app.phase == .recording }

        XCTAssertEqual(events.events, [
            "hardware.start", "capture.activate", "cue.complete", "capture.open",
        ])
        XCTAssertTrue(audio.isCaptureActive)
        XCTAssertNotNil(app.recordStart)
        app.requestDiscard()
        await waitUntil { app.phase == .idle }
    }

    func testBlockedSetupDoesNotPublishRecordingTimingOrElapsedTime() async {
        let audio = FakeAudioCapture()
        let gate = PermissionGate()
        let clock = FakeClock()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine()],
            permission: { await gate.request() },
            now: { clock.now }
        )

        app.startDictation()
        await waitUntil { await gate.requested }
        clock.advance(by: 30)
        app.updateElapsedFromPoll(now: clock.now)

        XCTAssertEqual(app.phase, .preparing)
        XCTAssertNil(app.recordStart)
        XCTAssertEqual(app.elapsed, 0)
        XCTAssertFalse(audio.isRunning)

        app.stopDictation()
        await gate.resolve(true)
        await waitUntil { app.currentSession == nil }
    }

    func testSetupDelayIsExcludedFromRecordedDuration() async {
        let audio = FakeAudioCapture()
        let gate = PermissionGate()
        let clock = FakeClock()
        let history = FakeHistoryStore()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Zwei Sekunden Aufnahme")],
            permission: { await gate.request() },
            history: history,
            now: { clock.now }
        )

        app.startDictation()
        await waitUntil { await gate.requested }
        clock.advance(by: 10)
        await gate.resolve(true)
        await waitUntil { audio.isRunning }

        XCTAssertEqual(app.phase, .recording)
        XCTAssertEqual(app.recordStart, clock.now)
        XCTAssertEqual(app.elapsed, 0)

        clock.advance(by: 2)
        app.updateElapsedFromPoll(now: clock.now)
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(history.records.first?.durationSecs ?? -1, 2, accuracy: 0.001)
    }

    func testSetupDelayDoesNotSatisfyShortTapThreshold() async {
        let audio = FakeAudioCapture()
        let gate = PermissionGate()
        let clock = FakeClock()
        let history = FakeHistoryStore()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Zu kurz")],
            permission: { await gate.request() },
            minimumPushToTalkDuration: PillChrome.presentationDelay,
            history: history,
            now: { clock.now }
        )

        app.startDictation()
        await waitUntil { await gate.requested }
        clock.advance(by: 10)
        await gate.resolve(true)
        await waitUntil { audio.isRunning }
        clock.advance(by: PillChrome.presentationDelay - 0.001)

        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertTrue(history.records.isEmpty)
    }

    func testSetupErrorTearsEverythingDown() async {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(startError: FakeError.setup)
        let app = makeApp(audio: audio, engines: [speech], directory: directory)

        app.startDictation()
        await waitUntil { app.currentSession == nil }

        let metrics = await speech.metrics()
        XCTAssertFalse(audio.isRunning)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(metrics.finishCount, 1)
        XCTAssertNil(app.currentSession)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("audio"),
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(files.isEmpty)
    }

    func testAudioStartErrorTearsEverythingDownWithFailedFeedbackOnly() async {
        let audio = FakeAudioCapture()
        audio.startError = FakeError.audio
        let speech = FakeSpeechEngine()
        let sound = SoundFeedbackSpy()
        let app = makeApp(audio: audio, engines: [speech], soundFeedback: sound)
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { app.currentSession == nil }

        let metrics = await speech.metrics()
        XCTAssertEqual(app.phase, .idle)
        XCTAssertNil(app.recordStart)
        XCTAssertEqual(app.elapsed, 0)
        XCTAssertEqual(audio.startCount, 1)
        XCTAssertEqual(audio.activateCount, 0)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(metrics.finishCount, 1)
        XCTAssertEqual(sound.events, [.failed])
        XCTAssertNil(app.currentSession)
    }

    func testDiscardNeverCancelsResultStream() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Nicht speichern")
        let app = makeApp(audio: audio, engines: [speech])

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.requestDiscard()
        await waitUntil { app.phase == .idle }

        let metrics = await speech.metrics()
        XCTAssertEqual(metrics.streamCancellationCount, 0)
        XCTAssertEqual(metrics.finishCount, 1)
        XCTAssertTrue(app.history.records.isEmpty)
    }

    func testStopDrainsBeforeSpeechFinish() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Fertig")
        let app = makeApp(audio: audio, engines: [speech])

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.requestDiscard()
        await waitUntil { app.phase == .idle }

        let metrics = await speech.metrics()
        XCTAssertEqual(metrics.finishCount, 1)
        XCTAssertFalse(audio.isRunning)
        XCTAssertEqual(metrics.streamCancellationCount, 0)
    }

    func testFinalizeTimeoutReturnsWithCurrentTextWithinLimit() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Zwischenstand")
        await speech.configureFinish(delay: 4_000_000_000, timeout: 3_000_000_000)
        let app = makeApp(audio: audio, engines: [speech])

        app.startDictation()
        await waitUntil { audio.isRunning }
        let started = Date()
        app.stopDictation()
        await waitUntil(timeout: 3.5) { !app.history.records.isEmpty }

        let metrics = await speech.metrics()
        XCTAssertLessThan(Date().timeIntervalSince(started), 3.5)
        XCTAssertEqual(app.history.records.first?.rawText, "Zwischenstand")
        XCTAssertTrue(metrics.finalizeStillRunning)
    }

    func testNonEndingResultStreamStillReturnsIdleAndUsesLatestText() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Kurzer Zwischenstand")
        await speech.configureFinishEndsResultStream(false)
        let app = makeApp(
            audio: audio,
            engines: [speech],
            consumeTimeoutNanoseconds: 20_000_000
        )

        app.startDictation()
        await waitUntil { audio.isRunning && app.partialText == "Kurzer Zwischenstand" }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        let metrics = await speech.metrics()
        XCTAssertEqual(app.history.records.first?.rawText, "Kurzer Zwischenstand")
        XCTAssertEqual(metrics.streamCancellationCount, 0)
    }

    func testEachDictationUsesFreshAudioCapture() async {
        let factory = AudioFactorySpy()
        let app = makeApp(
            audioFactory: { factory.make() },
            engines: [FakeSpeechEngine(), FakeSpeechEngine()]
        )

        app.startDictation()
        await waitUntil { factory.captures.first?.isRunning == true }
        app.requestDiscard()
        await waitUntil { app.phase == .idle }

        app.startDictation()
        await waitUntil { factory.captures.count == 2 && factory.captures[1].isRunning }

        XCTAssertEqual(factory.captures.count, 2)
        XCTAssertFalse(factory.captures[0] === factory.captures[1])
        app.requestDiscard()
        await waitUntil { app.phase == .idle }
    }

    func testTwoImmediateCommittedDictationsBothReturnIdle() async {
        let factory = AudioFactorySpy()
        let first = FakeSpeechEngine(text: "Erstes kurzes Diktat")
        await first.configureFinishEndsResultStream(false)
        let second = FakeSpeechEngine(text: "Zweites kurzes Diktat")
        let app = makeApp(
            audioFactory: { factory.make() },
            engines: [first, second],
            consumeTimeoutNanoseconds: 20_000_000
        )

        app.startDictation()
        await waitUntil {
            factory.captures.first?.isRunning == true
                && app.partialText == "Erstes kurzes Diktat"
        }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        app.startDictation()
        await waitUntil {
            factory.captures.count == 2
                && factory.captures[1].isRunning
                && app.partialText == "Zweites kurzes Diktat"
        }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(app.history.records.map(\.rawText), [
            "Zweites kurzes Diktat", "Erstes kurzes Diktat",
        ])
        let firstMetrics = await first.metrics()
        let secondMetrics = await second.metrics()
        XCTAssertEqual(firstMetrics.streamCancellationCount, 0)
        XCTAssertEqual(secondMetrics.streamCancellationCount, 0)
    }

    func testPhaseWatchdogRecoversHungTranscription() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Hängender Text")
        await speech.configureFinishEndsResultStream(false)
        let app = makeApp(
            audio: audio,
            engines: [speech],
            consumeTimeoutNanoseconds: 500_000_000
        )
        var toasts: [(String, Bool)] = []
        app.onToast = { toasts.append(($0, $1)) }
        app.startCommandLoop()

        app.startDictation()
        await waitUntil { audio.isRunning && app.partialText == "Hängender Text" }
        app.stopDictation()
        await waitUntil { app.phase == .transcribing }
        app.checkPhaseWatchdog(now: Date().addingTimeInterval(16))
        await waitUntil { app.phase == .idle }

        XCTAssertNil(app.currentSession)
        XCTAssertFalse(audio.isRunning)
        XCTAssertEqual(toasts.last?.0, Copy.toastTranscriptionAborted)
        XCTAssertEqual(toasts.last?.1, false)
    }

    func testRecordUsesLocaleSnapshotFromSession() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(text: "Locale Snapshot")
        let app = makeApp(audio: audio, engines: [speech])
        app.settings.language = "de_DE"

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.settings.language = "en_US"
        app.stopDictation()
        await waitUntil { !app.history.records.isEmpty }

        XCTAssertEqual(app.history.records.first?.localeID, "de_DE")
    }

    func testResolvedSpeechLocaleDeterminesSessionAndRecordMetadata() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(
            text: "Aufgelöste Locale",
            resolvedLocale: Locale(identifier: "de-DE")
        )
        let app = makeApp(audio: audio, engines: [speech])
        app.settings.language = "de_CH"

        app.startDictation()
        await waitUntil { audio.isRunning }

        XCTAssertEqual(app.currentSession?.locale.identifier, "de-DE")
        app.stopDictation()
        await waitUntil { !app.history.records.isEmpty }

        XCTAssertEqual(app.history.records.first?.localeID, "de-DE")
    }

    func testSecondSessionStartsWhileFirstFinalizeRests() async {
        let factory = AudioFactorySpy()
        let first = FakeSpeechEngine(text: "Erstes Diktat")
        await first.configureFinish(delay: 1_000_000_000, timeout: 50_000_000)
        let second = FakeSpeechEngine(text: "Zweites Diktat")
        let app = makeApp(
            audioFactory: { factory.make() },
            engines: [first, second]
        )

        app.startDictation()
        await waitUntil { factory.captures.first?.isRunning == true }
        app.stopDictation()
        await waitUntil { app.phase == .idle }
        let firstMetrics = await first.metrics()
        XCTAssertTrue(firstMetrics.finalizeStillRunning)

        app.startDictation()
        await waitUntil {
            guard factory.captures.count == 2,
                  factory.captures[1].isRunning else { return false }
            return await second.metrics().startCount == 1
        }

        XCTAssertEqual(app.phase, .recording)
        XCTAssertNotNil(app.currentSession)
        app.requestDiscard()
        await waitUntil { app.phase == .idle }
    }

    func testStopCueRunsInParallelWithSpeechFinalization() async {
        let stopCueGate = PermissionGate()
        let speech = FakeSpeechEngine(text: "Parallel")
        let sound = SoundFeedbackSpy(onPlay: { event in
            guard event == .recordingStopped else { return }
            _ = await stopCueGate.request()
        })
        let audio = FakeAudioCapture()
        let app = makeApp(audio: audio, engines: [speech], soundFeedback: sound)
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        await waitUntil { await stopCueGate.requested }
        await waitUntil { await speech.metrics().finishCount == 1 }

        XCTAssertEqual(app.phase, .transcribing)
        XCTAssertTrue(app.history.records.isEmpty)
        await stopCueGate.resolve(true)
        await waitUntil { app.phase == .idle }
        XCTAssertEqual(sound.events, [
            .recordingStarted, .recordingStopped, .processingCompleted,
        ])
    }

    func testSoundFeedbackSuccessTimelineWaitsForCueAndAudioStop() async {
        let timeline = EventLog()
        let audio = FakeAudioCapture()
        audio.onStart = { timeline.append("hardware.start") }
        audio.onActivate = { timeline.append("capture.activate") }
        audio.onOpen = { timeline.append("capture.open") }
        audio.onStop = { timeline.append("audio.stop") }
        let sound = SoundFeedbackSpy(timeline: timeline)
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Erfolgreich")],
            soundFeedback: sound
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(sound.events, [
            .recordingStarted, .recordingStopped, .processingCompleted,
        ])
        XCTAssertEqual(timeline.events, [
            "hardware.start", "capture.activate", "sound.recordingStarted", "capture.open",
            "audio.stop", "sound.recordingStopped", "sound.processingCompleted",
        ])
    }

    func testSetupFailurePlaysOnlyFailedFeedback() async {
        let sound = SoundFeedbackSpy()
        let app = makeApp(
            engines: [FakeSpeechEngine(startError: FakeError.setup)],
            soundFeedback: sound
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { app.currentSession == nil }

        XCTAssertEqual(sound.events, [.failed])
    }

    func testRuntimeFailureAfterStartStopsBeforeSingleFailureFeedback() async {
        let timeline = EventLog()
        let audio = FakeAudioCapture()
        audio.onStop = { timeline.append("audio.stop") }
        let sound = SoundFeedbackSpy(timeline: timeline)
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Fehler")],
            soundFeedback: sound
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { audio.isRunning }
        audio.fail(.processingBacklog)
        audio.fail(.conversionFailed("doppelt"))
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(sound.events, [.recordingStarted, .recordingStopped, .failed])
        XCTAssertEqual(timeline.events, [
            "sound.recordingStarted", "audio.stop", "sound.recordingStopped", "sound.failed",
        ])
    }

    func testDiscardAndShortTapPlayStartedThenStoppedWithoutTerminalFeedback() async {
        let factory = AudioFactorySpy()
        let sound = SoundFeedbackSpy()
        let clock = FakeClock()
        let app = makeApp(
            audioFactory: { factory.make() },
            engines: [FakeSpeechEngine(), FakeSpeechEngine()],
            minimumPushToTalkDuration: PillChrome.presentationDelay,
            now: { clock.now },
            soundFeedback: sound
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { factory.captures.first?.isRunning == true }
        app.requestDiscard()
        await waitUntil { app.phase == .idle }

        app.startDictation()
        await waitUntil { factory.captures.count == 2 && factory.captures[1].isRunning }
        clock.advance(by: PillChrome.presentationDelay - 0.001)
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(sound.events, [
            .recordingStarted, .recordingStopped,
            .recordingStarted, .recordingStopped,
        ])
    }

    func testHistoryFailurePlaysStoppedThenFailedWithoutCompleted() async {
        let history = FakeHistoryStore()
        history.insertError = FakeError.history
        let sound = SoundFeedbackSpy()
        let audio = FakeAudioCapture()
        let app = makeApp(
            audio: audio,
            engines: [FakeSpeechEngine(text: "Nicht gespeichert")],
            history: history,
            soundFeedback: sound
        )
        app.settings.soundOn = true

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(sound.events, [.recordingStarted, .recordingStopped, .failed])
    }

    func testSoundSettingIsSnapshottedPerSessionForAllOrNoneFeedback() async {
        let sound = SoundFeedbackSpy()
        let factory = AudioFactorySpy()
        let app = makeApp(
            audioFactory: { factory.make() },
            engines: [
                FakeSpeechEngine(text: "Still erfolgreich"),
                FakeSpeechEngine(text: "Mit Feedback erfolgreich"),
            ],
            soundFeedback: sound
        )

        app.settings.soundOn = false
        app.startDictation()
        await waitUntil { factory.captures.first?.isRunning == true }
        app.settings.soundOn = true
        app.stopDictation()
        await waitUntil { app.phase == .idle }
        XCTAssertTrue(sound.events.isEmpty)

        app.settings.soundOn = true
        app.startDictation()
        await waitUntil { factory.captures.count == 2 && factory.captures[1].isRunning }
        app.settings.soundOn = false
        app.stopDictation()
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(sound.events, [
            .recordingStarted, .recordingStopped, .processingCompleted,
        ])
        XCTAssertEqual(app.history.records.map(\.rawText), [
            "Mit Feedback erfolgreich", "Still erfolgreich",
        ])
    }
}
