# Stabilisierung und GitHub-Release

Datum: 27. August 2026

## Ziel

Stasi soll vor einer öffentlichen GitHub-Veröffentlichung stabil, erweiterbar und rechtlich vollständig sein.

Die bestehende App und ihre Bedienung bleiben erhalten. Bestätigte Fehler werden gezielt behoben. Ein vollständiger Neubau des Audio-Systems ist ausdrücklich nicht Teil dieser Runde.

## Erfolgskriterien

- Eine mit `scripts/make-app.sh` gebaute App startet auf einem fremden Mac ohne lokalen SwiftPM-Buildpfad.
- Eine beschädigte Historie wird niemals still als leer behandelt oder überschrieben.
- Jede Diktat-Session besitzt ihre eigene Audio-Capture-Instanz.
- Ein neuer Aufnahmestart ist erst möglich, wenn die vorherige Session vollständig abgebaut wurde.
- Doppelstarts, Converter-Fehler und Audioformatfehler werden sichtbar gemeldet.
- Mehrkanalgeräte führen weder zu Speicherzugriffen außerhalb des Puffers noch zu ungeklärten Formatfehlern.
- Bluetooth-Mikrofone werden nicht automatisch gewählt, wenn eine geeignete lokale Alternative vorhanden ist.
- Speech-Pufferüberläufe werden erkannt und führen nicht zu einer scheinbar erfolgreichen, unvollständigen Transkription.
- Text wird nur in die App eingefügt, die beim Start der Aufnahme als Ziel gespeichert wurde.
- Seitenspezifische Modifier-Hotkeys und die Hotkey-Erfassung funktionieren beim Loslassen korrekt.
- Aufnahme-Sounds sind über eine testbare Schnittstelle gekapselt und lassen sich später austauschen.
- MIT-Lizenz, Geist-OFL-Lizenz, README und Release-Dateien sind für ein öffentliches Repository vollständig.
- Alle neuen Fehlerpfade besitzen Regressionstests.

## Nicht Teil dieser Runde

- Vollständige Migration des Verlaufs auf SQLite oder SwiftData.
- Vollständiger Ersatz von `AppState` durch einen neuen Aufnahme-Koordinator.
- Neue Soundauswahl in den Einstellungen.
- Veröffentlichung eines GitHub-Releases.
- Developer-ID-Zertifikat oder Apple-Notarisierung ohne vorhandene Zugangsdaten.
- Öffentlicher Push zu GitHub.

## Architektur

### 1. Session-eigene Audioaufnahme

`AppState` erhält keine dauerhaft wiederverwendete `AudioCapturing`-Instanz mehr. Stattdessen wird eine Factory injiziert, die für jede `DictationSession` ein neues Capture-Objekt erzeugt.

Die Session besitzt dieses Objekt bis zum vollständig abgeschlossenen Teardown. Ein neuer Start wird während des Teardowns abgelehnt oder wartet kontrolliert. `AudioCapture.start` meldet einen Doppelstart als Fehler, statt erfolgreich zurückzukehren.

Damit kann verspätetes Aufräumen einer alten Session keine neue Aufnahme mehr stoppen.

### 2. Sicherer Aufnahmeablauf

Der Zustand `.recording`, der Timer und der Startton beginnen erst, nachdem Berechtigungen, Speech-Modell und Audioaufnahme bereit sind.

Der Stop-Ablauf lautet:

1. Audioeingang stoppen.
2. Bereits angenommene Audioblöcke kontrolliert abarbeiten.
3. Stop-Sound abspielen.
4. Speech finalisieren.
5. Ergebnis speichern und gegebenenfalls einfügen.

Fehler beim Rendern, Konvertieren oder Schreiben werden an die Session gemeldet. Die UI darf bei einem solchen Fehler nicht weiter eine laufende oder erfolgreiche Aufnahme anzeigen.

### 3. Audioformate und Geräte

Die Kanalzahl wird aus `AudioBufferList` mit korrekter variabler Speichergröße gelesen.

