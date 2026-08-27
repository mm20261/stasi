import Foundation

/// Besitzt sämtliche Ressourcen genau eines Diktats. Snapshots verhindern,
/// dass Einstellungs- oder Wörterbuchänderungen in eine laufende Session
/// hineinwirken.
@MainActor
final class DictationSession {
    enum State: Equatable {
        case settingUp
        case recording
        case stopping
        case finished
    }

    enum CompletionIntent: Equatable {
        case active
        case commit
        case discard
        case shortTap

        var treatsRuntimeFailureAsFatal: Bool {
            self == .active || self == .commit
        }
    }

    let id: UUID
    private(set) var locale: Locale
    let dictionaryEntries: [DictionaryEntry]
    private(set) var targetApplication: TargetApplication
    let audioURL: URL?
    let speech: any SpeechEngining
    let audio: any AudioCapturing
    let health = DictationSessionHealth()

    var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    var feedTask: Task<Void, Never>?
    var consumeTask: Task<Void, Never>?
    var setupTask: Task<Void, Never>?
    var state: State = .settingUp
    private(set) var completionIntent: CompletionIntent = .active

    private var teardownTask: Task<Void, Never>?
    private var audioStopTask: Task<URL?, Never>?
    private var shouldPreserveAudioFile = false
    private var shouldRecoverClosedAudioFile = false
    private var runtimeFailureHandled = false
    private var emittedSoundEvents: Set<SoundEvent> = []
    private(set) var recoveredAudioURL: URL?

    var teardownStarted: Bool { teardownTask != nil }

    func applyResolvedLocale(_ locale: Locale) {
        guard state == .settingUp else { return }
        self.locale = locale
    }

    func updateTargetApplication(_ targetApplication: TargetApplication) {
        guard state == .settingUp else { return }
        self.targetApplication = targetApplication
    }

    func beginRecording() -> Bool {
        guard state == .settingUp else { return false }
        state = .recording
        return true
    }

    func preserveAudioFile() {
        shouldPreserveAudioFile = true
    }

    func beginCompletion(_ intent: CompletionIntent) {
        guard completionIntent == .active else { return }
        completionIntent = intent
    }

    func beginRuntimeFailure() -> Bool {
        guard completionIntent.treatsRuntimeFailureAsFatal,
              !runtimeFailureHandled else { return false }
        runtimeFailureHandled = true
        shouldRecoverClosedAudioFile = true
        return true
    }

    func claimSoundEvent(_ event: SoundEvent) -> Bool {
        guard !emittedSoundEvents.contains(event) else { return false }
        switch event {
        case .recordingStarted:
            break
        case .recordingStopped:
            guard emittedSoundEvents.contains(.recordingStarted) else { return false }
        case .processingCompleted:
            guard emittedSoundEvents.contains(.recordingStopped) else { return false }
        case .failed:
            guard !emittedSoundEvents.contains(.recordingStarted)
                    || emittedSoundEvents.contains(.recordingStopped) else { return false }
        }
        emittedSoundEvents.insert(event)
        return true
    }

    init(id: UUID = UUID(),
         locale: Locale,
         dictionaryEntries: [DictionaryEntry],
         targetApplication: TargetApplication,
         audioURL: URL?,
         speech: any SpeechEngining,
         audio: any AudioCapturing) {
        self.id = id
        self.locale = locale
        self.dictionaryEntries = dictionaryEntries
        self.targetApplication = targetApplication
        self.audioURL = audioURL
        self.speech = speech
        self.audio = audio
    }

    /// Alle Abschluss- und Fehlerpfade teilen sich genau einen Audio-Stop und
    /// dessen Ergebnis. So kann ein Runtimefehler während des Worker-Drains die
    /// vom ersten Stop gelieferte Recovery-URL nicht durch einen zweiten Stop
    /// verlieren.
    func stopAudioOnce() async -> URL? {
        if let audioStopTask {
            return await audioStopTask.value
        }
        let audio = self.audio
        let task = Task { @MainActor in await audio.stop() }
        audioStopTask = task
        return await task.value
    }

    /// Vollständiger Fehler-/Abbruchpfad. Mehrfache oder gleichzeitig
    /// eintreffende Aufrufe teilen sich denselben Aufräum-Task.
    func teardown() async {
        if let teardownTask {
            await teardownTask.value
            return
        }

        let resourcesAlreadyFinished = state == .finished
        if !resourcesAlreadyFinished {
            state = .stopping
        }
        let continuation = audioContinuation
        let feedTask = self.feedTask
        let speech = self.speech
        let consumeTask = self.consumeTask
        let audioURL = self.audioURL
        let preserveCompletedAudio = shouldPreserveAudioFile
        let recoverClosedAudio = shouldRecoverClosedAudioFile

        let task = Task { @MainActor in
            let stoppedURL = await self.stopAudioOnce()
            if !resourcesAlreadyFinished {
                self.health.closeSpeechIngress(continuation)
                await feedTask?.value
                await speech.finish()
                if let consumeTask {
                    let completed = await TranscriptionEngine.waitForFinalize(
                        consumeTask,
                        timeoutNanoseconds: 2_000_000_000
                    )
                    if !completed {
                        DebugLog.log("STASI-APP: Session-Teardown – Consumer nach 2 s noch offen")
                    }
                }
            }
            if recoverClosedAudio, let stoppedURL {
                self.recoveredAudioURL = stoppedURL
            } else if !preserveCompletedAudio, let audioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        teardownTask = task
        await task.value

        audioContinuation = nil
        self.feedTask = nil
        self.consumeTask = nil
        state = .finished
    }
}
