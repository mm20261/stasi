# Hotkeys, Ziel-App und Sounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repariere Hotkey-Randfälle, verhindere Texteinfügung in die falsche App und kapsle Aufnahme-Sounds für spätere eigene Sounddateien.

**Architecture:** Seitenspezifische Modifier und Hotkey-Erfassung werden über pure Zustandshelfer testbar. Jede Session speichert einen unveränderlichen Ziel-App-Snapshot. `SoundFeedback` ersetzt direkte `NSSound`-Aufrufe und erzwingt eine sichere Reihenfolge zum Audio-Lifecycle.

**Tech Stack:** Swift 6, SwiftPM, XCTest, AppKit, Accessibility API, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-08-27-stabilisierung-und-github-release-design.md`

## Global Constraints

- Die Bedienung und bestehenden Hotkey-Formate bleiben kompatibel.
- Text wird bei einem Ziel-App-Wechsel nicht automatisch in die neue App geschrieben.
- Das Transkript bleibt bei verweigerter Einfügung in Verlauf und Zwischenablage verfügbar.
- Die Soundauswahl in den Einstellungen ist nicht Teil dieser Runde.
- `settings.soundOn` bleibt die zentrale Ein-/Aus-Einstellung.
- Jeder Produktionsschritt beginnt mit einem fehlschlagenden Regressionstest.
- Testbefehl:

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

---

### Task 1: Physische Modifier getrennt verfolgen

**Files:**
- Modify: `Sources/Stasi/Core/HotkeyEngine.swift:174-237`
- Create: `Tests/StasiTests/PhysicalModifierStateTests.swift`
- Modify: `Tests/StasiTests/ShortcutDetectorTests.swift`

**Interfaces:**
- Produces:

```swift
struct PhysicalModifierState {
    private(set) var pressedKeyCodes: Set<UInt64> = []

    mutating func processFlagsChanged(
        keyCode: UInt64,
        familyFlagIsSet: Bool
    ) -> Bool
}
```

Die Rückgabe ist der neue Zustand genau dieser physischen Taste.

- [ ] **Step 1: Schreibe die seitenspezifischen Regressionstests**

```swift
@Test func releasingRightCommandWhileLeftCommandRemainsPressedReleasesRight() {
    var state = PhysicalModifierState()

    #expect(state.processFlagsChanged(keyCode: rightCommand, familyFlagIsSet: true))
    #expect(state.processFlagsChanged(keyCode: leftCommand, familyFlagIsSet: true))
    #expect(!state.processFlagsChanged(keyCode: rightCommand, familyFlagIsSet: true))
    #expect(state.pressedKeyCodes.contains(leftCommand))
}
```

Ergänze spiegelbildliche Tests für Shift, Option und Control sowie einen Test gegen doppelte Start-/Release-Ereignisse.

- [ ] **Step 2: Führe die neuen Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.PhysicalModifierStateTests'
```

Expected: Typ fehlt.

- [ ] **Step 3: Implementiere den physischen Zustandshelfer**

Bei einem `flagsChanged`-Event gilt:

- Wenn diese konkrete Taste bereits als gedrückt bekannt ist, bedeutet das nächste Event Loslassen. Das Familienflag einer anderen Seite darf das nicht verhindern.
- Wenn sie nicht bekannt ist und das Familienflag gesetzt ist, bedeutet es Drücken.
- Duplizierte unplausible Events erzeugen keine zweite Aktion.

- [ ] **Step 4: Verwende den Helfer in `HotkeyEngine`**

Der bestehende Callback bleibt unverändert:

```swift
onPress?()
onRelease?()
```

Nur die Entscheidung, wann er ausgelöst wird, verwendet den neuen physischen Zustand.

- [ ] **Step 5: Führe Hotkey-Tests aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.PhysicalModifierStateTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.ShortcutDetectorTests'
```

Expected: PASS.

- [ ] **Step 6: Committe den Modifier-Fix**

```bash
git add Sources/Stasi/Core/HotkeyEngine.swift \
  Tests/StasiTests/PhysicalModifierStateTests.swift \
  Tests/StasiTests/ShortcutDetectorTests.swift