Speech-Eingabe wird auf ein unterstütztes Mono- oder Stereoformat begrenzt. Wenn das native Geräteformat nicht direkt verwendet werden kann, muss ein gültiger `AVAudioConverter` entstehen. Ein fehlender Converter ist ein Fehler und niemals gleichbedeutend mit „keine Konvertierung nötig“.

Der Mikrofonkatalog erfasst den Transporttyp. Bluetooth-Eingänge werden nicht automatisch als Standard gewählt, wenn ein eingebautes oder kabelgebundenes Mikrofon verfügbar ist. Eine ausdrücklich gespeicherte Nutzerauswahl bleibt respektiert, sofern sie unterstützt wird.

### 4. Kontrollierter Speech-Puffer

Der Speech-Puffer bleibt begrenzt, damit der Speicher nicht unkontrolliert wächst. Das Ergebnis jedes `yield` wird ausgewertet.

Bei einem Überlauf wird die Session als unvollständig markiert. Die App zeigt einen verständlichen Fehler und injiziert kein möglicherweise beschädigtes Transkript. Die vollständige WAV-Datei bleibt zur Wiederherstellung erhalten.

Die bestehende Reihenfolge der verbliebenen Audioblöcke bleibt erhalten.

### 5. Sichere Historie und Wörterbuch

`HistoryStore` unterscheidet zwischen:

- Datei fehlt.
- Datei ist gültig.
- Datei kann nicht gelesen oder dekodiert werden.

Bei einem Fehler wird die Originaldatei nicht überschrieben. Vor einer weiteren Speicherung wird eine datierte Sicherung angelegt oder der Schreibvorgang blockiert. Der Fehler wird an die UI weitergegeben.

`DictionaryStore` startet den Datei-Watcher auch dann, wenn beim Start bereits eine gültige Wörterbuchdatei vorhanden ist.

Eine spätere Datenbankmigration bleibt möglich, ist aber nicht Voraussetzung für diese Reparatur.

### 6. Hotkeys und Ziel-App

Seitenspezifische Modifier werden anhand ihres tatsächlichen physischen Zustands beendet. Ein weiterhin gedrückter Modifier derselben Familie darf das Loslassen der konfigurierten Seite nicht verdecken.

Die Hotkey-Erfassung behält eine vollständig erkannte Kombination, wenn anschließend nur ein Modifier losgelassen wird.

Vor der Texteinfügung werden Bundle-ID und Prozess der aktuell fokussierten App mit dem beim Aufnahmebeginn gespeicherten Ziel verglichen. Bei Abweichung wird nicht automatisch in die neue App geschrieben. Das Transkript bleibt in Verlauf und Zwischenablage verfügbar.

### 7. SoundFeedback

Sounds werden über eine kleine Schnittstelle gekapselt:

```swift
protocol SoundFeedback {
    func play(_ event: SoundEvent)
}

enum SoundEvent {
    case recordingStarted
    case recordingStopped
    case processingCompleted
    case failed
}
```

Die Produktion verwendet zunächst die vorhandenen Systemsounds. Tests verwenden ein Fake und prüfen Reihenfolge sowie Anzahl der Ereignisse.

Spätere eigene Dateien können in einer neuen Implementierung geladen werden, ohne `AppState` oder den Aufnahmeablauf erneut umzubauen.

### 8. Release-Paket

`scripts/make-app.sh` kopiert das von SwiftPM erzeugte `Stasi_Stasi.bundle` an den von `Bundle.module` erwarteten Ort innerhalb der App.

Ein Clean-Room-Smoke-Test baut die App, entfernt den lokalen `.build`-Pfad aus der Gleichung und prüft mindestens:

- Ressourcenbundle vorhanden.
- Geist-Schriften vorhanden.
- App startet bis zum normalen Prozesszustand.

Entwicklungssignierung und öffentlicher Release werden getrennt. Das Skript darf lokal weiterhin ad hoc signieren. Eine dokumentierte CI-Strecke für Developer ID, Hardened Runtime und Notarisierung wird vorbereitet, aber ohne Zugangsdaten nicht ausgeführt.

