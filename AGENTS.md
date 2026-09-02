# STASI – Projekt-Gedächtnis (Session-Übergreifend)

> Dieses File ist das Memory für Coding-Sessions. Es wird bei jedem Session-Start
> gelesen und enthält ALLES Wichtige: Stand, Architektur, harte Lektionen, Regeln.

## Kommunikation und Entwicklungsumgebung

- **Immer auf Deutsch** mit dem Nutzer schreiben und erklären.
- Repository-Anforderungen: macOS 26 sowie eine Toolchain mit Unterstützung für
  Swift Tools 6.2 (siehe `Package.swift`).

## Was ist Stasi?

Push-to-Talk-Diktat-App im Stil von **Wispr Flow**: globale Taste halten → sprechen →
loslassen → korrigierter Text wird per synthetischen Keyboard-Events in die fokussierte
App getippt. Komplett **on-device** via macOS-26-`SpeechTranscriber` (EN/DE).

- **Echte Mac-App** (Dock-Icon, App-Menü, ⌘,-Settings im Fenster) – bewusst KEIN
  Menu-bar-Utility, aber MIT sekundärem NSStatusItem-Menü.
- Name „Stasi" mit dezenter Ironie in der Copy („Wir hören zu.") – abschaltbar.
- Design: **v3-Handoff** (maßgeblich: `import/design_handoff_v3/DESIGN.md` +
  `preview.html`) – Sidebar-Layout (einklappbar 200↔64 px), Fonts **Geist + Geist Mono**
  (gebündelt), KEIN Dark Mode, **Akzent dynamisch: 5 Presets** (Anthrazit `#1A1917` *
  Standard, Blau, Orange, Grün, Violett), auswählbar in Einstellungen → DARSTELLUNG.
  Tokens: Verlauf-Hintergrund `#F3F6FA → #F8F7F3` (160°), weiße Karten `surface`
  Radius 16 ohne Border + **Akzent-Schatten `0 2px 8px`** (12 %), Controls r9 / Inputs
  r12 / Pill 999. Sekundärtext `sub #6F6C66` erfüllt ≥ 4,5:1 auf Weiß. Statusfarben
  fest: rec `#FF453A`, destructive `#C8102E`, success `#30A46C`; kleiner grüner Text
  nutzt `successText #1F7A4D`. Ironie-Copy standardmäßig AUS. Design-Tokens zentral in
  `Sources/Stasi/UI/Theme.swift` (Hex-Enum = Test-Vertrag in ThemeV3Tests); die
  v4-Aliasnamen (papier/stempelrot/linie/…) bleiben als Kompatibilitäts-Shim erhalten.
  Weitere Änderungen über den Handoff-Prozess.

> **Hinweis:** Das v4-„Registratur"-Design (Archivo, Stempelrot fest, Kopfkante-Karten)
> wurde verworfen und der v3-Look (Geist, Verlauf, 5 Akzent-Presets) wiederhergestellt –
> bei BEIBEHALT aller Funktionen aus dem V4-Umbau (Suche, Onboarding, Insights-V4,
> Mikrofon-Auswahl, Update-Prüfung, Retention). `import/design_handoff_v4/` ist gelöscht.
>
> **UI-Polish (25.08.):** App-Shell-Kopfzeile mit Avatar rechts oben (KEIN Overlay mehr –
> kollidierte mit Filter-Chips), Mindestfenster 960×620 (`windowResizability(.contentMinSize)`),
> Bericht/Insights/Protokolle auf ~1080 px zentriert gedeckelt, Buttons einheitlich
> Controls-r9 (keine Capsule-Mixe), „Jetzt ausprobieren" startet echte Probaufnahme,
> Status-Chip-Puls aktiv, Wörterbuch-Index mit 16 px Leading-Padding.
>
> **Aufnahme-Polish (26.08.):** Die 24-px-Pill bleibt unverändert hoch; ihre 14
> Pegelbalken wachsen symmetrisch von der Mittellinie über 4–20 px, nutzen
> 150 ms Peak-Hold und 35–100 % Weiß-Deckkraft. Push-to-talk wird erst ab
> 250 ms eingeblendet; kürzere Tipps werden ohne Pill, Status, Toast oder
> Protokoll still verworfen. Hands-free erscheint sofort. Nach dem Loslassen
> ersetzt ein textloser 36×36-px-AppKit-Spinner die früheren Phasentexte, aber
> erst nach `PillChrome.spinnerDelay` (200 ms über alle Verarbeitungsphasen).
> Bei Reduce Motion steht stattdessen ein ruhiger weißer Punkt. Erfolgs- und
> Verwerfen-Toasts sind entfernt; Fehler- und Warn-Toasts bleiben erhalten.

