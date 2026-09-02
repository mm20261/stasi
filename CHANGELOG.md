# Änderungsprotokoll

Alle bemerkenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.
Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
und das Projekt verwendet [Semantic Versioning](https://semver.org/lang/de/).

## [Unreleased]

### Hinzugefügt

- Deutsche und englische Oberfläche mit Systemsprachen-Automatik und manueller
  Auswahl in den Einstellungen.

### Behoben

- Satzanfang-Großschreibung überschrieb Wörterbuch-Ziele (macOS → MacOS) und
  griff nach Abkürzungen wie „z.B.“; deutsche Doppelwörter („das das“), das Adverb
  „eh“ und satzinitiale „Also,“/„Actually,“ wurden fälschlich entfernt; markerlose
  Selbstkorrektur ignorierte Negationen.
- Kaputte `dictionary.json` wurde beim nächsten Speichern überschrieben, ein defekter
  Datensatz machte die ganze Historie unsichtbar, eine kurz fehlende Datei setzte das
  Wörterbuch auf die Beispiel-Einträge zurück. Jetzt Schreibschutz, elementweises
  Laden, `.corrupt`-Sicherung, Schema-Version 1 und Aufräumen verwaister Audiodateien.
- Modell-Download lief in den 15-s-Watchdog („Bitte Stasi neu starten“); Einfügen
  ohne Watchdog; Tap-Neuinstallation während der Aufnahme verlor das Loslassen;
  Startton konnte die Aufnahme ewig blockieren; Update-Prüfung verstand `v0.10` nicht.
- Aufnahme-Pill lag unter anderen Fenstern und blieb beim Monitorwechsel stehen.
- Aufnahme startete erst nach dem kompletten Startton (≈ 760 ms statt 75 ms), Text wurde
  erst nach dem kompletten Stoppton (1,6 s) eingefügt. Beide Töne laufen jetzt parallel.

### Geändert

- Nachbearbeitung, Auto-gelernt und Historien-Schreiben laufen nicht mehr auf dem
  Hauptthread; Regelsätze und Regexe werden einmal kompiliert; Leerlauf-Poll schreibt
  keine Observable-Felder mehr.
- Historien- und Wörterbuchlisten laden lazy; Accessibility-Labels für Icon-Buttons;
  Kontrast kleiner Beschriftungen auf volle Deckkraft.
- Aufbewahrung und 7/30-Tage-Filter rechnen in Kalendertagen statt in 86 400 s.

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
