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

    let id: UUID
    let locale: Locale
    let dictionaryEntries: [DictionaryEntry]
    let targetApp: String
    let audioURL: URL?
    let speech: any SpeechEngining
    let audio: any AudioCapturing

    var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    var feedTask: Task<Void, Never>?
    var consumeTask: Task<Void, Never>?
    var setupTask: Task<Void, Never>?
    var state: State = .settingUp

    private var teardownTask: Task<Void, Never>?

    init(id: UUID = UUID(),
         locale: Locale,
         dictionaryEntries: [DictionaryEntry],
         targetApp: String,
         audioURL: URL?,
         speech: any SpeechEngining,
         audio: any AudioCapturing) {
        self.id = id
        self.locale = locale
        self.dictionaryEntries = dictionaryEntries
        self.targetApp = targetApp
        self.audioURL = audioURL
        self.speech = speech
        self.audio = audio
    }

    /// Vollständiger Fehler-/Abbruchpfad. Mehrfache oder gleichzeitig
    /// eintreffende Aufrufe teilen sich denselben Aufräum-Task.
    func teardown() async {
        if let teardownTask {
            await teardownTask.value
            return
        }

        state = .stopping
        let audio = self.audio
        let continuation = audioContinuation
        let feedTask = self.feedTask
        let speech = self.speech
        let consumeTask = self.consumeTask
        let audioURL = self.audioURL

        let task = Task { @MainActor in
            _ = audio.stop()
            continuation?.finish()
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
            if let audioURL {
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