git commit -m "fix(hotkey): seitenspezifisches Loslassen erkennen

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Hotkey-Erfassung gemeinsam und stabil machen

**Files:**
- Modify: `Sources/Stasi/UI/HotkeyCaptureMonitor.swift`
- Modify: `Sources/Stasi/UI/SettingsWindowView.swift:176-220`
- Modify: `Sources/Stasi/UI/OnboardingView.swift:370-403`
- Create: `Tests/StasiTests/HotkeyCaptureDraftTests.swift`

**Interfaces:**
- Produces:

```swift
struct HotkeyCaptureDraft: Equatable {
    private(set) var combo: HotkeyEngine.Combo?
    private(set) var isComplete: Bool

    mutating func process(_ event: HotkeyCaptureEvent)
}
```

- [ ] **Step 1: Schreibe Tests für vollständige und unvollständige Entwürfe**

```swift
@Test func completeComboSurvivesModifierRelease() {
    var draft = HotkeyCaptureDraft()
    draft.process(.modifier(.command))
    draft.process(.key(keyCode: 40, modifiers: [.command]))
    draft.process(.modifierReleased(.command))

    #expect(draft.combo == .init(keyCode: 40, modifiers: [.command]))
    #expect(draft.isComplete)
}

@Test func modifierOnlyDraftClearsOnRelease() {
    var draft = HotkeyCaptureDraft()
    draft.process(.modifier(.command))
    draft.process(.modifierReleased(.command))
    #expect(draft.combo == nil)
}
```

Ergänze `.cancel` und wiederholte Events.

- [ ] **Step 2: Führe die Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.HotkeyCaptureDraftTests'
```

- [ ] **Step 3: Implementiere den Reducer**

Regeln:

```swift
switch event {
case .modifier(let modifier):
    combo = .modifierOnly(modifier)
    isComplete = false
case .key(let keyCode, let modifiers):
    combo = .init(keyCode: keyCode, modifiers: modifiers)
    isComplete = true
case .modifierReleased:
    if !isComplete { combo = nil }
case .cancel:
    combo = nil
    isComplete = false
}
```

Passe die tatsächlichen vorhandenen Event- und Combo-Namen an. Erfinde kein zweites Format.

- [ ] **Step 4: Verwende denselben Reducer in Settings und Onboarding**

Entferne die auseinanderlaufende lokale Behandlung. „Übernehmen“ richtet sich nach `draft.isComplete` oder der bestehenden gültigen Modifier-only-Regel.

- [ ] **Step 5: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.HotkeyCaptureDraftTests'
git add Sources/Stasi/UI/HotkeyCaptureMonitor.swift \
  Sources/Stasi/UI/SettingsWindowView.swift \
  Sources/Stasi/UI/OnboardingView.swift \
  Tests/StasiTests/HotkeyCaptureDraftTests.swift
git commit -m "fix(hotkey): vollständigen Capture-Entwurf behalten

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Hotkey-Einstellung im `SettingsStore` zentralisieren

**Files:**
- Modify: `Sources/Stasi/Core/SettingsStore.swift`
- Modify: `Sources/Stasi/Core/AppState.swift:291-305,365-371`
- Modify: `Tests/StasiTests/SettingsAndHelpersTests.swift`
- Modify: `Tests/StasiTests/ShortcutDetectorTests.swift`

**Interfaces:**
- Produces:

```swift
var hotkeyCombo: HotkeyEngine.Combo
```

`AppState.currentCombo` delegiert nur noch an `settings.hotkeyCombo` oder entfällt.

- [ ] **Step 1: Schreibe Persistenztests mit isolierter UserDefaults-Suite**

```swift
@Test func hotkeyPersistsInInjectedSettingsStore() throws {
    let defaults = try isolatedDefaults()
    let first = SettingsStore(defaults: defaults)
    first.hotkeyCombo = testCombo

    let second = SettingsStore(defaults: defaults)
    #expect(second.hotkeyCombo == testCombo)
}

