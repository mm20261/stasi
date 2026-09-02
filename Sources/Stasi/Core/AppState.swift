import Foundation
import SwiftUI
import AppKit
import AVFoundation

// MARK: - AppState
// Zentrale State-Machine: idle → recording → transcribing → polishing → injecting → idle.
// Hotkey-Modi: Push-to-talk (halten) oder Umschalten (togglen).
// Ton-Feedback, WAV-Mitschrieb, Ziel-App-Erfassung.

@MainActor
@Observable
final class AppState {
    enum Phase: String {
        case idle = "BEREIT"
        case preparing = "VORBEREITUNG"
        case setupTimedOut = "NEUSTART NÖTIG"
        case recording = "AUFNAHME"
        case transcribing = "TRANSKRIBIERE"
        case polishing = "POLIERE"
        case injecting = "EINFÜGEN"
    }

    private(set) var phase: Phase = .idle {
        didSet {
            guard oldValue != phase else { return }
            let now = Date()
            phaseEnteredAt = now
            if phase == .transcribing { processingStartedAt = now }
            if phase == .idle || phase == .recording { processingStartedAt = nil }
            if phase == .idle { watchdogRecoveryQueued = false }
        }
    }
    /// Woher kommt die laufende Aufnahme – steuert ✕/✓ in der Pill (v4).
    private(set) var recordingSource: RecordingSource = .pushToTalk
    var partialText: String = ""
    private(set) var displayLevel: Double = 0
    private(set) var elapsed: TimeInterval = 0

    let settings: SettingsStore
    let dictionary: DictionaryStore
    let history: any HistoryStoring
    private let audioFactory: AudioCaptureFactory
    private let hotkeyInstallationEnabled: Bool
    private let startHotkey: @MainActor (HotkeyEngine, HotkeyEngine.Combo) -> Bool
    private let speechFactory: @MainActor (Locale, [String]) -> any SpeechEngining
    private let requestMicrophone: @MainActor () async -> Bool
    private let modelInstaller: @Sendable (Locale) async throws -> Void
    private let spellChecker: @MainActor (String, String) -> Bool
    private let audioDirectory: URL
    private let audioRecoveryStore: AudioRecoveryStore
    private let revealRecoveryFile: @MainActor (URL) -> Void
    private let frontmostApplication: @MainActor () -> TargetApplication?
    private let isTextFieldEditable: @Sendable () -> Bool
    private let injectText: @Sendable (String, pid_t) async -> Bool
    private let copyToClipboard: @MainActor (String) -> Void
    private let soundFeedback: any SoundFeedback
    private(set) var modelReadyByLocale: [String: Bool] = [:]
    @ObservationIgnored private var modelPreparationTasks: [String: Task<Bool, Never>] = [:]
    @ObservationIgnored private var knownWordCache: [String: Bool] = [:]
    private(set) var currentSession: DictationSession?
    private var teardownInProgress = false
    var hotkey: HotkeyEngine?
    /// Tap wurde angelegt (says nichts über Event-Lieferung!)
    private(set) var tapInstalled = false
    /// Bedienungshilfen erteilt + Tap installiert → Hotkey wirklich scharf
    /// (Session-Tap braucht keine Eingabe-Überwachung mehr)
    var hotkeyReady: Bool {
        tapInstalled && accessibilityGranted && hotkey?.isOperational == true
    }
    var accessibilityGranted = false
    var listenEventGranted = false

    /// Warum der Hotkey (noch) nicht scharf ist – für die UI.
    var hotkeyBlocker: String? {
        if !accessibilityGranted { return "Bedienungshilfen" }
        if hotkey?.gaveUp == true { return Copy.hotkeyRestartRequired }
        return nil
    }

    /// Wird von der Pill gesetzt: Nutzer will verwerfen (✕)
    var discardRequested = false
    /// Wird von der Pill gesetzt: Nutzer will sofort beenden + einfügen (✓)
    var commitRequested = false
    /// Toast-Rückmeldung (von AppDelegate an die Pill gebunden).
    /// Ein beim Start erkannter, unlesbarer Verlauf wird beim Installieren
    /// des Kanals unmittelbar und genau einmal sichtbar gemacht.
    var onToast: ((String, Bool) -> Void)? {
        didSet { presentUnreadableHistoryIfNeeded() }
    }

    private static let unreadableHistoryMessage =
        "Verlauf konnte nicht geladen werden. Die vorhandene Datei ist beschädigt und bleibt schreibgeschützt."

    private enum InjectionGateResult {
        case injected
        case targetOrFocusChanged
        case injectionFailed
    }
    private enum InjectionResultContext {
        case completedDictation
        case insertLast
    }
    private var didPresentUnreadableHistory = false
    private(set) var recordStart: Date?
    private let now: @MainActor () -> Date
    private let levelTraceEnabled: Bool
    private let consumeTimeoutNanoseconds: UInt64
    private let minimumPushToTalkDuration: TimeInterval
    private let maximumRecordingDuration: TimeInterval
    @ObservationIgnored private var lastLevelTraceUptime: TimeInterval = 0
    @ObservationIgnored private var phaseEnteredAt = Date()
    @ObservationIgnored private var processingStartedAt: Date?
    @ObservationIgnored private var watchdogRecoveryQueued = false
    @ObservationIgnored private var recordingLimitCommitQueued = false
    @ObservationIgnored private var modelPreparationWaiters = 0
    @ObservationIgnored private var activeInjectionID: UUID?
    private let permissionCheckMailbox = PermissionCheckMailbox()

    // MARK: Command-Channel
    // Hotkey-Tap-Callbacks und @objc-Button-Thunks dürfen KEINE Tasks spawnen
    // (macOS 26.6 korrumpiert sonst Executor-Metadaten → SwiftUI-Crashes).
    // Stattdessen: thread-sicheres yield in einen AsyncStream; EIN Task aus
    // echtem Concurrency-Kontext (startCommandLoop) konsumiert die Commands.
    enum HotkeyCommand: Sendable, Equatable {
        case press, release, discard, commit, handsFree, copyLast, insertLast, tapStopped
        case prepareModel(Locale)
        case audioRuntimeError(AudioCaptureRuntimeError, UUID)
        case recordingLimitReached
        case phaseWatchdog
        case deleteHistory(TranscriptionRecord)
        case deleteAllHistory
        case applyRetention
    }
    nonisolated static let copyLastChord = HotkeyEngine.Combo(
        keyCode: 8,
        flags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue
    )
    nonisolated static let insertLastChord = HotkeyEngine.Combo(
        keyCode: 9,
        flags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue
    )
    private let commandStream: AsyncStream<HotkeyCommand>
    private let commandContinuation: AsyncStream<HotkeyCommand>.Continuation
    private var commandLoopStarted = false

