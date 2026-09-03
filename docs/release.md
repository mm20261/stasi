# Release-Ablauf

Diese Anleitung beschreibt den aktuellen öffentlichen Release-Weg ohne bezahlten
Apple-Developer-Account und den später vorgesehenen, signierten Workflow-Weg.

## Veröffentlichungsstand vom 3. September 2026

`v0.10.0` ist der erste öffentliche Release von Stasi. Er wird lokal für Apple
Silicon (`arm64`) gebaut, ad-hoc signiert und ohne Apple-Notarisierung als
`Stasi-0.10.0.zip` auf GitHub Releases veröffentlicht. Der Homebrew-Tap
`mm20261/homebrew-tap` verteilt dasselbe Artefakt als Cask `stasi`.

„Unsigniert“ bedeutet hier: ohne Apple-Developer-ID; technisch trägt die App eine
ad-hoc-Signatur. Diese besitzt keine stabile Apple-Team-Identität. Deshalb blockiert
Gatekeeper das quarantänisierte ZIP zunächst, und macOS fragt nach Updates die
Berechtigungen für Mikrofon und Bedienungshilfen erneut ab. Die Nutzerhinweise dazu
stehen in `README.md` und `docs/troubleshooting.md`.

Der GitHub-Release-Workflow bleibt für einen späteren Developer-ID- und
Notarisierungsweg erhalten. Solange seine sechs Secrets fehlen, wird sein
Publish-Job übersprungen; der lokale ad-hoc-Ablauf in diesem Dokument ist bis dahin
der maßgebliche Veröffentlichungsweg.

Bereits eingerichtet sind das öffentliche Repository, der gegen Löschung und
Force-Push geschützte Branch `main` sowie das Environment `release` mit Required
Reviewer `mm20261` und den Deploymentquellen `main` und `v*`.

## Release-Vertrag

- Tag: `vMAJOR.MINOR.PATCH`
- Bundle-Version: `MAJOR.MINOR.PATCH`
- Versionsquelle: `VERSION` im Repo-Root
- Release-Endpunkt: `https://api.github.com/repos/mm20261/stasi/releases/latest`
- Architektur des ersten Releases: ausschließlich `arm64`
- Artefakt: `Stasi-MAJOR.MINOR.PATCH.zip`
- Signierung des aktuellen öffentlichen Builds: ad hoc mit `codesign --sign -`
- Notarisierung des aktuellen öffentlichen Builds: keine
- Homebrew-Cask: `stasi` im Tap `mm20261/homebrew-tap`

Tag, Inhalt von `VERSION`, Bundle-Version, ZIP-Dateiname, GitHub-Release und
Cask-Version müssen exakt dieselbe Versionsnummer tragen.

## Aktueller Ablauf: ad-hoc signierter Release

Im folgenden Beispiel steht `X.Y.Z` für die freizugebende Versionsnummer. Für den
ersten Release ist das `0.10.0`.

### 1. Version und freizugebenden Stand prüfen

Der Release-Commit muss auf `main` liegen. `VERSION` muss ausschließlich die
Versionsnummer ohne vorangestelltes `v` enthalten.

```bash
git switch main
release_version="$(tr -d '\r\n' < VERSION)"
test "$release_version" = 'X.Y.Z'
test "$(git branch --show-current)" = 'main'
```

Vor dem Taggen die vollständige Testsuite ausführen:

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

### 2. Release-Tag auf `main` erstellen und pushen

```bash
git tag "v$release_version"
git push origin "v$release_version"
```

Der Tag-Push startet den GitHub-Workflow. Dessen Verify-Job darf laufen; ohne die
Developer-ID-Secrets muss der Publish-Job übersprungen werden. Das öffentliche
Artefakt wird anschließend mit den folgenden lokalen Schritten erzeugt.

### 3. App lokal ad-hoc signiert bauen

```bash
STASI_SIGNING_MODE=adhoc ./scripts/make-app.sh
```

Der Build muss die Version aus `VERSION` übernehmen. Anschließend Bundle-Version,
Bundle-ID, Architektur und ad-hoc-Signatur prüfen:

```bash
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  build/Stasi.app/Contents/Info.plist)" = "$release_version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  build/Stasi.app/Contents/Info.plist)" = "$release_version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  build/Stasi.app/Contents/Info.plist)" = 'app.stasi.macos'
test "$(lipo -archs build/Stasi.app/Contents/MacOS/Stasi)" = 'arm64'
codesign --verify --deep --strict --verbose=2 build/Stasi.app
```

### 4. Smoke-Test ausführen

```bash
./scripts/smoke-test-app.sh
```

### 5. Versionsgebundenes ZIP und SHA-256 erzeugen

```bash
ditto -c -k --keepParent build/Stasi.app "Stasi-$release_version.zip"
shasum -a 256 "Stasi-$release_version.zip"
```

Den ausgegebenen SHA-256-Wert unverändert in die Release-Notizen und anschließend in
den Homebrew-Cask übernehmen. Vor der Veröffentlichung kann das ZIP zusätzlich in
ein temporäres Verzeichnis entpackt und das enthaltene Bundle erneut geprüft werden:

