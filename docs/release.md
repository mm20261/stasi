# Release-Ablauf

Diese Anleitung beschreibt den aktuellen Vertrag für veröffentlichte, mit Developer
ID signierte und von Apple notarisierte Builds. Lokale Entwicklungssignaturen sind
nicht für die öffentliche Verteilung bestimmt.

## Lokaler Übergabestand vom 28. August 2026

Dieser Abschnitt ist eine Übergabe für den nächsten Agenten. Er wird vor der finalen
öffentlichen Veröffentlichung entfernt oder in einen abgeschlossenen Release-Befund
umgewandelt.

- Lokaler Branch: `worktree-transcript-cleanup-impl`
- Geprüfter Stand vor diesem Übergabe-Commit: `b7af044`
- Remote `main`: `5a5224a`
- Lokale Commits vor Remote `main`: 16
- GitHub-Zustand: `PRIVATE`, Default-Branch `main`, keine Tags, keine Releases, nur
  Remote-Branch `main`
- Es wurde nichts gepusht, veröffentlicht oder öffentlich geschaltet.

Lokal fertig und reviewt:

- stärkere regelbasierte Neustart- und Selbstkorrekturbereinigung,
- originalgetreue Auditwerte sowie erhaltener Rohtext,
- kontrollierte Bundle-Version über `STASI_VERSION`,
- Bundle-, Update-Endpunkt- und Architekturprüfungen,
- Tag-/Verify-/Publish-Workflow mit fail-closed Secrets,
- Developer-ID-, Notarisierungs-, ZIP-, SHA- und Release-Prüfkette,
- README und diese Release-Dokumentation.

Verifikation auf `b7af044`:

```text
582 Tests
4 erwartete TCC-Skips
0 Fehler
Release-Metadaten-Smoke vollständig grün
Finaler Opus-Review: keine Critical- oder Important-Findings
```

Bewusst offen:

- `actionlint` wurde auf ausdrücklichen Nutzerwunsch nicht installiert. YAML,
  Expressions, Outputs, `needs`, Permissions, Trigger und Job-Gates wurden stattdessen
  mit Ruby, `bash -n`, statischen Scans und Opus geprüft.
- Developer-ID-Signierung, Apple-Notarisierung, Stapling, Gatekeeper des frisch
  heruntergeladenen ZIPs und `gh release create` benötigen den autorisierten
  GitHub-Lauf.
- Deferred Minor: Tag-Push und manueller Main-Dispatch desselben Tags verwenden
  verschiedene Concurrency-Gruppen und können parallel bis zur Release-Erstellung
  laufen.
- Deferred Minor: Der Diagnosebefehl `mkdir release-check` ist bei Wiederholung nicht
  idempotent.

Nächster Agent:

1. `docs/superpowers/specs/2026-08-28-transkript-release-und-autorenbereinigung-design.md`
   lesen.
2. Die drei Pläne unter `docs/superpowers/plans/2026-08-28-*` lesen.
3. Mit `docs/superpowers/plans/2026-08-28-historie-und-veroeffentlichung.md`
   fortfahren.
4. Vor Force-Push, Sichtbarkeitswechsel, Secret-Einrichtung, Tag-Push, Release und
   Homebrew-Tap jeweils erneut eine ausdrückliche Nutzerfreigabe einholen.
5. Zuerst den vollständigen öffentlichen Audit ausführen. Bei einem historischen echten
   Secret stoppen, rotieren und einen separaten Inhaltsrewrite planen.

## Release-Vertrag

- Tag: `vMAJOR.MINOR.PATCH`
- Bundle: `MAJOR.MINOR.PATCH`
- Release-Endpunkt: `https://api.github.com/repos/mm20261/stasi/releases/latest`
- Runner: `macos-26`, erste Veröffentlichung nur `arm64`
- Verify-Job: ohne Release-Secrets
- Publish-Job: Environment `release`, `contents: write`
- Fehlende Secrets: Fehler, kein Skip
- Assets: `Stasi.zip`, `Stasi.zip.sha256`