## Aktueller Stand (Stand: 28.08.2026 – öffentliches Repo, Release vorbereitet)

**Release-Status:** Repository ist ÖFFENTLICH (github.com/mm20261/stasi) mit
bereinigter Historie (nur Philipp Meder / Noreply-Adresse, objektgenau verifiziert,
siehe `docs/history-rewrite.md` und `docs/release.md`). `main` ist gegen Force-Push
und Löschung geschützt; Release-Environment `release` mit Required Reviewer und
Deploymentquellen `main` + `v*` steht. **Offen bis v0.10.0:** sechs Environment-Secrets
(interaktiv), Tag-Push → signierter/notarisierter Workflow → Release-Assets prüfen,
danach Homebrew-Tap `mm20261/homebrew-tap`. Transkript-Neustartbereinigung und
Tag-/Verify-/Publish-Workflow (fail-closed) sind umgesetzt; vollständige Suite grün
(siehe CI-Log).

**Umgesetzte Audit-Blöcke:** 1A Session-Lifecycle · 1B Tap/WAV/Watcher ·
1C kleine Korrektheitsfixes · 2 UX/Feedback/A11y · 3A regelbasierte
Nachbearbeitung · 3B Auto-gelernt.

**Funktioniert end-to-end:** Hotkey (rechte ⌘ halten) → Aufnahme → on-device-Transkription
(EN/DE) → deterministische Nachbearbeitung STANDARD (Zögerlaute, Stotterer, konservative
Selbstkorrekturen, Diskurs-Füller, Text-Hygiene) → Dictionary-Korrektur → Injection in fokussierte App → Protokoll-
Historie (persistiert, Play/Export .txt/.md/Audio .wav/Löschen). UI im
v3-Look (Geist, Verlauf-Hintergrund, 5 Akzent-Presets, weiße Karten r16 + Akzent-Schatten):
Sidebar mit Icons/Akzent-Aktivzeile + Tooltips eingeklappt, „Der Bericht" (Suchfeld-Topbar,
Datumszeile, Anleitungsleiste mit Status-Chip „Bereit"/„Hotkey inaktiv", Hero
„Zuletzt diktiert" mit Kopieren/Anhören, „Früher heute"-Einzeiler, Rail mit Leitzahl +
Deine-Akte), eigener **Insights**-Screen (KW-Leitzahl-Karte, App-Balken in Akzent-Stufen,
Streak-Heatmap mit Stempel-Badge), **Protokolle** gruppiert nach Tag mit
Aktenzeichen/WPM/Korrektur-/Poliert-Badges und einsehbarem Rohtext, Aufnahme-Pill auf
**Akzent-Basis** (✕/✓ in beiden Aufnahmemodi), zweizeiligem Live-Transkript und
sichtbarer Modell-Vorbereitung;
ein textloser **36×36-px-AppKit-Spinner** zeigt verzögert die Verarbeitung; unter
Reduce Motion bleibt er als ruhiger Punkt stehen. **Toasts 36 px** erscheinen nur
noch für Fehler und Warnungen, **Onboarding 4 Schritte** bei erstem Start + Leerzustand erster Start
im Bericht. Die Menüleiste verwendet pro Phase ein explizit gecachtes Symbol.
Nach jedem Diktat landet der korrigierte Text **automatisch in der Zwischenablage**
(⌘V zum Einfügen – wie bei Wispr). **Hands-free per frei wählbarem Modifier-Doppeltipp**
(fn, linkes/rechtes ⌘/⌥/⌃/⇧; persistierbar an/aus) sowie
**⌃⌘C/⌃⌘V** für letztes Protokoll kopieren/einfügen laufen über den EINEN Session-Tap
via `ShortcutDetector`. **Push-to-talk-Shortcut frei belegbar**
(Modifier + Taste, Recorder-Feld inline mit Vorschau + Übernehmen).
**Aus dem V4-Umbau beibehalten:** ⌘F-Suche über alle Protokolle (Trefferzähler, Filter
ALLE/7T/30T, „Export aller Protokolle" als .md; ⌘F wechselt global dorthin und fokussiert
das Suchfeld), Update-Prüfung in ÜBER (GitHub-Releases-API, numerischer Versionsvergleich,
Statuszeile und Release-URL, persistiert), Mikrofon-Auswahl per Popover
(Transport-UID persistiert, wird pro Engine via kAudioOutputUnitProperty_CurrentDevice
gesetzt – Systemstandard bleibt unangetastet).
**Speicher-Sektion**: Aufbewahrungsdauer als Segmented mit ausgeschriebenen Labels +
„Alles löschen" (Retention purged beim Start, bei Änderung und ~60s-Poll).
Das Mikrofon-Popover zeigt den echten Systemstandard-Gerätenamen und den Auswahlstatus;
der frühere kosmetische Fake-Pegel ist entfernt.
Nach jedem neuen Protokoll schlägt **Auto-gelernt** wiederholt diktierte, unbekannte
Begriffe vor (DE konservativ über Großschreibung mitten im Satz, EN zusätzlich über
unbekannte Wörter). Vorschläge lassen sich übernehmen oder dauerhaft ignorieren.

