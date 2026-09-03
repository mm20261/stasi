# Fehlerbehebung

Stasi benötigt Mikrofon-, Spracherkennungs- und Bedienungshilfen-Zugriff. Die
Bundle-ID lautet `app.stasi.macos`.

## App lässt sich nicht öffnen (Gatekeeper)

Der GitHub-Release ist nicht notarisiert. Das heruntergeladene ZIP trägt deshalb ein
Quarantäne-Attribut, und macOS blockiert den ersten Start mit dem Hinweis, dass Apple
die App nicht überprüfen kann.

1. `Stasi.app` nach `/Applications` ziehen und einmal versuchen, die App zu öffnen.
2. **Systemeinstellungen → Datenschutz & Sicherheit** öffnen.
3. Unten bei der blockierten App **Trotzdem öffnen** wählen und den Start bestätigen.

Rechtsklick → Öffnen reicht seit macOS 15 nicht mehr. Alternativ kann das
Quarantäne-Attribut im Terminal entfernt werden:

```bash
xattr -dr com.apple.quarantine /Applications/Stasi.app
```

Bei einer Homebrew-Installation entfernt der Cask die Quarantäne selbst. Falls die
Blockade trotzdem erscheint:

```bash
xattr -dr com.apple.quarantine /Applications/Stasi.app
```

Die App wurde nicht von Apple geprüft. Wer die Ausnahme nicht setzen möchte, kann
den offenen Quellcode selbst bauen.

## Nach einem Update fragt macOS die Rechte erneut

Die öffentlichen Builds sind nur ad-hoc signiert und besitzen deshalb keine stabile
Apple-Team-Identität. macOS fragt nach jedem Update die Berechtigungen für Mikrofon
und Bedienungshilfen erneut ab.

Entferne bei Bedarf den alten Stasi-Eintrag unter **Systemeinstellungen → Datenschutz
& Sicherheit → Bedienungshilfen**, füge die aktuell installierte App erneut hinzu und
starte sie neu. Falls der alte Zustand bestehen bleibt, beende Stasi und setze beide
Berechtigungen im Terminal zurück:

```bash
tccutil reset Accessibility app.stasi.macos
tccutil reset Microphone app.stasi.macos
```

Starte Stasi danach erneut und erteile beide Berechtigungen über die macOS-Dialoge.
Die Reset-Befehle erteilen keine Rechte, sondern entfernen nur die bisherigen
Zuordnungen.

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
