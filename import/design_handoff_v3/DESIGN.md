# Stasi — Design-Handoff v3 (aktueller Stand)

> Referenz des **aktuell implementierten** Designs für die nächste Cloud-Design-Runde.
> Alle Tokens, Screens und Texte sind 1:1 aus dem Code (`Sources/Stasi/UI/Theme.swift` + Views).
> Stand: 25.08.2026 · App-Version 0.9 · 161 Tests grün.
>
> **Nachzutrag:** Nach der v3-Runde wurden Features ergänzt (Suche, Onboarding, Insights-Leitzahl,
> Mikrofon-Auswahl, Update-Prüfung, Retention, DARSTELLUNG-Akzentkreise) — siehe Abschnitt 6.
> Das v4-„Registratur"-Experiment (Archivo, Stempelrot fest, Kopfkante-Karten) wurde verworfen;
> der v3-Look (Geist, Verlauf, 5 Akzent-Presets) ist mit diesen Features wieder maßgeblich.

---

## 1. Design-Tokens

### Farben (Light Mode — kein Dark Mode)

| Token | Wert | Verwendung |
|---|---|---|
| bg | `linear-gradient(160deg, #F3F6FA, #F8F7F3)` | Fensterhintergrund (Verlauf) |
| sf (surface) | `#FFFFFF` | Karten, Listen |
| ink | `#1A1917` | Primärtext |
| sub | `#8A8780` | Sekundärtext |
| line | `#ECEAE4` | Trennlinien |
| hov | `#F1F4F8` | Hover-Flächen, Key-Badges |
| recRed | `#FF453A` | Aufnahme-Rot (Pulsdot, PTT-Indikator) |
| destructive | `#C8102E` | Löschen-Hover |
| success | `#30A46C` | „Erteilt"-Status, ✓ |

### Akzent (5 Presets, Standard Anthrazit)

| Name | Wert |
|---|---|
| Anthrazit *(Standard)* | `#1A1917` |
| Blau | `#1D4E89` |
| Orange | `#D64500` |
| Grün | `#2D6A4F` |
| Violett | `#5B4A8A` |

- **Akzent-Tint** (aktive Flächen, Badge-Hintergründe): Akzent bei 12 % Opacity.
- **Kartenschatten**: `0 2px 8px` in Akzent bei 12 % Opacity.
- **Pill-Hintergrund** (Aufnahme): `color-mix(accent 88%, #000 12%)`.

### Typografie (Geist / Geist Mono, gebündelt)

| Stil | Font | Größe/Gewicht | Tracking |
|---|---|---|---|
| H1 (Screens) | Geist | 27 px / 700 | −0.015 em |
| Stat-Wert (Rail) | Geist | 24 px / 600 | tabular-nums |
| Big-Stat (Insights) | Geist | 28 px / 700 | tabular-nums |
| Fließtext | Geist | 13 px | — |
| Sekundär | Geist | 12 px | — |
| Kicker | Geist Mono | 10 px / 500 | 0.14 em, UPPERCASE |
| Nav | Geist | 13 px | — |
| Wordmark „STASI" | Geist Mono | 15 px / 600 | 0.14 em |
| Zeiten/Meta | Geist Mono | 10–11 px | tabular-nums |

### Raum & Form

- Sidebar: **200 px**, eingeklappt **64 px** (Icon-only, Transition 0.25 s).
- Karten: **Radius 16 px**, **keine Border**, Akzent-Schatten.
- Controls: Radius 9 px · Inputs: Radius 12 px · Pill/Toggles: 999 px.
- Grid-Gap: 12 px · Content-Padding: 32 px horizontal, unten 80 px.
- Fenster: 1200 × 780.

### Bewegung & Micro-Interaktionen

- Transitions: 150 ms · Panel: 250 ms (smooth) · Hover: 180 ms (easeInOut).
- Nav-Hover: `translateX(3px)` · Karten-Hover (Insights-Stats): `translateY(-3px)` · Icon-Hover: `scale(1.1)`.