### 9. GitHub-Hygiene

- Projektlizenz: MIT.
- Vollständiger OFL-1.1-Text für Geist wird mit Quellcode und App-Ressourcen verteilt.
- Eine einzige kanonische Icon-Quelle bleibt im Repository. Abgeleitete Größen und `.icns` werden beim Build erzeugt oder eindeutig als Release-Artefakt behandelt.
- Der Update-Endpunkt wird aus einer zentralen Release-Konfiguration gelesen. Solange kein echtes öffentliches Repository feststeht, zeigt die UI keinen grünen Erfolgszustand für eine fehlgeschlagene Prüfung.
- README-Testzahlen werden nicht mehr als schnell veraltende feste Zahl dargestellt.
- Testbefehle verwenden keine fest codierte ARM-Buildstruktur.
- Persönliche Hardwaredaten werden aus `AGENTS.md` entfernt.
- Es findet kein automatischer öffentlicher Push statt.

### 10. Git-Historie

Die vorhandene Commit-E-Mail soll vor dem öffentlichen Push durch eine neutrale Adresse ersetzt werden.

Dieser Schritt erfolgt erst nach Abschluss und Verifikation aller Codeänderungen. Vor dem Umschreiben wird der genaue Ersatzwert bestätigt. Das Umschreiben verändert Commit-IDs und benötigt deshalb eine eigene Sicherung und eine letzte ausdrückliche Bestätigung.

## Fehlerbehandlung

Fehler werden nicht mehr still in Erfolg umgewandelt.

Für Nutzende gelten diese Regeln:

- Eine beschädigte Historie wird gemeldet und geschützt.
- Ein Speech-Pufferüberlauf verhindert automatische Einfügung.
- Ein Ziel-App-Wechsel verhindert Einfügung in die falsche App.
- Audioformat- und Gerätefehler beenden die Session geordnet.
- Eine WAV-Datei wird nur als gültiger Wiederherstellungspfad angezeigt, wenn sie tatsächlich fertig geschrieben wurde.

Interne Fehlertexte dürfen technische Details enthalten. Die sichtbare Meldung bleibt kurz und handlungsorientiert.

## Tests

Jedes Paket beginnt mit mindestens einem fehlschlagenden Regressionstest.

Erforderliche Testgruppen:

- Beschädigte, fehlende und gültige `history.json`.
- Externe Wörterbuchänderung direkt nach Neustart.
- Doppelstart und schneller Start nach Kurztipp.
- Alte Session kann neue Session nicht stoppen.
- Speech-Pufferüberlauf.
- Drei oder mehr Audiokanäle und Mehrpuffer-`AudioBufferList`.
- Fehlender `AVAudioConverter`.
- Bluetooth-Default mit lokaler Alternative.
- Seitenspezifisches Modifier-Loslassen.
- Hotkey-Erfassung nach Modifier-Release.
- Ziel-App-Wechsel vor Einfügung.
- Timer beginnt erst nach erfolgreichem Audio-Start.
- Sound-Reihenfolge bei Start, Stop und Fehler.
- Gepackte App enthält Ressourcenbundle und Lizenzdateien.

Nach jedem Paket laufen die betroffenen Tests. Vor Abschluss laufen die gesamte Testsuite, der App-Build und der Paket-Smoke-Test.

## Umsetzung und Commits

Die Arbeit wird in kleinen, thematischen Commits ausgeführt:

1. Design und Regressionstests für Datensicherheit.
2. Historie und Wörterbuch reparieren.
3. Audio-Lifecycle und session-eigene Capture-Instanzen.
4. Audioformate, Geräte und Speech-Puffer.
5. Hotkeys, Ziel-App und echte Aufnahmedauer.
6. SoundFeedback.
7. Ressourcenbundle und Release-Smoke-Test.
8. Lizenzen, Icons, README und Update-Konfiguration.
9. Abschlussprüfung und gegebenenfalls kleine Korrekturen.
10. Git-Historie separat nach letzter Bestätigung.

Jeder Commit muss eigenständig bauen und seine zugehörigen Tests bestehen.
