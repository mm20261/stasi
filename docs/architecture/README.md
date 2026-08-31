# Runtime-Architektur

![Vorschau der Stasi Runtime-Architektur](stasi-runtime-preview.png)

- [Interaktive Architekturkarte](stasi-runtime.architecture.html)
- [Editierbare Archify-Quelle](stasi-runtime.architecture.json)

GitHub zeigt die PNG-Vorschau direkt an. Die interaktive HTML-Datei ist vollständig
in einer Datei enthalten. Zum Benutzen herunterladen und lokal im Browser öffnen.

Die Karte bildet den Diktat-Hauptpfad ab:

`App-Shell → AppState → DictationSession → AudioCapture → TranscriptionEngine → Nachbearbeitung → Verlauf & Ausgabe → Ziel-App`

Die Quellbelege sind an Commit
[`020f0f8`](https://github.com/mm20261/stasi/commit/020f0f82848b120acf4ee0c64bd5e7ffdb69f1e0)
gebunden. Verwendet wurden ausschließlich eingecheckte Produktionsquellen und
gezielt ausgewählte Architekturinformationen. Lokale Transkripte, Wörterbücher,
Audioaufnahmen, Logs und `.claude/`-Dateien sind nicht enthalten.

## Prüfen und neu erzeugen

Benötigt wird [Archify v2.16.0](https://github.com/tt-a1i/archify/releases/tag/v2.16.0).

```bash
node ~/.claude/skills/archify/bin/archify.mjs validate \
  architecture docs/architecture/stasi-runtime.architecture.json \
  --quality showcase \
  --repo-root . \
  --json

node ~/.claude/skills/archify/bin/archify.mjs deliver \
  architecture docs/architecture/stasi-runtime.architecture.json \
  docs/architecture/stasi-runtime.architecture.html \
  --quality showcase \
  --repo-root . \
  --json
```

Der aktuelle Stand besteht alle 9 Showcase-Prüfungen mit 0 Fehlern und
0 Warnungen. Die Sichtprüfung bestand in Light und Dark bei 1440×900 sowie
2048×1320. Auch 1600×1000 und 1920×1080 waren ohne Überlauf.

Die selbst verfassten Inhalte sind Deutsch. Archifys feste Bedienelemente bleiben
Englisch, weil der Renderer derzeit nur Englisch und vereinfachtes Chinesisch als
vollständige Viewer-Sprachen unterstützt.
