# Handoff: Stasi — lokales Diktier- & Transkriptions-Tool (macOS)

> Historisches Designarchiv, kein Runtime- oder Build-Input. Die kanonische App-Icon-Quelle liegt unter `Resources/AppIcon.png`; generierte PNG-/ICNS-Derivate gehören nicht in Git.

## Overview
Stasi ist eine lokale macOS-Diktier-App im Stil von Wispr Flow: systemweites Diktieren per Hotkey, Transkript-Verlauf, Wörterbuch mit Ersetzungen, Einstellungen, lokales Konto ohne Login. UI-Sprache: Deutsch. Der Name wird mit dezenter Ironie in der Copy gespielt („Wir hören zu.", „Überwachungsbericht") — abschaltbar.

## About the Design Files
Die Dateien in diesem Bundle sind **Design-Referenzen in HTML** (interaktiver Prototyp), kein Produktionscode. Aufgabe: die Designs in der Zielumgebung nachbauen (z. B. Electron + React, Tauri, oder Swift/AppKit). Existiert noch kein Codebase, ist **Tauri (Rust + Webview) oder Electron mit React** die naheliegendste Wahl, da das Design webbasiert spezifiziert ist. Für die eigentliche Transkription lokales Whisper (z. B. whisper.cpp) vorgesehen — nicht Teil dieses Designs.

- `Stasi v2.dc.html` — **maßgebliches finales Design** (Flow-artige Anordnung, einklappbare Sidebar, Mini-Pill mit Pegel-Waveform). Im Browser öffnen.
- `Stasi.dc.html` — ältere v1 als Referenz.
- `Stasi Icons.dc.html` — Icon-Showcase.
- `assets/` + `icons/` — historische SVG-Referenzen; die früheren exportierten PNG-Derivate wurden aus Git entfernt.
- `macos-window.jsx`, `image-slot.js`, `support.js` — Prototyp-Laufzeit, NICHT übernehmen.

## Fidelity
**High-fidelity.** Farben, Typografie, Abstände, Copy und Interaktionen sind final gemeint und sollen pixelgenau übernommen werden.

## Design Tokens

### Farben — Light Mode
| Token | Wert | Verwendung |
|---|---|---|
| bg | `#F4F4F2` | Fenster-/Seitenhintergrund |
| sf (surface) | `#FFFFFF` | Karten, Listen |
| ink | `#1A1917` | Primärtext |
| sub | `#716E67` | Sekundärtext |
| line | `#E4E2DC` | Rahmen, Trennlinien |
| hov | `#ECEAE5` | Hover-Flächen, Key-Badges |
| pill | `#1A1917` | Aufnahme-Pill-Hintergrund |
| pillInk | `#F4F2ED` | Text auf der Pill |

### Farben — Dark Mode (bewusst „weiches" Grau, kein Schwarz)
| Token | Wert |
|---|---|
| bg | `#252420` |
| sf | `#2F2E2A` |
| ink | `#F0EEE9` |
| sub | `#A3A099` |
| line | `#3D3B36` |
| hov | `#383631` |
| pill | `#403E38` |
| pillInk | `#F2F0EB` |

### Akzent
- Standard-Akzent: Blau `#1D4E89` (User-wählbar; Alternativen: `#1A1917`, `#D64500`, `#C8102E`, `#8A1E1E`, `#B5892E`, `#2D6A4F`, `#5B4A8A`)
- **Dark Mode**: Akzent automatisch aufhellen: `color-mix(in oklab, <akzent> 62%, #E8ECF2 38%)`
- Akzent-Tint (aktive Nav, Tabs, Chart): `color-mix(in oklab, var(--ac) 11%, var(--sf))`
- Auf der dunklen Pill: `color-mix(in oklab, var(--ac) 45%, var(--pillInk))`
- Aufnahme-Rot (Pulsdot, Menubar): `#FF453A` / `#FF4D2E`
- Destruktiv (Löschen-Hover): `#C8102E`