Beispiel: Der Tag `v0.10.0` erzeugt ein Bundle mit
`CFBundleShortVersionString=0.10.0` und `CFBundleVersion=0.10.0`. Die Release-App
enthält den oben genannten Update-Endpunkt; die Architektur des App-Binärprogramms
muss exakt `arm64` sein.

## Automatischer Tag-, Verify- und Publish-Ablauf

Der Workflow `.github/workflows/release.yml` startet entweder beim Push eines
Release-Tags `v*` oder kontrolliert manuell vom geschützten Branch `main`. Beim
manuellen Start wird ein bereits vorhandener Tag im Format `vMAJOR.MINOR.PATCH`
als `release_tag` angegeben. Beide Pfade lösen den Tag auf einen exakten Commit auf;
bei einem Tag-Event muss dieser Commit mit dem Event-Commit übereinstimmen.

Der Job `verify` läuft mit `contents: read` und ohne Environment oder Release-Secrets.
Er checkt den aufgelösten Commit detached aus, führt die vollständige Testsuite aus,
baut die App mit der aus dem Tag abgeleiteten Version und dem Release-Endpunkt und
führt den Smoke-Test mit der erwarteten Architektur `arm64` aus.

Nur nach erfolgreichem `verify` erreicht der Lauf den Job `publish`. Dieser Job:

1. verwendet das geschützte Environment `release` und nur dort `contents: write`,
2. checkt erneut exakt den zuvor verifizierten Commit aus,
3. baut mit derselben Version und demselben Update-Endpunkt ein unsigned Bundle,
4. validiert Bundle-Version, Update-Endpunkt und `arm64`,
5. signiert mit Developer ID und Hardened Runtime, notarisiert und stapelt das Ticket,
6. prüft Signatur, Gatekeeper, Inhalte und Architektur des finalen Archivs,
7. erzeugt und verifiziert die SHA-256-Prüfsumme und
8. veröffentlicht exakt `Stasi.zip` und `Stasi.zip.sha256` am bestehenden, nochmals
   verifizierten Release-Tag.

Der Workflow verwendet keine Marketplace-Actions. Git-Zugriffe laufen mit einem
temporären `GIT_ASKPASS`-Skript; temporäre Schlüssel-, Zertifikats- und
Schlüsselbunddateien werden auch im Fehlerfall entfernt.

## GitHub-Environment und Tag-Schutz

Das Environment `release` besitzt den Required Reviewer `mm20261`. Für die
ausdrücklich gewählte Solo-Freigabe ist `prevent_self_review: false` gesetzt:
`mm20261` darf den eigenen Deployment-Lauf freigeben. Die Solo-Freigabe benötigt
keine zweite Person; Selbstfreigabe bleibt zulässig.

Zulässige Deploymentquellen sind ausschließlich der geschützte Branch `main` für
kontrollierte manuelle Läufe und eng begrenzte Release-Tags `v*`. Eine
Branch-Protection-Regel schützt `main`. Ein Tag-Ruleset schützt Erstellung und
Änderung der Tags `v*`.

Die folgenden sechs Werte liegen ausschließlich als Environment-Secrets in
`release`:

- `STASI_DEVELOPER_ID_CERTIFICATE_BASE64`: Base64-kodierte PKCS#12-Datei mit
  Developer-ID-Zertifikat und privatem Schlüssel.
- `STASI_DEVELOPER_ID_CERTIFICATE_PASSWORD`: Passwort der PKCS#12-Datei.
- `STASI_DEVELOPER_ID_APPLICATION`: vollständiger Name der Developer-ID-Application-
  Identität.
- `STASI_NOTARY_PRIVATE_KEY_BASE64`: Base64-kodierter App-Store-Connect-API-Schlüssel
  im `.p8`-Format.
