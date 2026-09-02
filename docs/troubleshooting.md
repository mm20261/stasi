# Fehlerbehebung

Stasi benötigt Mikrofon-, Spracherkennungs- und Bedienungshilfen-Zugriff. Die
Bundle-ID lautet `app.stasi.macos`.

## Berechtigungen vollständig zurücksetzen

Beende Stasi und führe bei Bedarf die folgenden Befehle im Terminal aus:

```bash
tccutil reset Microphone app.stasi.macos
tccutil reset Accessibility app.stasi.macos
tccutil reset SpeechRecognition app.stasi.macos
```

Starte die App danach erneut und erteile die Berechtigungen über die angezeigten
macOS-Dialoge. Ein Reset entfernt bestehende Zustimmungen; er erteilt keine neuen.

## Hotkey reagiert nicht

Der globale Hotkey benötigt Bedienungshilfen-Zugriff. Entferne Stasi unter
**Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen** vollständig
aus der Liste, füge die aktuell gebaute beziehungsweise installierte App erneut hinzu
und starte sie neu. Das ist besonders nach einem Update, Zertifikatswechsel oder
einer Neusignierung wichtig, weil macOS alte Einträge trotz sichtbarem Schalter nicht
mehr der aktuellen Code-Signatur zuordnen kann.

Zur Eingrenzung kann Stasi ohne globalen Event-Tap gestartet werden:

```bash
STASI_NO_TAP=1 build/Stasi.app/Contents/MacOS/Stasi
```

Dieser Diagnosemodus deaktiviert Push-to-talk, Hands-free und die globalen
Zusatz-Shortcuts.

## Pill erscheint nicht

- Push-to-talk kürzer als 250 ms wird absichtlich still verworfen; halte die Taste
  etwas länger. Hands-free zeigt die Pill sofort.
- Prüfe, ob Mikrofon und Bedienungshilfen freigegeben sind und ob der Status in der
  App den Hotkey als bereit meldet.
- Vergewissere dich, dass die in den Einstellungen angezeigte Push-to-talk-Taste mit
  der tatsächlich gedrückten Taste übereinstimmt.
- Beim ersten Einsatz einer Sprache kann zunächst das lokale Sprachmodell vorbereitet
  werden.

## Text landet nicht in der Ziel-App

Fokussiere vor der Aufnahme ein beschreibbares Textfeld und prüfe den
Bedienungshilfen-Zugriff. Manche Ziel-Apps blockieren synthetische Tastaturereignisse.
Stasi kopiert den korrigierten Text nach jedem erfolgreichen Diktat zusätzlich in die
Zwischenablage; füge ihn in diesem Fall mit ⌘V ein.

## Erster Sprachwechsel dauert lange

macOS muss das lokale Modell einer Sprache beim ersten Wechsel gegebenenfalls laden
oder herunterladen. Lass Stasi geöffnet und warte, bis die Modellvorbereitung
abgeschlossen ist. Spätere Wechsel sind normalerweise schneller.

## Debug-Log

Das rotierende Laufzeitprotokoll liegt hier:

```text
~/Library/Application Support/Stasi/debug.log
```

Die vorherige Datei kann als `debug.log.1` daneben liegen. Teile nur den für das
Problem relevanten Ausschnitt und entferne vorher persönliche Diktatinhalte oder
andere vertrauliche Angaben.
