import Foundation
import SwiftUI
import AppKit
import AVFoundation

// MARK: - AppState
// Zentrale State-Machine: idle → recording → transcribing → injecting → idle.
// Hotkey-Modi: Push-to-talk (halten) oder Umschalten (togglen).
// Ton-Feedback, WAV-Mitschrieb, Ziel-App-Erfassung.

@MainActor
@Observable
final class AppState {
    enum Phase: String {
        case idle = "BEREIT"
        case recording = "AUFNAHME"
        case transcribing = "TRANSKRIBIERE"
        case injecting = "EINFÜGEN"
    }

    private(set) var phase: Phase = .idle
    var partialText: String = ""
    private(set) var displayLevel: Double = 0
    private(set) var elapsed: TimeInterval = 0

    let settings: SettingsStore
    let dictionary: DictionaryStore
    let history: HistoryStore
    let audio = AudioCapture()
    // Pro Diktat eine frische Engine (actor, eigener Executor)
    private var speech: TranscriptionEngine?
    private var feedTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    var hotkey: HotkeyEngine?
    /// Tap wurde angelegt (says nichts über Event-Lieferung!)
    private(set) var tapInstalled = false
    /// Bedienungshilfen erteilt + Tap installiert → Hotkey wirklich scharf
    /// (Session-Tap braucht keine Eingabe-Überwachung mehr)
    var hotkeyReady: Bool { tapInstalled && accessibilityGranted }
    var accessibilityGranted = false
    var listenEventGranted = false

    /// Warum der Hotkey (noch) nicht scharf ist – für die UI.
    var hotkeyBlocker: String? {
        if !accessibilityGranted { return "Bedienungshilfen" }
        return nil
    }

    /// Wird von der Pill gesetzt: Nutzer will verwerfen (✕)
    var discardRequested = false
    /// Wird von der Pill gesetzt: Nutzer will sofort beenden + einfügen (✓)
    var commitRequested = false
    /// Toast-Rückmeldung (von AppDelegate an die Pill gebunden)
    var onToast: ((String, Bool) -> Void)?

    private var recordStart: Date?
    private var elapsedTimer: Timer?
    private var currentAudioURL: URL?

