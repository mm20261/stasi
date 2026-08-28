# Transkriptbereinigung, öffentlicher Release und Autorenbereinigung

Datum: 28. August 2026

## Ziel

Stasi soll gesprochene Fehlstarts deutlich stärker lokal bereinigen und anschließend einfach an andere Personen verteilt werden können.

Die Installation soll nach einer einmaligen Homebrew-Installation mit diesem Befehl möglich sein:

```bash
brew install --cask mm20261/tap/stasi
```

Vor der öffentlichen Veröffentlichung werden die vorhandenen Claude-Co-Author-Trailer aus der vollständigen Git-Historie entfernt. Philipp Meder bleibt der einzige auf GitHub zugeordnete Autor.

## Bestätigte Entscheidungen

- Die gesamte erreichbare Git-Historie wird bereinigt.
- Claude- und Anthropic-Co-Author-Trailer werden entfernt.
- Author- und Committer-Name bleiben Philipp Meder.
- Author- und Committer-E-Mail werden für die öffentliche Historie auf `260910895+mm20261@users.noreply.github.com` vereinheitlicht.
- Zeitstempel, Dateien und Commit-Topologie bleiben erhalten.
- Die stärkere Transkriptbereinigung bleibt vollständig lokal und regelbasiert.
- Der unveränderte Rohtext bleibt im Verlauf gespeichert.
- Das Apple-On-Device-Sprachmodell wird nicht für einen generativen Komplett-Rewrite eingesetzt.
- Das Haupt-Repository darf nach einer öffentlichen Sicherheitsprüfung sichtbar werden.
- Ein Apple-Developer-Program-Zugang und eine Developer-ID-Signatur sind vorhanden.
- Die erste öffentliche Version unterstützt Apple Silicon und macOS 26.
- Releases werden als signiertes und notarisiertes ZIP veröffentlicht.
- Ein öffentliches Homebrew-Tap liefert den Ein-Befehl-Installationsweg.
- Ein DMG ist zunächst nicht erforderlich.

## Erfolgskriterien

### Git-Historie

- Alle beim Umschreiben erreichbaren Commits bleiben in derselben Reihenfolge erhalten.
- Die Ausgangsbasis umfasst 98 bestehende Commits; neue Umsetzungs-Commits kommen vor der Bereinigung hinzu.
- Der aktuelle Tree-Hash bleibt nach dem Umschreiben identisch.
- Kein erreichbarer Commit enthält danach einen `Co-Authored-By`-Trailer für Claude oder Anthropic.
- Alle erreichbaren Commits besitzen weiterhin Philipp Meder als Author und Committer.
- Ihre E-Mail ist ausschließlich `260910895+mm20261@users.noreply.github.com`.
- GitHub ordnet diese Adresse weiterhin dem Konto `mm20261` zu.
- Nur `main` wird auf GitHub überschrieben.
- Der Push schlägt fehl, wenn sich `origin/main` seit der letzten Prüfung verändert hat.
- Keine alten Tags, Release-Refs oder Remote-Branches halten die alte Historie erreichbar.

### Transkriptbereinigung

- Explizite Korrekturen wie „nein“, „ich meine“, „warte“ oder „Korrektur“ dürfen einen längeren ersten Versuch ersetzen.
- Markerlose wiederholte Satzanfänge werden innerhalb eines Satzes erkannt.
- Der spätere und vollständigere Versuch wird behalten.
- Über `.`, `!` oder `?` hinweg wird nichts entfernt.
- Offensichtlich getrennte oder vollständige Wiederholungen bleiben erhalten.
- Der Rohtext bleibt unverändert gespeichert.
- Der bereinigte Text wird weiterhin als `.selfCorrection` protokolliert.
- Ein zweiter Polishing-Durchlauf verändert das Ergebnis nicht weiter.

### Veröffentlichung

- Ein Tag im Format `vMAJOR.MINOR.PATCH` startet einen kontrollierten Release-Lauf.
- Der Release-Lauf testet, baut, signiert, notarisiert und prüft die App.
- Fehlende Release-Credentials führen zu einem Fehler und niemals zu einem scheinbar erfolgreichen Publish-Lauf.
- Das GitHub Release enthält ein notarisiertes `Stasi.zip` und eine SHA-256-Prüfsumme.
- Die App kennt den öffentlichen GitHub-Release-Endpunkt.
- Ein Homebrew-Cask installiert `Stasi.app` nach `/Applications`.
- Gatekeeper akzeptiert die veröffentlichte App ohne Quarantäne-Umgehung.
- README und Release-Dokumentation erklären Installation, Berechtigungen, Updates und Deinstallation.