### Typografie
- UI: **Geist** (400/500/600/700), Google Fonts
- Mono (Zeiten, Kicker, Badges, Wordmark): **Geist Mono** (400/500/600)
- H1 Screens: 28px/600, letter-spacing −0.01em
- Fließtext/Listen: 13.5px, line-height 1.6–1.65
- Sekundär: 12–12.5px; Mono-Kicker: 10.5–11px, letter-spacing 0.1–0.14em, UPPERCASE
- Stat-Werte: 24px/600, tabular-nums
- Zahlen immer `font-variant-numeric: tabular-nums`

### Sonstiges
- Karten: radius 12px, 1px line-Border, KEINE Schatten
- Buttons/Inputs: radius 8–9px; Pills/Toggles: radius 999px
- Fenster: 1080×700, radius 14px, Schatten `0 0 0 1px rgba(0,0,0,.18), 0 24px 60px rgba(0,0,0,.3)`
- Spacing-Rhythmus: 12px Grid-Gaps, 14–18px Zellen-Padding, 26–36px Sektionsabstände
- Fokus: 2px Akzent-Outline; `prefers-reduced-motion` respektieren
- Transitions: background/filter 150ms

## Screens / Views

### 1. Sidebar (212px, immer sichtbar)
- Traffic Lights oben, dann Wordmark „STASI" (Geist Mono 600, 17px, letter-spacing 0.12em) + Tagline „Wir hören zu." (12px sub)
- Nav: Der Bericht, Protokolle, Wörterbuch, Einstellungen, Konto — 13.5px, 16px-Stroke-Icons, aktiv = Akzent-Tint-Hintergrund + Akzentfarbe + 600
- Unten: „Erscheinungsbild"-Button mit Mond/Sonne-Icon (Theme-Toggle), darunter Versionszeile klein (9.5px mono): „v 0.9 · Akte 001 / © meder.dev"

