# STASI – Projekt-Gedächtnis (Session-Übergreifend)

> Dieses File ist das Memory für Coding-Sessions. Es wird bei jedem Session-Start
> gelesen und enthält ALLES Wichtige: Stand, Architektur, harte Lektionen, Regeln.

## Kommunikation

- **Immer auf Deutsch** mit dem Nutzer schreiben und erklären.
- Nutzer: Philipp, MacBook Pro M5 Pro (Mac17,8), 64 GB, macOS 26.6.2, Xcode 26.6 (Swift 6.3.3).

## Was ist Stasi?

Push-to-Talk-Diktat-App im Stil von **Wispr Flow**: globale Taste halten → sprechen →
loslassen → korrigierter Text wird per synthetischen Keyboard-Events in die fokussierte
App getippt. Komplett **on-device** via macOS-26-`SpeechTranscriber` (EN/DE).

- **Echte Mac-App** (Dock-Icon, App-Menü, ⌘,-Settings im Fenster) – bewusst KEIN
  Menu-bar-Utility, aber MIT sekundärem NSStatusItem-Menü.
- Name „Stasi" mit dezenter Ironie in der Copy („Wir hören zu.") – abschaltbar.
- Design: **v3-Handoff** (maßgeblich: `Import/design_handoff_v3/DESIGN.md` +
  `preview.html`) – Sidebar-Layout (einklappbar 200↔64 px), Fonts **Geist + Geist Mono**
  (gebündelt), KEIN Dark Mode, **Akzent dynamisch: 5 Presets** (Anthrazit `#1A1917` *
  Standard, Blau, Orange, Grün, Violett), auswählbar in Einstellungen → DARSTELLUNG.
  Tokens: Verlauf-Hintergrund `#F3F6FA → #F8F7F3` (160°), weiße Karten `surface`
  Radius 16 ohne Border + **Akzent-Schatten `0 2px 8px`** (12 %), Controls r9 / Inputs
  r12 / Pill 999. Statusfarben fest: rec `#FF453A`, destructive `#C8102E`,
  success `#30A46C`. Ironie-Copy standardmäßig AUS. Design-Tokens zentral in
  `Sources/Stasi/UI/Theme.swift` (Hex-Enum = Test-Vertrag in ThemeV3Tests); die
  v4-Aliasnamen (papier/stempelrot/linie/…) bleiben als Kompatibilitäts-Shim erhalten.
  Weitere Änderungen über den Handoff-Prozess.

> **Hinweis:** Das v4-„Registratur"-Design (Archivo, Stempelrot fest, Kopfkante-Karten)
> wurde verworfen und der v3-Look (Geist, Verlauf, 5 Akzent-Presets) wiederhergestellt –
> bei BEIBEHALT aller Funktionen aus dem V4-Umbau (Suche, Onboarding, Insights-V4,
> Mikrofon-Auswahl, Update-Prüfung, Retention). `Import/design_handoff_v4/` ist gelöscht.
>
> **UI-Polish (25.08.):** App-Shell-Kopfzeile mit Avatar rechts oben (KEIN Overlay mehr –
> kollidierte mit Filter-Chips), Mindestfenster 960×620 (`windowResizability(.contentMinSize)`),
> Bericht/Insights/Protokolle auf ~1080 px zentriert gedeckelt, Buttons einheitlich
> Controls-r9 (keine Capsule-Mixe), „Jetzt ausprobieren" startet echte Probaufnahme,
> Status-Chip-Puls aktiv, Wörterbuch-Index mit 16 px Leading-Padding.

## Aktueller Stand (Stand: 25.08.2026 – v3-Look mit V4-Features)