## Nicht Teil dieser Runde

- Cloudbasierte Textbereinigung.
- Generativer Rewrite mit Apple Foundation Models.
- Automatische Spracherkennung pro Aufnahme.
- Bereinigung über vollständige Satzgrenzen hinweg.
- Intel- oder Universal-Binary-Unterstützung.
- Sparkle oder ein anderer selbstinstallierender Updater.
- DMG- oder PKG-Erzeugung.
- Automatisches Umgehen von Mikrofon-, Bedienungshilfen- oder Gatekeeper-Zustimmungen.
- Änderung der Bundle-ID `app.stasi.macos`.

## Architektur

### 1. Stärkere Selbstkorrektur im bestehenden Polisher

Die neue Logik bleibt in `Sources/Stasi/Core/SelfCorrectionResolver.swift`.

`TranscriptionEngine`, `AppState`, `TranscriptionRecord`, `TextInjector`, History-Schema und UI benötigen für die Kernfunktion keine neue Schnittstelle.

Der bestehende Ablauf bleibt:

1. Apple Speech liefert den finalen Rohtext.
2. `TranscriptPolisher` entfernt Zögerlaute und einfache Wiederholungen.
3. `SelfCorrectionResolver` löst explizite und markerlose Neustarts auf.
4. `TextTidy` bereinigt Leerraum und Interpunktion.
5. Die Wörterbuchkorrektur läuft weiter wie bisher.
6. Rohtext und bereinigter Text werden getrennt gespeichert.
7. Nur der bereinigte Text wird kopiert und eingefügt.

### 2. Explizite Korrekturen

Der vorhandene Markerweg wird erweitert.

Er darf nicht mehr nur fast identische Rahmen mit genau einer abweichenden Position erkennen. Er soll zusätzlich zwei Fälle abdecken:

- Ein identischer rechter Rahmen vervollständigt den links abgebrochenen Versuch.
- Der rechte Versuch ersetzt mehrere zusammenhängende Wörter innerhalb desselben wiederholten Rahmens.

Beispiele:

```text
Hallo, mein Name ist, nein, hallo, mein Name ist Philipp
→ Hallo, mein Name ist Philipp
```

```text
Wir treffen uns Montag um zehn, ich meine, wir treffen uns Dienstag um zwölf
→ Wir treffen uns Dienstag um zwölf
```

Starke Sicherheitsgrenzen bleiben erhalten:

- Keine Auflösung über Satzgrenzen.
- Keine alleinstehende Namenskorrektur ohne wiederholten Rahmen.
- Fragen bleiben geschützt.
- Negations- und Quantifizierungsänderungen bleiben geschützt, wenn kein eindeutiger wiederholter Rahmen vorliegt.
- Ein Marker ohne vollständigen zweiten Versuch löscht nichts.

### 3. Markerlose Neustarts

Nach der Markerauflösung sucht der Resolver innerhalb desselben Satzes nach einem wiederholten Anfang.

Die Erkennung verwendet normalisierte Wort-Tokens, behält aber die Originalbereiche für die Ausgabe und die `Edit`-Details.

Ein Kandidat wird nur entfernt, wenn alle Bedingungen erfüllt sind:

1. Zwei nahe Versuche besitzen einen gemeinsamen Anfang von mindestens drei Wörtern.
2. Die Wiederholung liegt in einem begrenzten Wortfenster.
3. Der zweite Versuch enthält eine Fortsetzung oder eine klarere Ersetzung.
4. Der erste Versuch beginnt am Satz- oder Klauselanfang.
5. Zwischen beiden Versuchen liegt keine Satzendmarke `.`, `!` oder `?`.
6. Der längste passende gemeinsame Anfang gewinnt.
7. Entfernte Bereiche überlappen sich nicht.
8. Der Resolver verarbeitet einen Bereich nur einmal.

Beispiele:

```text
Hallo, mein Name ist Peter, hallo, mein Name ist Philipp
→ Hallo, mein Name ist Philipp
```

```text
Wir treffen uns Montag, wir treffen uns Dienstag
→ Wir treffen uns Dienstag
```

```text
Sehr gut. Sehr gut.
→ Sehr gut. Sehr gut.
```

```text
Ich sage „Hallo, mein Name ist Philipp“ und wiederhole „Hallo, mein Name ist Philipp“.
→ bleibt unverändert
```

