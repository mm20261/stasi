# STASI · Design-Handoff

> **Überholt** – maßgeblich ist `import/design_handoff_v3/DESIGN.md`; dieses Dokument
> bleibt als historischer Brief erhalten.

**Für:** Externe Gestaltung (Figma / Framer / KI-Design-Tool / Handentwurf)
**Ziel:** Du lieferst Werte + Screen-Entwürfe zurück, ich baue sie 1:1 in die App ein.
**Regel:** Jeder visuelle Wert im Code kommt aus einem Token. Dein Entwurf darf also
keinen Wert verwenden, der keinen Slot unten hat – sonst gibt es keinen Platz dafür.

---

## 1 · Produkt-Kontext

| | |
|---|---|
| Plattform | macOS 26, native SwiftUI-App |
| Typ | Echte Mac-App (Dock, App-Menü) + schwebendes Diktat-Overlay |
| Zweck | Push-to-Talk-Diktat: Taste halten → sprechen → Text wird eingefügt |
| Fenstergrößen | Hauptfenster 760×700 (resizable), Settings 500×560, Overlay 360×84 |

**Lesbarkeit ist Priorität 1** (dein Feedback zu v2). Verbindliche Mindestanforderungen:

- Fließtext ≥ 13 pt, Labels ≥ 12 pt (nicht 10–11 wie bisher)
- Sekundärtext-Kontrast ≥ 4.5:1 auf seiner Fläche (v2-Wert `#76756F` auf Weiß war zu schwach)
- Zeilenhöhe ≥ 1.4 für Transkriptionstexte
- Keine Schrift unter 11 pt irgendwo im UI

## 2 · Screens & Pflicht-Inhalte

### A · Hauptfenster
1. **Recorder-Bereich** (oben): Level-Anzeige (Balken *oder* Zeiger – deine Wahl),
   Record-Taste (Zustände: bereit / aufnahme / aktiv-Puls), Zeit-Zähler,
   Live-Transkript während Aufnahme (2–3 Zeilen)
2. **Historie**: Suchfeld, Liste von Einträgen. Eintrag = Zeitstempel, Sprachkürzel,
   Text (mehrzeilig), Copy-Button, optional Korrekturzeile (`„x“ → y`, grün) und
   Korrekturzähler. Leerezustand („noch keine Aufnahmen“) und Such-Leerzustand designen!
3. **Dictionary**: Suchfeld, „Hinzufügen“-Button, Eintragsliste.
   Eintrag = Typ-Badge (`WORT` / `KORREKTUR`), Inhalt, optionale Notiz,
   Warnzeile (amber, bei riskanten Quellen), Edit/Delete-Aktionen.
4. **Add/Edit-Dialog** (Sheet): Typ-Umschalter (Wort ↔ Korrektur), Felder je Typ,
   Notizfeld, Warnanzeige live beim Tippen, Abbrechen/Speichern.

### B · Settings-Fenster (⌘,)
Hotkey-Anzeige + Aufnahme-Modus, Statuszeile (aktiv/inaktiv), Sprache EN/DE,
zwei Berechtigungszeilen (Mikrofon, Bedienungshilfen – mit „Erteilt ✓“ bzw.
Reparatur-Hinweis), Info-Block (Version, Engine).

### C · FlowBar-Overlay (schwebt über anderen Apps)
Kompakt-Pille 360×84: Status-Dot, Titel („Aufnahme“/„Transkribiere…“),
Live-Text (2 Zeilen). Zwei Zustände: recording / transcribing.
Muss auf hellem UND dunklem Untergrund funktionieren.

### D · Menüleisten-Menü
Status-Zeile, Sprach-Umschalter, „Öffnen“, „Einstellungen…“, „Beenden“.
(Nur Textmenü – kein Designaufwand außer ggf. Icons.)

### E · App-Icon (macOS Squircle)
1024 px, funktioniert in 16 px. Motiv frei, aber: ein Akzentfarbe-Einsatz max.,
lesbar auf hellem und dunklem Desktop.

## 3 · Zustands-Matrix (alles designen!)

| Komponente | idle | recording | transcribing | injecting |
|---|---|---|---|---|
| Record-Taste | Punkt rot | Stop-Symbol, pulsierend | disabled | disabled |
| Level | 0 / leer | aktiv | einfrierend | — |
| Zähler | 00:00:00 | läuft | steht | steht |
| FlowBar | versteckt | sichtbar | sichtbar | kurz sichtbar |

Fehler-/Sonderzustände: Mikrofon verweigert, Bedienungshilfen fehlt,
Engine-Fehlermeldung (im Recorder-Bereich), Dictionary-Datei korrupt.

## 4 · Token-Vertrag (die Slots, die du füllst)

> Historischer Token-Vertrag. Maßgeblich ist die aktuelle Vorschau unter
> `import/design_handoff_v3/preview.html`.

### Farbe (9 Slots)
| Token | Rolle | Vorgabe |
|---|---|---|
| `background` | Fenstergrund | hell |
| `surface` | Karten/Flächen | hebt sich vom Grund ab |
| `surfaceSecondary` | Chips, Eingabefelder | zwischen background & surface |
| `ink` | Primärtext | Kontrast ≥ 7:1 auf surface |
| `inkSecondary` | Sekundärtext/Meta | Kontrast ≥ 4.5:1 auf surface |
| `accent` | **Record/Aktionen – einziger Akzent** | |
| `accentPressed` | Akzent gedrückt | dunkler als accent |
| `success` | Korrekturen, „aktiv“ | |
| `warning` | Dictionary-Warnungen | |

Dazu 2 Struktur-Werte: `border` (Hauch-Kante) und `shadowColor/strength`
(weiche Karte vs. schwebendes Panel).

### Typografie (4 Slots)
| Token | Größe (min!) | Einsatz |
|---|---|---|
| `font.label` | 12 | Buttons, Abschnitts-Titel |
| `font.body` | 13–15 | Transkripte, Listen |
| `font.title` | 17–20 | Fenster-/Karten-Titel |
| `font.counter` | 14–16, monospaced tabellarisch | Zeit-Zähler |

Ggf. Wunsch-Font angeben (muss auf macOS verfügbar sein; System-Font = sicher).

### Raum & Form
`space` (Skala 4–32), `radiusControl`, `radiusCard`, `radiusPanel`,
`borderWidth` (fast immer 1).

### Bewegung
`motionFast` (Tasten, ~120–200 ms), `motionPanel` (Einblenden, ~200–350 ms),
Level-Animation (Charakter: schnellen Anschlag? weich? — Beschreibung genügt).

## 5 · Was du mir zurückgibst

1. **V3-Handoff prüfen** (`import/design_handoff_v3/preview.html`)
2. **Screens** als Bilder/Frames: Hauptfenster (mit Historie + Dictionary gefüllt),
   Settings, FlowBar (beide Zustände), Add/Edit-Sheet, Icon
3. Optional: Font-Datei/-Name, falls kein Systemfont

Ich mache daraus dann: neue `Theme.swift`-Tokens + View-Anpassungen + neuen
Icon-Generator + aktualisierte HTML-Vorschau zur Gegenprobe.

## 6 · Aktueller Stand als Referenz

- Code-Tokens: `Sources/Stasi/UI/Theme.swift`
- Maßgebliche Vorschau: `import/design_handoff_v3/preview.html`