    /// Von überall (Tap-Callback, @objc-Thunk) sicher aufrufbar – kein Task,
    /// kein Actor-Hop, nur ein thread-sicheres yield.
    nonisolated func enqueue(_ cmd: HotkeyCommand) {
        commandContinuation.yield(cmd)
    }

    /// Aus AppDelegate.wireUp (SwiftUI onAppear = echter MainActor-Kontext).
    func startCommandLoop() {
        guard !commandLoopStarted else { return }
        commandLoopStarted = true
        Task { [weak self] in
            guard let stream = self?.commandStream else { return }
            for await cmd in stream {
                guard let self else { return }
                switch cmd {
                case .press: hotkeyPressed()
                case .release: hotkeyReleased()
                case .discard: requestDiscard()
                case .commit: requestCommit()
                case .handsFree: handsFreeToggle()
                case .copyLast: copyLast()
                case .insertLast: insertLast()
                case .tapStopped:
                    tapInstalled = false
                    if phase == .recording, recordingSource == .pushToTalk {
                        requestCommit()
                    }
                case .prepareModel(let locale): await prepareModel(for: locale)
                case let .audioRuntimeError(error, sessionID):
                    await handleAudioRuntimeErrorCommand(error, sessionID: sessionID)
                case .recordingLimitReached:
                    guard phase == .recording else { break }
                    onToast?("Maximaldauer erreicht – Aufnahme wird beendet.", false)
                    requestCommit()
                case .phaseWatchdog: await recoverFromPhaseWatchdog()
                case .deleteHistory(let record): await performDeleteHistoryRecord(record)
                case .deleteAllHistory: await performDeleteAllHistory()
                case .applyRetention: await performRetention()
                }
            }
        }
    }

    init(settings: SettingsStore,
         dictionary: DictionaryStore? = nil,
         history: (any HistoryStoring)? = nil,
         audioFactory: @escaping AudioCaptureFactory = { AudioCapture() },
         speechFactory: @escaping @MainActor (Locale, [String]) -> any SpeechEngining = {
             TranscriptionEngine(locale: $0, biasWords: $1)
         },
         requestMicrophone: @escaping @MainActor () async -> Bool = {
             await Permissions.requestMicrophone()
         },
         modelInstaller: @escaping @Sendable (Locale) async throws -> Void = {
             try await TranscriptionEngine.ensureModelInstalled(locale: $0)
         },
         spellChecker: @escaping @MainActor (String, String) -> Bool = { word, language in
             var wordCount = 0
             let misspelling = NSSpellChecker.shared.checkSpelling(
                 of: word,
                 startingAt: 0,
                 language: language,
                 wrap: false,
                 inSpellDocumentWithTag: 0,
                 wordCount: &wordCount
             )
             return misspelling.location == NSNotFound
         },
         consumeTimeoutNanoseconds: UInt64 = 2_000_000_000,
         minimumPushToTalkDuration: TimeInterval = PillChrome.presentationDelay,
         maximumRecordingDuration: TimeInterval = 10 * 60,
         installHotkey: Bool = true,
         startHotkey: @escaping @MainActor (HotkeyEngine, HotkeyEngine.Combo) -> Bool = { engine, _ in
             engine.start()
         },
         audioDirectory: URL? = nil,
         audioRecoveryStore: AudioRecoveryStore? = nil,
         revealRecoveryFile: @escaping @MainActor (URL) -> Void = { url in
             NSWorkspace.shared.activateFileViewerSelecting([url])
         },
         frontmostApplication: @escaping @MainActor () -> TargetApplication? = {
             guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
             return TargetApplication(
                 localizedName: application.localizedName ?? "Unbekannte App",
                 bundleIdentifier: application.bundleIdentifier,
                 processIdentifier: application.processIdentifier
             )
         },
         isTextFieldEditable: @escaping @Sendable () -> Bool = {
             TextInjector.isFocusedElementEditable()
         },
         injectText: @escaping @Sendable (String, pid_t) async -> Bool = { text, targetPID in
             await TextInjector.inject(text, targetPID: targetPID)
         },
         copyToClipboard: @escaping @MainActor (String) -> Void = { text in
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString(text, forType: .string)
         },
         now: @escaping @MainActor () -> Date = { Date() },
         soundFeedback: any SoundFeedback = SystemSoundFeedback()) {
        self.settings = settings
        self.dictionary = dictionary ?? DictionaryStore()
        self.history = history ?? HistoryStore()
        self.audioFactory = audioFactory
        self.hotkeyInstallationEnabled = installHotkey
        self.startHotkey = startHotkey
        self.speechFactory = speechFactory
        self.requestMicrophone = requestMicrophone
        self.modelInstaller = modelInstaller
        self.spellChecker = spellChecker
        self.consumeTimeoutNanoseconds = consumeTimeoutNanoseconds
        self.minimumPushToTalkDuration = minimumPushToTalkDuration
        self.maximumRecordingDuration = maximumRecordingDuration
        let resolvedAudioDirectory = audioDirectory ?? DictionaryStore.appSupportDirectory
            .appendingPathComponent("audio", isDirectory: true)
        self.audioDirectory = resolvedAudioDirectory
        self.audioRecoveryStore = audioRecoveryStore ?? AudioRecoveryStore(
            directory: resolvedAudioDirectory.deletingLastPathComponent()
                .appendingPathComponent("Audio Recovery", isDirectory: true)
        )
        do {
            try self.audioRecoveryStore.cleanup()
        } catch {
            DebugLog.log("STASI-AUDIO: Recovery-Cleanup beim Start fehlgeschlagen: \(error.localizedDescription)")
        }
        self.revealRecoveryFile = revealRecoveryFile
        self.frontmostApplication = frontmostApplication
        self.isTextFieldEditable = isTextFieldEditable
        self.injectText = injectText
        self.copyToClipboard = copyToClipboard
        self.now = now
        self.soundFeedback = soundFeedback
        levelTraceEnabled = ProcessInfo.processInfo.environment["STASI_LEVEL_TRACE"] == "1"
        (commandStream, commandContinuation) = AsyncStream.makeStream(of: HotkeyCommand.self)
        accessibilityGranted = Permissions.accessibilityGranted
        listenEventGranted = Permissions.listenEventGranted
        if installHotkey {
            installTap() // installiert nur, wenn Bedienungshilfen erteilt sind
        }

        // Audio→Engine-Verdrahtung passiert pro Diktat in startDictation
        // (Stream + EIN Drain-Task, garantiert Puffer-Reihenfolge).
    }