**Test-Suite:** Vor Commits muss die vollständige Suite unter `Tests/StasiTests/`
laufen; Pipeline-E2E-Tests bleiben ohne TCC-Consent gegatet.
TDD etabliert – bei Änderungen an Logik: erst Test, dann Fix.

### Bekannte Grenzen / offene Punkte
- Regelbasierte Nachbearbeitung AUS/STANDARD ist aktiv; ein optionaler Modell-Feinschliff
  ist nicht Bestandteil des aktuellen Builds.
- Sprache „Automatisch" = Systemsprache (SpeechTranscriber kann nicht pro Äußerung erkennen)
- Eingabe-Überwachung entfällt als aktive Berechtigung; `ListenEvent` bleibt ausschließlich
  diagnostisch erfasst und ist kein UI-Blocker.

## Architektur

```
Sources/Stasi/
├── MainApp.swift              StasiApp (WindowGroup + globale ⌘F-Commands), AppDelegate
│                             (Poll-Timer 20Hz UI / ≤1Hz Permissions + Stall-Watchdog),
│                             StatusBarController (NSStatusItem+NSMenu, Phasen-Icons gecacht –
│                             bewusst KEIN MenuBarExtra!)
├── Core/
│   ├── AppState.swift         @MainActor @Observable State-Machine idle→recording→transcribing
│   │                          →polishing→injecting; Session-Snapshots vor Nachbearbeitung,
│   │                          Modellbereitschaft pro Locale, Hotkey-Modi
│   │                          (PTT/Umschalten), Sounds, WAV-Mitschrieb, aktive Zusatz-Shortcuts
│   │                          (copyLast/insertLast/handsFree), PTT-Kurztipp <250 ms still,
│   │                          Aufnahmedauer aus dem bestehenden 20-Hz-Poll, Spellchecker-Cache,
│   │                          Auto-gelernt-Zusammenführung, applyRetention
│   ├── DictationSession.swift @MainActor Besitzer einer Diktat-Session: unveränderliche Snapshots,
│   │                          Setup/Feed/Consume-Tasks und idempotentes Teardown
│   ├── SettingsStore.swift    @Observable mit GESPEICHERTEN Properties + didSet-UserDefaults;
│   │                          Retention-Enum (Nie/1Tag/1Woche/2Wochen/1Monat),
│   │                          Akzent-Presets (accentHex, Theme.sharedSettings), handsFreeOn +
│   │                          handsFreeKeyCode (Default fn, nur Modifier),
│   │                          postProcessing (AUS/STANDARD, Default STANDARD);
│   │                          kein Appearance-Setting (App bleibt bewusst Light-only)
│   ├── AudioCapture.swift     AVAudioEngine-Tap; Render-Thread NUR: lock-geschützter RMS +
│   │                          thread-safe yield; WAV auf serialer writeQueue
│   ├── TranscriptionEngine.swift  SpeechAnalyzer/SpeechTranscriber, Biasing via
│   │                          AnalysisContext.contextualStrings[.general]; LIFECYCLE: NIE den
│   │                          Ergebnis-Strom canceln (Speech-Worker trapt!), Analyzer "ruht
│   │                          aus" in retiredAnalyzers; Session-Guard gegen Cross-Write;
│   │                          statische Fassade zur Sprachmodell-Vorbereitung
│   ├── CorrectionEngine.swift Garantierter Korrektur-Pass (siehe Regeln!)
│   ├── PolishLocale.swift     Reine, strikt getrennte DE-/EN-Regellisten
│   ├── TextTidy.swift         Reine Whitespace-/Satzzeichen-/Großschreibungs-Hygiene
│   ├── FillerFilter.swift     Reine Zögerlaut-, Stotter- und Diskursfüller-Pässe
│   ├── SelfCorrectionResolver.swift  Konservative Rahmenregel + starker Klassen-Fallback
│   ├── TranscriptPolisher.swift  Orchestriert STANDARD-Pässe und Summary; AUS = alter Korrekturpfad
│   ├── AutoLearnScout.swift  Reine DE-/EN-Kandidatenheuristik mit Protokollzählung
│   ├── DictionaryModel.swift  EntryType word/correction/learned + CommonWords-Warnungen
│   ├── DictionaryStore.swift  dictionary.json inkl. Auto-gelernt-Ignorierliste + File-Watcher
│   ├── TranscriptionRecord.swift  Record-Modell inkl. optionaler PolishSummary + HistoryStore
│   │                          (alte history.json kompatibel, deleteAll/purge)
│   ├── HotkeyEngine.swift     CGEventTap listen-only (Session-Tap) + ShortcutDetector
│   │                          (⌃⌘V/⌃⌘C + konfigurierter Modifier-Doppeltipp, pur testbar)
│   ├── StatsCalculator.swift  Insights-/Rail-Statistik (WPM, Streaks, App-Nutzung, Zeit
│   │                          gespart, Wochen-Delta, Heatmap, Kompaktformat, KW-Kicker,
│   │                          Tipzeit-Schätzung)
│   ├── ProtocolSearch.swift   Volltextsuche + Filter (ALLE/7T/30T), Tagesgruppierung,
│   │                          FileNumber (Aktenzeichen), ProtocolExporter (alle .md)
│   ├── PillChrome.swift       RecordingSource + 250-ms-Aufnahme-/200-ms-Spinner-Schwelle +
│   │                          Live-Text/Modellstatus → Pill-Geometrie; MicLevelBars 4–20 px/Peak-Hold
│   ├── UpdateChecker.swift    Release-Fetch (GitHub-API) + numerischer Versionsvergleich
│   │                          + Statuszeile; persistiert Version, Prüfzeit und Release-URL
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
│                              Recorder-Feld, Akzent-Presets, Update-Zeile),
│                              HotkeyCaptureMonitor (ObjC-Main-Thread-Hop), AccountView
│                              (Kreis-Avatar/Signaturkarte), OnboardingView,
│                              RecordingPill.swift (pures AppKit: Aufnahme/symmetrische
│                              Waveform/Live-Text/textloser Spinner/Fehler-Toast), Effects.swift
└── Support/                   Permissions.swift (Mikrofon/AX; ListenEvent nur Diagnose),
                               DebugLog.swift (Rotation >2 MB nach debug.log.1), VirtualKey.swift

scripts/make-app.sh            → build/Stasi.app (stabil signiert, Icon aus Resources/AppIcon.png)
Tests/StasiTests/              → vollständige XCTest-Suite: AutoLearnScout/TextTidy/FillerFilter/
                                 SelfCorrectionResolver/TranscriptPolisher/DictationSession/
                                 HotkeyReenablePolicy/AudioCaptureFile/DictionaryWatcher/ThemeV3/
                                 CopyV3/ProtocolSearch/PillChrome/UpdateChecker + Bestand
```