@Test func invalidStoredHotkeyFallsBackToDefault() throws {
    let defaults = try isolatedDefaults()
    defaults.set(Data("bad".utf8), forKey: "stasi.hotkey.combo")
    #expect(SettingsStore(defaults: defaults).hotkeyCombo == .defaultPTT)
}
```

- [ ] **Step 2: Schreibe einen AppState-Test gegen `UserDefaults.standard`-Bypass**

Nach `applyHotkey(testCombo)` muss der injizierte Store geändert sein. Eine separate Standard-Suite bleibt unverändert.

- [ ] **Step 3: Führe Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.SettingsAndHelpersTests'
```

- [ ] **Step 4: Implementiere `hotkeyCombo` im Store**

Verwende denselben Key wie bisher. Dekodiere einmal im Initializer. Persistiere im `didSet` oder in einer vorhandenen Store-Hilfsmethode.

- [ ] **Step 5: Entferne direkte `UserDefaults.standard`-Zugriffe aus `AppState`**

```swift
var currentCombo: HotkeyEngine.Combo { settings.hotkeyCombo }

func applyHotkey(_ combo: HotkeyEngine.Combo) {
    settings.hotkeyCombo = combo
    restartHotkey(with: combo)
}
```

- [ ] **Step 6: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.SettingsAndHelpersTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.ShortcutDetectorTests'
git add Sources/Stasi/Core/SettingsStore.swift \
  Sources/Stasi/Core/AppState.swift \
  Tests/StasiTests/SettingsAndHelpersTests.swift \
  Tests/StasiTests/ShortcutDetectorTests.swift
git commit -m "refactor(settings): Hotkey zentral persistieren

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Ziel-App als Session-Snapshot sichern

**Files:**
- Modify: `Sources/Stasi/Core/DictationSession.swift:15-45`
- Modify: `Sources/Stasi/Core/AppState.swift:413-426,654-745`
- Modify: `Sources/Stasi/Core/TextInjector.swift`
- Modify: `Sources/Stasi/Core/TranscriptionRecord.swift`
- Create: `Tests/StasiTests/TargetApplicationMatcherTests.swift`
- Modify: `Tests/StasiTests/DictationSessionTests.swift`

**Interfaces:**
- Produces:

```swift
struct TargetApplication: Equatable, Sendable {
    let localizedName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
}

enum TargetApplicationMatcher {
    static func matches(
        captured: TargetApplication,
        current: TargetApplication?
    ) -> Bool
}
```

`DictationSession` erhält:

```swift
let targetApplication: TargetApplication
```

`AppState` erhält injizierbar:

```swift
frontmostApplication: @escaping @MainActor () -> TargetApplication?
```

- [ ] **Step 1: Schreibe pure Matching-Tests**

```swift
@Test func sameBundleAndProcessMatches() {
    #expect(TargetApplicationMatcher.matches(captured: slack, current: slack))
}

@Test func sameBundleDifferentProcessDoesNotMatch() {
    let relaunched = TargetApplication(
        localizedName: slack.localizedName,
        bundleIdentifier: slack.bundleIdentifier,
        processIdentifier: slack.processIdentifier + 1
    )
    #expect(!TargetApplicationMatcher.matches(captured: slack, current: relaunched))
}

@Test func missingCurrentApplicationDoesNotMatch() {
    #expect(!TargetApplicationMatcher.matches(captured: slack, current: nil))
}
```

- [ ] **Step 2: Schreibe Sessiontests für Fokuswechsel**

Nach Aufnahmebeginn wechselt die Fake-Frontmost-App von Slack zu Notes. Prüfe:

```swift
#expect(textInjector.callCount == 0)
#expect(clipboard.string == finalText)
#expect(fakeHistory.records.first?.targetApp == "Slack")
#expect(appState.toast?.message.contains("Slack") == true)
```

Auch bei gleicher App muss ein nicht editierbares Element Injection verhindern.