    // MARK: Command-Channel
    // Hotkey-Tap-Callbacks und @objc-Button-Thunks dürfen KEINE Tasks spawnen
    // (macOS 26.6 korrumpiert sonst Executor-Metadaten → SwiftUI-Crashes).
    // Stattdessen: thread-sicheres yield in einen AsyncStream; EIN Task aus
    // echtem Concurrency-Kontext (startCommandLoop) konsumiert die Commands.
    enum HotkeyCommand: Sendable { case press, release, discard, commit }
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
        Task {
            for await cmd in commandStream {
                switch cmd {
                case .press: hotkeyPressed()
                case .release: hotkeyReleased()
                case .discard: requestDiscard()
                case .commit: requestCommit()
                }
            }
        }
    }

    init(settings: SettingsStore) {
        self.settings = settings
        self.dictionary = DictionaryStore()
        self.history = HistoryStore()
        (commandStream, commandContinuation) = AsyncStream.makeStream(of: HotkeyCommand.self)
        accessibilityGranted = Permissions.accessibilityGranted
        listenEventGranted = Permissions.listenEventGranted
        installTap() // installiert nur, wenn Eingabe-Überwachung erteilt ist

        // Audio→Engine-Verdrahtung passiert pro Diktat in startDictation
        // (Stream + EIN Drain-Task, garantiert Puffer-Reihenfolge).
    }

    // MARK: Hotkey

    private func installTap() {
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
        let hk = HotkeyEngine(combo: currentCombo)
        // Kein Task, kein Actor-Hop im Tap-Pfad – nur enqueue (thread-sicher).
        hk.onPress = { [weak self] in self?.enqueue(.press) }
        hk.onRelease = { [weak self] in self?.enqueue(.release) }
        if hk.start() {
            hotkey = hk
            tapInstalled = true
        }
    }

    /// Aus dem AppDelegate-Poll: Berechtigungen prüfen. TCC-Preflights sind
    /// XPC-Calls – bewusst nur ~1×/s (20 Hz Preflights können die TCC-Dialoge
    /// blockieren, was der Nutzer als "eingefrorenes Fenster" erlebte).
    func refreshPermissionState() {
        hotkey?.ensureEnabled()
        applyPermissionState(ax: Permissions.accessibilityGranted,
                             listen: Permissions.listenEventGranted)
    }

    private var permissionCheckInFlight = false

    /// Poll-Variante: Preflights im Hintergrund. Hängt tccd (typisch direkt
    /// nach Ad-hoc-Re-Sign), blockiert sonst jeder Check den Main-Thread –
    /// das war das "Fenster tot, Klicks versacken"-Symptom.
    func refreshPermissionStateAsync() {
        guard !permissionCheckInFlight else { return }
        permissionCheckInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ax = Permissions.accessibilityGranted
            let listen = Permissions.listenEventGranted
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.permissionCheckInFlight = false
                    self.applyPermissionState(ax: ax, listen: listen)
                }
            }
        }
    }

    private func applyPermissionState(ax: Bool, listen: Bool) {
        guard ax != accessibilityGranted || listen != listenEventGranted else { return }
        DebugLog.log("STASI-APP: Rechte geändert – AX=\(ax) Listen=\(listen)")
        accessibilityGranted = ax
        listenEventGranted = listen
        // Session-Tap braucht Bedienungshilfen (die auch fürs Einfügen nötig sind).
        if ax && !tapInstalled {
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

    static let hotkeyDefaultsKey = "stasi.hotkey.combo"

    func applyHotkey(_ combo: HotkeyEngine.Combo) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: Self.hotkeyDefaultsKey)
        }
        hotkey?.stop()
        hotkey = nil
        tapInstalled = false // sonst blockt der installTap-Guard den neuen Hotkey
        installTap()
    }

    var currentCombo: HotkeyEngine.Combo {
        if let data = UserDefaults.standard.data(forKey: Self.hotkeyDefaultsKey),
           let c = try? JSONDecoder().decode(HotkeyEngine.Combo.self, from: data) {
            return c
        }
        return .defaultPTT
    }

    /// Modus-abhängige Auswertung (Push-to-talk vs. Umschalten)
    private func hotkeyPressed() {
        DebugLog.log("STASI-APP: hotkeyPressed (Modus \(settings.hotkeyMode.rawValue), Phase \(phase.rawValue))")
        switch settings.hotkeyMode {
        case .pushToTalk:
            startDictation()
        case .toggle:
            phase == .recording ? requestCommit() : startDictation()
        }
    }

    private func hotkeyReleased() {
        DebugLog.log("STASI-APP: hotkeyReleased (Modus \(settings.hotkeyMode.rawValue), Phase \(phase.rawValue))")
        guard settings.hotkeyMode == .pushToTalk else { return }
        stopDictation(commit: true)
    }

    func playStartSound() {
        guard settings.soundOn else { return }
        NSSound(named: "Tink")?.play()
    }

    func playStopSound() {
        guard settings.soundOn else { return }
        NSSound(named: "Pop")?.play()
    }

    // MARK: Aufnahme-Steuerung

    func startDictation() {
        guard phase == .idle else { return }
        partialText = ""
        discardRequested = false
        commitRequested = false
        phase = .recording
        recordStart = Date()
        elapsed = 0
        startElapsedTimer()
        playStartSound()

        DebugLog.log("STASI-APP: startDictation → Phase recording")
        Task { @MainActor in
            do {
                // Mikrofon-Recht ZUERST klären (async, blockiert nichts) –
                // die AVAudioEngine ohne Recht anzufassen hängt sonst den
                // Main-Thread in der synchronen TCC-Abfrage fest.
                guard await Permissions.requestMicrophone() else {
                    DebugLog.log("STASI-APP: startDictation abgebrochen – Mikrofon-Recht fehlt")
                    onToast?("Mikrofon-Zugriff fehlt – in Systemeinstellungen erlauben", false)
                    phase = .idle
                    stopElapsedTimer()
                    return
                }

                let biasWords = DictionaryBiaser(entries: dictionary.entries).vocabularyContext()
                let speech = TranscriptionEngine(locale: settings.transcriptionLocale, biasWords: biasWords)
                self.speech = speech

                let chunks = try await speech.start()
                guard let format = await speech.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }
                DebugLog.log("STASI-APP: Engine bereit (\(format.sampleRate) Hz)")

                // Audio muss die Engine in Aufnahme-Reihenfolge erreichen:
                // ein Stream + EIN Drain-Task (kein Task pro Puffer!).
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation
                self.feedTask = Task.detached(priority: .userInitiated) {
                    for await chunk in audioStream {
                        await speech.feed(chunk)
                    }
                }

                // WAV-Mitschrieb für Play/Export
                let audioDir = DictionaryStore.appSupportDirectory.appendingPathComponent("audio", isDirectory: true)
                try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
                currentAudioURL = audioDir.appendingPathComponent("\(UUID().uuidString).wav")

                try audio.start(outputFormat: format, recordTo: currentAudioURL) { chunk in
                    audioContinuation.yield(chunk)
                }
                DebugLog.log("STASI-APP: audio.start fertig – Aufnahme läuft")

                // Nutzer hat während des Hochfahrens schon losgelassen?
                guard self.phase == .recording else {
                    DebugLog.log("STASI-APP: Start abgebrochen – Phase wechselte während Setup")
                    _ = self.audio.stop()
                    audioContinuation.finish()
                    self.audioContinuation = nil
                    await self.feedTask?.value
                    self.feedTask = nil
                    await speech.finish()
                    self.speech = nil
                    return
                }

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            self.partialText = chunk.text
                        }
                    } catch {
                        DebugLog.log("STASI-APP: Transkript-Strom Fehler: \(error.localizedDescription)")
                    }
                }
            } catch {
                DebugLog.log("STASI-APP: startDictation FEHLER: \(error.localizedDescription)")
                partialText = "⚠︎ \(error.localizedDescription)"
                phase = .idle
                currentAudioURL = nil
                self.speech = nil
            }
        }
    }

    func stopDictation(commit: Bool) {
        guard phase == .recording else {
            DebugLog.log("STASI-APP: stopDictation ignoriert (Phase \(phase.rawValue))")
            return
        }
        DebugLog.log("STASI-APP: stopDictation (commit=\(commit))")
        guard commit else {
            requestDiscard()
            return
        }
        phase = .transcribing
        stopElapsedTimer()
        playStopSound()
        let recordedURL = audio.stop()
        let duration = elapsed
        let speech = self.speech

        Task { @MainActor in
            defer { resetLevel() }
            // Erst alle gepufferten Chunks in die Engine drainen, DANN
            // finalisieren – sonst fehlt das Satzende.
            audioContinuation?.finish()
            audioContinuation = nil
            await feedTask?.value
            feedTask = nil
            DebugLog.log("STASI-APP: Audio gedraint, finalisiere…")
            await speech?.finish()
            await consumeTask?.value
            consumeTask = nil
            self.speech = nil

            let raw = partialText
            DebugLog.log("STASI-APP: Transkription fertig (\(raw.count) Zeichen)")
            finishTranscription(rawText: raw,
                                duration: duration,
                                audioURL: recordedURL ?? currentAudioURL)
            currentAudioURL = nil
        }
    }

    /// Pill-Aktionen
    func requestDiscard() {
        guard phase == .recording else { return }
        DebugLog.log("STASI-APP: requestDiscard")
        discardRequested = true
        stopElapsedTimer()
        playStopSound()
        _ = audio.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil
        let speech = self.speech
        self.speech = nil
        onToast?("Aufnahme verworfen", false)
        Task { @MainActor in
            await speech?.finish() // Stream sauber beenden
            try? FileManager.default.removeItem(at: currentAudioURL ?? URL(fileURLWithPath: "/dev/null"))
            currentAudioURL = nil
            resetLevel()
            partialText = ""
            phase = .idle
        }
    }

    func requestCommit() {
        guard phase == .recording else { return }
        stopDictation(commit: true)
    }

    private func finishTranscription(rawText: String, duration: Double, audioURL: URL?) {
        DebugLog.log("STASI-APP: finishTranscription (\(rawText.count) Zeichen roh)")
        let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Korrektur-Pass (garantierter Pfad)
        let (corrected, applied) = CorrectionEngine.correct(trimmedRaw, entries: dictionary.entries)
        let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            try? FileManager.default.removeItem(at: audioURL ?? URL(fileURLWithPath: "/dev/null"))
            partialText = ""
            phase = .idle
            return
        }

        history.insert(
            TranscriptionRecord(
                date: Date(),
                localeID: settings.transcriptionLocale.identifier,
                rawText: trimmedRaw,
                correctedText: trimmed,
                corrections: applied,
                durationSecs: duration,
                targetApp: NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
                audioPath: audioURL?.path
            )
        )

        phase = .injecting
        partialText = trimmed
        onToast?("Protokolliert. Eingefügt ✓", true)
        Task.detached(priority: .userInitiated) {
            TextInjector.inject(trimmed)
            await MainActor.run { [weak self] in
                self?.phase = .idle
                self?.partialText = ""
            }
        }
    }

    func copy(_ record: TranscriptionRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.correctedText, forType: .string)
    }

    // MARK: Level / Timer

    /// VU-Ballistik: schneller Anschlag, träges Zurückfallen.
    /// Wird aus dem Main-Poll gerufen (keine Tasks aus dem Render-Thread).
    func ingestLevelFromPoll() {
        guard phase == .recording else { return }
        let raw = audio.latestLevel
        let clamped = min(max(raw, 0), 1)
        displayLevel = clamped > displayLevel ? clamped : max(clamped, displayLevel * 0.88)
    }

    private func resetLevel() {
        displayLevel = 0
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        // Statisch MainActor-isoliert (Timer auf Main-RunLoop) → kein Task nötig
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordStart else { return }
            self.elapsed = Date().timeIntervalSince(start)
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