- `STASI_NOTARY_KEY_ID`: Key-ID dieses API-Schlüssels.
- `STASI_NOTARY_ISSUER_ID`: Issuer-ID dieses API-Schlüssels.

Gleichnamige Repository- oder Organisationssecrets sind verboten; vorhandene
breiter sichtbare Kopien müssen entfernt werden. Secrets dürfen weder in Workflow,
Dokumentation noch Logs kopiert werden. Der Publish-Schritt prüft alle sechs Werte
vor der Verwendung und beendet den Lauf bei einem fehlenden oder leeren Wert mit
Fehler. Die Veröffentlichung ist damit fail-closed.

## Reguläre Veröffentlichung

1. Auf `main` die vollständige Suite und den App-Smoke-Test ausführen:

   ```bash
   swift build --build-tests
   xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
   ./scripts/smoke-test-app.sh
   ```

2. Den geschützten Tag, beispielsweise `v0.10.0`, auf dem freigegebenen Commit
   erstellen. Das Tag-Ruleset muss wirksam sein. Der Tag-Push startet den Workflow;
   alternativ wird der kontrollierte manuelle Lauf von `main` mit `release_tag`
   `v0.10.0` gestartet.
3. Das Deployment in `release` als Required Reviewer `mm20261` prüfen und freigeben.
4. Nach erfolgreichem Publish sicherstellen, dass der GitHub Release ausschließlich
   `Stasi.zip` und `Stasi.zip.sha256` als Binärassets enthält.
5. Beide Assets separat herunterladen und die ausgelieferte Datei prüfen:

   ```bash
   mkdir release-check
   gh release download v0.10.0 \
     --pattern 'Stasi.zip' \
     --pattern 'Stasi.zip.sha256' \
     --dir release-check
   (
     cd release-check
     shasum -a 256 -c Stasi.zip.sha256
   )
   ```

Die Release-Notizen dürfen keine Secrets enthalten. Erst ein vollständig grüner
Verify- und Publish-Lauf gilt als erfolgreiche Veröffentlichung.

## Manueller Notfallpfad: lokale Diagnose und Wiederherstellungsprüfung

Dieser Pfad dient ausschließlich einer bewusst beaufsichtigten lokalen Diagnose,
Artefaktvorbereitung und Wiederherstellungsprüfung. Er lädt nichts hoch, erstellt
keinen Release und ersetzt das GitHub-Environment-Gate nicht. Eine öffentliche
Veröffentlichung erfolgt ausschließlich über den oben beschriebenen
Tag-/Verify-/Publish-Workflow mit dem Environment `release` und Required Review.

Die lokalen Schritte prüfen Tests, App-Smoke, Bundle-Metadaten, Architektur,
Developer-ID-Signatur, Hardened Runtime, Notarisierung, Gatekeeper, ZIP-Inhalt und
SHA-256-Prüfsumme. Sie prüfen weder den geschützten Workflow-Checkout noch die
Environment-Secrets oder das Required-Reviewer-Gate. Developer-ID-Identität und
`notarytool`-Profil müssen bereits sicher im lokalen Schlüsselbund eingerichtet sein;
ihre Werte gehören nicht ins Repository.

1. Tests ausführen und das Release-Bundle unsigned bauen:

   ```bash
   swift build --build-tests
   xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
   ./scripts/smoke-test-app.sh

   STASI_VERSION='0.10.0' \
   STASI_RELEASE_API_URL='https://api.github.com/repos/mm20261/stasi/releases/latest' \
   STASI_SIGNING_MODE=none \
   ./scripts/make-app.sh
   ```

2. Vor dem Signieren Version, Endpunkt und Architektur prüfen:

   ```bash
   test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
     build/Stasi.app/Contents/Info.plist)" = '0.10.0'
   test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
     build/Stasi.app/Contents/Info.plist)" = '0.10.0'
   test "$(/usr/libexec/PlistBuddy -c 'Print :STASI_RELEASE_API_URL' \
     build/Stasi.app/Contents/Info.plist)" = \
     'https://api.github.com/repos/mm20261/stasi/releases/latest'
   test "$(lipo -archs build/Stasi.app/Contents/MacOS/Stasi)" = 'arm64'
   ```

