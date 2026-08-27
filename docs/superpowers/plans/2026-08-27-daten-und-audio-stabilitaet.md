# Daten- und Audio-Stabilität Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verhindere Datenverlust, Session-Rennen, stille Speech-Aussetzer und Abstürze bei ungewöhnlichen Audiogeräten.

**Architecture:** `HistoryStore` bekommt einen expliziten Fehlerzustand und blockiert Schreibzugriffe auf eine unlesbare Datei. Jede `DictationSession` besitzt eine eigene `AudioCapturing`-Instanz aus einer Factory. Audio- und Speech-Puffer bleiben begrenzt, melden Überläufe aber sichtbar. Geräte- und Speech-Lifecycle-Regeln werden in kleine testbare Helfer ausgelagert.

**Tech Stack:** Swift 6, SwiftPM, XCTest, AppKit, AVFoundation, CoreAudio, SpeechAnalyzer.

**Spec:** `docs/superpowers/specs/2026-08-27-stabilisierung-und-github-release-design.md`

## Global Constraints

- Kein SQLite-/SwiftData-Umbau in dieser Runde.
- Kein vollständiger Ersatz von `AppState` oder `DictationSession`.
- Kein recycelter AUHAL-Renderpuffer darf ungekopiert asynchron weitergereicht werden.
- Apple-`resultsTask` darf wegen des bekannten Lifecycle-Problems nicht blind gecancelt werden.
- Jeder Produktionsschritt beginnt mit einem fehlschlagenden Regressionstest.
- Jeder Commit muss bauen und seine gezielten Tests bestehen.
- Architekturunabhängiger Testbefehl:

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

---

### Task 1: Beschädigte Historie schützen

**Files:**
- Modify: `Sources/Stasi/Core/TranscriptionRecord.swift:47-115`
- Modify: `Sources/Stasi/Core/AppState.swift:690-720`
- Test: `Tests/StasiTests/StoreTests.swift:144-260`
- Test: `Tests/StasiTests/DictationSessionTests.swift`

**Interfaces:**
- Produces:

```swift
enum HistoryStoreState: Equatable {
    case missing
    case loaded
    case unreadable(String)
}

enum HistoryStoreError: LocalizedError {
    case writeBlockedByUnreadableHistory(URL)
    case encodingFailed(String)
    case writeFailed(URL, String)
}

@MainActor @Observable final class HistoryStore {
    private(set) var state: HistoryStoreState
    private(set) var lastError: String?
    func save() throws
    func insert(_ record: TranscriptionRecord, at position: Int = 0) throws
}
```

- [ ] **Step 1: Schreibe Tests für fehlende, gültige und beschädigte Dateien**

```swift
@Test func missingHistoryIsNotAnError() throws {
    let directory = try temporaryDirectory()
    let store = HistoryStore(directory: directory)
    #expect(store.records.isEmpty)
    #expect(store.state == .missing)
    #expect(store.lastError == nil)
}

@Test func malformedHistoryIsUnreadableAndPreserved() throws {
    let directory = try temporaryDirectory()
    let url = directory.appending(path: "history.json")
    let original = Data("{not-json".utf8)
    try original.write(to: url)

    let store = HistoryStore(directory: directory)

    guard case .unreadable = store.state else {
        Issue.record("Expected unreadable state")
        return
    }
    #expect(try Data(contentsOf: url) == original)
}

@Test func insertCannotOverwriteUnreadableHistory() throws {
    let directory = try temporaryDirectory()
    let url = directory.appending(path: "history.json")
    let original = Data("{not-json".utf8)
    try original.write(to: url)
    let store = HistoryStore(directory: directory)

    #expect(throws: HistoryStoreError.self) {
        try store.insert(.fixture())
    }
    #expect(store.records.isEmpty)
    #expect(try Data(contentsOf: url) == original)
}
```

- [ ] **Step 2: Führe die Historientests aus und bestätige das erwartete Rot**