    deinit {
        commandContinuation.finish()
    }

    private func presentUnreadableHistoryIfNeeded() {
        guard !didPresentUnreadableHistory,
              case .unreadable = history.state,
              let onToast else { return }
        didPresentUnreadableHistory = true
        onToast(Self.unreadableHistoryMessage, false)
    }

    // MARK: Hotkey

    private func installTap() {
        guard hotkeyInstallationEnabled else { return }
        // Debug-Notausstieg: Start ohne Event-Tap (STASI_NO_TAP=1 setzen)
        guard ProcessInfo.processInfo.environment["STASI_NO_TAP"] == nil else {
            NSLog("STASI-HK: Tap übersprungen (STASI_NO_TAP gesetzt)")
            return
        }
        // NIEMALS ohne Berechtigung installieren: macOS deaktiviert den
        // unberechtigten Tap, wiederholtes Re-Enablen entzieht dem Prozess
        // ALLE Maus-Events (Fenster wirkte komplett tot, Klicks versackten).
        // Session-Tap (.cgSessionEventTap/.defaultTap) braucht Bedienungshilfen.
        guard accessibilityGranted else {
            DebugLog.log("STASI-APP: installTap übersprungen – Bedienungshilfen fehlt")
            return
        }
        guard !tapInstalled else { return }
        DebugLog.log("STASI-APP: installTap – Bedienungshilfen erteilt, erstelle Session-Tap")
        let hk = HotkeyEngine(
            combo: currentCombo,
            chords: [Self.copyLastChord, Self.insertLastChord],
            handsFreeEnabled: settings.handsFreeOn,
            handsFreeKeyCode: settings.handsFreeKeyCode
        )
        // Kein Task, kein Actor-Hop im Tap-Pfad – nur enqueue (thread-sicher).
        hk.onPress = { [weak self] in self?.enqueue(.press) }
        hk.onRelease = { [weak self] in self?.enqueue(.release) }
        hk.onHandsFree = { [weak self] in self?.enqueue(.handsFree) }
        hk.onChord = { [weak self] chord in
            guard let command = Self.hotkeyCommand(for: chord) else { return }
            self?.enqueue(command)
        }
        hk.onTapStopped = { [weak self] in self?.enqueue(.tapStopped) }
        if startHotkey(hk, currentCombo) {
            hotkey = hk
            tapInstalled = true
        }
    }

    /// Aus dem AppDelegate-Poll: Berechtigungen prüfen. TCC-Preflights sind
    /// XPC-Calls – bewusst nur ~1×/s (20 Hz Preflights können die TCC-Dialoge
    /// blockieren, was der Nutzer als "eingefrorenes Fenster" erlebte).
    func refreshPermissionState() {
        if accessibilityGranted { hotkey?.ensureEnabled() }
        applyPermissionState(ax: Permissions.accessibilityGranted,
                             listen: Permissions.listenEventGranted)
    }

    /// Poll-Variante: Preflights im Hintergrund. Hängt tccd (typisch direkt
    /// nach Ad-hoc-Re-Sign), blockiert sonst jeder Check den Main-Thread –
    /// das war das "Fenster tot, Klicks versacken"-Symptom.
    func refreshPermissionStateAsync() {
        guard permissionCheckMailbox.begin() else { return }
        let mailbox = permissionCheckMailbox
        DispatchQueue.global(qos: .utility).async {
            let ax = Permissions.accessibilityGranted
            let listen = Permissions.listenEventGranted
            mailbox.finish(ax: ax, listen: listen)
        }
    }

    /// Billiger Lock-Read aus dem bestehenden Main-Poll. Die GCD-Closure
    /// berührt niemals MainActor-Zustand und benötigt keinen Executor-Hop.
    func applyPendingPermissionStateFromPoll() {
        guard let result = permissionCheckMailbox.consume() else { return }
        applyPermissionState(ax: result.ax, listen: result.listen)
    }

    private func applyPermissionState(ax: Bool, listen: Bool) {
        guard ax != accessibilityGranted || listen != listenEventGranted else { return }
        DebugLog.log("STASI-APP: Rechte geändert – AX=\(ax) Listen=\(listen)")
        accessibilityGranted = ax
        listenEventGranted = listen
        // Session-Tap braucht Bedienungshilfen (die auch fürs Einfügen nötig sind).
        if ax && !tapInstalled && hotkey?.gaveUp != true {
            installTap()
        }
    }

