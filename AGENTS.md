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
- Design: „Cloud Design"-Handoff (Nutzer hat es extern gestaltet) in `Import/design_handoff_stasi/`
  – Sidebar-Layout, Geist/Geist-Mono-Fonts (gebündelt), Light/Dark, 8 wählbare Akzentfarben.
  Design-Tokens zentral in `Sources/Stasi/UI/Theme.swift`. Vorschau: `preview/tokens.html`.
  Ursprüngliche Spezifikation: `DESIGN-HANDOFF.md`.

## Aktueller Stand (Stand: 24.08.2026, später Abend)

**Funktioniert end-to-end:** Hotkey (rechte ⌘ halten) → Aufnahme → on-device-Transkription
(EN/DE) → Dictionary-Biasing + Korrektur-Pass → Injection in fokussierte App → Protokoll-
Historie (persistiert, Play/Export .txt/.md/Löschen) → Dashboard mit Stats + Wochenchart.
Aufnahme-Pill (Wispr-Kompaktstil, rein AppKit) mit ✕ Verwerfen / ✓ Sofort einfügen + Toasts.

**Test-Suite: 54 Tests, 0 Fehler** (`Tests/StasiTests/`). 4 Pipeline-E2E-Tests sind gated
(siehe Regeln unten). TDD etabliert – bei Änderungen an Logik: erst Test, dann Fix.

### Bekannte Platzhalter („Bald" im UI)
- Hands-free-Modus (Doppeltipp fn), ⌃⌘V (letztes Protokoll einfügen), ⌃⌘C (kopieren)
- „Auto-gelernt": UI + Store-Mechanik da (`EntryType.learned`, `promote`), aber automatische
  Begriffs-Erkennung beim Diktieren noch NICHT aktiv
- KI-Nachbearbeitung (Toggle stored, inaktiv) · Mikrofon-Auswahl (nutzt aktives macOS-Gerät)
- Sprache „Automatisch" = Systemsprache (SpeechTranscriber kann nicht pro Äußerung erkennen)

## Architektur

```
Sources/Stasi/
├── MainApp.swift              StasiApp (WindowGroup + Commands), AppDelegate (Poll-Timer
│                             20Hz UI / 1Hz Permissions + Stall-Watchdog), StatusBarController
│                             (NSStatusItem+NSMenu – bewusst KEIN MenuBarExtra!)
├── Core/
│   ├── AppState.swift         @MainActor @Observable State-Machine idle→recording→transcribing
│   │                          →injecting; Hotkey-Modi (PTT/Umschalten), Sounds, WAV-Mitschrieb
│   ├── SettingsStore.swift    @Observable mit GESPEICHERTEN Properties + didSet-UserDefaults
│   ├── AudioCapture.swift     AVAudioEngine-Tap; Render-Thread NUR: lock-geschützter RMS +
│   │                          thread-safe yield; WAV auf serialer writeQueue
│   ├── TranscriptionEngine.swift  SpeechAnalyzer/SpeechTranscriber, Biasing via
│   │                          AnalysisContext.contextualStrings[.general]; LIFECYCLE: NIE den
│   │                          Ergebnis-Strom canceln (Speech-Worker trapt!), Analyzer "ruht
│   │                          aus" in retiredAnalyzers; Session-Guard gegen Cross-Write
│   ├── CorrectionEngine.swift Garantierter Korrektur-Pass (siehe Regeln!)
│   ├── DictionaryModel.swift  EntryType word/correction/learned + CommonWords-Warnungen
│   ├── DictionaryStore.swift  ~/Library/Application Support/Stasi/dictionary.json + File-Watcher
│   ├── TranscriptionRecord.swift  Record-Modell + HistoryStore (history.json, persistiert)
│   ├── HotkeyEngine.swift     CGEventTap listen-only + NSEvent-Fallback-Monitor + ensureEnabled
│   ├── BiasProvider.swift     Wörterbuch → kurze Kontextliste (max 12, kürzeste zuerst)
│   └── TextInjector.swift     CGEvents mit Unicode-Chunks (24er), Thread.sleep-Gating
├── UI/                        Theme.swift (Tokens), RootView, Sidebar, DashboardView,
│                              ProtocolsView, DictionaryView, SettingsWindowView, AccountView,
│                              RecordingPill.swift (AppKit!), Effects.swift (pulseForever)
└── Support/                   Permissions.swift (Mikrofon/AX/ListenEvent!), VirtualKey.swift

scripts/make-app.sh            → build/Stasi.app (ad-hoc signiert, Icon aus Import/-PNGs)
scripts/gen_icon.swift         → Fallback-Icon-Generator
preview/token-template.json    → Design-Token-Vorlage für den Nutzer
Tests/StasiTests/              → 54 Tests (XCTest)
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
   liefert. Nach `finalizeAndFinishThroughEndOfInput` (mit 3-s-Timeout, Analyzer-Referenz
   VORHER lokal capturen) endet der Strom natürlich; alte Analyzer ruhen in
   `retiredAnalyzers`. Session-Guard (`sessionID`) gegen Cross-Session-Writes.

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

11. **CGEventTap NIEMALS ohne Eingabe-Überwachungs-Recht installieren oder re-enablen.**
    macOS deaktiviert den unberechtigten Tap; wird er trotzdem sekündlich per
    `CGEvent.tapEnable` wieder eingeschaltet, entzieht der WindowServer dem Prozess
    ALLE Maus-Events: Fenster rendert normal, Hotkey/Tastatur geht, aber jeder Klick
    (auch Dock-Icon) versackt – kein Crash, kein Log. Diagnose-Weg: Mini-AppKit-App
    bekam Klicks, Stasi nicht; `STASI_NO_TAP=1` (Debug-Env-Var in `installTap`)
    isolierte den Tap als Ursache. Fix: `installTap`/`ensureEnabled` sind hinter
    `listenEventGranted` gegated; nach Rechte-Erteilung installiert der Poll den Tap.
    ABER: Die ListenEvent-Freigabe greift für den LAUFENDEN Prozess oft erst nach
    App-Neustart – der Preflight sagt schon "erteilt", der Tap wird trotzdem
    deaktiviert. Deshalb gibt `ensureEnabled` nach 3 Deaktivierungen auf
    (`gaveUp`), stoppt den Tap und verlangt einen Neustart.
    UPDATE: Der Tap ist jetzt `.cgSessionEventTap` + `.defaultTap`
    und braucht NUR Bedienungshilfen – Eingabe-Überwachung entfällt komplett.

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
- Suite: CorrectionEngine (14), Stores (12), Settings/Copy/Keys/Level (24), Pipeline (4 aktiv
  + 4 gated). Bei Logik-Änderungen: erst Test schreiben/ändern, dann implementieren (TDD).
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
- Hands-free-Modus + ⌃⌘V/⌃⌘C-Shortcuts real implementieren
- whisper.cpp-Fallback mit echtem Initial-Prompt-Biasing (BiasProvider-Hook existiert)
- Sprachwechsel pro Äußerung · Snippets · KI-Nachbearbeitung (Toggle vorhanden)
- Design-Feinschliff: Nutzer findet v2 „altbacken" → neues Design kommt aus
  `Import/design_handoff_stasi/` (bereits umgesetzt) – weitere Änderungen über
  `DESIGN-HANDOFF.md`-Prozess (Token-Vertrag!)