**Funktioniert end-to-end:** Hotkey (rechte ⌘ halten) → Aufnahme → on-device-Transkription
(EN/DE) → Dictionary-Biasing + Korrektur-Pass → Injection in fokussierte App → Protokoll-
Historie (persistiert, Play/Export .txt/.md/Audio .wav/Löschen). UI im
v3-Look (Geist, Verlauf-Hintergrund, 5 Akzent-Presets, weiße Karten r16 + Akzent-Schatten):
Sidebar mit Icons/Akzent-Aktivzeile + Tooltips eingeklappt, „Der Bericht" (Suchfeld-Topbar,
Datumszeile, Anleitungsleiste mit Status-Chip „Bereit"/„Hotkey inaktiv", Hero
„Zuletzt diktiert" mit Kopieren/Anhören, „Früher heute"-Einzeiler, Rail mit Leitzahl +
Deine-Akte), eigener **Insights**-Screen (KW-Leitzahl-Karte, App-Balken in Akzent-Stufen,
Streak-Heatmap mit Stempel-Badge), **Protokolle** gruppiert nach Tag mit
Aktenzeichen/WPM/Korrekturen-Badges, Aufnahme-Pill auf **Akzent-Basis** (✕/✓ nur bei PTT,
weg bei Hands-free), **Toasts 36 px** („Protokolliert ✓" Stil), **Onboarding 4 Schritte** bei
erstem Start + Leerzustand erster Start im Bericht.
Nach jedem Diktat landet der korrigierte Text **automatisch in der Zwischenablage**
(⌘V zum Einfügen – wie bei Wispr). **Fn-Doppeltipp** (Hands-free Toggle) über den
EINEN Session-Tap via `ShortcutDetector`. **Push-to-talk-Shortcut frei belegbar**
(Modifier + Taste, Recorder-Feld inline mit Vorschau + Übernehmen).
**Aus dem V4-Umbau beibehalten:** ⌘F-Suche über alle Protokolle (Trefferzähler, Filter
ALLE/7T/30T, „Export aller Protokolle" als .md), Update-Prüfung in ÜBER (GitHub-Releases-API,
numerischer Versionsvergleich, Statuszeile, persistiert), Mikrofon-Auswahl per Popover
(Transport-UID persistiert, wird pro Engine via kAudioOutputUnitProperty_CurrentDevice
gesetzt – Systemstandard bleibt unangetastet).
**Speicher-Sektion**: Aufbewahrungsdauer als Segmented (NIE/1T/1W/2W/1MONAT) +
„AKTE VERNICHTEN" (Retention purged beim Start, bei Änderung und ~60s-Poll).

**Test-Suite: 188 Tests, 0 Fehler** (`Tests/StasiTests/`; davon 4 Pipeline-E2E gated).
TDD etabliert – bei Änderungen an Logik: erst Test, dann Fix.

### Bekannte Platzhalter („Bald" im UI)
- „Auto-gelernt": UI + Store-Mechanik da (`EntryType.learned`, `promote`), aber automatische
  Begriffs-Erkennung beim Diktieren noch NICHT aktiv
- KI-Nachbearbeitung (Toggle stored, inaktiv)
- Sprache „Automatisch" = Systemsprache (SpeechTranscriber kann nicht pro Äußerung erkennen)
- Mic-Popover-Pegelbalken sind kosmetisch animiert (kein echter Live-Level)
- Onboarding-Schritt 3: Recorder zeigt Vorschau; Übernehmen setzt den Hotkey

## Architektur

```
Sources/Stasi/
├── MainApp.swift              StasiApp (WindowGroup + Commands), AppDelegate (Poll-Timer
│                             20Hz UI / 1Hz Permissions + Stall-Watchdog), StatusBarController
│                             (NSStatusItem+NSMenu – bewusst KEIN MenuBarExtra!)
├── Core/
│   ├── AppState.swift         @MainActor @Observable State-Machine idle→recording→transcribing
│   │                          →injecting; Hotkey-Modi (PTT/Umschalten), Sounds, WAV-Mitschrieb,
│   │                          Zusatz-Shortcuts (copyLast/insertLast/handsFree), applyRetention
│   ├── DictationSession.swift @MainActor Besitzer einer Diktat-Session: unveränderliche Snapshots,
│   │                          Setup/Feed/Consume-Tasks und idempotentes Teardown
│   ├── SettingsStore.swift    @Observable mit GESPEICHERTEN Properties + didSet-UserDefaults;
│   │                          Retention-Enum (Nie/1Tag/1Woche/2Wochen/1Monat),
│   │                          Akzent-Presets (accentHex, Theme.sharedSettings)
│   ├── AudioCapture.swift     AVAudioEngine-Tap; Render-Thread NUR: lock-geschützter RMS +
│   │                          thread-safe yield; WAV auf serialer writeQueue
│   ├── TranscriptionEngine.swift  SpeechAnalyzer/SpeechTranscriber, Biasing via
│   │                          AnalysisContext.contextualStrings[.general]; LIFECYCLE: NIE den
│   │                          Ergebnis-Strom canceln (Speech-Worker trapt!), Analyzer "ruht
│   │                          aus" in retiredAnalyzers; Session-Guard gegen Cross-Write
│   ├── CorrectionEngine.swift Garantierter Korrektur-Pass (siehe Regeln!)
│   ├── DictionaryModel.swift  EntryType word/correction/learned + CommonWords-Warnungen
│   ├── DictionaryStore.swift  ~/Library/Application Support/Stasi/dictionary.json + File-Watcher
│   ├── TranscriptionRecord.swift  Record-Modell + HistoryStore (history.json, deleteAll/purge)
│   ├── HotkeyEngine.swift     CGEventTap listen-only (Session-Tap) + ShortcutDetector
│   │                          (⌃⌘V/⌃⌘C-Chords + Fn-Doppeltipp, pur testbar)
│   ├── StatsCalculator.swift  Insights-/Rail-Statistik (WPM, Streaks, App-Nutzung, Zeit
│   │                          gespart, Wochen-Delta, Heatmap, Kompaktformat, KW-Kicker,
│   │                          Tipzeit-Schätzung)
│   ├── ProtocolSearch.swift   Volltextsuche + Filter (ALLE/7T/30T), Tagesgruppierung,
│   │                          FileNumber (Aktenzeichen), ProtocolExporter (alle .md)
│   ├── PillChrome.swift       RecordingSource (pushToTalk/handsFree) → ✕/✓-Sichtbarkeit
│   ├── UpdateChecker.swift    Release-Fetch (GitHub-API) + numerischer Versionsvergleich
│   │                          + Statuszeile; persistiert lastChecked/availableVersion
│   ├── MicrophoneSelection.swift  MicDevice/MicrophoneCatalog (reine Logik, getestet)
│   │                          + MicrophoneScanner (CoreAudio: scan/defaultUID/
│   │                          apply via kAudioOutputUnitProperty_CurrentDevice)
│   ├── OnboardingModel.swift  4-Schritte-State-Maschine (Willkommen→Befugnisse→Hotkey→Probe)
│   ├── BiasProvider.swift     Wörterbuch → kurze Kontextliste (max 12, kürzeste zuerst)
│   └── TextInjector.swift     CGEvents mit Unicode-Chunks (24er), Thread.sleep-Gating
├── UI/                        Theme.swift (v3-Tokens: Hex-Enum = Test-Vertrag, CardStyle
│                              r16 + Akzent-Schatten, KeyBadge, StatusChip, reduced-motion-
│                              Helfer, v4-Aliasse papier/stempelrot/linie/…), RootView
│                              (+ Onboarding-Overlay erster Start), Sidebar (Icons,
│                              Akzent-Aktivzeile, Tooltips eingeklappt), DashboardView
│                              (Hero/Rail), ProtocolsView (Suche/AZ/Tagesgruppen),
│                              InsightsView (Leitzahl/Akzent-Stufen/Stempel), DictionaryView
│                              (Segmented-Tabs), SettingsWindowView (Mic-Popover,
│                              Recorder-Feld, Akzent-Presets, Update-Zeile), AccountView
│                              (Kreis-Avatar/Signaturkarte), OnboardingView,
│                              RecordingPill.swift (AppKit!, Akzent-Pill), Effects.swift
└── Support/                   Permissions.swift (Mikrofon/AX/ListenEvent!), VirtualKey.swift

scripts/make-app.sh            → build/Stasi.app (stabil signiert, Icon aus Import/…/icons/anthrazit)
scripts/gen_icon.swift         → Fallback-Icon-Generator
Tests/StasiTests/              → 188 Tests (XCTest): DictationSession/HotkeyReenablePolicy/
                                 AudioCaptureFile/DictionaryWatcher/ThemeV3/CopyV3/
                                 ProtocolSearch/PillChrome/UpdateChecker + Bestand
```

## ⚠️ HART ERARBEITETE REGELN (macOS 26.6 / Swift 6.3 – NICHT verletzen!)

Diese Lektionen stammen aus 6 dokumentierten Crashes + Freezes. Jede davon war ein
echter, vom Nutzer reproduzierter Bug:

1. **KEIN `Task { @MainActor … }` aus GCD-Timern / Audio-Render-Thread / NSEvent-Monitoren.**
   Task-Churn aus Kontexten ohne Swift-Concurrency-Root korruptiert die Executor-Metadaten
   → `swift_task_isMainExecutor` crasht später ZUFÄLLIG in SwiftUI (Buttons, Forms, Timeline-
   Views). Timer-Blöcke auf dem Main-RunLoop erben MainActor statisch → direkt aufrufen.
   Level aus dem Render-Thread: nur lock-geschützter Wert schreiben, Main-Poll liest ihn.

2. **KEIN SwiftUI in manuell verwalteten NSPanels** (borderless/nonactivating).
   Button-Gesture-Crash + EnvironmentBox-Crash. Die Aufnahme-Pill und Toasts sind
   deshalb **pure AppKit**. AppKit-Button-Aktionen: `@objc nonisolated` +
   `Task { @MainActor in … }`-Hop (Thunk darf keinen Executor-Check machen).

3. **KEIN `MenuBarExtra` mit `@Environment`-Zugriff** – crasht (rendert teils außerhalb
   des Main-Actors). Statusleiste ist klassisches NSStatusItem + NSMenu. Icons werden
   **gecacht** – 20×/s `NSImage(contentsOf:)` aus dem Poll riss den Main-Thread runter
   (= „Fenster tot, Klicks versacken"-Freeze ohne Crash-Report).

4. **CorrectionEngine: ALLE Matches einmal sammeln, von hinten ersetzen.**
   Eine While-Schleife mit erneutem Suchen läuft ENDLOS, wenn die Ersetzung selbst
   wieder matcht (case-insensitive: „grüße"→„Grüße", „anthropic"→„Anthropic").
   Das war der große „Loslassen tut nichts / Fenster friert ein"-Bug.
   Regex-Trenner zwischen Wortteilen: `[ \t\-\u2011]{0,2}` – die 0 ist Pflicht
   (zusammengeklebte Formen „CloudCode").

5. **Speech-Lifecycle: Ergebnis-Strom NIEMALS canceln.** Apples `SpeechRecognizerWorker`
   trapt (EXC_BREAKPOINT in `preRunRecognition`), wenn er in einen abgebrochenen Stream
   liefert. `finalizeAndFinishThroughEndOfInput` läuft in einem unstrukturierten Task aus
   dem `TranscriptionEngine`-actor; eine First-wins-`CheckedContinuation` liefert nach
   3 s den letzten Text-Stand zurück, ohne den Finalize-Task zu canceln (KEINE TaskGroup –
   deren Scope würde auf ein nicht-kooperatives Kind warten). Analyzer, Transcriber,
   Finalize- und Ergebnis-Task werden bei Timeout/Fehler in `retiredAnalyzers` stark bis
   zu ihrem natürlichen Ende gehalten und erst danach entfernt. Session-Identität schützt
   nach jedem `await` gegen Cross-Session-Writes.

6. **TCC-Preflights maximal ~1 Hz.** `AXIsProcessTrusted`/`CGPreflightListenEventAccess`
   20×/s können die System-Dialoge einfrieren („Eingabe-erteilen-Fenster frozen").
   Permission-Buttons lösen NUR die Apple-Dialoge aus (`CGRequestListenEventAccess` /
   `AXIsProcessTrustedWithOptions`); als Fallback bei früher abgewiesenem Dialog öffnet
   nach 1,5 s ohne Erfolg das passende Pane direkt (Eingabe-Überwachung ≠ Bedienungshilfen!).

7. **Zwei getrennte TCC-Berechtigungen nötig:** Bedienungshilfen (AX) UND **Eingabe-
   Überwachung** (ListenEvent) – ohne Letztere wird der CGEventTap angelegt, liefert
   aber NULL Events (Symptom: „Druck startet Aufnahme nicht"). `CGEvent.tapIsEnabled`
   prüfen und re-enablen (macOS deaktiviert Taps bei Timeout) + NSEvent-Fallback-Monitor.

8. **SettingsStore: nur gespeicherte `@Observable`-Properties** (computed-over-UserDefaults
   wird NICHT getrackt → Views aktualisieren nicht). Persistenz über `didSet`.
   `Theme.accent` liest über `Theme.sharedSettings` (weak) → Views tracken accentHex
   automatisch, KEIN `.id(epoch)`-Vollneubau (der crashte im Gesture-Graph!).

9. **Rebuild = neue ad-hoc-Signatur = TCC-Einträge ungültig.** Nach jedem `make-app.sh`
   müssen Eingabe-Überwachung/Bedienungshilfen neu erteilt werden. Reset-Befehle:
   `tccutil reset ListenEvent app.stasi.macos` (auch: Accessibility, Microphone).
   Bei eingefrorenen TCC-Dialogen: `killall "System Settings" UserNotificationCenter`.

10. **SpeechTranscriber headless (xctest) ohne TCC-Consent: `preRunRecognition` trapt.**
    Pipeline-E2E-Tests sind deshalb gated: `STASI_PIPELINE_E2E=1` in App-Kontext.

11. **CGEventTap NIEMALS ohne Bedienungshilfen-Recht installieren oder re-enablen.**
    macOS deaktiviert den unberechtigten Tap; wird er trotzdem wiederholt per
    `CGEvent.tapEnable` eingeschaltet, entzieht der WindowServer dem Prozess ALLE
    Maus-Events (Klick-Blackhole ohne Crash). Der Session-Tap läuft als
    `.cgSessionEventTap` + `.defaultTap` und braucht NUR Bedienungshilfen – Eingabe-
    Überwachung entfällt. `tapDisabledByTimeout/ByUserInput` setzt im Callback
    ausschließlich Flag + Log und re-armt NIEMALS. Nur der AX-gegatete ~1-Hz-Poll
    ruft `ensureEnabled()` auf; die reine Policy erlaubt maximal 3 Reaktivierungen.
    Danach setzt sie `gaveUp`, invalidiert/stoppt den Tap und meldet über
    `onTapStopped` „Neustart nötig". `hotkeyReady` folgt dem echten Engine-Zustand.

12. **Audio/Speech-Pipeline. Drei Gesetze:**
    a) `TranscriptionEngine` ist ein **eigener actor**, NIEMALS @MainActor – die
       Speech-Maschinerie auf dem MainActor korrumpierte dessen Executor
       ("Arbeit verschwindet": Command-Loop tot, Runloop lebt, kein Crash).
    b) Tap-Puffer werden IMMER kopiert/konvertiert bevor sie die Capture
       verlassen – AVAudioEngine recycelt den Puffer nach Callback-Rückkehr
       (Weiterreichen = Heap-Korruption, Quelle der Executor-Crashes).
    c) Aufnahme im NATIVEN Format (48 kHz Float32), Konvertierung via
       AVAudioConverter ins `preferredInputFormat` der Engine (16 kHz Int16).
       SpeechAnalyzer mit Float32 füttern ist eine harte Precondition → Prozess-Kill.
    Verdrahtung: Audio-Thread yieldet in EINEN AsyncStream, EIN Drain-Task
    füttert die Engine (Reihenfolge garantiert; nie Task pro Puffer).
    Mikrofon-Recht wird VOR AVAudioEngine-Start per `await requestMicrophone()`
    geklärt – die synchrone TCC-Abfrage im HAL-Start hängt sonst den Main-Thread.

13. **Stabile Signatur:** `make-app.sh` signiert mit dem selbstsignierten
    Zertifikat "Stasi Dev Signing" (Login-Schlüsselbund) → TCC-Rechte überleben
    Rebuilds. Fallback ad hoc nur, wenn das Zertifikat fehlt. TCC-Einträge in
    Systemeinstellungen können nach Signatur-Wechsel als Karteileichen "an"
    zeigen, ohne zu gelten → `tccutil reset` + frisch über den App-Dialog erteilen.

14. **Debug-Log:** `DebugLog.log()` schreibt nach
    `~/Library/Application Support/Stasi/debug.log` (NSLog landet auf diesem
    System nicht zuverlässig im Unified Log). Erste Anlaufstelle bei Fehlersuche.

## Tests

- **`swift test` kann an der Runner-Infra hängen** – zuverlässig:
  `swift build --build-tests && xcrun xctest .build/arm64-apple-macosx/debug/StasiPackageTests.xctest`
- Suite: CorrectionEngine (14), Stores (12), Settings/Copy/Keys/Level (28), Pipeline (4 aktiv
  + 4 gated), DictationSession (13), HotkeyReenablePolicy (8), AudioCaptureFile (4),
  DictionaryWatcher (2), StatsCalculator (+V4, 22), ShortcutDetector (10), ThemeV3 (7), CopyV3 (13),
  ProtocolSearch (10), PillChrome (4), UpdateChecker (8), MicrophoneCatalog (6),
  Onboarding (6). Bei Logik-Änderungen: erst Test schreiben/ändern, dann implementieren
  (TDD).
- Diagnose-Logs laufen mit: `STASI-HK PRESS/RELEASE`, `STASI-PILL ✓/✕`, `STASI-APP …`,
  `STASI-WATCH` (Main-Thread-Stalls >1 s). Lesen:
  `log show --last 30m --predicate 'eventMessage CONTAINS "STASI"' --style compact`

## Build & Run

```bash
./scripts/make-app.sh && open build/Stasi.app   # bauen + starten
swift build                                      # nur kompilieren
open Package.swift                               # in Xcode öffnen
```

Nach Rebuild: TCC neu erteilen (App zeigt Status im Bericht + Einstellungen).

## Offene Ideen / Roadmap

- Auto-gelernt aktivieren (Begriffe aus Transkripten vorschlagen)
- whisper.cpp-Fallback mit echtem Initial-Prompt-Biasing (BiasProvider-Hook existiert)
- Sprachwechsel pro Äußerung · Snippets · KI-Nachbearbeitung (Toggle vorhanden)
- Hands-free (Fn-Doppeltipp) neu belegbar machen (aktuell fest verdrahtet)
- Design-Feinschliff: weitere Änderungen über den `Import/design_handoff_stasi/`-Prozess
