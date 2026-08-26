import AVFoundation
import XCTest
@testable import Stasi

@MainActor
final class DictationSessionTests: XCTestCase {
    private enum FakeError: Error { case setup, audio }

    private final class FakeAudioCapture: AudioCapturing, @unchecked Sendable {
        var latestLevel: Double = 0
        private(set) var isRunning = false
        private(set) var startCount = 0
        private(set) var stopCount = 0
        var startError: Error?

        func ingestNativeBuffer(_ buffer: AVAudioPCMBuffer) {
            latestLevel = AudioCapture.computeLevel(of: buffer)
        }

        func start(outputFormat: AVAudioFormat,
                   recordTo url: URL?,
                   preferredMicUID: String?,
                   onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws {
            startCount += 1
            if let startError { throw startError }
            isRunning = true
        }

        func stop() -> URL? {
            stopCount += 1
            isRunning = false
            return nil
        }
    }

    private actor FakeSpeechEngine: SpeechEngining {
        struct Metrics: Sendable {
            let startCount: Int
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
        var finishDelayNanoseconds: UInt64 = 0
        var timeoutNanoseconds: UInt64?
        var finishEndsResultStream = true
        private(set) var finalizeStillRunning = false

        init(text: String = "", startError: Error? = nil) {
            self.text = text
            self.startError = startError
        }

        func configureFinish(delay: UInt64, timeout: UInt64?) {
            finishDelayNanoseconds = delay
            timeoutNanoseconds = timeout
        }

        func configureFinishEndsResultStream(_ value: Bool) {
            finishEndsResultStream = value
        }

        func metrics() -> Metrics {
            Metrics(startCount: startCount,
                    finishCount: finishCount,
                    streamCancellationCount: streamCancellationCount,
                    finalizeStillRunning: finalizeStillRunning)
        }

        func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
            startCount += 1
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

        func feed(_ chunk: AudioChunk) async { feedCount += 1 }

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

    private final class SpellCheckerSpy {
        private(set) var calls: [(word: String, language: String)] = []

        func isKnown(_ word: String, language: String) -> Bool {
            calls.append((word, language))
            return false
        }
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

    private func makeApp(audio: FakeAudioCapture,
                         engines: [FakeSpeechEngine],
                         permission: @escaping @MainActor () async -> Bool = { true },
                         modelInstaller: @escaping @Sendable (Locale) async throws -> Void = { _ in },
                         spellChecker: @escaping @MainActor (String, String) -> Bool = { _, _ in true },
                         consumeTimeoutNanoseconds: UInt64 = 2_000_000_000,
                         minimumPushToTalkDuration: TimeInterval = 0,
                         directory: URL? = nil) -> AppState {
        let root = directory ?? makeDirectory()
        let dictionary = DictionaryStore(directory: root.appendingPathComponent("dictionary"))
        let history = HistoryStore(directory: root.appendingPathComponent("history"))
        var remaining = engines
        return AppState(
            settings: makeSettings(),
            dictionary: dictionary,
            history: history,
            audio: audio,
            speechFactory: { _, _ in remaining.removeFirst() },
            requestMicrophone: permission,
            modelInstaller: modelInstaller,
            spellChecker: spellChecker,
            consumeTimeoutNanoseconds: consumeTimeoutNanoseconds,
            minimumPushToTalkDuration: minimumPushToTalkDuration,
            installHotkey: false,
            audioDirectory: root.appendingPathComponent("audio")
        )
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

    func testFinishedDictationMergesLearnedCandidateUsingInjectedSpellChecker() async {
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
        app.history.insert(TranscriptionRecord(
            date: Date().addingTimeInterval(-60),
            localeID: "de_DE",
            rawText: "Der Frobulator hilft",
            correctedText: "Der Frobulator hilft",
            corrections: []
        ))

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation(commit: true)
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

    func testSessionSnapshotsAreImmutable() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine()
        let locale = Locale(identifier: "de_DE")
        let entry = DictionaryEntry(type: .word, value: "Stasi")
        let url = makeDirectory().appendingPathComponent("snapshot.wav")
        let session = DictationSession(locale: locale,
                                       dictionaryEntries: [entry],
                                       targetApp: "TextEdit",
                                       audioURL: url,
                                       speech: speech,
                                       audio: audio)

        XCTAssertEqual(session.locale.identifier, "de_DE")
        XCTAssertEqual(session.dictionaryEntries, [entry])
        XCTAssertEqual(session.targetApp, "TextEdit")
        XCTAssertEqual(session.audioURL, url)
    }

    func testNewSessionStartsInSettingUpState() {
        let session = DictationSession(locale: Locale(identifier: "de_DE"),
                                       dictionaryEntries: [], targetApp: "", audioURL: nil,
                                       speech: FakeSpeechEngine(), audio: FakeAudioCapture())
        XCTAssertEqual(session.state, .settingUp)
    }

    func testSessionsHaveDistinctIDs() {
        let first = DictationSession(locale: .current, dictionaryEntries: [], targetApp: "",
                                     audioURL: nil, speech: FakeSpeechEngine(), audio: FakeAudioCapture())
        let second = DictationSession(locale: .current, dictionaryEntries: [], targetApp: "",
                                      audioURL: nil, speech: FakeSpeechEngine(), audio: FakeAudioCapture())
        XCTAssertNotEqual(first.id, second.id)
    }

    func testTeardownIsIdempotent() async {
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine()
        let session = DictationSession(locale: .current, dictionaryEntries: [], targetApp: "",
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
        let session = DictationSession(locale: .current, dictionaryEntries: [], targetApp: "",
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
        app.stopDictation(commit: true)
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

    func testCompletionAndDiscardStaySilentWhileErrorsStillToast() async {
        let audio = FakeAudioCapture()
        let app = makeApp(
            audio: audio,
            engines: [
                FakeSpeechEngine(text: "Erfolgreiches Diktat"),
                FakeSpeechEngine(text: "Wird verworfen"),
                FakeSpeechEngine(),
            ]
        )
        var toasts: [(String, Bool)] = []
        app.onToast = { toasts.append(($0, $1)) }

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation(commit: true)
        await waitUntil { app.phase == .idle }

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.requestDiscard()
        await waitUntil { app.phase == .idle }

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation(commit: true)
        await waitUntil { app.phase == .idle }

        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(toasts.first?.0, Copy.toastNothingHeard)
        XCTAssertEqual(toasts.first?.1, false)
    }

    func testSetupErrorTearsEverythingDown() async {
        let directory = makeDirectory()
        let audio = FakeAudioCapture()
        let speech = FakeSpeechEngine(startError: FakeError.setup)
        let app = makeApp(audio: audio, engines: [speech], directory: directory)

        app.startDictation()
        await waitUntil { app.phase == .idle }

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

    func testAudioStartErrorTearsEverythingDown() async {
        let audio = FakeAudioCapture()
        audio.startError = FakeError.audio
        let speech = FakeSpeechEngine()
        let app = makeApp(audio: audio, engines: [speech])

        app.startDictation()
        await waitUntil { app.phase == .idle }

        let metrics = await speech.metrics()
        XCTAssertEqual(audio.startCount, 1)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(metrics.finishCount, 1)
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
        app.stopDictation(commit: true)
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
        app.stopDictation(commit: true)
        await waitUntil { app.phase == .idle }

        let metrics = await speech.metrics()
        XCTAssertEqual(app.history.records.first?.rawText, "Kurzer Zwischenstand")
        XCTAssertEqual(metrics.streamCancellationCount, 0)
    }

    func testTwoImmediateCommittedDictationsBothReturnIdle() async {
        let audio = FakeAudioCapture()
        let first = FakeSpeechEngine(text: "Erstes kurzes Diktat")
        await first.configureFinishEndsResultStream(false)
        let second = FakeSpeechEngine(text: "Zweites kurzes Diktat")
        let app = makeApp(
            audio: audio,
            engines: [first, second],
            consumeTimeoutNanoseconds: 20_000_000
        )

        app.startDictation()
        await waitUntil { audio.isRunning && app.partialText == "Erstes kurzes Diktat" }
        app.stopDictation(commit: true)
        await waitUntil { app.phase == .idle }

        app.startDictation()
        await waitUntil { audio.isRunning && app.partialText == "Zweites kurzes Diktat" }
        app.stopDictation(commit: true)
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
        app.stopDictation(commit: true)
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
        app.stopDictation(commit: true)
        await waitUntil { !app.history.records.isEmpty }

        XCTAssertEqual(app.history.records.first?.localeID, "de_DE")
    }

    func testSecondSessionStartsWhileFirstFinalizeRests() async {
        let audio = FakeAudioCapture()
        let first = FakeSpeechEngine(text: "Erstes Diktat")
        await first.configureFinish(delay: 1_000_000_000, timeout: 50_000_000)
        let second = FakeSpeechEngine(text: "Zweites Diktat")
        let app = makeApp(audio: audio, engines: [first, second])

        app.startDictation()
        await waitUntil { audio.isRunning }
        app.stopDictation(commit: true)
        await waitUntil { app.phase == .idle }
        let firstMetrics = await first.metrics()
        XCTAssertTrue(firstMetrics.finalizeStillRunning)

        app.startDictation()
        await waitUntil { await second.metrics().startCount == 1 }

        XCTAssertEqual(app.phase, .recording)
        XCTAssertNotNil(app.currentSession)
        app.requestDiscard()
        await waitUntil { app.phase == .idle }
    }
}