## ⚠️ HART ERARBEITETE REGELN (macOS 26.6 / Swift 6.3 – NICHT verletzen!)

Diese Lektionen stammen aus 7 dokumentierten Crashes + Freezes. Jede davon war ein
echter, vom Nutzer reproduzierter Bug:

1. **KEIN `Task { @MainActor … }` aus GCD-Timern / Audio-Render-Thread / NSEvent-Monitoren.**
   Task-Churn aus Kontexten ohne Swift-Concurrency-Root korruptiert die Executor-Metadaten
   → `swift_task_isMainExecutor` crasht später ZUFÄLLIG in SwiftUI (Buttons, Forms, Timeline-
   Views). `MainActor.assumeIsolated` in RunLoop-Timern, NSEvent-Monitoren oder GCD-
   Callbacks ist **VERBOTEN**: Es führt denselben dynamischen
   `swift_task_isCurrentExecutor`-Check aus und segfaultete am 26.08.2026 im Leerlauf
   (`Stasi-2026-08-26-105541.ips`, `objc_opt_class` auf `0x1e` aus `AppDelegate.poll()`).
   Stattdessen ObjC-Target-Timer bzw. lock-geschützten Zustand + Main-Poll verwenden.
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
   Finalize- und Ergebnis-Task werden bei Timeout/Fehler in `retiredAnalyzers` stark bis
   zu ihrem natürlichen Ende gehalten und erst danach entfernt. Session-Identität schützt
   nach jedem `await` gegen Cross-Session-Writes.