```bash
archive_check="$(mktemp -d)"
ditto -x -k "Stasi-$release_version.zip" "$archive_check"
codesign --verify --deep --strict --verbose=2 "$archive_check/Stasi.app"
test "$(lipo -archs "$archive_check/Stasi.app/Contents/MacOS/Stasi")" = 'arm64'
```

Das temporäre Prüfverzeichnis danach entfernen.

### 6. GitHub-Release veröffentlichen

Die Release-Notizen müssen mindestens die SHA-256-Prüfsumme, die Beschränkung auf
`arm64`, den Hinweis auf die fehlende Developer-ID-Signierung und Notarisierung sowie
die Gatekeeper-Installationsschritte enthalten. Mit einer vorbereiteten lokalen
Notizdatei lautet der Aufruf:

```bash
gh release create "v$release_version" "Stasi-$release_version.zip" \
  --title "Stasi $release_version" \
  --notes-file /path/to/release-notes.md
```

Danach auf der GitHub-Release-Seite prüfen, dass Tag, Titel, ZIP-Dateiname und die in
den Notizen veröffentlichte SHA-256-Prüfsumme übereinstimmen.

### 7. Homebrew-Cask aktualisieren

Im Repository `mm20261/homebrew-tap` die Datei `Casks/stasi.rb` aktualisieren:

- `version` auf `X.Y.Z` setzen.
- `sha256` exakt auf den zuvor mit `shasum -a 256` ermittelten Wert setzen.
- Prüfen, dass der Cask das versionsgebundene ZIP des GitHub-Releases verwendet.

Nach Veröffentlichung des aktualisierten Taps die Installation mit dem empfohlenen
Befehl prüfen:

```bash
brew install --cask mm20261/tap/stasi
```

Für bereits installierte Versionen lautet der Update-Befehl:

```bash
brew upgrade --cask stasi
```

Wegen der ad-hoc-Signatur müssen Mikrofon und Bedienungshilfen nach einem Update
erneut freigegeben werden.

## Zukunft: signierter und notarisierter Workflow

Sobald eine Apple Developer ID vorhanden und alle sechs Secrets gesetzt sind, kann
der vorhandene Workflow `.github/workflows/release.yml` den signierten Weg
übernehmen. Der Verify-Job löst den Tag auf einen exakten Commit auf, gleicht die
Tag-Version mit `VERSION` ab, führt die vollständige Testsuite aus, baut die App und
prüft den Smoke-Test sowie `arm64`.

Der Publish-Job verwendet das geschützte Environment `release`. Mit vollständig
gesetzten Secrets baut er denselben verifizierten Commit erneut, signiert die App mit
Developer ID und Hardened Runtime, notarisiert sie, heftet das Ticket an, prüft
Signatur und Gatekeeper und veröffentlicht die geprüften Release-Artefakte. Ohne
vollständige Secrets bleibt dieser Publish-Job übersprungen.

Das Environment `release` besitzt den Required Reviewer `mm20261`. Zulässige
Deploymentquellen sind der geschützte Branch `main` für kontrollierte manuelle Läufe
und Release-Tags `v*`.

### Benötigte Environment-Secrets

Die folgenden sechs Werte dürfen ausschließlich als Environment-Secrets in
`release` liegen:

- `STASI_DEVELOPER_ID_CERTIFICATE_BASE64`: Base64-kodierte PKCS#12-Datei mit
  Developer-ID-Zertifikat und privatem Schlüssel.
- `STASI_DEVELOPER_ID_CERTIFICATE_PASSWORD`: Passwort der PKCS#12-Datei.
- `STASI_DEVELOPER_ID_APPLICATION`: vollständiger Name der Developer-ID-Application-
  Identität.
- `STASI_NOTARY_PRIVATE_KEY_BASE64`: Base64-kodierter App-Store-Connect-API-Schlüssel
  im `.p8`-Format.
- `STASI_NOTARY_KEY_ID`: Key-ID dieses API-Schlüssels.
- `STASI_NOTARY_ISSUER_ID`: Issuer-ID dieses API-Schlüssels.

Gleichnamige Repository- oder Organisationssecrets sind verboten. Secret-Werte
dürfen weder in Workflow, Dokumentation, Release-Notizen noch Logs kopiert werden.

## Entitlements und lokale Entwicklung

`Release/Stasi.entitlements` enthält ausschließlich
`com.apple.security.device.audio-input`. Die App ist nicht sandboxed;
Mikrofon-, Spracherkennungs- und Bedienungshilfen-Zustimmungen bleiben getrennte
TCC-Berechtigungen.

Für lokale Entwicklungsbuilds verwendet `STASI_SIGNING_MODE=local` die Identität
`Stasi Dev Signing` oder ersatzweise eine ad-hoc-Signatur. Öffentliche Releases ohne
Developer ID müssen dagegen ausdrücklich mit `STASI_SIGNING_MODE=adhoc` gebaut
werden. `scripts/make-app.sh` liest die Version standardmäßig aus `VERSION`;
`STASI_VERSION` ist nur eine explizite Überschreibung.