Run:

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.HistoryStoreTests'
```

Expected: Die neuen Tests scheitern, weil `state` fehlt und `insert` nicht wirft.

- [ ] **Step 3: Implementiere explizite Ladezustände ohne `try?`**

```swift
func load() {
    guard fileManager.fileExists(atPath: fileURL.path) else {
        records = []
        state = .missing
        lastError = nil
        return
    }

    do {
        let data = try Data(contentsOf: fileURL)
        records = try decoder.decode([TranscriptionRecord].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
        state = .loaded
        lastError = nil
    } catch {
        records = []
        let message = error.localizedDescription
        state = .unreadable(message)
        lastError = message
    }
}
```

Vor jeder Mutation:

```swift
private func ensureWritable() throws {
    if case .unreadable = state {
        throw HistoryStoreError.writeBlockedByUnreadableHistory(fileURL)
    }
}
```

`insert`, `delete`, `deleteAll`, `purge` und `save` rufen `ensureWritable()` auf und mutieren erst danach.

- [ ] **Step 4: Passe App-Aufrufer an den werfenden Store an**

In `AppState`:

```swift
do {
    try history.insert(record)
} catch {
    toast = ToastState(
        message: "Verlauf konnte nicht gespeichert werden. Die Audiodatei bleibt erhalten.",
        kind: .error
    )
    return
}
```

Lösch- und Retention-Aufrufer zeigen ebenfalls einen Fehler und behaupten keinen Erfolg.

- [ ] **Step 5: Prüfe, dass eine fertige WAV-Datei bei Speicherfehler erhalten bleibt**

Erweitere den Session-Test mit einer `HistoryStore`-Fake, deren `insert` wirft. Prüfe:

```swift
#expect(fakeHistory.insertCount == 1)
#expect(fileManager.fileExists(atPath: finishedWAV.path))
#expect(textInjector.callCount == 0)
#expect(appState.phase == .idle)
```

- [ ] **Step 6: Führe Store- und Sessiontests aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.HistoryStoreTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
```

Expected: PASS.

- [ ] **Step 7: Committe den Datensicherheitsfix**

```bash
git add Sources/Stasi/Core/TranscriptionRecord.swift \
  Sources/Stasi/Core/AppState.swift \
  Tests/StasiTests/StoreTests.swift \
  Tests/StasiTests/DictationSessionTests.swift
git commit -m "fix(store): beschädigte Historie vor Überschreiben schützen

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Wörterbuch-Watcher nach Neustart aktivieren

**Files:**
- Modify: `Sources/Stasi/Core/DictionaryStore.swift:22-62,180-230`
- Test: `Tests/StasiTests/DictionaryWatcherTests.swift`

**Interfaces:**
- Consumes: bestehendes `DictionaryStore(directory:)`.
- Produces: Nach jedem erfolgreichen oder fehlenden Initial-Load läuft genau ein Datei-Watcher.

- [ ] **Step 1: Schreibe den fehlschlagenden Neustart-Test**

```swift
@Test func watchesExistingDictionaryImmediatelyAfterInit() async throws {
    let directory = try temporaryDirectory()
    let url = directory.appending(path: "dictionary.json")
    try encode([DictionaryEntry(term: "Alt", replacement: "Alt")]).write(to: url)

    let store = DictionaryStore(directory: directory)
    try encode([DictionaryEntry(term: "Neu", replacement: "Neu")])
        .write(to: url, options: .atomic)

    try await eventually(timeout: .seconds(1)) {
        store.entries.map(\.term) == ["Neu"]
    }
}
```

- [ ] **Step 2: Führe nur die Watcher-Tests aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictionaryWatcherTests'
```

Expected: FAIL, weil nach vorhandenem File kein Watcher läuft.

- [ ] **Step 3: Starte den Watcher genau einmal nach `load()`**

```swift
init(directory: URL? = nil) {
    // bestehende URL-Einrichtung
    load()
    restartWatcher()
}
```

Entferne oder idempotentisiere doppelte `restartWatcher()`-Aufrufe aus Seed-/Save-Pfaden. `restartWatcher()` beendet zuerst den alten Watcher und erzeugt danach genau einen neuen.

- [ ] **Step 4: Führe alle Dictionary-Tests aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictionaryWatcherTests'
```

Expected: PASS einschließlich vorhandener Recreate- und Save-Tests.

- [ ] **Step 5: Committe den Watcher-Fix**

```bash
git add Sources/Stasi/Core/DictionaryStore.swift \
  Tests/StasiTests/DictionaryWatcherTests.swift
git commit -m "fix(dictionary): Watcher bei bestehender Datei starten

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Eigene Audio-Capture-Instanz pro Session

**Files:**
- Modify: `Sources/Stasi/Core/AppState.swift:38-43,136-175,402-619`
- Modify: `Sources/Stasi/Core/DictationSession.swift:31-88`
- Modify: `Sources/Stasi/Core/AudioCapture.swift:134-198`
- Test: `Tests/StasiTests/DictationSessionTests.swift`
- Test: `Tests/StasiTests/AudioCaptureFileTests.swift`

**Interfaces:**
- Produces:

```swift
typealias AudioCaptureFactory = @MainActor () -> any AudioCapturing

enum AudioCaptureError: LocalizedError {
    case alreadyRunning
    // bestehende Fälle bleiben erhalten
}
```

`AppState.init` erhält:

```swift
audioFactory: @escaping AudioCaptureFactory = { AudioCapture() }
```

- [ ] **Step 1: Erweitere die Test-Fakes um eine protokollierende Factory**

```swift
@MainActor final class AudioFactorySpy {
    private(set) var captures: [FakeAudioCapture] = []

    func make() -> any AudioCapturing {
        let capture = FakeAudioCapture()
        captures.append(capture)
        return capture
    }
}
```

Schreibe Tests für:

```swift
#expect(factory.captures.count == 2)
#expect(factory.captures[0] !== factory.captures[1])
```

und einen Teardown-Test, bei dem `captures[0].stop()` verspätet endet. Die zweite Aufnahme darf bis dahin nicht starten.

- [ ] **Step 2: Schreibe einen direkten Doppelstart-Test für `AudioCapture`**

```swift
@Test func secondStartWhileRunningThrows() throws {
    let capture = AudioCapture(/* vorhandene Test-Injektionen */)
    try capture.start(outputFormat: format, recordTo: nil, preferredMicUID: nil) { _ in }
    #expect(throws: AudioCaptureError.alreadyRunning) {
        try capture.start(outputFormat: format, recordTo: nil, preferredMicUID: nil) { _ in }
    }
    _ = capture.stop()
}
```

- [ ] **Step 3: Führe die Lifecycle-Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.AudioCaptureFileTests'
```

Expected: Factory-Signatur fehlt und Doppelstart wirft nicht.

- [ ] **Step 4: Ersetze `AppState.audio` durch `audioFactory`**

```swift
private let audioFactory: AudioCaptureFactory
private var teardownInProgress = false
```

In `startDictation()`:

```swift
guard !teardownInProgress else { return }
let audio = audioFactory()
let session = DictationSession(
    speech: speechFactory(),
    audio: audio,
    targetApplication: targetApplication
)
currentSession = session
```

- [ ] **Step 5: Serialisiere den Teardown**

Alle Abschluss-, Fehler- und Kurztipp-Pfade laufen durch genau eine Methode:

```swift
private func teardown(_ session: DictationSession) async {
    guard !session.teardownStarted else { return }
    teardownInProgress = true
    defer { teardownInProgress = false }
    await session.teardown()
    if currentSession === session {
        currentSession = nil
    }
}
```

Die UI darf bei einem Kurztipp sofort verschwinden. Der interne Start-Guard bleibt aber bis zum Ende von `await session.teardown()` aktiv.

- [ ] **Step 6: Mache Doppelstart zu einem echten Fehler**

In `AudioCapture.start`:

```swift
stateLock.lock()
defer { stateLock.unlock() }
guard !isRunningStorage else {
    throw AudioCaptureError.alreadyRunning
}
```

Verwende die bestehende Synchronisationsstrategie des Typs. Führe keine neue Sperre im Rendercallback ein.

- [ ] **Step 7: Führe Lifecycle-Tests erneut aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.AudioCaptureFileTests'
```

Expected: PASS.

- [ ] **Step 8: Committe den Session-Lifecycle**

```bash
git add Sources/Stasi/Core/AppState.swift \
  Sources/Stasi/Core/DictationSession.swift \
  Sources/Stasi/Core/AudioCapture.swift \
  Tests/StasiTests/DictationSessionTests.swift \
  Tests/StasiTests/AudioCaptureFileTests.swift
git commit -m "fix(audio): Capture pro Diktat-Session isolieren

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Speech-Pufferüberlauf sichtbar behandeln

**Files:**
- Create: `Sources/Stasi/Core/DictationSessionHealth.swift`
- Modify: `Sources/Stasi/Core/AppState.swift:472-501`
- Create: `Tests/StasiTests/DictationSessionHealthTests.swift`
- Modify: `Tests/StasiTests/DictationSessionTests.swift`

**Interfaces:**
- Produces:

```swift
final class DictationSessionHealth: @unchecked Sendable {
    enum Failure: Equatable, Sendable {
        case speechBufferOverflow
        case speechStreamTerminated
    }

    var failure: Failure? { get }
    func record(_ result: AsyncStream<AudioChunk>.Continuation.YieldResult)
}
```

- [ ] **Step 1: Schreibe pure Health-Tests**

```swift
@Test func droppedChunkMarksOverflow() {
    let health = DictationSessionHealth()
    health.record(.dropped(.fixture()))
    #expect(health.failure == .speechBufferOverflow)
}

@Test func firstFailureWins() {
    let health = DictationSessionHealth()
    health.record(.dropped(.fixture()))
    health.record(.terminated)
    #expect(health.failure == .speechBufferOverflow)
}
```

- [ ] **Step 2: Schreibe den langsamen Speech-Integrationstest**

Erzeuge mehr als 64 Chunks, während `FakeSpeechEngine.feed` blockiert. Prüfe:

```swift
#expect(fakeHistory.records.isEmpty)
#expect(textInjector.callCount == 0)
#expect(appState.phase == .idle)
#expect(fileManager.fileExists(atPath: finishedWAV.path))
#expect(appState.toast?.message.contains("unvollständig") == true)
```

- [ ] **Step 3: Führe die neuen Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionHealthTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
```

- [ ] **Step 4: Implementiere den thread-sicheren Health-Zustand**

Nutze die im Projekt vorhandene Lock-Konvention. `record` darf nur den ersten Fehler setzen.

- [ ] **Step 5: Werte jedes `yield` aus**

```swift
let result = audioContinuation.yield(chunk)
health.record(result)
```

Verwende `.bufferingOldest(64)`, damit bereits angenommene Chunks ihre Reihenfolge behalten. Bei `.dropped` wird kein scheinbar erfolgreiches Ergebnis gespeichert oder injiziert.

- [ ] **Step 6: Prüfe Health vor Finalisierung und Speicherung**

Nach Audio-Stop und Feed-Drain:

```swift
if health.failure != nil {
    await failSession(
        message: "Die Aufnahme war unterbrochen. Die Audiodatei bleibt erhalten.",
        preserveWAV: true
    )
    return
}
```

- [ ] **Step 7: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionHealthTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
git add Sources/Stasi/Core/DictationSessionHealth.swift \
  Sources/Stasi/Core/AppState.swift \
  Tests/StasiTests/DictationSessionHealthTests.swift \
  Tests/StasiTests/DictationSessionTests.swift
git commit -m "fix(speech): Pufferüberlauf als Sessionfehler behandeln

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Mehrpuffer- und Mehrkanalgeräte sicher behandeln

**Files:**
- Modify: `Sources/Stasi/Core/MicrophoneSelection.swift`
- Modify: `Sources/Stasi/Core/AudioCapture.swift:223-469`
- Modify: `Tests/StasiTests/MicrophoneCatalogTests.swift`
- Modify: `Tests/StasiTests/AudioCaptureFileTests.swift`

**Interfaces:**
- Produces:

```swift
enum MicrophoneTransport: Equatable, Sendable {
    case builtIn
    case wired
    case bluetooth
    case virtual
    case unknown(UInt32)
}

typealias AudioConverterFactory =
    @Sendable (AVAudioFormat, AVAudioFormat) -> AVAudioConverter?
```

`MicDevice` erhält `transport`, `inputChannels` und `isSupportedForSpeech`.

- [ ] **Step 1: Schreibe Tests für variable `AudioBufferList`**

Baue im Test eine Liste mit mindestens drei `AudioBuffer`-Einträgen. Der Produktionshelfer muss sie über `UnsafeMutableAudioBufferListPointer` lesen.

```swift
#expect(inputChannelCount(from: listPointer) == 3)
```

- [ ] **Step 2: Schreibe Tests für 3+-Kanal-Hardwareformate**

```swift
@Test func clientFormatLimitsSpeechToSupportedChannelCount() throws {
    let native = try makeFormat(channels: 6)
    let client = try AudioCapture.clientInputFormat(for: native)
    #expect(client.channelCount == 1 || client.channelCount == 2)
}
```

- [ ] **Step 3: Schreibe den Converter-nil-Test**

Injiziere eine `AudioConverterFactory`, die `nil` liefert. Bei unterschiedlichen Formaten muss `start` `.converterUnavailable` werfen und die AudioUnit abbauen.

- [ ] **Step 4: Schreibe Katalogtests für Bluetooth-Fallback**

```swift
@Test func automaticDefaultPrefersBuiltInOverBluetoothSystemDefault() {
    let selected = MicrophoneCatalog.automaticDefault(from: [bluetoothDefault, builtIn])
    #expect(selected?.uid == builtIn.uid)
}

@Test func explicitSupportedBluetoothSelectionIsRespected() {
    let selected = MicrophoneCatalog.resolve(
        preferredUID: bluetooth.uid,
        devices: [bluetooth, builtIn]
    )
    #expect(selected?.uid == bluetooth.uid)
}
```

- [ ] **Step 5: Führe Audio- und Katalogtests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.MicrophoneCatalogTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.AudioCaptureFileTests'
```

- [ ] **Step 6: Ersetze manuelle Buffer-Offsets**

Nutze:

```swift
let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
```

Kein Zugriff über den Byte-Span des einzelnen `mBuffers`-Feldes.

- [ ] **Step 7: Begrenze das Clientformat**

Erzeuge ein explizites unterstütztes Monoformat für Speech. Wenn das Hardwareformat mehr Kanäle besitzt, bleibt es Hardwareformat der AudioUnit; das Client-/Converterziel bleibt Mono.

- [ ] **Step 8: Behandle einen fehlenden Converter als Fehler**

```swift
if inputFormat != outputFormat {
    guard let converter = converterFactory(inputFormat, outputFormat) else {
        teardownAudioUnit()
        throw AudioCaptureError.converterUnavailable(
            input: inputFormat,
            output: outputFormat
        )
    }
    self.converter = converter
}
```

- [ ] **Step 9: Lies und mappe den CoreAudio-Transporttyp**

Nutze `kAudioDevicePropertyTransportType`. Mappe mindestens eingebaute, USB/kabelgebundene, Bluetooth-, virtuelle und unbekannte Geräte.

- [ ] **Step 10: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.MicrophoneCatalogTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.AudioCaptureFileTests'
git add Sources/Stasi/Core/MicrophoneSelection.swift \
  Sources/Stasi/Core/AudioCapture.swift \
  Tests/StasiTests/MicrophoneCatalogTests.swift \
  Tests/StasiTests/AudioCaptureFileTests.swift
git commit -m "fix(audio): Mehrkanalgeräte und Bluetooth-Fallback absichern

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Realtime-Pfad begrenzen und Runtimefehler melden

**Files:**
- Modify: `Sources/Stasi/Core/AudioCapture.swift:474-695`
- Modify: `Sources/Stasi/Core/DictationSession.swift`
- Modify: `Sources/Stasi/Core/AppState.swift`
- Modify: `Tests/StasiTests/AudioCaptureFileTests.swift`
- Modify: `Tests/StasiTests/DictationSessionTests.swift`

**Interfaces:**
- Produces:

```swift
enum AudioCaptureRuntimeError: Equatable, Sendable {
    case renderFailed(OSStatus)
    case bufferCopyFailed
    case conversionFailed(String)
    case wavWriteFailed(String)
    case processingBacklog
}
```

`AudioCapturing.start` erhält zusätzlich:

```swift
onRuntimeError: @escaping @Sendable (AudioCaptureRuntimeError) -> Void
```

- [ ] **Step 1: Schreibe Tests für Runtimefehler und Backlog**

Testfälle:

```swift
#expect(errorSpy.values == [.conversionFailed("test")])
#expect(errorSpy.values == [.processingBacklog])
#expect(fakeHistory.records.isEmpty)
#expect(textInjector.callCount == 0)
```

Ein Fehler darf nur einmal gemeldet werden.

- [ ] **Step 2: Schreibe den Pufferbesitz-Regressionstest**

Verändere den simulierten Renderpuffer nach Rückkehr des Callbacks. Der an Speech weitergereichte Chunk muss unverändert bleiben.

- [ ] **Step 3: Führe Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.AudioCaptureFileTests'
```

- [ ] **Step 4: Trenne Callback und serielle Verarbeitung minimal**

Realtime-Callback:

1. `AudioUnitRender`.
2. Sofortige Kopie in eigenen Speicher aus einem begrenzten Pool oder einer begrenzten Queue.
3. Nicht blockierendes Einreihen.
4. Bei voller Queue einmal `.processingBacklog` melden.

Serielle Verarbeitung:

1. RMS.
2. Conversion.
3. WAV-Schreiben.
4. `onBuffer`.

Logging, `AVAudioConverter` und Datei-I/O dürfen nicht im Realtime-Callback laufen.

- [ ] **Step 5: Begrenze den Writer-Backlog**

Verwende eine feste kleine Kapazität, die mit Tests steuerbar ist. Bei Überlauf wird die Session beendet. Es gibt keine unbounded Closure-Queue.

- [ ] **Step 6: Beende die Session bei Runtimefehler geordnet**

`AppState` verarbeitet den ersten Fehler über den gemeinsamen Teardown. Keine History und keine Injection. Eine WAV wird nur angeboten, wenn `stop()` sie sauber geschlossen zurückgibt.

- [ ] **Step 7: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.AudioCaptureFileTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
git add Sources/Stasi/Core/AudioCapture.swift \
  Sources/Stasi/Core/DictationSession.swift \
  Sources/Stasi/Core/AppState.swift \
  Tests/StasiTests/AudioCaptureFileTests.swift \
  Tests/StasiTests/DictationSessionTests.swift
git commit -m "fix(audio): Realtime-Verarbeitung begrenzen und Fehler melden

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Speech-Locale und hängende Analyzer begrenzen

**Files:**
- Modify: `Sources/Stasi/Core/TranscriptionEngine.swift:62-92,153-290`
- Modify: `Tests/StasiTests/TranscriptionPipelineTests.swift`
- Modify: `Tests/StasiTests/DictationSessionTests.swift`
- Create: `Tests/StasiTests/SpeechLifecyclePolicyTests.swift`

**Interfaces:**
- Produces:

```swift
enum TranscriptionError: LocalizedError {
    case unsupportedLocale(String)
    case tooManyRetiredAnalyzers
}

enum SpeechLocaleResolution {
    static func resolve(
        requested: Locale,
        supportedEquivalent: Locale?
    ) throws -> Locale
}

actor SpeechRetirementLimiter {
    init(limit: Int)
    func reserve() throws
    func release()
}
```

- [ ] **Step 1: Schreibe Locale-Resolution-Tests**

```swift
@Test func unsupportedLocaleDoesNotFallBackToEnglish() {
    #expect(throws: TranscriptionError.unsupportedLocale("fr-FR")) {
        try SpeechLocaleResolution.resolve(
            requested: Locale(identifier: "fr-FR"),
            supportedEquivalent: nil
        )
    }
}
```

Prüfe zusätzlich, dass angeforderte und im Record gespeicherte Locale nach erfolgreicher Auflösung übereinstimmen.

- [ ] **Step 2: Schreibe Retirement-Limit-Tests**

```swift
@Test func blocksWhenRetiredAnalyzerLimitIsReached() async throws {
    let limiter = SpeechRetirementLimiter(limit: 2)
    try await limiter.reserve()
    try await limiter.reserve()
    await #expect(throws: TranscriptionError.tooManyRetiredAnalyzers) {
        try await limiter.reserve()
    }
}
```

Prüfe, dass natürliche Fertigstellung `release()` aufruft.

- [ ] **Step 3: Führe die Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.SpeechLifecyclePolicyTests'
```

- [ ] **Step 4: Entferne den stillen `en-US`-Fallback**

Wenn keine unterstützte äquivalente Locale existiert, wirft Setup `.unsupportedLocale`. Der sichtbare Fehler nennt die nicht unterstützte Sprache und verweist auf die Spracheinstellung.

- [ ] **Step 5: Begrenze Retirees ohne Cancellation**

Vor dem Retire wird ein Slot reserviert. Nach natürlichem Ende von Finalize und Resultstream wird er freigegeben. Bei vollem Limit werden neue Speech-Starts abgelehnt. `resultsTask.cancel()` wird nicht ergänzt.

- [ ] **Step 6: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.SpeechLifecyclePolicyTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.TranscriptionPipelineTests'
git add Sources/Stasi/Core/TranscriptionEngine.swift \
  Tests/StasiTests/SpeechLifecyclePolicyTests.swift \
  Tests/StasiTests/TranscriptionPipelineTests.swift \
  Tests/StasiTests/DictationSessionTests.swift
git commit -m "fix(speech): Locale und hängende Analyzer kontrollieren

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Daten- und Audio-Gesamtprüfung

**Files:**
- Verify only.

- [ ] **Step 1: Führe die vollständige Testsuite aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

Expected: Alle Tests PASS.

- [ ] **Step 2: Führe Debug- und Release-Build aus**

```bash
swift build
swift build -c release
```

Expected: Beide Builds erfolgreich, keine neuen Warnungen in veränderten Dateien.

- [ ] **Step 3: Prüfe Diff und Arbeitsbaum**

```bash
git diff --check
git status --short
```

Expected: Kein Whitespace-Fehler. Nur bewusst noch offene Dateien aus späteren Plänen dürfen uncommitted sein.

- [ ] **Step 4: Erzeuge bei nötigen kleinen Korrekturen einen eigenen Commit**

```bash
git add <nur-korrigierte-dateien>
git commit -m "fix: Daten- und Audio-Stabilisierung abschließen

Co-Authored-By: Claude <noreply@anthropic.com>"
```