- [ ] **Step 3: Führe Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.TargetApplicationMatcherTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
```

- [ ] **Step 4: Erfasse die Ziel-App beim Start**

Baue `TargetApplication` aus `NSWorkspace.shared.frontmostApplication` mit Name, Bundle-ID und PID. Speichere den Wert unveränderlich in `DictationSession`.

- [ ] **Step 5: Prüfe die Ziel-App direkt vor Injection**

```swift
let sameTarget = TargetApplicationMatcher.matches(
    captured: session.targetApplication,
    current: frontmostApplication()
)

if sameTarget && isFocusedElementEditable() {
    injectText(finalText)
} else {
    copyToClipboard(finalText)
    showTargetChangedNotice(for: session.targetApplication.localizedName)
}
```

History wird in beiden Fällen gespeichert. Bestehendes `targetApp` bleibt der lokalisierte Name. Neue Codable-Felder sind optional, falls Bundle-ID/PID gespeichert werden.

- [ ] **Step 6: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.TargetApplicationMatcherTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
git add Sources/Stasi/Core/DictationSession.swift \
  Sources/Stasi/Core/AppState.swift \
  Sources/Stasi/Core/TextInjector.swift \
  Sources/Stasi/Core/TranscriptionRecord.swift \
  Tests/StasiTests/TargetApplicationMatcherTests.swift \
  Tests/StasiTests/DictationSessionTests.swift
git commit -m "fix(injection): nur in ursprüngliche Ziel-App schreiben

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Aufnahmephase und Dauer an echten Audiostart binden

**Files:**
- Modify: `Sources/Stasi/Core/AppState.swift:402-513`
- Modify: `Sources/Stasi/Core/DictationSession.swift`
- Modify: `Tests/StasiTests/DictationSessionTests.swift`
- Modify: `Tests/StasiTests/PillChromeTests.swift`

**Interfaces:**
- Consumes: session-eigene Audio-Capture-Factory aus Plan 1.
- Produces: `recordStart` wird erst nach erfolgreichem `audio.start()` gesetzt.

- [ ] **Step 1: Schreibe Setup-Verzögerungs- und Startfehler-Tests**

```swift
@Test func recordingPhaseStartsOnlyAfterAudioStart() async {
    let gate = AsyncGate()
    speech.prepareGate = gate
    await appState.startDictation()

    #expect(appState.phase != .recording)
    #expect(appState.recordStart == nil)

    gate.open()
    await eventually { appState.phase == .recording }
    #expect(appState.recordStart != nil)
}

@Test func audioStartFailureNeverPublishesRecording() async {
    audio.startError = TestError.startFailed
    await appState.startDictation()
    #expect(appState.phase == .idle)
    #expect(appState.recordStart == nil)
}
```

Ergänze einen Test, der eine künstliche Setup-Verzögerung und zwei Sekunden echte Aufnahme verwendet. Der Record muss ungefähr zwei Sekunden enthalten, nicht Setup plus Aufnahme.

- [ ] **Step 2: Führe Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
```

- [ ] **Step 3: Verschiebe Status, Timer und Startzeit hinter `audio.start()`**

Reihenfolge:

```swift
session.state = .settingUp
try await preparePermissionsAndSpeech()
try session.audio.start(...)
session.state = .recording
recordStart = clock.now
elapsed = 0
phase = .recording
```

Die Kurztipp-Schwelle misst nur `clock.now - recordStart`.

- [ ] **Step 4: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.PillChromeTests'
git add Sources/Stasi/Core/AppState.swift \
  Sources/Stasi/Core/DictationSession.swift \
  Tests/StasiTests/DictationSessionTests.swift \
  Tests/StasiTests/PillChromeTests.swift
git commit -m "fix(session): Dauer an echten Audiostart binden

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: `SoundFeedback` einführen

**Files:**
- Create: `Sources/Stasi/Core/SoundFeedback.swift`
- Modify: `Sources/Stasi/Core/AppState.swift:390-398,535-603`
- Create: `Tests/StasiTests/SoundFeedbackTests.swift`
- Modify: `Tests/StasiTests/DictationSessionTests.swift`

