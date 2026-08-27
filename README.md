# STASI

Push-to-Talk-Diktat für macOS – Wispr-Flow-Style, komplett on-device.

Rechte **Command-Taste halten** → Startton abwarten → sprechen → loslassen. Der korrigierte Text
wird in die fokussierte App getippt.

## Features (v0.9.0)

- **Echte Mac-App**: Dock-Icon, App-Menü, ⌘,-Settings, resizable Hauptfenster
- **On-device-Transkription** via macOS-26 `SpeechTranscriber` (EN/DE)
- **Deterministische Nachbearbeitung** mit den Stufen AUS und STANDARD:
  sprachspezifische Zögerlaute, Stotterer, konservative Selbstkorrekturen,
  Diskurs-Füller und Text-Hygiene – vollständig regelbasiert
- **Dictionary**: Wörter & Korrekturpaare (`cloud code` → `Claude Code`),
  inkl. Biasing der Engine + garantiertem Nachkorrektur-Pass
  - Datei: `~/Library/Application Support/Stasi/dictionary.json`
    (menschenlesbar, Hand-Edits erscheinen live in der UI)
- **Auto-gelernt**: Wiederholt diktierte unbekannte Begriffe werden vorgeschlagen und
  können übernommen oder dauerhaft ignoriert werden
- **Aufnahme-Pill** aus purem AppKit mit Pegel, zweizeiligem Live-Text und
  Phasenanzeige für Transkribieren, Polieren und Einfügen
- **Protokolle** mit Abspielen, Kopieren, Audio-/Text-/Markdown-Export,
  Rohtext-Ansicht, Korrektur- und Poliert-Nachweis
- **Globale Suche mit ⌘F** über alle Protokolle samt 7-/30-Tage-Filtern und
  Gesamtexport als Markdown
- **Dashboard und Insights** mit Wochenvergleich, App-Nutzung, Streak-Heatmap,
  Wortzahl, Diktiergeschwindigkeit und geschätzter Zeitersparnis
- **Onboarding** für Rechte, Hotkey, Modellvorbereitung und Probaufnahme
- **Aufbewahrung**: Nie, 1 Tag, 1 Woche, 2 Wochen oder 1 Monat; Audio wird mit gelöscht
- **Globale Zusatz-Shortcuts**: ⌃⌘C kopiert und ⌃⌘V fügt das letzte Protokoll erneut ein
- **Hands-free** per Fn-Doppeltipp, in den Einstellungen ein- und ausschaltbar
- **Update-Prüfung** über GitHub Releases mit direktem Link zur verfügbaren Version
- **Menüleisten-Status** mit explizit gecachten Symbolen je Verarbeitungsphase

## Design-System

Alle Views ziehen aus den Tokens in `Sources/Stasi/UI/Theme.swift`
(Farben, Typo, Raum, Motion) – Geist/Geist-Mono-Fonts, ausschließlich Light Mode
und 5 wählbare Akzent-Presets. Maßgebliche Vorschau:
`import/design_handoff_v3/preview.html` im Browser öffnen.

## Bauen & Starten

```bash
./scripts/make-app.sh          # baut build/Stasi.app
open build/Stasi.app
```

Entwicklung:

```bash
swift build                    # Kompilieren
open Package.swift             # In Xcode öffnen
```

Tests (307 Tests; vier Speech-Pipeline-E2E-Fälle sind ohne TCC-Consent gegatet):

```bash
swift build --build-tests
xcrun xctest .build/arm64-apple-macosx/debug/StasiPackageTests.xctest
```

`swift test` kann in der Runner-Infrastruktur hängen; der direkte `xctest`-Aufruf ist
der zuverlässige Weg.

## Erster Start – Berechtigungen

1. **Mikrofon** – Systemdialog beim ersten Aufnehmen bestätigen
2. **Bedienungshilfen** – für den globalen Hotkey und das Text-Einfügen;
   Settings (⌘,) → Berechtigungen → Link folgt zu System Settings

## Architektur

```
Sources/Stasi/
├── MainApp.swift            App-Szene, AppDelegate (Poll), Statusleiste
├── Core/
│   ├── AppState.swift       State-Machine: idle→recording→transcribing→polishing→injecting
│   ├── DictationSession.swift     Besitzer und Lebenszyklus eines Diktats
│   ├── AudioCapture.swift   Mikrofon-Capture (nativ→Engine-Format), WAV, VU-Pegel
│   ├── TranscriptionEngine.swift  SpeechAnalyzer/SpeechTranscriber (actor) + Biasing
│   ├── DictionaryStore.swift      JSON-Persistenz + File-Watching
│   ├── CorrectionEngine.swift     Garantierter Korrektur-Pass
│   ├── PolishLocale.swift         Sprachspezifische DE-/EN-Regellisten
│   ├── TextTidy.swift             Whitespace-, Satzzeichen- und Großschreibungs-Hygiene
│   ├── FillerFilter.swift         Zögerlaut-, Stotter- und Diskursfüller-Pässe
│   ├── SelfCorrectionResolver.swift  Konservative Selbstkorrekturen
│   ├── TranscriptPolisher.swift   Orchestriert AUS/STANDARD und Änderungsnachweis
│   ├── AutoLearnScout.swift       Reine Kandidatensuche für Auto-gelernt
│   ├── BiasProvider.swift         Wörterbuch → Engine-Kontext
│   ├── HotkeyEngine.swift   CGEventTap für PTT, Hands-free und Zusatz-Shortcuts
│   ├── TextInjector.swift   Synthetische Keyboard-Events
│   └── SettingsStore.swift, DictionaryModel.swift, TranscriptionRecord.swift
├── UI/
│   ├── Theme.swift          Design-Tokens (Cloud Design)
│   ├── RootView.swift, Sidebar.swift, DashboardView.swift, ProtocolsView.swift,
│   ├── DictionaryView.swift, SettingsWindowView.swift, AccountView.swift,
│   └── RecordingPill.swift  Aufnahme-Pill + Toasts (pure AppKit)
└── Support/                 Permissions, VirtualKey, DebugLog
```

Debug-Log: `~/Library/Application Support/Stasi/debug.log`

## Diagnose- und Sicherheitsvariablen

- `STASI_NO_TAP=1` startet ohne globalen Event-Tap und hilft bei der Eingrenzung
  von Hotkey-/TCC-Problemen.
- `STASI_POLISH=off` erzwingt Nachbearbeitungsstufe AUS, unabhängig von der
  gespeicherten Einstellung.

## Roadmap-Ideen

- Sprach-Auto-Umschalter, Snippets, lokale LLM-Politur, whisper.cpp-Fallback