Die Suche erhält eine feste Obergrenze für Fenstergröße und Kandidatenzahl. Damit bleibt die Laufzeit auch bei langen Transkripten vorhersehbar.

### 4. Änderungsprotokoll und Wiederherstellung

Der Resolver liefert weiterhin strukturierte `Edit`-Einträge mit `removed` und `kept`.

`TranscriptPolisher` zählt die Änderung weiter als `.selfCorrection`. Vorhandene Badges und Detailansichten bleiben nutzbar.

Der unveränderte finale Speech-Text bleibt in `TranscriptionRecord.rawText`. Der bereinigte Text bleibt in `correctedText`.

Es gibt deshalb immer einen nachvollziehbaren Wiederherstellungspfad, auch wenn eine aggressive Regel im Einzelfall zu viel entfernt.

### 5. Versionsquelle

`scripts/make-app.sh` erhält eine kontrollierte Release-Version über `STASI_VERSION`.

Für lokale Builds bleibt ein dokumentierter Entwicklungswert möglich. Für einen Publish-Lauf gilt:

- Der Git-Tag besitzt das Format `vMAJOR.MINOR.PATCH`.
- Der Workflow leitet daraus `MAJOR.MINOR.PATCH` ab.
- Der Wert muss mit der in das App-Bundle geschriebenen Version übereinstimmen.
- Ungültige oder widersprüchliche Versionen stoppen den Lauf.

Die Bundle-ID bleibt konstant. Das stabilisiert macOS-Berechtigungen über Updates hinweg.

### 6. GitHub-Release-Workflow

`.github/workflows/release.yml` wird von einer reinen Vorbereitung zu einem echten Publish-Workflow erweitert.

Der Ablauf lautet:

1. Auslöser ist ein Release-Tag `v*` oder ein kontrollierter manueller Lauf mit derselben Versionsprüfung.
2. Tests und der vorhandene Paket-Smoke-Test laufen zuerst.
3. Die App wird für Apple Silicon im Release-Modus gebaut.
4. Die Developer-ID wird nur im geschützten GitHub-Environment `release` geladen.
5. Hardened Runtime und die bestehenden Mikrofon-Entitlements werden verwendet.
6. Das App-Bundle wird signiert.
7. Das ZIP wird an Apple zur Notarisierung gesendet.
8. Das Ticket wird an die App geheftet.
9. `codesign`, `stapler` und `spctl` prüfen das Ergebnis.
10. `Stasi.zip` und `Stasi.zip.sha256` werden als GitHub Release veröffentlicht.

Der finalen Publish-Stufe wird gezielt `contents: write` gegeben. Andere Jobs behalten `contents: read`.

Fehlende Signier- oder Notarisierungsdaten sind in einem Publish-Lauf ein harter Fehler. Ein erfolgreicher Skip ist nicht zulässig.

Secrets werden ausschließlich über GitHub Environments und GitHub Secrets bereitgestellt. Zertifikate, Passwörter und API-Schlüssel gelangen nie in Dateien, Logs oder Commit-Nachrichten.

### 7. Öffentlicher Update-Endpunkt

Der Release-Build setzt:

```text
STASI_RELEASE_API_URL=https://api.github.com/repos/mm20261/stasi/releases/latest
```

`UpdateChecker` zeigt dadurch auf den echten öffentlichen Release-Kanal.

Die App prüft nur, ob eine neue Version vorhanden ist. Die Installation des Updates übernimmt Homebrew oder ein manueller Download. Ein stiller Selbst-Updater wird nicht ergänzt.

### 8. Homebrew-Tap

Ein separates öffentliches Repository `mm20261/homebrew-tap` enthält:

```text
Casks/stasi.rb
```

Der Cask enthält:

- Release-Version.
- SHA-256 des veröffentlichten ZIPs.
- URL zum GitHub-Release-Asset.
- `app "Stasi.app"`.
- Mindestanforderung macOS 26.
- Apple-Silicon-Beschränkung für die erste Version.
- Sinnvolle `zap`-Einträge für Einstellungen und lokale App-Daten.

Installation:

```bash
brew install --cask mm20261/tap/stasi
```

Update:

```bash
brew upgrade --cask stasi
```

Deinstallation:

```bash
brew uninstall --cask stasi
```

Der erste Cask kann zusammen mit dem ersten Release veröffentlicht werden. Die automatische Aktualisierung des Casks bei späteren Releases ist eine optionale kleine Folgestufe; der erste Release darf den Cask kontrolliert manuell aktualisieren.