6. **TCC-Preflights maximal ~1 Hz.** `AXIsProcessTrusted`, Mikrofonstatus und das nur noch
   diagnostische `CGPreflightListenEventAccess` dürfen nicht im 20-Hz-Poll laufen; das kann
   Systemdialoge einfrieren. Berechtigungsaktionen öffnen ausschließlich den passenden
   Apple-Dialog bzw. nach 1,5 s ohne Erfolg direkt das zugehörige Systemeinstellungen-Pane.

7. **Für den aktuellen Session-Tap ist Bedienungshilfen-Zugriff (AX) maßgeblich.**
   Eingabe-Überwachung (`ListenEvent`) wird nur noch diagnostisch erfasst und ist kein
   UI-Blocker. `CGEvent.tapIsEnabled` bleibt für Timeout-/Deaktivierungsdiagnose relevant.

8. **SettingsStore: nur gespeicherte `@Observable`-Properties** (computed-over-UserDefaults
   wird NICHT getrackt → Views aktualisieren nicht). Persistenz über `didSet`.
   `Theme.accent` liest über `Theme.sharedSettings` (weak) → Views tracken accentHex
   automatisch, KEIN `.id(epoch)`-Vollneubau (der crashte im Gesture-Graph!).

9. **Signatur-Wechsel macht TCC-Einträge ungültig.** Die stabile Dev-Signatur verhindert
   das bei normalen Builds; nach Fallback auf ad hoc oder Zertifikatswechsel Rechte neu
   erteilen. Reset-Befehle: `tccutil reset Accessibility app.stasi.macos` (bei Bedarf auch
   Microphone/ListenEvent).
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
    d) `AudioCapturing` (und jedes Protokoll im Audio-Render-Pfad) darf NIE
       `@MainActor` sein; Tap-Closures müssen `@Sendable`/nonisolated sein. Sonst baut
       Swift 6 einen `swift_task_isCurrentExecutor`-Check in den Realtime-Thread, der
       als `EXC_BREAKPOINT` in `dispatch_assert_queue` crasht (reproduziert am
       26.08.2026, Crash-Report `Stasi-2026-08-26-074353.ips`).
    e) Die `AVAudioEngine` wird pro Aufnahme erzeugt und nach `stop()` freigegeben.
       Eine dauerhaft gehaltene Engine hält das Eingabegerät belegt – bei Bluetooth-
       Headsets bleibt macOS dann im HFP-Telefonie-Profil (Ausgabe fällt auf 24 kHz,
       Ton klingt „unter Wasser“), reproduziert am 26.08.2026.

