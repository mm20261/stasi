# STASI

Push-to-Talk-Diktat für macOS – Wispr-Flow-Style, komplett on-device.

Rechte **Command-Taste halten** → sprechen → loslassen. Der korrigierte Text
wird in die fokussierte App getippt.

## Features (v0.1)

- **Echte Mac-App**: Dock-Icon, App-Menü, ⌘,-Settings, resizable Hauptfenster
- **On-device-Transkription** via macOS-26 `SpeechTranscriber` (EN/DE)
- **Dictionary**: Wörter & Korrekturpaare (`cloud code` → `Claude Code`),
  inkl. Biasing der Engine + garantiertem Nachkorrektur-Pass
  - Datei: `~/Library/Application Support/Stasi/dictionary.json`
    (menschenlesbar, Hand-Edits erscheinen live in der UI)
- **Aufnahme-Pill** (unten mittig) mit Live-Waveform, ✕ Verwerfen / ✓ Einfügen
- **Protokolle**: Historie mit Abspielen, Export (.txt/.md) und Korrektur-Anzeige
- **Dashboard** mit Statistiken und Wochenchart
- Menüleisten-Extra als sekundärer Status/Schnellzugriff

## Design-System „Cloud Design"

Alle Views ziehen aus den Tokens in `Sources/Stasi/UI/Theme.swift`
(Farben, Typo, Raum, Motion) – Geist/Geist-Mono-Fonts, Light/Dark,
8 wählbare Akzentfarben. Vorschau: `preview/tokens.html` im Browser öffnen.

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

## Erster Start – Berechtigungen

1. **Mikrofon** – Systemdialog beim ersten Aufnehmen bestätigen
2. **Bedienungshilfen** – für globalen Hotkey + Text-Einfügen;
   Settings (⌘,) → Berechtigungen → Link folgt zu System Settings

## Architektur

```
Sources/Stasi/
├── MainApp.swift            App-Szene, AppDelegate (Poll), Statusleiste
├── Core/
│   ├── AppState.swift       State-Machine: idle→recording→transcribing→injecting
│   ├── AudioCapture.swift   Mikrofon-Capture (nativ→Engine-Format), WAV, VU-Pegel
│   ├── TranscriptionEngine.swift  SpeechAnalyzer/SpeechTranscriber (actor) + Biasing
│   ├── DictionaryStore.swift      JSON-Persistenz + File-Watching
│   ├── CorrectionEngine.swift     Garantierter Korrektur-Pass
│   ├── BiasProvider.swift         Wörterbuch → Engine-Kontext
│   ├── HotkeyEngine.swift   CGEventTap Push-to-Talk (Session-Tap)
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

## Roadmap-Ideen

- Sprach-Auto-Umschalter, Snippets, lokale LLM-Politur, whisper.cpp-Fallback