### 9. Öffentliche Repository-Prüfung

Bevor die Sichtbarkeit geändert wird, erfolgt eine vollständige Prüfung des gesamten erreichbaren Repository-Inhalts auf:

- Secrets und Zugangsdaten.
- Persönliche Daten.
- interne Pfade und Hardwaredaten.
- nicht veröffentlichbare Dokumente.
- Lizenzvollständigkeit.
- binäre oder große lokale Artefakte.
- verbleibende Claude- oder Anthropic-Nennungen, getrennt nach Git-Attribution und normalem Dokumentinhalt.

Normale historische Texte mit Claude-Erwähnungen beeinflussen die Contributor-Zuordnung nicht. Sie werden nur entfernt, wenn sie intern, unnötig oder für die öffentliche Dokumentation ungeeignet sind.

Die Änderung der Repository-Sichtbarkeit erfolgt erst nach erfolgreicher Prüfung und nach der bereinigten Historie.

### 10. Git-Historienbereinigung

Die Historienbereinigung ist der letzte lokale Schritt vor öffentlichem Release und Sichtbarkeitswechsel.

Ausgangslage:

- 98 erreichbare Commits auf `origin/main`.
- Alle 98 mit Philipp Meder als Author und Committer.
- 93 mit Claude-Co-Author-Trailer.
- Keine Remote-Tags, Releases oder Pull Requests.
- Nur der Remote-Branch `main`.

Der Ablauf:

1. Das bestehende Arbeitsrepository bleibt als Rückfallebene erhalten.
2. Ein unveränderter Remote-Mirror wird als zusätzliches Backup erstellt.
3. Ein zweiter Mirror wird für `git filter-repo` verwendet.
4. Eine Message-Callback-Regel entfernt ausschließlich `Co-Authored-By`-Trailer, deren Name oder E-Mail Claude beziehungsweise Anthropic zugeordnet ist.
5. Author- und Committer-E-Mail werden auf `260910895+mm20261@users.noreply.github.com` gesetzt; ihre Namen bleiben `Philipp Meder`.
6. Commit-Anzahl, Tip-Tree, Author, Committer und Repository-Integrität werden geprüft.
7. Remote-Branches, Tags, Releases und Pull Requests werden unmittelbar vor dem Push erneut geprüft.
8. Nur `refs/heads/main` wird mit einer expliziten `--force-with-lease`-Erwartung auf den vorher geprüften Remote-Tip gepusht.
9. Der Push wird abgebrochen, wenn sich `origin/main` verändert hat.
10. Nach erfolgreichem Push wird ein frischer Arbeitsclone angelegt.
11. Im frischen Clone wird `user.email` auf die GitHub-`noreply`-Adresse gesetzt.
12. Alte lokale Branches und Mirrors werden nicht versehentlich gepusht.

Da der Root-Commit einen Trailer enthält, ändern sich alle Commit-Hashes. Datei-Snapshots und der aktuelle Tree bleiben gleich.

## Fehlerbehandlung

### Transkript

- Ohne eindeutigen zweiten Versuch wird nichts gelöscht.
- Bei überlappenden Kandidaten gewinnt nur der längste sichere Kandidat.
- Ein interner Erkennungsfehler darf keine leere Ausgabe erzeugen.
- Der Rohtext bleibt unabhängig vom Ergebnis erhalten.

### Release

- Fehlende Credentials stoppen den Publish-Lauf.
- Fehlgeschlagene Tests, Signierung, Notarisierung oder Gatekeeper-Prüfung verhindern das GitHub Release.
- Ein Release wird erst erstellt, wenn das endgültige ZIP vollständig geprüft ist.
- Eine fehlerhafte Cask-Prüfsumme verhindert die Homebrew-Installation.

### Git-Historie

- Das Umschreiben geschieht ausschließlich in einem separaten Mirror.
- Ein veränderter Remote-Tip verhindert den Force-Push.
- Abweichende Commit-Anzahl oder ein abweichender Tree-Hash verhindern den Push.
- Neue Tags, Releases oder Pull Requests stoppen den Ablauf für eine erneute Bewertung.
- Es wird niemals `git push --mirror` verwendet.

## Tests und Prüfungen

### SelfCorrectionResolver

Positive Regressionstests:

- Identischer Rahmen plus Fortsetzung nach starkem Marker.
- Mehrwort-Ersetzung nach schwachem Marker mit wiederholtem Rahmen.
- Markerloser Neustart mit drei oder mehr gemeinsamen Wörtern.
- Deutsche und englische Varianten.
- Kommas und Gedankenstriche zwischen den Versuchen.
- Zwei aufeinanderfolgende Neustarts enden beim letzten vollständigen Versuch.
- `Edit.removed` und `Edit.kept` sind korrekt.

Negative Regressionstests:

- Vollständige Wiederholung ohne längeren zweiten Versuch.
- Zwei getrennte Sätze.
- Fragen.
- Zitate und ausdrücklich angekündigte Wiederholungen.
- Alle bestehenden Negations-, Quantifizierungs- und Namensschutzfälle.
- Nur ein oder zwei unsichere gemeinsame Wörter.

Eigenschaften:

- `polish(polish(text)) == polish(text)`.
- Nichtleerer Rohtext erzeugt nicht durch die neue Regel allein eine leere Ausgabe.
- Entfernte Bereiche überlappen sich nicht.
- Die Laufzeit bleibt durch feste Fenster begrenzt.

### TranscriptPolisher und AppState

- Nachbearbeitungsstufe STANDARD bereinigt den Neustart.
- Nachbearbeitungsstufe AUS lässt den Rohtext unverändert.
- `selfCorrectionsResolved` und Badge bleiben korrekt.
- History speichert Rohtext und bereinigten Text getrennt.
- Zwischenablage und Injector erhalten denselben bereinigten Text.
- Ein Injection-Fehler verändert die gespeicherten Texte nicht.

### Release

- Tag- und App-Version stimmen überein.
- Ein ungültiger Tag stoppt den Workflow.
- Fehlende Secrets stoppen einen Publish-Lauf.
- Das ZIP enthält App-Ressourcen, Lizenzdateien und die erwartete Architektur.
- Signatur, Hardened Runtime, Notarisierung und Gatekeeper-Prüfung bestehen.
- SHA-256-Datei entspricht dem veröffentlichten ZIP.
- Homebrew kann den Cask prüfen und installieren.
- Die gebaute App enthält den öffentlichen Update-Endpunkt.

### Abschlussprüfung

Vor der Veröffentlichung laufen mindestens:

```bash
swift test
./scripts/make-app.sh
./scripts/smoke-test-app.sh
```

Zusätzlich werden Release-Workflow, Cask, Repository-Sichtbarkeit und GitHub Release nach der Veröffentlichung erneut geprüft.

## Reihenfolge der Umsetzung

1. Regressionstests für explizite und markerlose Neustarts schreiben.
2. `SelfCorrectionResolver` erweitern.
3. Polisher- und AppState-Integration prüfen.
4. Versionsquelle in `scripts/make-app.sh` kontrollierbar machen.
5. Release-Workflow für Tag, Signierung, Notarisierung und GitHub Release erweitern.
6. README und `docs/release.md` aktualisieren.
7. Öffentlichen Homebrew-Cask vorbereiten.
8. Gesamte lokale Tests und Paketprüfung ausführen.
9. Öffentliche Repository-Prüfung durchführen und Befunde bereinigen.
10. Alle lokalen Änderungen auf `main` integrieren.
11. Vollständige Git-Historie in separaten Mirrors bereinigen und verifizieren.
12. Bereinigtes `main` geschützt force-pushen.
13. Frischen Clone anlegen und GitHub-Attribution erneut prüfen.
14. Repository öffentlich schalten.
15. GitHub-Environment und Secrets einrichten.
16. Ersten Release-Tag nach letzter Sichtprüfung erstellen und pushen.
17. Release-Artefakte und Gatekeeper-Ergebnis prüfen.
18. `mm20261/homebrew-tap` veröffentlichen und Installation testen.

## Sicherheitsgrenzen für äußere Aktionen

Die folgenden Schritte sind einzeln sichtbar und werden nur nach unmittelbar vorheriger Zustandsprüfung ausgeführt:

- Force-Push von `main`.
- Änderung des Repositorys von privat zu öffentlich.
- Anlage oder Änderung des öffentlichen Homebrew-Taps.
- Push des ersten Release-Tags.
- Veröffentlichung des ersten GitHub Releases.

Zugangsdaten werden nicht im Chat, in Dateien oder in Befehlsargumenten gespeichert. Interaktive Geheimnisse werden über GitHub Secrets beziehungsweise das geschützte Environment `release` eingerichtet.