---

## 2. Screens

### 2.1 Sidebar (immer sichtbar, einklappbar)
- Oben rechts: Panel-Toggle (Sidebar-Icon, 28×28). Eingeklappt bleibt das **Balken-Logo** zentriert sichtbar.
- Wordmark: 3 Akzent-Balken (9/16/6 px hoch) + „STASI" (Geist Mono 15/600, gesperrt).
- Tagline: „Wir hören zu." (Ironie an) / „Lokales Diktat." (Ironie aus) — 11 px sub.
- Nav (aktive Zeile = **Akzentfläche + weißer Text** + Schatten): Der Bericht, Insights, Wörterbuch, Konto.
- Unten fixiert: „Einstellungen" (gleicher Stil wie Nav).
- Versionszeile (9.5 px mono): „v 0.9 · Akte 001" / „© meder.dev".

### 2.2 Der Bericht (Startseite)
- Kicker (Akzent): „TAGESBERICHT · {WOCHENTAG, DATUM}".
- H1: „Guten Morgen/Tag/Nachmittag/Abend, {Name}."
- Optional: Hotkey-Blocker-Hinweis (roter Punkt + „Hotkey inaktiv – Bedienungshilfen fehlt" + „Erteilen").
- **Grid 1fr | 252 px Rail** (Gap 18):
  - Links: „HEUTE"-Kicker + „{n} Protokolle" + „Alle ansehen" (Akzent-Link).
    - Karte (r16): Zeilen mit Zeit (mono 10.5, 64 px), Text (13/1.6, 3 Zeilen geclampt, Klick klappt auf), Meta „→ App · 0:38 · 61 Wörter", rechts Play (filled, Akzent bei aktiv) / Kopieren (→ ✓ 1.6 s) / ⋯-Menü.
    - ⋯-Menü: Audio extrahieren (.wav) / Export .txt / Export .md / Trenner / Löschen (rot).
  - Rail: Karte „Wörter gesamt / Wörter · Minute / Serie" (Wert 24/600 + Label 12 sub), darunter „Deine Akte"-Karte (Titel 14/600, Hinweis, 6-px-Fortschrittsbalken Akzent, „NÄCHSTER EINTRAG IN X WÖRTERN").

### 2.3 Insights
- H1 „Insights" + Sub (Ironie: „Der Überwachungsbericht. Lückenlos, versteht sich.").
- 3 Big-Stat-Karten (28/700 + mono-Label + Akzent-Delta, Hover `translateY(-3px)`):
  Wörter/Woche (+ Delta % ggü. KW) · Wörter/Minute („× schneller als Tippen") · Zeit gespart („diese Woche").
- „Wohin diktiert wird": App-Zeilen mit 8-px-Akzent-Balken + Prozent.
- „{n} Tage Serie" + „REKORD · {m} TAGE": Heatmap **16 Wochen × 7 Tage** (Quadrate, Akzent mit Opacity 0.08–1.0).

### 2.4 Protokolle (Vollhistorie)
- H1 + Sub „{n} Protokolle · alles dokumentiert, nichts vergessen."
- Karte, Zeilen wie „Heute", aber mit voller Zeit (HH:MM:SS) + Korrektur-Badges. Gleiche Aktionen (Play/Kopieren/⋯-Menü inkl. Audio-Export).

### 2.5 Wörterbuch (max 620 px)
- H1 + Sub „Eigene Begriffe, damit Stasi sie korrekt protokolliert."
- **Tabs** (Segmented): Begriffe / Ersetzungen / Auto-gelernt.
- Begriffe: Input (r12, surface + Schatten) + Akzent-Button „Hinzufügen"; Zeilen mit Stift (Inline-Edit + „Speichern") und Mülleimer (hover rot).
- Ersetzungen: zwei Inputs (Kürzel → Langform) + Hinzufügen.
- Auto-gelernt: „Übernehmen"/„Ignorieren"; Empty „Alles gesichtet".