**Interfaces:**
- Produces:

```swift
enum SoundEvent: Equatable, Sendable {
    case recordingStarted
    case recordingStopped
    case processingCompleted
    case failed
}

protocol SoundFeedback: Sendable {
    func play(_ event: SoundEvent)
}

struct SystemSoundFeedback: SoundFeedback {
    func play(_ event: SoundEvent)
}
```

`AppState.init` erhält:

```swift
soundFeedback: any SoundFeedback = SystemSoundFeedback()
```

- [ ] **Step 1: Schreibe eine Sound-Spy und Ereignistests**

```swift
final class SoundFeedbackSpy: SoundFeedback, @unchecked Sendable {
    private(set) var events: [SoundEvent] = []
    func play(_ event: SoundEvent) { events.append(event) }
}
```

Testfälle:

```swift
#expect(spy.events == [.recordingStarted, .recordingStopped, .processingCompleted])
#expect(audio.events.firstIndex(of: .stop)! < spy.eventsTimeline.firstIndex(of: .recordingStopped)!)
```

Zusätzlich:

- Setup-Fehler: nur `.failed`.
- Runtimefehler nach Start: `.recordingStarted`, `.failed`.
- Kurztipp/Verwerfen: `.recordingStarted`, `.recordingStopped`, kein `.processingCompleted`.
- `settings.soundOn == false`: keine Events.

- [ ] **Step 2: Führe Sound- und Sessiontests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.SoundFeedbackTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
```

- [ ] **Step 3: Implementiere `SystemSoundFeedback`**

Mappe zunächst die bestehenden Sounds. Lade keine neuen Dateien in dieser Runde.

```swift
func play(_ event: SoundEvent) {
    let name: NSSound.Name?
    switch event {
    case .recordingStarted: name = /* bisheriger Startsound */
    case .recordingStopped: name = /* bisheriger Stopsound */
    case .processingCompleted: name = nil
    case .failed: name = nil
    }
    if let name { NSSound(named: name)?.play() }
}
```

Verwende die tatsächlichen bisherigen Namen aus `AppState`.

- [ ] **Step 4: Ersetze direkte `NSSound`-Aufrufe**

```swift
private func playSound(_ event: SoundEvent) {
    guard settings.soundOn else { return }
    soundFeedback.play(event)
}
```

- [ ] **Step 5: Erzwinge die sichere Reihenfolge**

Erfolgsablauf:

```swift
try session.audio.start(...)
playSound(.recordingStarted)

let wavURL = session.audio.stop()
playSound(.recordingStopped)
await drainSpeechFeed()
await session.speech.finish()
try history.insert(record)
playSound(.processingCompleted)
```

Fehlerpfade senden genau einmal `.failed`. `.recordingStopped` kommt erst nach `audio.stop()`.

- [ ] **Step 6: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.SoundFeedbackTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.DictationSessionTests'
git add Sources/Stasi/Core/SoundFeedback.swift \
  Sources/Stasi/Core/AppState.swift \
  Tests/StasiTests/SoundFeedbackTests.swift \
  Tests/StasiTests/DictationSessionTests.swift
git commit -m "refactor(sound): Aufnahmefeedback testbar kapseln

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Dauerformatierung zentral korrigieren

**Files:**
- Modify: `Sources/Stasi/Core/TranscriptionRecord.swift`
- Modify: `Sources/Stasi/Core/ProtocolSearch.swift:122-125`
- Modify: `Sources/Stasi/UI/ProtocolsView.swift:334-336`
- Modify: `Sources/Stasi/UI/OnboardingView.swift:315-317`
- Modify: `Sources/Stasi/UI/RecordingPill.swift:353`
- Modify: `Tests/StasiTests/SettingsAndHelpersTests.swift`
- Modify: `Tests/StasiTests/ProtocolSearchTests.swift`

**Interfaces:**
- Produces:

```swift
enum DurationFormatter {
    static func minutesAndSeconds(_ interval: TimeInterval) -> String
}
```

- [ ] **Step 1: Schreibe Grenzwerttests**

```swift
@Test(arguments: [
    (0.0, "0:00"),
    (59.4, "0:59"),
    (59.6, "1:00"),
    (60.0, "1:00"),
    (119.6, "2:00"),
    (-1.0, "0:00")
])
func formatsRoundedDuration(input: TimeInterval, expected: String) {
    #expect(DurationFormatter.minutesAndSeconds(input) == expected)
}
```

- [ ] **Step 2: Führe Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.SettingsAndHelpersTests'
```