    /// Aus der UI gerufen: Löst NUR die Apple-Dialoge aus („Empfang von
    /// Tastatureingaben" bzw. Bedienungshilfen-Hinweis) mit dem Button
    /// „Systemeinstellungen öffnen". Kein direktes Pane-Öffnen daneben –
    /// sonst öffnet sich alles doppelt.
    ///
    /// Ausnahme: Wurde der Dialog früher mit „Nicht erlauben" abgewiesen,
    /// erscheint er nie wieder – dann öffnet sich nach 1,5 s ohne Erfolg
    /// das passende Pane als Rückfallebene.
    func requestMissingPermissions() {
        // Nur noch Bedienungshilfen nötig (Session-Tap + TextInjector).
        let axBefore = accessibilityGranted
        if !accessibilityGranted { Permissions.promptAccessibility() }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            self.refreshPermissionState()
            if !self.accessibilityGranted && !axBefore {
                Permissions.openSystemSettings("Privacy_Accessibility")
            }
        }
    }

    nonisolated static func hotkeyCommand(for chord: HotkeyEngine.Combo) -> HotkeyCommand? {
        switch chord {
        case copyLastChord: .copyLast
        case insertLastChord: .insertLast
        default: nil
        }
    }

    func applyHotkey(_ combo: HotkeyEngine.Combo) {
        settings.hotkeyCombo = combo
        reinstallHotkey()
    }

    func setHandsFreeEnabled(_ enabled: Bool) {
        guard settings.handsFreeOn != enabled else { return }
        settings.handsFreeOn = enabled
        reinstallHotkey()
    }

    func applyHandsFreeKeyCode(_ keyCode: UInt64) {
        guard VirtualKey.isHandsFreeModifier(keyCode),
              settings.handsFreeKeyCode != keyCode else { return }
        settings.handsFreeKeyCode = keyCode
        reinstallHotkey()
    }

    private func reinstallHotkey() {
        if phase == .recording, recordingSource == .pushToTalk {
            enqueue(.commit)
        }
        hotkey?.stop()
        hotkey = nil
        tapInstalled = false // sonst blockt der installTap-Guard den neuen Hotkey
        installTap()
    }

    // MARK: Sprachmodell-Vorbereitung

    func modelReady(for locale: Locale) -> Bool {
        modelReadyByLocale[locale.identifier] == true
    }

    var currentSessionModelReady: Bool {
        guard let currentSession else { return true }
        return modelReady(for: currentSession.locale)
    }

    func prepareModel(for locale: Locale) async {
        let key = locale.identifier
        guard modelReadyByLocale[key] != true else { return }

        modelPreparationWaiters += 1
        defer { modelPreparationWaiters -= 1 }

        if let running = modelPreparationTasks[key] {
            modelReadyByLocale[key] = await running.value
            return
        }

        modelReadyByLocale[key] = false
        let installer = modelInstaller
        let task = Task.detached(priority: .utility) {
            do {
                try await installer(locale)
                return true
            } catch {
                DebugLog.log("STASI-SPEECH: Modellvorbereitung fehlgeschlagen: \(error.localizedDescription)")
                return false
            }
        }
        modelPreparationTasks[key] = task
        let ready = await task.value
        modelPreparationTasks[key] = nil
        modelReadyByLocale[key] = ready
    }

    var currentCombo: HotkeyEngine.Combo { settings.hotkeyCombo }

    /// Modus-abhängige Auswertung (Push-to-talk vs. Umschalten)
    private func hotkeyPressed() {
        DebugLog.log("STASI-APP: hotkeyPressed (Modus \(settings.hotkeyMode.rawValue), Phase \(phase.rawValue))")
        switch settings.hotkeyMode {
        case .pushToTalk:
            startDictation()
        case .toggle:
            if phase == .recording {
                requestCommit()
            } else if phase == .preparing {
                stopDictation()
            } else {
                startDictation()
            }
        }
    }

    private func hotkeyReleased() {
        DebugLog.log("STASI-APP: hotkeyReleased (Modus \(settings.hotkeyMode.rawValue), Phase \(phase.rawValue))")
        guard settings.hotkeyMode == .pushToTalk else { return }
        stopDictation()
    }

    private func playSound(_ event: SoundEvent, for session: DictationSession) async {
        guard session.claimSoundEvent(event), session.soundFeedbackEnabled else { return }
        await soundFeedback.play(event)
    }

    private func playRecordingStartCue(for session: DictationSession) async -> Bool {
        if session.soundFeedbackEnabled {
            let completed = await session.startCue { [soundFeedback] in
                await soundFeedback.play(.recordingStarted)
            }
            guard completed else { return false }
        }
        guard !Task.isCancelled,
              session === currentSession,
              session.state == .settingUp else { return false }
        return session.claimSoundEvent(.recordingStarted)
    }

    // MARK: Aufnahme-Steuerung

    private func captureTargetApplication() -> TargetApplication {
        frontmostApplication() ?? TargetApplication(
            localizedName: "Unbekannte App",
            bundleIdentifier: nil,
            processIdentifier: 0
        )
    }

    private func setupShouldContinue(_ session: DictationSession) async -> Bool {
        guard session === currentSession else { return false }
        if Task.isCancelled, session.state == .settingUp {
            session.state = .stopping
        }
        switch session.state {
        case .settingUp:
            return true
        case .stopping:
            await teardown(session)
            finishAbortedSession(session)
            return false
        case .recording, .finished:
            return false
        }
    }

    func startDictation(source: RecordingSource = .pushToTalk) {
        if phase == .preparing {
            stopDictation()
            return
        }
        guard phase == .idle, currentSession == nil, !teardownInProgress else {
            if currentSession != nil || teardownInProgress {
                onToast?("Vorherige Aufnahme wird noch beendet.", false)
            }
            return
        }
        resetSessionPresentationToIdle()
        recordingSource = source

        let locale = settings.transcriptionLocale
        let dictionaryEntries = dictionary.entries
        let biasWords = DictionaryBiaser(entries: dictionaryEntries).vocabularyContext()
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let audio = audioFactory()
        let session = DictationSession(
            locale: locale,
            dictionaryEntries: dictionaryEntries,
            audioURL: audioURL,
            soundFeedbackEnabled: settings.soundOn,
            speech: speechFactory(locale, biasWords),
            audio: audio
        )
        currentSession = session
        phase = .preparing

        DebugLog.log("STASI-APP: startDictation → Setup")
        session.setupTask = Task { @MainActor [weak self, weak session] in
            guard let self, let session,
                  session === self.currentSession,
                  session.state == .settingUp else { return }
            do {
                // Mikrofon-Recht ZUERST klären (async, blockiert nichts) –
                // die Audio-Hardware ohne Recht anzufassen hängt sonst den
                // Main-Thread in der synchronen TCC-Abfrage fest.
                let microphoneGranted = await self.requestMicrophone()
                guard await self.setupShouldContinue(session) else { return }
                guard microphoneGranted else {
                    DebugLog.log("STASI-APP: startDictation abgebrochen – Mikrofon-Recht fehlt")
                    self.onToast?("Mikrofon-Zugriff fehlt – in Systemeinstellungen erlauben", false)
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if !Permissions.microphoneGranted {
                            Permissions.openSystemSettings("Privacy_Microphone")
                        }
                    }
                    await self.teardown(session)
                    await self.playSound(.failed, for: session)
                    self.finishAbortedSession(session)
                    return
                }

                let resolvedLocale = try await session.speech.resolvedLocale(for: session.locale)
                guard await self.setupShouldContinue(session) else { return }
                session.applyResolvedLocale(resolvedLocale)

                await self.prepareModel(for: resolvedLocale)
                guard await self.setupShouldContinue(session) else { return }

                let chunks = try await session.speech.start()
                guard await self.setupShouldContinue(session) else { return }
                self.modelReadyByLocale[session.locale.identifier] = true
                let format = await session.speech.preferredInputFormat()
                guard await self.setupShouldContinue(session) else { return }
                guard let format else {
                    throw TranscriptionError.noAudioFormat
                }
                DebugLog.log("STASI-APP: Engine bereit (\(format.sampleRate) Hz)")

                // Audio muss die Engine in Aufnahme-Reihenfolge erreichen:
                // ein Stream + EIN Drain-Task (kein Task pro Puffer!).
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingOldest(64)
                )
                session.audioContinuation = audioContinuation
                let speech = session.speech
                let health = session.health
                session.feedTask = Task.detached(priority: .userInitiated) {
                    for await chunk in audioStream {
                        guard health.failure == nil else { break }
                        await speech.feed(chunk)
                    }
                }

                session.consumeTask = Task { @MainActor [weak self, weak session] in
                    do {
                        for try await chunk in chunks {
                            guard let self, let session,
                                  session === self.currentSession else { return }
                            self.partialText = chunk.text
                        }
                    } catch {
                        DebugLog.log("STASI-APP: Transkript-Strom Fehler: \(error.localizedDescription)")
                    }
                }

                try session.audio.start(
                    outputFormat: format,
                    recordTo: session.audioURL,
                    preferredMicUID: self.settings.preferredMicUID,
                    captureInitiallyActive: false,
                    onRuntimeErrorAccepted: { error in
                        // Der Reporter liefert diese Health-Grenze seriell off-RT.
                        // AudioCapture.stop() flusht sie nach dem Worker-Drain, bevor
                        // ein Commit die Session als gesund weiterverarbeiten darf.
                        health.recordAudioRuntimeFailure(error)
                        health.closeSpeechIngress(audioContinuation)
                    },
                    onRuntimeError: { [weak self, weak session] error in
                        guard let self, let session else { return }
                        self.enqueue(.audioRuntimeError(error, session.id))
                    }
                ) { chunk in
                    health.ingest(chunk, into: audioContinuation)
                }
                if let runtimeError = health.audioRuntimeError {
                    await self.handleAudioRuntimeError(runtimeError, session: session)
                    return
                }
                guard await self.setupShouldContinue(session) else { return }
                guard session.audio.activateCapture() else {
                    await self.handleCaptureActivationFailure(session)
                    return
                }
                session.markCaptureActivationWon()
                let startCueCompleted = await self.playRecordingStartCue(for: session)
                guard await self.setupShouldContinue(session),
                      startCueCompleted else { return }
                if let runtimeError = health.audioRuntimeError {
                    await self.handleAudioRuntimeError(runtimeError, session: session)
                    return
                }
                guard session.audio.openCapture() else {
                    await self.handleCaptureActivationFailure(session)
                    return
                }
                guard session.assignTargetApplication(self.captureTargetApplication()) else { return }
                let recordingStartCandidate = self.now()
                guard session.beginRecording() else { return }
                self.recordStart = recordingStartCandidate
                self.elapsed = 0
                self.phase = .recording
                DebugLog.log("STASI-APP: audio.start fertig – Aufnahme läuft")
            } catch {
                DebugLog.log("STASI-APP: startDictation FEHLER: \(error.localizedDescription)")
                guard await self.setupShouldContinue(session) else { return }
                await self.teardown(session)
                await self.playSound(.failed, for: session)
                self.onToast?(error.localizedDescription, false)
                self.finishAbortedSession(session)
            }
        }
    }

    private func requestSetupStop(_ session: DictationSession,
                                  intent: DictationSession.CompletionIntent,
                                  timedOut: Bool = false) {
        guard session === currentSession, session.state == .settingUp else { return }
        session.beginCompletion(intent)
        session.cancelStartCue()
        session.setupTask?.cancel()
        session.state = .stopping
        if timedOut {
            phase = .setupTimedOut
        }
    }

    func stopDictation() {
        guard let session = currentSession else {
            DebugLog.log("STASI-APP: stopDictation ignoriert (keine Session)")
            return
        }
        if session.state == .settingUp {
            DebugLog.log("STASI-APP: stopDictation während Setup")
            requestSetupStop(session, intent: .shortTap)
            return
        }
        guard phase == .recording, session.state == .recording else {
            DebugLog.log("STASI-APP: stopDictation ignoriert (Phase \(phase.rawValue))")
            return
        }
        DebugLog.log("STASI-APP: stopDictation (commit=true)")
        let duration = snapshotRecordingDuration()
        if recordingSource == .pushToTalk,
           duration < minimumPushToTalkDuration {
            session.beginCompletion(.shortTap)
            silentlyAbortShortPushToTalk(session)
            return
        }
        session.beginCompletion(.commit)
        session.state = .stopping
        phase = .transcribing

        Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            await session.setupTask?.value
            guard session === self.currentSession else { return }

            guard session.audio.isRunning else {
                DebugLog.log("STASI-APP: Kurz-Tipp während Setup")
                await self.teardown(session)
                self.finishAbortedSession(session)
                return
            }

            let recordedURL = await session.stopAudioOnce()
            let stopCueTask = Task { @MainActor [weak self, weak session] in
                guard let self, let session else { return }
                await self.playSound(.recordingStopped, for: session)
            }
            if session.health.failure == .audioRuntimeFailure {
                DebugLog.log("STASI-APP: Commit-Drain wegen Audio-Runtimefehler abgebrochen")
                await stopCueTask.value
                await self.completeTerminalFailure(
                    session,
                    fallbackMessage: "Die Audioaufnahme ist fehlgeschlagen und wurde verworfen."
                )
                return
            }
            // Stop-Cue und Speech-Finalisierung laufen parallel. Das terminale
            // Ergebnis wartet weiterhin auf beide, sodass die Ereignisfolge stabil bleibt.
            // Erst alle gepufferten Chunks in die Engine drainen, DANN
            // finalisieren – sonst fehlt das Satzende.
            session.health.closeSpeechIngress(session.audioContinuation)
            session.audioContinuation = nil
            await session.feedTask?.value
            guard session === self.currentSession else { return }
            session.feedTask = nil
            DebugLog.log("STASI-APP: Audio gedraint, finalisiere…")
            await session.speech.finish()
            guard session === self.currentSession else { return }
            if let consumeTask = session.consumeTask {
                let completed = await TranscriptionEngine.waitForFinalize(
                    consumeTask,
                    timeoutNanoseconds: self.consumeTimeoutNanoseconds
                )
                if !completed {
                    DebugLog.log("STASI-APP: Consumer-Timeout – nutze letzten Text-Stand")
                }
            }
            guard session === self.currentSession else { return }
            session.consumeTask = nil
            await stopCueTask.value
            guard session === self.currentSession else { return }
            session.setupTask = nil
            session.state = .finished
            self.resetLevel()

            if session.health.failure != nil {
                DebugLog.log("STASI-APP: Session terminal unvollständig – gemeinsamer Abschluss")
                await self.completeTerminalFailure(
                    session,
                    fallbackMessage: "Die Aufnahme ist unvollständig und wurde verworfen."
                )
                return
            }

            let raw = self.partialText
            DebugLog.log("STASI-APP: Transkription fertig (\(raw.count) Zeichen)")
            await self.finishTranscription(rawText: raw,
                                           duration: duration,
                                           audioURL: recordedURL ?? session.audioURL,
                                           session: session)
        }
    }

    private func handleCaptureActivationFailure(_ session: DictationSession) async {
        DebugLog.log("STASI-AUDIO: Capture-Aktivierung von Runtimefehler überholt")
        await completeTerminalFailure(
            session,
            fallbackMessage: "Die Audioaufnahme ist fehlgeschlagen und wurde verworfen."
        )
    }

    private func handleAudioRuntimeError(_ error: AudioCaptureRuntimeError,
                                         session: DictationSession) async {
        DebugLog.log("STASI-AUDIO: Runtimefehler – \(String(describing: error))")
        await completeTerminalFailure(
            session,
            fallbackMessage: "Die Audioaufnahme ist fehlgeschlagen und wurde verworfen."
        )
    }

    private func handleAudioRuntimeErrorCommand(
        _ error: AudioCaptureRuntimeError,
        sessionID: UUID
    ) async {
        guard let session = currentSession, session.id == sessionID else { return }
        if session.state == .settingUp, let setupTask = session.setupTask {
            session.cancelStartCue()
            await setupTask.value
            guard let currentSession, currentSession.id == sessionID else { return }
        }
        await handleAudioRuntimeError(error, session: session)
    }

    private func completeTerminalFailure(
        _ session: DictationSession,
        fallbackMessage: String
    ) async {
        guard let task = session.terminalFailure(starting: { [weak self, weak session] in
            guard let self, let session, session === self.currentSession else { return }
            session.cancelStartCue()
            session.state = .stopping
            self.phase = .transcribing
            await self.teardown(session)
            let recoveredURL = session.recoveredAudioURL.flatMap {
                self.registerRecoveryAudio(at: $0)
            }
            await self.playSound(.failed, for: session)
            self.finishAbortedSession(session)
            if recoveredURL != nil {
                self.onToast?(
                    "Die Aufnahme ist unvollständig. Die Wiederherstellungsdatei wurde im Finder geöffnet.",
                    false
                )
            } else {
                self.onToast?(fallbackMessage, false)
            }
        }) else { return }
        await task.value
    }

    private func registerRecoveryAudio(at sourceURL: URL) -> URL? {
        do {
            let recoveredURL = try audioRecoveryStore.register(sourceURL)
            revealRecoveryFile(recoveredURL)
            return recoveredURL
        } catch {
            DebugLog.log("STASI-AUDIO: Recovery-Datei konnte nicht registriert werden: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pill-Aktionen
    func requestDiscard() {
        guard phase == .recording else { return }
        guard let session = currentSession else { return }
        DebugLog.log("STASI-APP: requestDiscard")
        discardRequested = true
        session.beginCompletion(.discard)
        session.state = .stopping
        phase = .transcribing
        Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            await session.setupTask?.value
            guard session === self.currentSession else { return }
            await self.teardown(session)
            self.finishAbortedSession(session)
        }
    }

    /// Ein versehentlicher PTT-Tipp bleibt bis zum vollständigen Teardown als
    /// Verarbeitung sichtbar. So signalisiert die UI, warum eine zweite Press-
    /// Kante noch keine Aufnahme startet, ohne einen unsicheren Pending-Start zu
    /// erzeugen, der nach dem Loslassen zur Geisteraufnahme werden könnte.
    private func silentlyAbortShortPushToTalk(_ session: DictationSession) {
        DebugLog.log("STASI-APP: PTT-Kurztipp <250 ms – Teardown sichtbar")
        session.state = .stopping
        resetLevel()
        partialText = ""
        phase = .transcribing
        Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            await self.teardown(session)
            self.finishAbortedSession(session)
        }
    }

    func requestCommit() {
        guard phase == .recording else { return }
        stopDictation()
    }

    /// Wird direkt aus dem bestehenden 20-Hz-Main-RunLoop-Poll gerufen.
    /// Nur ein thread-sicheres Enqueue; kein Task entsteht im Timer-Callback.
    func checkPhaseWatchdog(now: Date = Date(), timeout: TimeInterval = 15) {
        if phase == .recording {
            _ = snapshotRecordingDuration(at: now)
            guard !recordingLimitCommitQueued,
                  elapsed >= maximumRecordingDuration else { return }
            recordingLimitCommitQueued = true
            enqueue(.recordingLimitReached)
            return
        }
        guard phase == .preparing || phase == .transcribing
                || phase == .polishing || phase == .injecting else { return }
        guard !(phase == .preparing && modelPreparationWaiters > 0) else { return }
        guard !watchdogRecoveryQueued,
              now.timeIntervalSince(phaseEnteredAt) >= timeout else { return }
        watchdogRecoveryQueued = true
        DebugLog.log("STASI-WATCH: Phase \(phase.rawValue) hängt seit ≥15 s – Recovery")
        enqueue(.phaseWatchdog)
    }

    private func recoverFromPhaseWatchdog() async {
        if phase == .preparing, let session = currentSession {
            if session.state == .settingUp {
                requestSetupStop(session, intent: .discard, timedOut: true)
            } else if session.state == .stopping {
                phase = .setupTimedOut
            } else {
                watchdogRecoveryQueued = false
                return
            }
            await teardown(session)
            finishAbortedSession(session)
            onToast?("Die Aufnahmevorbereitung hat zu lange gedauert. Bitte erneut versuchen.", false)
            DebugLog.log("STASI-WATCH: Setup abgeräumt, neuer Start ist möglich")
            return
        }
        if phase == .injecting {
            resetSessionPresentationToIdle()
            onToast?("Einfügen fehlgeschlagen, Text liegt in der Zwischenablage", false)
            DebugLog.log("STASI-WATCH: Hängendes Einfügen auf BEREIT zurückgesetzt")
            return
        }
        guard phase == .transcribing || phase == .polishing else {
            watchdogRecoveryQueued = false
            return
        }
        let session = currentSession
        currentSession = nil
        resetSessionPresentationToIdle()
        onToast?(Copy.toastTranscriptionAborted, false)
        if let session {
            await self.teardown(session)
        }
        DebugLog.log("STASI-WATCH: Zustandsmaschine auf BEREIT zurückgesetzt")
    }

    private func finishTranscription(rawText: String,
                                     duration: Double,
                                     audioURL: URL?,
                                     session: DictationSession) async {
        guard session === currentSession else { return }
        phase = .polishing

        // Snapshot-Grenze für Block 3C: ab hier darf kein veränderlicher
        // Session-/Settings-Zustand mehr in die Nachbearbeitung hineinlaufen.
        let rawSnapshot = rawText
        let localeSnapshot = session.locale
        let dictionarySnapshot = session.dictionaryEntries
        let configuredLevel = settings.postProcessing
        let levelSnapshot = TranscriptPolisher.effectiveLevel(configured: configuredLevel)
        guard let targetApplicationSnapshot = session.targetApplication else {
            await completeTerminalFailure(session, fallbackMessage: "Die Ziel-App konnte nicht erfasst werden.")
            return
        }
        let audioURLSnapshot = audioURL
        let durationSnapshot = duration

        DebugLog.log("STASI-APP: finishTranscription (\(rawText.count) Zeichen roh)")
        let outcome = await Task.detached(priority: .userInitiated) {
            TranscriptPolisher.polishSync(
                rawSnapshot,
                locale: localeSnapshot,
                entries: dictionarySnapshot,
                level: levelSnapshot
            )
        }.value
        guard session === currentSession, phase == .polishing else { return }
        let trimmedRaw = rawSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = outcome.text

        guard !trimmed.isEmpty else {
            await teardown(session)
            resetSessionPresentationToIdle()
            onToast?(Copy.toastNothingHeard, false)
            return
        }

        let newRecord = TranscriptionRecord(
            date: Date(),
            localeID: localeSnapshot.identifier,
            rawText: trimmedRaw,
            correctedText: trimmed,
            corrections: outcome.corrections,
            durationSecs: durationSnapshot,
            targetApp: targetApplicationSnapshot.localizedName,
            audioPath: audioURLSnapshot?.path,
            polish: outcome.summary
        )
        do {
            try await history.insert(newRecord)
        } catch {
            DebugLog.log("STASI-APP: Verlauf speichern fehlgeschlagen: \(error.localizedDescription)")
            session.preserveAudioFile()
            await teardown(session)
            await playSound(.failed, for: session)
            resetSessionPresentationToIdle()
            onToast?("Verlauf konnte nicht gespeichert werden. Die Audiodatei bleibt erhalten.", false)
            return
        }
        guard session === currentSession, phase == .polishing else { return }

        let historicalRecords = history.records.filter { $0.id != newRecord.id }
        let learningDictionarySnapshot = dictionary.entries
        let ignoredLearnedSnapshot = dictionary.ignoredLearned
        let possible = await Task.detached(priority: .userInitiated) {
            AutoLearnScout.potentialCandidates(
                newRecord: newRecord,
                dictionary: learningDictionarySnapshot,
                ignored: ignoredLearnedSnapshot,
                locale: localeSnapshot
            )
        }.value
        guard session === currentSession, phase == .polishing else { return }

        // NSSpellChecker ist AppKit und nicht thread-sicher. Ausschließlich diese
        // kleine, vorab begrenzte Liste wird deshalb auf dem MainActor geprüft.
        let unknown = possible.filter { [self] candidate in
            !isKnownWord(candidate.spelling, locale: localeSnapshot)
        }
        guard session === currentSession, phase == .polishing else { return }

        let learned = await Task.detached(priority: .userInitiated) {
            AutoLearnScout.candidates(
                from: unknown,
                newRecord: newRecord,
                historyExcludingNew: historicalRecords
            )
        }.value
        guard session === currentSession, phase == .polishing else { return }
        dictionary.mergeLearned(learned)

        session.preserveAudioFile()
        await teardown(session)
        await playSound(.processingCompleted, for: session)
        phase = .injecting
        let injectionID = UUID()
        activeInjectionID = injectionID
        partialText = trimmed
        // Auto-Kopieren: Das letzte Protokoll liegt immer in der Zwischenablage,
        // auch wenn Ziel-App oder Textfokus vor dem Einfügen gewechselt haben.
        copyToClipboard(trimmed)

        let frontmostApplication = frontmostApplication
        let isTextFieldEditable = isTextFieldEditable
        let injectText = injectText
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await Self.runInjectionGate(
                text: trimmed,
                capturedTarget: targetApplicationSnapshot,
                frontmostApplication: frontmostApplication,
                isTextFieldEditable: isTextFieldEditable,
                injectText: injectText
            )
            // Zwei Poll-Zyklen Sichtbarkeit, auch wenn das Einfügen nur einen
            // kurzen CGEvent-Chunk benötigt. Der verzögerte Spinner bleibt bei
            // insgesamt schneller Verarbeitung trotzdem unsichtbar.
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run { [weak self] in
                guard let self, self.activeInjectionID == injectionID else { return }
                self.presentInjectionResult(
                    result,
                    target: targetApplicationSnapshot,
                    context: .completedDictation
                )
                self.resetSessionPresentationToIdle()
            }
        }
    }

    private nonisolated static func runInjectionGate(
        text: String,
        capturedTarget: TargetApplication,
        frontmostApplication: @escaping @MainActor () -> TargetApplication?,
        isTextFieldEditable: @escaping @Sendable () -> Bool,
        injectText: @escaping @Sendable (String, pid_t) async -> Bool
    ) async -> InjectionGateResult {
        let sameTargetBeforeEditabilityCheck = await frontmostApplication().map {
            TargetApplicationMatcher.matches(captured: capturedTarget, current: $0)
        } ?? false
        guard sameTargetBeforeEditabilityCheck, isTextFieldEditable() else {
            return .targetOrFocusChanged
        }

        let sameTargetImmediatelyBeforeInjection = await frontmostApplication().map {
            TargetApplicationMatcher.matches(captured: capturedTarget, current: $0)
        } ?? false
        guard sameTargetImmediatelyBeforeInjection else {
            return .targetOrFocusChanged
        }

        return await injectText(text, capturedTarget.processIdentifier)
            ? .injected
            : .injectionFailed
    }

    private func presentInjectionResult(
        _ result: InjectionGateResult,
        target: TargetApplication,
        context: InjectionResultContext
    ) {
        switch result {
        case .injected:
            break
        case .injectionFailed:
            let suffix = context == .completedDictation
                ? "Der vollständige Text bleibt in Verlauf und Zwischenablage."
                : "Der Text bleibt in der Zwischenablage."
            onToast?("Einfügen in \(target.localizedName) ist fehlgeschlagen. \(suffix)", false)
        case .targetOrFocusChanged:
            onToast?(
                "Nicht in \(target.localizedName) eingefügt: Ziel-App oder Textfokus hat sich geändert. Der Text liegt in der Zwischenablage.",
                false
            )
        }
    }

    private func teardown(_ session: DictationSession) async {
        if session.teardownStarted {
            await session.teardown()
            await playSound(.recordingStopped, for: session)
            return
        }
        teardownInProgress = true
        defer { teardownInProgress = false }
        await session.teardown()
        await playSound(.recordingStopped, for: session)
        if currentSession === session {
            currentSession = nil
        }
    }

    private func finishAbortedSession(_ session: DictationSession) {
        guard currentSession == nil || session === currentSession else { return }
        currentSession = nil
        resetSessionPresentationToIdle()
    }

    private func resetSessionPresentationToIdle() {
        resetLevel()
        partialText = ""
        elapsed = 0
        recordStart = nil
        discardRequested = false
        commitRequested = false
        recordingLimitCommitQueued = false
        activeInjectionID = nil
        phase = .idle
    }

    private func isKnownWord(_ word: String, locale: Locale) -> Bool {
        let polishLocale = PolishLocale(locale: locale)
        let language: String
        switch polishLocale {
        case .de: language = "de"
        case .en: language = "en"
        case .other: return true
        }
        let key = "\(language):\(word.lowercased())"
        if let cached = knownWordCache[key] { return cached }
        let known = spellChecker(word, language)
        if knownWordCache.count >= 5_000 {
            knownWordCache.removeAll(keepingCapacity: true)
        }
        knownWordCache[key] = known
        return known
    }

    func copy(_ record: TranscriptionRecord) {
        copyToClipboard(record.correctedText)
    }

    // MARK: Zusatz-Shortcuts

    private func copyLast() {
        guard let record = history.records.first else { return }
        copy(record)
    }

    private func insertLast() {
        guard phase == .idle else { return }
        guard let record = history.records.first else { return }
        let text = record.correctedText
        copy(record)
        guard let capturedTarget = frontmostApplication() else {
            onToast?("Nicht eingefügt: Keine Ziel-App erkannt. Der Text liegt in der Zwischenablage.", false)
            return
        }
        let frontmostApplication = frontmostApplication
        let isTextFieldEditable = isTextFieldEditable
        let injectText = injectText
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await Self.runInjectionGate(
                text: text,
                capturedTarget: capturedTarget,
                frontmostApplication: frontmostApplication,
                isTextFieldEditable: isTextFieldEditable,
                injectText: injectText
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.presentInjectionResult(result, target: capturedTarget, context: .insertLast)
            }
        }
    }

    /// Modifier-Doppeltipp – Hands-free: Aufnahme starten bzw. beenden (Togglen).
    func handsFreeToggle() {
        if phase == .idle {
            startDictation(source: .handsFree)
        } else if phase == .preparing {
            stopDictation()
        } else if phase == .recording {
            requestCommit()
        }
    }

    func deleteHistoryRecord(_ record: TranscriptionRecord) {
        enqueue(.deleteHistory(record))
    }

    private func performDeleteHistoryRecord(_ record: TranscriptionRecord) async {
        do {
            try await history.delete(record)
        } catch {
            DebugLog.log("STASI-APP: Verlauf löschen fehlgeschlagen: \(error.localizedDescription)")
            onToast?("Protokoll konnte nicht gelöscht werden.", false)
        }
    }

    func deleteAllHistory() {
        enqueue(.deleteAllHistory)
    }

    private func performDeleteAllHistory() async {
        do {
            try await history.deleteAll()
        } catch {
            DebugLog.log("STASI-APP: Verlauf vollständig löschen fehlgeschlagen: \(error.localizedDescription)")
            onToast?("Verlauf konnte nicht gelöscht werden.", false)
        }
    }

    /// Aufbewahrungsdauer anwenden: Protokolle + Audio löschen, die älter
    /// als die eingestellte Dauer sind.
    func applyRetention() {
        guard settings.retention.days != nil else { return }
        if case .unreadable = history.state {
            onToast?(Self.unreadableHistoryMessage, false)
            return
        }
        enqueue(.applyRetention)
    }

    private func performRetention() async {
        guard let days = settings.retention.days else { return }
        do {
            let purged = try await history.purge(olderThan: days)
            if purged > 0 {
                DebugLog.log("STASI-APP: Retention – \(purged) alte Protokolle gelöscht")
            }
        } catch {
            DebugLog.log("STASI-APP: Retention fehlgeschlagen: \(error.localizedDescription)")
            let message: String
            if case .unreadable = history.state {
                message = Self.unreadableHistoryMessage
            } else {
                message = "Aufbewahrungsdauer konnte nicht angewendet werden."
            }
            onToast?(message, false)
        }
    }

    // MARK: Level / Timer

    /// VU-Ballistik: schneller Anschlag, träges Zurückfallen.
    /// Wird aus dem Main-Poll gerufen (keine Tasks aus dem Render-Thread).
    func ingestLevelFromPoll() {
        guard phase == .recording, let audio = currentSession?.audio else { return }
        let raw = audio.latestLevel
        let clamped = min(max(raw, 0), 1)
        displayLevel = clamped > displayLevel ? clamped : max(clamped, displayLevel * 0.88)
        if levelTraceEnabled {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastLevelTraceUptime >= 1 {
                lastLevelTraceUptime = now
                DebugLog.log(String(format: "STASI-LEVEL: raw=%.3f display=%.3f",
                                    raw, displayLevel))
            }
        }
    }

    private func resetLevel() {
        displayLevel = 0
    }

    private func snapshotRecordingDuration(at explicitNow: Date? = nil) -> TimeInterval {
        guard let start = recordStart else {
            elapsed = 0
            return 0
        }
        let current = explicitNow ?? now()
        elapsed = max(elapsed, max(0, current.timeIntervalSince(start)))
        return elapsed
    }

    /// Der bestehende 20-Hz-App-Poll aktualisiert zugleich die Aufnahmedauer;
    /// dadurch braucht die Pill keinen eigenen Einblende-Timer.
    func updateElapsedFromPoll(now explicitNow: Date? = nil) {
        guard phase == .recording else { return }
        let current = explicitNow ?? now()
        _ = snapshotRecordingDuration(at: current)
        guard !recordingLimitCommitQueued,
              elapsed >= maximumRecordingDuration else { return }
        recordingLimitCommitQueued = true
        enqueue(.recordingLimitReached)
    }

    /// Durchgehende Dauer ab Loslassen über Transkription, Nachbearbeitung
    /// und Einfügen. Der bestehende Main-Poll liest sie ohne zusätzlichen Timer.
    func processingElapsed(now: Date = Date()) -> TimeInterval {
        guard let start = processingStartedAt,
              phase == .transcribing || phase == .polishing || phase == .injecting else {
            return 0
        }
        return max(0, now.timeIntervalSince(start))
    }
}

final class PermissionCheckMailbox: @unchecked Sendable {
    struct Result: Sendable {
        let ax: Bool
        let listen: Bool
    }

    private let lock = NSLock()
    private var checking = false
    private var pending: Result?

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !checking else { return false }
        checking = true
        return true
    }

    func finish(ax: Bool, listen: Bool) {
        lock.lock()
        pending = Result(ax: ax, listen: listen)
        checking = false
        lock.unlock()
    }

    func consume() -> Result? {
        lock.lock()
        defer { lock.unlock() }
        guard let pending else { return nil }
        self.pending = nil
        return pending
    }
}