### 2. Der Bericht (Dashboard)
- Mono-Kicker in Akzent: „TAGESBERICHT · MONTAG, 24. AUGUST", H1 „Guten Morgen, {Name}."
- Hotkey-Karte: Key-Badges „⌥ Leertaste" + Hinweistext (abhängig vom Modus) + Akzent-Pill-Button „Diktat simulieren" (→ Aufnahme starten)
- Kicker „ÜBERWACHUNGSBERICHT KW 35 — LÜCKENLOS ERFASST"
- 4 Stat-Kacheln (Grid 4×1fr, gap 12): Wert 24px + Mono-Label + Akzent-Delta. Werte einzeilig (nowrap)
- Darunter Grid 1.2fr/1fr: Balkenchart „Wörter pro Tag" (Mo–So, aktiver Tag = Vollakzent, Rest Akzent-Tint, min-height 5px) und „Letzte Protokolle" (3 Zeilen: Zeit mono, Titel ellipsis, „→ App" in Akzent) mit „Alle ansehen"

### 3. Protokolle
- H1 + Sub „{n} Protokolle · alles dokumentiert, nichts vergessen."
- Eine Karte, Zeilen getrennt durch line (letzte Zeile ohne Border):
  - Zeit-Spalte 88px mono 11px
  - Text direkt sichtbar, 3 Zeilen geclampt (`-webkit-line-clamp`), Klick toggelt voll/geklappt
  - Meta-Zeile darunter mono 10.5px: „→ Mail · 0:38 · 61 Wörter"
  - Rechts Icon-Buttons (30×30, radius 8, sub-Farbe, hover hov-bg): **Play** (toggelt Wiedergabe, aktiv = Akzent + Stop-Icon), **Kopieren** (wird 1.6s zu Akzent-Häkchen), **⋯-Menü**
  - ⋯-Menü (Dropdown, sf-bg, line-Border, radius 10, Schatten): Audio extrahieren (.wav) / Export als .txt / Export als .md / Trenner / Löschen (rot)
- Empty State: „Keine Protokolle" + „Die Akte ist leer. Das kommt selten vor."

### 4. Wörterbuch
- Tabs (Segmented, sf-bg): Begriffe / Ersetzungen / Auto-gelernt
- **Begriffe**: Input + Akzent-Button „Hinzufügen" (Enter geht auch); darunter Karte mit Zeilen: Begriff links, rechts Stift-Icon (Bearbeiten → Zeile wird Input + „Speichern") und Mülleimer-Icon (Löschen, hover rot)
- **Ersetzungen**: zwei Inputs (Kürzel mono → Langform) + Hinzufügen; Zeilen: Kürzel als mono-Badge → Text, rechts „Bearbeiten"/„Löschen" (Bearbeiten → Inline-Inputs + Speichern)
- **Auto-gelernt**: Hinweistext, Zeilen: Begriff + mono-Note („7× DIKTIERT · QUELLE: SLACK"), Buttons „Übernehmen" (→ wandert zu Begriffe) und „Ignorieren". Empty State: „Alles gesichtet"

### 5. Einstellungen (max-width 600)
Sektionen mit Mono-Kickern, je eine Karte:
- **AUFNAHME**: 4 Shortcut-Zeilen (Label + Beschreibung links, Key-Badges + „Ändern" rechts): Push-to-talk „⌥ Leertaste" / Hands-free-Modus „Doppeltipp fn" / Letztes Protokoll einfügen „⌃ ⌘ V" / Letztes Protokoll kopieren „⌃ ⌘ C". Danach Modus-Zeile mit Segmented Push-to-talk/Umschalten (Beschreibung wechselt mit)
- **EINGABE**: Mikrofon-Select (MacBook Pro Mikrofon / AirPods Pro / Shure MV7), Sprache-Select (Automatisch erkennen / Deutsch / Englisch)
- **VERHALTEN**: 3 Toggles (40×24, Knob 18px, an = Akzent): Ton-Feedback, KI-Nachbearbeitung („Entfernt Füllwörter — ähm, äh, quasi"), Autostart
- **DARSTELLUNG**: Segmented Hell/Dunkel
- **ÜBER**: Version-Badge „V 0.9 · AKTE 001", Updates-Zeile mit Button „Auf GitHub prüfen" (Repo-URL einsetzen)
- Fußnote: „Alle Aufnahmen werden lokal auf deinem Mac verarbeitet. Niemand hört mit. Ehrlich. Das wäre ja auch ironisch."

### 6. Konto
- Sub: „Deine Akte. Ausnahmsweise führst du sie selbst."
- Karte: rundes Profilbild 76px (Drag-and-drop/Dateiauswahl) + NAME-Input (steuert Begrüßung) + Hinweis „Kein Login, keine E-Mail — alles bleibt auf diesem Mac."
- Signatur-Karte: „Stasi · v 0.9 · Akte 001", „Gebaut von meder.dev. Weitergeben erlaubt. Zuhören sowieso.", Link meder.dev
- Oben rechts im Fenster (alle Screens): 34px-Avatar-Kreis (Bild oder Initiale des Namens), Klick → Konto

### 7. Aufnahme-Pill (Overlay, unten mittig, alle Screens)
Dunkle Pill (pill-bg, radius 999, Schatten, Slide-up 250ms):
- ✕-Button links (28px Kreis, rgba-weiß 14%): Aufnahme **verwerfen**
- Roter Pulsdot (9px, 1.1s Opacity-Puls)
- 12 animierte Waveform-Balken (3px, Akzent-Pill-Farbe, scaleY-Loop 0.7–1.06s versetzt)
- Live-Text (letzte Wörter sichtbar, rtl-Ellipsis), Timer mono, „→ Notizen" 
- ✓-Button rechts (28px, pillInk-bg): **sofort beenden + bis dahin Transkribiertes einfügen**
- Nach Abschluss: Toast-Pill „Protokolliert. In Notizen eingefügt ✓" (2.6s)

## Interactions & Behavior
- Hotkey-Modi: Push-to-talk (halten/loslassen) vs. Umschalten (Start/Stopp) — global wählbar, Hands-free zusätzlich per eigenem Hotkey
- Pill: ✕ verwirft (Toast „Aufnahme verworfen"), ✓ committet sofort; fertiges Diktat committet automatisch nach 650ms
- Kopieren: Clipboard + Icon-Feedback 1.6s
- Export: .txt = Rohtext; .md = `# Protokoll · {when}` + Text
- Theme-Wechsel: sofort, ohne Reload; Mond↔Sonne-Icon
- Alle Listen: letzte Zeile ohne Trennlinie; Hover-Flächen 150ms

## State Management
- `theme` (hell/dunkel), `accent`, `irony` (schaltet ironische Copy app-weit)
- `userName`, Avatar-Bild (lokal persistiert)
- `transcripts[]` {id, when, app, dur, words, text, audio?}, `expandedId`, `playingId`, `menuId`, `copiedId`
- `terms[]`, `replacements[]` {from, to}, `learned[]` {term, note} + Edit-Zustände
- Settings: `hotkeyMode`, `mic`, `lang`, `sound`, `ai`, `autostart`
- Aufnahme: `recording`, `liveWords[]`, `recSecs`

## Assets
- `icons/` — historische Dock-Icon-SVG-Referenz; exportierte PNG-Größen wurden als generierte Derivate entfernt. Menubar-/Favicon-SVGs liegen unter `assets/`.
- Fonts: Geist + Geist Mono (Google Fonts / Vercel, OFL)
- Alle UI-Icons sind Inline-SVGs (24er-ViewBox, stroke 1.7–1.8, round caps) — aus `Stasi.dc.html` übernehmbar

## Files
- `Stasi v2.dc.html` — kompletter Prototyp (maßgeblich)
- `Stasi.dc.html` — v1 (Referenz)
- `Stasi Icons.dc.html` — Icon-Showcase
- `assets/*.svg`, `icons/**` — Grafik-Assets

## v2-Änderungen (maßgeblich gegenüber obiger Screen-Beschreibung)
- Standard-Akzent jetzt Anthrazit `#1A1917`; ironische Copy standardmäßig AUS; kein Dark Mode
- "Der Bericht" = Startseite: Begrüßung, Protokoll-Liste "HEUTE" (Zeit / Text 3 Zeilen geclampt / Play, Kopieren, ⋯-Menü), rechts 252px-Rail (Wörter gesamt, WPM, Serie + "Deine Akte"-Fortschritt)
- Eigener Insights-Screen: 3 Stat-Karten, "Wohin diktiert wird"-Balken, Streak-Heatmap (16×7)
- Sidebar einklappbar (200px ↔ 64px Icon-only, Panel-Icon oben, Transition .25s); Einstellungen als eigener Punkt UNTEN links; kein "Diktat simulieren"-Button — Aufnahme startet nur per Hotkey
- Mini-Aufnahme-Pill: 26px hoch, unten mittig: ✕ (16px) · roter Punkt · 14 Pegel-Balken (2px breit, Höhe 2-14px, reagieren auf Lautstärke, transition .12s) · Timer 9px mono · ✓ (17px). Toast: "Protokolliert ✓"
- Karten: radius 16px, ohne Border, Schatten 0 2px 8px color-mix(accent 12%); Hintergrund linear-gradient(160deg,#F3F6FA,#F8F7F3); Mikro-Animationen: Nav-Hover translateX(3px), Karten-Hover translateY(-3px), Icon-Hover scale(1.1)
- App-Icon in beiden Tönen unter icons-v2/ (blau + anthrazit)
