# Release-Ablauf

Diese Anleitung trennt den lokalen Entwicklungsbuild von einer späteren öffentlichen Developer-ID-Veröffentlichung. Die lokale Signatur ist weder notarisiert noch außerhalb des eigenen Macs automatisch vertrauenswürdig. Das Skript führt keine Notarisierung, Veröffentlichung, Netzwerkoperation oder Git-Aktion aus.

## Tatsächliche Fähigkeiten und minimale Entitlements

Stasi verwendet nachweislich:

- Audioeingabe über Core Audio/AVFoundation für die Diktataufnahme,
- lokale Spracherkennung,
- Accessibility- und Core-Graphics-APIs für den globalen Hotkey und das Einfügen von Text,
- optional `URLSession` für eine konfigurierte Update-Prüfung,
- lokale Dateien und `UserDefaults` für Einstellungen, Wörterbuch, Protokolle und Aufnahmen.

`Release/Stasi.entitlements` enthält ausschließlich `com.apple.security.device.audio-input`. Dieses Resource-Access-Entitlement wird für Audioeingabe unter der späteren Hardened Runtime benötigt. `NSMicrophoneUsageDescription` und `NSSpeechRecognitionUsageDescription` im `Info.plist` sind davon getrennte TCC-Nutzungstexte. Auch die Zustimmung zu Bedienungshilfen wird von TCC verwaltet; sie ist kein Entitlement.

Die App ist nicht im App Sandbox. Deshalb sind weder `com.apple.security.app-sandbox` noch Sandbox-Datei- oder Sandbox-Netzwerk-Entitlements gesetzt. Die optionale Update-Prüfung belegt Netzwerkverwendung, erfordert bei einer nicht sandboxed App aber kein Network-Client-Entitlement. Für Bedienungshilfen wird ebenfalls kein privates oder zusätzliches Entitlement ergänzt.

## Lokaler Build und Test

Voraussetzung ist die im Repository beschriebene macOS-/Swift-Toolchain.

1. Vollständige Tests ausführen:

   ```bash
   swift build --build-tests
   xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
   ```

2. App mit dem Standardmodus `local` bauen. Das Skript verwendet die vorhandene Code-Signing-Identität `Stasi Dev Signing`; fehlt sie, verwendet es ad hoc (`-`). Beide Varianten sind nur lokale Entwicklungssignaturen.

   ```bash
   STASI_SIGNING_MODE=local ./scripts/make-app.sh
   codesign --verify --deep --strict --verbose=2 build/Stasi.app
   codesign -d --verbose=4 --entitlements - build/Stasi.app
   ```

   `STASI_SIGNING_MODE` darf nur `local` oder `none` sein. Ein unbekannter Wert beendet den Build mit einem Fehler. Der lokale Modus aktiviert die Hardened Runtime bewusst nicht: Das verhindert keine spätere Developer-ID-Prüfung, behauptet aber auch keine öffentliche Vertrauensstellung oder Notarisierung.

3. Den normalen Paket- und Start-Smoke-Test ausführen. Er baut standardmäßig erneut im Modus `local` und behält seine strikte Signaturprüfung bei:

   ```bash
   ./scripts/smoke-test-app.sh
   ```

4. `none` ist ausschließlich eine Diagnose für die Bundle-Erzeugung. Sie überspringt nur den abschließenden Bundle-Signierschritt; Ressourcen, Icon, Update-Konfiguration und Lizenzdateien werden unverändert gepackt:

   ```bash
   rm -rf build-unsigned
   STASI_SIGNING_MODE=none STASI_APP_OUTPUT_DIR=build-unsigned ./scripts/make-app.sh
   if codesign --verify --deep --strict build-unsigned/Stasi.app; then
       echo "Fehler: Diagnose-Bundle ist unerwartet signiert" >&2
       exit 1
   else
       echo "Erwartet: Diagnose-Bundle besitzt keine gültige Bundle-Signatur"
   fi
   ```

   Der normale Smoke-Test wird nicht mit `STASI_SIGNING_MODE=none` ausgeführt: Seine unveränderte `codesign --verify`-Stufe muss für reguläre Builds erfolgreich bleiben und würde ein unsigned Diagnose-Bundle absichtlich zurückweisen. `none` ist kein Release- oder Verteilungsmodus.

## Manueller GitHub-Actions-Build

`.github/workflows/release.yml` ist ausschließlich über `workflow_dispatch` startbar und läuft auf dem von GitHub dokumentierten Standard-Arm64-Runner `macos-26`. Quelle für Bezeichnung und Architektur: [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), geprüft am 28. August 2026.

Der Workflow verwendet keine Marketplace-Actions. Er initialisiert Git selbst, lädt mit dem von GitHub bereitgestellten, auf `contents: read` beschränkten `GITHUB_TOKEN` ausschließlich den Commit aus `GITHUB_SHA`, checkt ihn detached aus und verifiziert den resultierenden `HEAD`. Das Token wird über ein temporäres `GIT_ASKPASS`-Skript bereitgestellt, nicht in eine URL oder Git-Konfiguration geschrieben; das Skript wird anschließend gelöscht.

Jeder manuelle Lauf führt Tests, einen lokalen beziehungsweise ad-hoc signierten Build und den vollständigen Smoke-Test aus. Developer-ID-Signierung und Notarisierung folgen danach nur, wenn **alle** folgenden GitHub-Actions-Repository-Secrets nicht leer gesetzt sind:

- `STASI_DEVELOPER_ID_CERTIFICATE_BASE64`: Base64-kodierte PKCS#12-Datei mit Zertifikat und privatem Schlüssel für „Developer ID Application“.
- `STASI_DEVELOPER_ID_CERTIFICATE_PASSWORD`: Passwort der PKCS#12-Datei.
- `STASI_DEVELOPER_ID_APPLICATION`: vollständiger Name der zu verwendenden Developer-ID-Application-Identität.
- `STASI_NOTARY_PRIVATE_KEY_BASE64`: Base64-kodierter privater App-Store-Connect-API-Schlüssel im `.p8`-Format.
- `STASI_NOTARY_KEY_ID`: Key-ID dieses API-Schlüssels.
- `STASI_NOTARY_ISSUER_ID`: Issuer-ID dieses API-Schlüssels.

Die Secret-Werte werden ausschließlich über die GitHub-Actions-Umgebung übergeben und dürfen weder in Workflow-Datei, Dokumentation noch Logs kopiert werden. Bei fehlendem oder unvollständigem Secret-Satz meldet der Lauf den Skip ausdrücklich; Tests, lokaler/ad-hoc Build und Smoke-Test bleiben davon unberührt. Sind alle Secrets vorhanden, importiert der Workflow Zertifikat und Notarisierungsprofil in einen temporären Schlüsselbund, baut zunächst unsigned, signiert mit Developer ID und Hardened Runtime, notarisiert, stapelt und prüft das Bundle. Temporäre Schlüssel-, Zertifikats- und Schlüsselbunddateien werden auch bei einem Fehler entfernt.

Der erzeugte Build bleibt ausschließlich im flüchtigen Runner-Dateisystem. Der Workflow enthält keinen Push, keine Tag-Erzeugung, kein GitHub Release, keinen Artifact-Upload und kein Deployment. Ein Download oder eine Veröffentlichung benötigt eine getrennte Änderung und ausdrückliche Freigabe.

## Developer ID, Hardened Runtime und Notarisierung

Die folgenden Schritte sind ein manueller Ablauf für eine spätere öffentliche Freigabe. Sie benötigen eine gültige Developer-ID-Application-Identität und ein zuvor sicher im Schlüsselbund eingerichtetes `notarytool`-Profil. Identitäten, Team-IDs, Apple-ID-Daten, Passwörter, App-spezifische Passwörter, API-Schlüssel und andere Secret-Werte gehören nicht ins Repository.

1. Nach erfolgreichen Tests und dem normalen Smoke-Test die zu verwendenden Namen in der aktuellen Shell setzen. Die konkreten Werte werden von der freigebenden Person gewählt und nicht eingecheckt:

   ```bash
   export STASI_DEVELOPER_ID_APPLICATION='<Developer ID Application identity>'
   export STASI_NOTARY_KEYCHAIN_PROFILE='<notarytool keychain profile name>'
   ```

2. Frisch bauen und anschließend ausdrücklich mit Developer ID, Zeitstempel, Hardened Runtime und den geprüften Entitlements neu signieren:

   ```bash
   STASI_SIGNING_MODE=none ./scripts/make-app.sh
   codesign --force \
     --sign "$STASI_DEVELOPER_ID_APPLICATION" \
     --options runtime \
     --timestamp \
     --entitlements Release/Stasi.entitlements \
     build/Stasi.app
   codesign --verify --deep --strict --verbose=2 build/Stasi.app
   codesign -d --verbose=4 --entitlements - build/Stasi.app
   ```

   Vor dem nächsten Schritt muss die freigebende Person Identität, Bundle-ID, Version und Entitlements in der Ausgabe prüfen. Eine erfolgreiche Developer-ID-Signatur allein bedeutet noch nicht, dass die App notarisiert oder von Gatekeeper akzeptiert ist.

3. Das signierte App-Bundle ohne Metadatenverlust für den Notardienst archivieren und die Übertragung synchron abwarten:

   ```bash
   rm -f build/Stasi-notary.zip
   ditto -c -k --keepParent build/Stasi.app build/Stasi-notary.zip
   xcrun notarytool submit build/Stasi-notary.zip \
     --keychain-profile "$STASI_NOTARY_KEYCHAIN_PROFILE" \
     --wait
   ```

   Nur bei einem ausdrücklich erfolgreichen Notarisierungsergebnis fortfahren. Fehlerprotokolle werden geprüft; die Signatur- oder Entitlements-Anforderungen werden nicht durch Abschalten der Hardened Runtime umgangen.

4. Ticket anheften und danach Signatur sowie Gatekeeper-Bewertung erneut prüfen:

   ```bash
   xcrun stapler staple build/Stasi.app
   xcrun stapler validate build/Stasi.app
   codesign --verify --deep --strict --verbose=2 build/Stasi.app
   spctl --assess --type execute --verbose=4 build/Stasi.app
   ```

5. Erst nach diesen Prüfungen darf ein endgültiges Distributionsarchiv aus der gestapelten App erzeugt werden:

   ```bash
   rm -f build/Stasi.zip
   ditto -c -k --keepParent build/Stasi.app build/Stasi.zip
   ```

## Verbindliche menschliche Freigabe

Kein Tag, Push, GitHub Release, Upload in einen öffentlichen Kanal oder sonstige Veröffentlichung erfolgt automatisch. Vor jeder Außenwirkung muss eine verantwortliche Person die Testausgaben, Smoke-Prüfung, Developer-ID-Identität, Hardened-Runtime-Entitlements, erfolgreiche Notarisierung, Staple-Validierung, `codesign`-Prüfung, `spctl`-Bewertung und das endgültige Artefakt ausdrücklich freigeben. Ohne diese Freigabe endet der Ablauf lokal.