3. Mit Developer ID und Hardened Runtime signieren, Signaturmerkmale prüfen,
   notarisierten ZIP-Transport einreichen und das Ticket anheften:

   ```bash
   export STASI_DEVELOPER_ID_APPLICATION='<Developer ID Application identity>'
   export STASI_NOTARY_KEYCHAIN_PROFILE='<notarytool keychain profile name>'

   codesign --force \
     --sign "$STASI_DEVELOPER_ID_APPLICATION" \
     --options runtime \
     --timestamp \
     --entitlements Release/Stasi.entitlements \
     build/Stasi.app
   codesign --verify --deep --strict --verbose=2 build/Stasi.app
   codesign -d --verbose=4 build/Stasi.app 2>&1 | grep -Eq 'flags=.*runtime'
   test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
     build/Stasi.app/Contents/Info.plist)" = 'app.stasi.macos'

   ditto -c -k --keepParent build/Stasi.app build/Stasi-notary.zip
   xcrun notarytool submit build/Stasi-notary.zip \
     --keychain-profile "$STASI_NOTARY_KEYCHAIN_PROFILE" \
     --wait
   xcrun stapler staple build/Stasi.app
   xcrun stapler validate build/Stasi.app
   codesign --verify --deep --strict --verbose=2 build/Stasi.app
   spctl --assess --type execute --verbose=4 build/Stasi.app
   ```

4. Nach allen bisherigen Prüfungen das lokale Diagnosearchiv und seine Prüfsumme
   erzeugen und die Prüfsumme sofort gegen das ZIP prüfen:

   ```bash
   ditto -c -k --keepParent build/Stasi.app build/Stasi.zip
   (
     cd build
     shasum -a 256 Stasi.zip >Stasi.zip.sha256
     shasum -a 256 -c Stasi.zip.sha256
   )
   ```

5. Das finale ZIP entpacken und das enthaltene Bundle erneut lokal prüfen:

   ```bash
   archive_check="$(mktemp -d)"
   trap 'rm -rf "$archive_check"' EXIT
   ditto -x -k build/Stasi.zip "$archive_check"

   test -d "$archive_check/Stasi.app"
   codesign --verify --deep --strict --verbose=2 "$archive_check/Stasi.app"
   codesign -d --verbose=4 "$archive_check/Stasi.app" 2>&1 | \
     grep -Eq 'flags=.*runtime'
   xcrun stapler validate "$archive_check/Stasi.app"
   spctl --assess --type execute --verbose=4 "$archive_check/Stasi.app"
   test "$(lipo -archs "$archive_check/Stasi.app/Contents/MacOS/Stasi")" = 'arm64'
   ```

`build/Stasi.zip` und `build/Stasi.zip.sha256` bleiben lokale Diagnoseartefakte und
werden nicht veröffentlicht. Für eine öffentliche Freigabe muss der geschützte
Tag-/Verify-/Publish-Workflow repariert beziehungsweise erneut ausgeführt werden; er
baut und prüft seine Release-Assets selbst hinter dem Environment-Gate.

## Entitlements und lokale Entwicklung

`Release/Stasi.entitlements` enthält ausschließlich
`com.apple.security.device.audio-input`. Die App ist nicht sandboxed;
Mikrofon-, Spracherkennungs- und Bedienungshilfen-Zustimmungen bleiben getrennte
TCC-Berechtigungen.

Für lokale Entwicklungsbuilds verwendet `STASI_SIGNING_MODE=local` die Identität
`Stasi Dev Signing` oder ersatzweise eine ad-hoc-Signatur. `STASI_SIGNING_MODE=none`
ist nur für den bewusst anschließend signierten Release-/Diagnosepfad vorgesehen und
stellt allein kein verteilbares Artefakt her.