### 2.6 Einstellungen (max 620 px)
Sektionen mit Mono-Kickern, je eine Karte:
1. **AUFNAHME**: Shortcut-Zeilen — Push-to-talk (Badge + „Ändern" → Recorder, erfasst Modifier), Hands-free „fn ×2" (aktiv). Modus-Zeile (Segmented Push-to-talk/Umschalten). Berechtigungs-Zeilen (Eingabe-Überwachung + Bedienungshilfen, „Erteilt ✓" / „Freigeben").
2. **EINGABE**: Mikrofon (Systemstandard-Hinweis) + Sprache (Automatisch/Deutsch/Englisch).
3. **VERHALTEN**: Ton-Feedback · KI-Nachbearbeitung (inaktiv) · Autostart · Ironische Texte.
4. **DARSTELLUNG**: 5 Akzent-Farbkreise (aktive Farbe mit 2-px-Ring).
5. **SPEICHER**: „Aufnahmen aufbewahren" (Nie/1 Tag/1 Woche/2 Wochen/1 Monat) + „Alles löschen" (Bestätigungsdialog).
6. **ÜBER**: Version „V 0.9 · AKTE 001", „Auf GitHub prüfen"-Link, Privacy-Fußnote.

### 2.7 Konto (max 560 px)
- H1 + Sub (Ironie: „Deine Akte. Ausnahmsweise führst du sie selbst.").
- Profil-Karte: Avatar 72 px (Bild oder Initiale, Klick = Bild wählen) + „NAME"-Input + „Kein Login, keine E-Mail — alles bleibt auf diesem Mac."
- Signatur-Karte: „STASI · V 0.9 · AKTE 001", „Gebaut von meder.dev…", Link meder.dev.

### 2.8 Aufnahme-Pill (Overlay, unten mittig, 26 px hoch)
- Akzent-Hintergrund (88 % + Schwarz 12 %), Radius 999, Schatten, Schwebe-Animation (3 s, −3 px).
- ✕ (16 px Kreis, weiß 16 % bg) · roter Pulsdot (5 px, Opacity-Puls 1.1 s) · **14 Pegelbalken** (2 px breit, Höhe 2–16 px, reagieren auf Lautstärke — Stille = flach, laut = voller Ausschlag) · Timer (mono 9 px) · ✓ (17 px, weiß, Akzent-Haken).

### 2.9 Toast (36 px)
- „Protokolliert ✓" (Textfeld getroffen) bzw. „In Zwischenablage kopiert – ⌘V zum Einfügen" (kein Textfeld) bzw. „Aufnahme verworfen".
- Dunkle Pill, Erfolg = grüner Haken, Fehler = rotes ✕. Auto-Ausblendung 2.6 s.

---

## 3. Verhalten

- **Push-to-talk**: Hotkey halten → aufnehmen, loslassen → transkribieren + einfügen. Hotkey **frei belegbar** (Modifier + Taste; Standard rechte ⌘).
- **Umschalten-Modus**: einmal drücken startet, nochmal stoppt.
- **Hands-free**: Fn-Doppeltipp (350-ms-Fenster) toggelt Aufnahme.
- **Auto-Kopieren**: nach jedem Diktat liegt der korrigierte Text automatisch in der Zwischenablage → ⌘V zum Einfügen (wie Wispr).
- **Editable-Prüfung**: vor dem Einfügen wird per Accessibility geprüft, ob ein Textfeld fokussiert ist (`AXTextField`/`AXTextArea`/`AXWebArea`/`AXComboBox`). Falls nicht → **kein Einfügen, kein System-Beep**, nur Toast + Zwischenablage.
- **Retention**: Aufbewahrungsdauer Nie/1 Tag/1 Woche/2 Wochen/1 Monat; purged alte Protokolle + WAVs (App-Start, Settings-Änderung, ~60-s-Poll). „Alles löschen" entfernt alles.
- **Kopieren-Feedback**: Icon wird 1.6 s zum Akzent-Häkchen.
- **Export**: .txt = Rohtext, .md = `# Protokoll · {when}`, .wav = Audio-Datei.

---

## 4. Copy (Deutsch, Ironie schaltbar)

| Stelle | Ironie an | Ironie aus |
|---|---|---|
| Tagline (Sidebar) | „Wir hören zu." | „Lokales Diktat." |
| Protokolle-Sub | „… alles dokumentiert, nichts vergessen." | „{n} Protokolle" |
| Empty Protokolle | „Die Akte ist leer. Das kommt selten vor." | „Noch keine Protokolle." |
| Insights-Sub | „Der Überwachungsbericht. Lückenlos, versteht sich." | „Deine Diktier-Statistik." |
| Konto-Sub | „Deine Akte. Ausnahmsweise führst du sie selbst." | „Dein Profil — lokal gespeichert." |
| Privacy-Fußnote | „… Niemand hört mit. Ehrlich. Das wäre ja auch ironisch." | „Alle Aufnahmen werden ausschließlich lokal … verarbeitet." |

---

## 5. Assets

- App-Icon: `Import/design_handoff_stasi/icons/anthrazit/` (PNG 16–1024 + SVG).
- Menubar-Icons: `Sources/Stasi/Resources/Assets/menubar*.png`.
- Fonts: `Sources/Stasi/Resources/Fonts/Geist.ttf` + `GeistMono.ttf`.

---

## 6. Erweiterungen seit v3 (Features im v3-Look)

Diese Features kamen nach dem v3-Handoff dazu und sind inzwischen fester Bestandteil.
Alle im v3-Visual (Geist, Verlauf, weiße Karten, Akzent):

- **Suche (⌘F)** über alle Protokolle: Suchfeld-Topbar im Bericht + eigener Suchbereich in
  Protokolle; Trefferzähler, Filter-Chips ALLE/7T/30T, „Export aller Protokolle" als .md.
- **Bericht-Feinschliff:** Datumszeile (mono, UPPERCASE), Anleitungsleiste mit Status-Chip
  „Bereit"/„Hotkey inaktiv", Hero „Zuletzt diktiert" (Kopieren/Anhören/⋯), „Früher heute"-
  Einzeiler mit „Alle Protokolle ansehen", Rail mit Leitzahl („Wörter insgesamt diktiert")
  statt drei Einzelwerten + „Deine Akte"-Fortschrittsbalken. Leerzustand erster Start +
  Warnkarte „Berechtigung fehlt".
- **Insights:** eine große **Leitzahl-Karte** (Wörter/Woche mit Delta, Nebenwerte
  Wörter/Minute + Serie) statt drei Big-Stat-Karten; „Wohin diktiert wird" als
  Akzent-Stufen-Balken; Serie-Heatmap mit „REKORD"-Stempel-Badge.
- **Protokolle:** Zeilen mit zweizeiliger Mono-Spalte (Zeit + Aktenzeichen), App-Badge,
  WPM, Korrekturen- und Aktenzeichen-Badges, Play/Kopieren/⋯ (inkl. Audio-Export).
- **Onboarding (4 Schritte):** Willkommen → Befugnisse → Hotkey → Probediktat; bei erstem
  Start über dem Bericht.
- **Mikrofon-Auswahl:** Popover in EINGABE (Geräte-Liste, STANDARD-Häkchen, Pegel-Fußzeile).
- **Update-Prüfung:** in ÜBER („Aktuelle Version prüfen", Statuszeile, Update-Button).
- **SPEICHER:** Aufbewahrungsdauer (Segmented NIE/1T/1W/2W/1MONAT) + „Akte vernichten".
- **DARSTELLUNG:** 5 Akzent-Farbkreise (aktive Farbe mit 2-px-Ring) — zurück aus dem
  v3-Urzustand, da Akzent wieder dynamisch ist.
