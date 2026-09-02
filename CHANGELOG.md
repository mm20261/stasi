# Änderungsprotokoll

Alle bemerkenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.
Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
und das Projekt verwendet [Semantic Versioning](https://semver.org/lang/de/).

## [Unreleased]

## [0.10.0] - unveröffentlicht

### Hinzugefügt

- Vollständig lokale Diktierpipeline für Deutsch und Englisch mit frei belegbarem
  Push-to-talk, Umschaltmodus und konfigurierbarem Hands-free-Modifikator-Doppeltipp.
- Regelbasierte Nachbearbeitung für Zögerlaute, Stotterer, Selbstkorrekturen,
  Diskursfüller und Text-Hygiene.
- Wörterbuch mit Engine-Biasing, garantiertem Korrekturpass und Vorschlägen unter
  „Auto-gelernt“.
- Persistente Protokolle mit Suche, Filtern, Wiedergabe, Rohtext, Export,
  Aufbewahrungsregeln und vollständigem Markdown-Export.
- Dashboard, Insights, Streak-Heatmap, App-Nutzung, Onboarding und anpassbare
  Akzentfarben im v3-Design.
- Mikrofon-Auswahl, globale Kurzbefehle für das letzte Protokoll und manuelle
  Update-Prüfung über die GitHub-Releases-API.
- Aufnahme-Pill mit Pegelanzeige und Live-Transkript sowie verzögerter,
  bewegungsreduzierter Verarbeitungsanzeige.
- Fail-closed Release-Workflow für Tests, Developer-ID-Signierung, Notarisierung,
  Stapling, Prüfsumme und GitHub-Release-Assets.

### Geändert

- Kurze Push-to-talk-Tipps unter 250 ms werden still verworfen; Fehler- und
  Warnhinweise bleiben erhalten.
- Der korrigierte Text wird zusätzlich automatisch in die Zwischenablage kopiert.

[Unreleased]: https://github.com/mm20261/stasi/compare/v0.10.0...HEAD
[0.10.0]: https://github.com/mm20261/stasi/releases/tag/v0.10.0
