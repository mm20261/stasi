# Git-Historienbereinigung

## Zweck

Vor der öffentlichen Veröffentlichung werden ausschließlich Claude- und
Anthropic-Co-Author-Trailer entfernt. Author und Committer bleiben Philipp
Meder. Ihre E-Mail wird auf
`260910895+mm20261@users.noreply.github.com` gesetzt.

## Unverändert

- jeder Datei-Tree
- Parent-Reihenfolge und Merge-Topologie
- Author- und Committer-Zeitstempel
- Betreff und übriger Nachrichtentext

## Sicherheitsgrenzen

- dynamische Commit-Anzahl am Freeze
- Remote- und lokales Mirror-Backup
- objektgenaue Prüfung über die `git-filter-repo`-Commit-Map
  (`scripts/verify-history-rewrite.py`)
- `--force-with-lease` nur für `refs/heads/main`
- kein `git push --mirror`
- Abbruch bei neuem Remote-Tip, Tag, Release, Branch oder Pull Request

## Öffentlicher Audit (28. August 2026)

- **gitleaks 8.30.1**: Scan über alle 114 vom finalen Branch erreichbaren
  Commits sowie ein zweiter Lauf mit `--log-opts=--all` (117 Commits über alle
  Refs): **keine Secrets gefunden.**
- **Private Daten** (`/Users/`, `/private/tmp`, `/var/folders/`, Serial,
  Team ID, Apple ID, Issuer ID, Key ID): aktueller Stand und gesamte Historie
  geprüft; 1.248 eindeutige Treffer, **alle** False Positives durch
  „serial"/„Serial" in Serialisierungs-Code (z. B. `JSONSerialization`,
  „serialer writeQueue"). Keine echten Pfade, Hardwarekennungen oder
  Account-IDs.
- **Persönlicher Handle `leomcguire`** (Bestandteil der privaten
  Author-E-Mail): Die zwei verbleibenden GitHub-Links in
  `docs/archive/design_handoff_stasi/Stasi.dc.html` und `Stasi v2.dc.html`
  wurden vor dem Freeze auf `mm20261/stasi` umgestellt. Historische Nennungen
  in alten Commits (u. a. früherer `UpdateChecker.swift`, gelöschte
  `import/`-Dateien) werden **bewusst akzeptiert**: Es handelt sich um einen
  öffentlich bekannten GitHub-Handle, nicht um ein Secret. Die
  E-Mail-Bereinigung des Rewrites entfernt die direkte Verknüpfung zum
  privaten Postfach.
- **Interne Session-Pläne** (`docs/superpowers/`): aus dem finalen Baum
  entfernt (Commit `chore(audit): entferne interne Session-Pläne`). Sie
  enthielten reale lokale Pfade und den persönlichen Handle. Historische
  Kopien in alten Commits werden akzeptiert; sie enthalten keine Secrets.
- **Claude-/Anthropic-Textnennungen**: 68 Treffer im finalen Stand, alle
  harmlos – Wörterbuch-Beispielkorrekturen („cloud code" → „Claude Code"),
  Test-Fixtures und Code-Kommentare. Sie bleiben unberührt; nur die
  Co-Author-Trailer (112 Commits) werden vom Rewrite entfernt.
- **Große und binäre Objekte**: Größte Objekte sind App-Icons (PNG/ICNS),
  gebündelte Geist-Fonts mit OFL-Lizenzen und Quelltext. Keine `.p8`, `.p12`,
  Schlüsselbunddateien, Audioaufnahmen oder ZIP/DMG/PKG-Artefakte in der
  Historie.
- **Verifikation vor dem Audit**: 582 Tests bestanden (4 erwartete
  TCC-Skips), Release-Metadaten-Smoke-Test mit `STASI_VERSION=0.10.0` grün.

Echte Secrets stoppen den Ablauf; es wurden keine gefunden.