- [ ] **Step 3: Implementiere einmaliges Runden vor Minutenberechnung**

```swift
static func minutesAndSeconds(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}
```

- [ ] **Step 4: Ersetze alle manuellen Varianten**

Alle aufgeführten Stellen rufen nur noch `DurationFormatter.minutesAndSeconds(...)` auf.

- [ ] **Step 5: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.SettingsAndHelpersTests'
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.ProtocolSearchTests'
git add Sources/Stasi/Core/TranscriptionRecord.swift \
  Sources/Stasi/Core/ProtocolSearch.swift \
  Sources/Stasi/UI/ProtocolsView.swift \
  Sources/Stasi/UI/OnboardingView.swift \
  Sources/Stasi/UI/RecordingPill.swift \
  Tests/StasiTests/SettingsAndHelpersTests.swift \
  Tests/StasiTests/ProtocolSearchTests.swift
git commit -m "fix(copy): Diktatdauer konsistent runden

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Kleine UI-Duplikate entfernen

**Files:**
- Modify: `Sources/Stasi/UI/DashboardView.swift:576-626`
- Modify: `Sources/Stasi/UI/Effects.swift`
- Modify: `Sources/Stasi/UI/Theme.swift:269-321`
- Modify: `Tests/StasiTests/ThemeV3Tests.swift`

**Interfaces:**
- Consumes: vorhandenes `.pulseForever(intensity:)` und `CardStyle`.
- Produces: keine neue öffentliche API.

- [ ] **Step 1: Ergänze Strukturtests**

Prüfe mit bestehenden Theme-Testmustern:

- `PermissionWarningCard` verwendet den gemeinsamen Reduce-Motion-Helfer.
- `secondaryCard` rendert weiterhin dieselben Tokens wie vorher.

- [ ] **Step 2: Führe Theme-Tests aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.ThemeV3Tests'
```

- [ ] **Step 3: Entferne lokalen Pulszustand**

`PermissionWarningCard` verwendet `.pulseForever(intensity:)`. Bei Reduce Motion bleibt kein `pulseOn`-Zustand hängen.

- [ ] **Step 4: Delegiere `SecondaryCardStyle` an `CardStyle`**

Behalte die öffentliche `secondaryCard`-View-Erweiterung. Entferne nur die identische zweite Implementierung.

- [ ] **Step 5: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.ThemeV3Tests'
git add Sources/Stasi/UI/DashboardView.swift \
  Sources/Stasi/UI/Effects.swift \
  Sources/Stasi/UI/Theme.swift \
  Tests/StasiTests/ThemeV3Tests.swift
git commit -m "refactor(ui): Animation und Kartenstil wiederverwenden

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Hotkey-, Ziel-App- und Sound-Gesamtprüfung

**Files:**
- Verify only.

- [ ] **Step 1: Führe die vollständige Testsuite aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

Expected: Alle Tests PASS.

- [ ] **Step 2: Baue Debug und Release**

```bash
swift build
swift build -c release
```

Expected: Erfolgreich.

- [ ] **Step 3: Prüfe direkte Sound- und Hotkey-Persistenz-Bypässe**

```bash
git grep -n 'NSSound' Sources/Stasi/Core/AppState.swift
git grep -n 'UserDefaults.standard' Sources/Stasi/Core/AppState.swift
```

Expected: keine Treffer.

- [ ] **Step 4: Prüfe Diff und Arbeitsbaum**

```bash
git diff --check
git status --short
```

Expected: keine unbeabsichtigten Änderungen.