13. **Stabile Signatur:** `make-app.sh` signiert mit dem selbstsignierten
    Zertifikat "Stasi Dev Signing" (Login-Schlüsselbund) → TCC-Rechte überleben
    Rebuilds. Fallback ad hoc nur, wenn das Zertifikat fehlt. TCC-Einträge in
    Systemeinstellungen können nach Signatur-Wechsel als Karteileichen "an"
    zeigen, ohne zu gelten → `tccutil reset` + frisch über den App-Dialog erteilen.

14. **Debug-Log:** `DebugLog.log()` schreibt nach
    `~/Library/Application Support/Stasi/debug.log` (NSLog landet auf diesem System nicht
    zuverlässig im Unified Log). Über 2 MB wird die vorherige Datei nach `debug.log.1`
    rotiert. Erste Anlaufstelle bei Fehlersuche.

15. **StasiResources.bundle: NIEMALS `Bundle.module` als Fallback auswerten.**
    SwiftPMs generierter `Bundle.module`-Accessor bricht mit fatalError ab, wenn das
    Paket-Bundle `Stasi_Stasi.bundle` in der .app fehlt (kaputte/veraltete Kopie aus
    Downloads) → EXC_BREAKPOINT direkt beim Start in `FontLoader` (Crash vom
    01.09.2026). `StasiResources.resolve()` muss ohne Paket-Fund auf `Bundle.main`
    zurückfallen; Ressourcen fehlen dann, aber die App startet. In `make-app.sh`/
    Release-CI wird das Paket-Bundle zusätzlich explizit verifiziert.

## Tests

- **`swift test` kann an der Runner-Infra hängen** – zuverlässig:
  ```bash
  swift build --build-tests
  xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
  ```
- Vor Commits muss die vollständige Suite laufen. Pipeline-E2E-Tests benötigen
  TCC-Consent und bleiben ohne passenden App-Kontext gegatet. Bei Logik-Änderungen:
  erst Test schreiben/ändern, dann implementieren (TDD).
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

- Block 3C – optionaler Modell-Feinschliff (FoundationModels) mit Weißlisten-Gitter,
  bewusst verschoben: Apples On-Device-Modell invertierte im Test Selbstkorrekturen
  („nein" → „nicht") und ließ Satzteile weg; Plan-Abschnitt 3C in
  `~/.claude/plans/kannst-du-bitte-einmal-floating-chipmunk.md`.
- whisper.cpp-Fallback mit echtem Initial-Prompt-Biasing (BiasProvider-Hook existiert)
- Sprachwechsel pro Äußerung · Snippets
- Design-Feinschliff: historischer Handoff nur als Referenz unter `docs/archive/design_handoff_stasi/`; neue Änderungen direkt aus dem aktuellen App-Stand ableiten
