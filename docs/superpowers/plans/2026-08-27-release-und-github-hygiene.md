# Release und GitHub-Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Erzeuge ein übertragbares macOS-App-Paket und bereite Repository, Lizenzen, Updateprüfung und Release-Ablauf für eine öffentliche GitHub-Veröffentlichung vor.

**Architecture:** `make-app.sh` ermittelt Binary und SwiftPM-Ressourcen über `swift build --show-bin-path` und paketiert sie vollständig. Ein eigener Smoke-Test prüft das fertige Bundle. Release-Konfiguration wird zentral und optional. Signierung und Notarisierung werden vorbereitet, aber ohne Zugangsdaten nicht ausgeführt.

**Tech Stack:** SwiftPM, Bash, macOS `codesign`, `iconutil`, `sips`, GitHub Actions, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-27-stabilisierung-und-github-release-design.md`

## Global Constraints

- Kein öffentlicher Push, Tag oder GitHub Release.
- Keine Notarisierung ohne vorhandene Apple-Zugangsdaten.
- Lokale ad-hoc-Signierung bleibt möglich.
- Projektlizenz ist MIT.
- Geist wird mit vollständigem SIL-OFL-1.1-Text verteilt.
- Git-Historie wird in diesem Plan nicht umgeschrieben.
- Das spätere History-Rewrite braucht eine eigene letzte Bestätigung.
- Jeder Commit muss seine gezielten Checks bestehen.

---

### Task 1: Paket-Smoke-Test für SwiftPM-Ressourcen schreiben

**Files:**
- Create: `scripts/smoke-test-app.sh`
- Modify: `scripts/make-app.sh:17-29`
- Reference: `Package.swift:8-12`
- Reference: `Sources/Stasi/UI/Theme.swift:11-20`

**Interfaces:**
- Produces: ausführbares `scripts/smoke-test-app.sh`.
- Consumes: optional `STASI_APP_OUTPUT_DIR`; Standard bleibt `build/`.

- [ ] **Step 1: Schreibe einen zunächst fehlschlagenden Bundle-Test**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Stasi.app"
RESOURCE_BUNDLE="$APP/Contents/Resources/Stasi_Stasi.bundle"

"$ROOT/scripts/make-app.sh"

test -x "$APP/Contents/MacOS/Stasi"
test -d "$RESOURCE_BUNDLE"
test -f "$RESOURCE_BUNDLE/Geist.ttf" || \
  test -f "$RESOURCE_BUNDLE/Fonts/Geist.ttf"
test -f "$RESOURCE_BUNDLE/GeistMono.ttf" || \
  test -f "$RESOURCE_BUNDLE/Fonts/GeistMono.ttf"
test -f "$RESOURCE_BUNDLE/menubar.png" || \
  test -f "$RESOURCE_BUNDLE/Assets/menubar.png"
test -f "$RESOURCE_BUNDLE/menubar-recording.png" || \
  test -f "$RESOURCE_BUNDLE/Assets/menubar-recording.png"

codesign --verify --deep --strict --verbose=2 "$APP"
```

Ermittle die tatsächlichen SwiftPM-Unterpfade einmal aus dem erzeugten Bundle und halte danach genau diese Pfade im Test fest. Verwende nicht dauerhaft beide Alternativen.

- [ ] **Step 2: Mache das Skript ausführbar und bestätige den Fehler**

```bash
chmod +x scripts/smoke-test-app.sh
./scripts/smoke-test-app.sh
```

Expected: FAIL, weil `Stasi_Stasi.bundle` fehlt.

- [ ] **Step 3: Ersetze fest codierte Binary-Pfade in `make-app.sh`**

```bash
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/Stasi"
RESOURCE_BUNDLE="$BIN_DIR/Stasi_Stasi.bundle"
```

Prüfe vor dem Kopieren:

```bash
test -x "$BINARY" || { echo "Stasi binary fehlt: $BINARY" >&2; exit 1; }
test -d "$RESOURCE_BUNDLE" || { echo "Ressourcenbundle fehlt: $RESOURCE_BUNDLE" >&2; exit 1; }
```

- [ ] **Step 4: Kopiere das Ressourcenbundle in die App**

```bash
mkdir -p "$APP/Contents/Resources"
rm -rf "$APP/Contents/Resources/Stasi_Stasi.bundle"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/Stasi_Stasi.bundle"
```

Der Zielort muss mit dem von Swifts generiertem `Bundle.module`-Accessor erwarteten relativen Pfad übereinstimmen. Verifiziere das anhand der erzeugten `resource_bundle_accessor.swift`.

- [ ] **Step 5: Ergänze einen Clean-Room-Lauf**

Der Smoke-Test kopiert die fertige `.app` nach `.build/test-artifacts/clean-room/`, setzt das Arbeitsverzeichnis dorthin und startet ausschließlich das App-Executable. Nutze `STASI_NO_TAP=1`, damit der globale Tap im Test nicht aktiv wird.

```bash
STASI_NO_TAP=1 "$CLEAN_APP/Contents/MacOS/Stasi" >"$LOG" 2>&1 &
PID=$!
sleep 2
kill -0 "$PID"
kill "$PID"
wait "$PID" || true
```

Prüfe das Log auf `fatal error` und fehlende Ressourcen.

- [ ] **Step 6: Führe Smoke-Test und Signaturprüfung aus**

```bash
./scripts/smoke-test-app.sh
codesign --verify --deep --strict --verbose=2 build/Stasi.app
```

Expected: PASS.

- [ ] **Step 7: Committe Paketfix und Smoke-Test**

```bash
git add scripts/make-app.sh scripts/smoke-test-app.sh
git commit -m "fix(release): SwiftPM-Ressourcenbundle paketieren

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: MIT- und Geist-OFL-Lizenzen ausliefern

**Files:**
- Create: `LICENSE`
- Create: `Sources/Stasi/Resources/Licenses/MIT.txt`
- Create: `Sources/Stasi/Resources/Licenses/Geist-OFL-1.1.txt`
- Modify: `README.md`
- Modify: `scripts/smoke-test-app.sh`

**Interfaces:**
- Produces: vollständige Rechtstexte im Repo und im SwiftPM-Ressourcenbundle.

- [ ] **Step 1: Erweitere den Smoke-Test um fehlende Lizenzprüfungen**

```bash
MIT_FILE="$RESOURCE_BUNDLE/Licenses/MIT.txt"
OFL_FILE="$RESOURCE_BUNDLE/Licenses/Geist-OFL-1.1.txt"

test -f "$MIT_FILE"
test -f "$OFL_FILE"
grep -q 'MIT License' "$MIT_FILE"
grep -q 'SIL OPEN FONT LICENSE Version 1.1' "$OFL_FILE"
```

Passe die Pfade exakt an Swifts tatsächliche Resource-Struktur an.

- [ ] **Step 2: Führe den Smoke-Test aus und bestätige Rot**

```bash
./scripts/smoke-test-app.sh
```

Expected: FAIL, weil Lizenzdateien fehlen.

- [ ] **Step 3: Ergänze den Standard-MIT-Text**

Root-`LICENSE` und `Sources/Stasi/Resources/Licenses/MIT.txt` enthalten denselben vollständigen MIT-Text mit:

```text
Copyright (c) 2026 Philipp Meder
```

- [ ] **Step 4: Ergänze den vollständigen unveränderten OFL-1.1-Text**

`Sources/Stasi/Resources/Licenses/Geist-OFL-1.1.txt` enthält den vollständigen offiziellen SIL Open Font License 1.1-Text. Keine gekürzte Zusammenfassung.

- [ ] **Step 5: Dokumentiere beide Lizenzen im README**

```markdown
## Lizenz

Der Quellcode steht unter der MIT-Lizenz. Siehe `LICENSE`.
Die mitgelieferten Geist-Schriften stehen unter der SIL Open Font License 1.1.
Der vollständige Text liegt unter `Sources/Stasi/Resources/Licenses/Geist-OFL-1.1.txt`.
```

- [ ] **Step 6: Führe Smoke-Test aus und committe**

```bash
./scripts/smoke-test-app.sh
git add LICENSE README.md \
  Sources/Stasi/Resources/Licenses/MIT.txt \
  Sources/Stasi/Resources/Licenses/Geist-OFL-1.1.txt \
  scripts/smoke-test-app.sh
git commit -m "docs(license): MIT und Geist-OFL ausliefern

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Update-Konfiguration zentralisieren

**Files:**
- Modify: `Sources/Stasi/Core/UpdateChecker.swift:18-171`
- Modify: `Sources/Stasi/UI/SettingsWindowView.swift:790-833`
- Modify: `Tests/StasiTests/UpdateCheckerTests.swift`
- Modify: `scripts/make-app.sh`

**Interfaces:**
- Produces:

```swift
enum ReleaseConfiguration {
    static var repositoryAPIURL: URL? { get }
}

enum UpdateCheckStatus: Equatable {
    case neverChecked
    case checking
    case upToDate(Date)
    case updateAvailable(version: String, url: URL, checkedAt: Date)
    case failed(message: String)
}
```

- [ ] **Step 1: Schreibe Tests für fehlende Quelle und HTTP-Fehler**

```swift
@Test func missingReleaseURLIsNotReportedAsSuccess() async {
    let checker = UpdateChecker(fetcher: FakeFetcher(), repositoryURL: nil)
    await checker.check()
    guard case .failed = checker.status else {
        Issue.record("Expected failed status")
        return
    }
}

@Test func fetchFailureDoesNotShowUpToDate() async {
    let checker = UpdateChecker(fetcher: FailingFetcher(), repositoryURL: testURL)
    await checker.check()
    guard case .failed = checker.status else {
        Issue.record("Expected failed status")
        return
    }
}
```

Ergänze erfolgreiche gleiche und neuere Version sowie eine pure UI-Farbableitung.

- [ ] **Step 2: Führe Update-Tests aus und bestätige Rot**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.UpdateCheckerTests'
```

- [ ] **Step 3: Lies die Release-URL aus einer zentralen Bundle-Konfiguration**

`ReleaseConfiguration.repositoryAPIURL` liest `STASI_RELEASE_API_URL` aus `Bundle.main.infoDictionary`. `make-app.sh` schreibt den Wert nur, wenn die Umgebungsvariable gesetzt ist.

```bash
if [[ -n "${STASI_RELEASE_API_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :STASI_RELEASE_API_URL string $STASI_RELEASE_API_URL" "$PLIST"
fi
```

Kein hart codierter Fallback auf das nicht erreichbare Repository.

- [ ] **Step 4: Modellieren den Checkstatus explizit**

`lastChecked` bedeutet nur einen erfolgreichen Check. Fehler setzen `.failed` und keinen grünen Zustand. Ein früherer Update-Link darf intern erhalten bleiben, aber die aktuelle UI zeigt den Fehler.

- [ ] **Step 5: Passe die Settings-UI an**

- Neutral bei `.neverChecked`.
- Spinner bei `.checking`.
- Grün nur bei `.upToDate`.
- Update-Aktion bei `.updateAvailable`.
- Warnfarbe und kurze Meldung bei `.failed`.

- [ ] **Step 6: Führe Tests aus und committe**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest" \
  -XCTest 'StasiTests.UpdateCheckerTests'
git add Sources/Stasi/Core/UpdateChecker.swift \
  Sources/Stasi/UI/SettingsWindowView.swift \
  Tests/StasiTests/UpdateCheckerTests.swift \
  scripts/make-app.sh
git commit -m "fix(update): fehlgeschlagene Prüfung ehrlich anzeigen

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: README und `AGENTS.md` öffentlich bereinigen

**Files:**
- Modify: `README.md:57-65`
- Modify: `AGENTS.md:6-10,97,300-310`

**Interfaces:**
- Produces: portable Testbefehle und keine persönliche Hardwarebeschreibung.

- [ ] **Step 1: Erfasse die aktuell unerwünschten Treffer**

```bash
grep -nE '\.build/[^ ]+/debug/StasiPackageTests\.xctest|Mac17,8|64 GB|<bisherige-private-e-mail>' README.md AGENTS.md || true
```

Speichere die erwarteten Treffer im Arbeitsprotokoll. Keine Produktionsänderung.

- [ ] **Step 2: Ersetze den Testbefehl**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

Entferne feste Testzahlen. Formuliere stattdessen, dass die vollständige Suite vor Commits laufen muss.

- [ ] **Step 3: Entferne persönliche Hardwaredaten**

Behalte nur sachliche Mindestanforderungen aus `Package.swift`, beispielsweise macOS 26 und die erforderliche Xcode-/Swift-Version, sofern sie im Repo tatsächlich festgelegt ist.

- [ ] **Step 4: Prüfe die Doku**

```bash
! grep -nE '\.build/[^ ]+/debug/StasiPackageTests\.xctest|Mac17,8|64 GB|<bisherige-private-e-mail>' README.md AGENTS.md
```

Expected: kein Treffer.

- [ ] **Step 5: Committe die öffentliche Doku**

```bash
git add README.md AGENTS.md
git commit -m "docs: öffentliche Entwicklungsanleitung bereinigen

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Eine kanonische Icon-Quelle herstellen

**Files:**
- Create: `Resources/AppIcon.png`
- Modify: `scripts/make-app.sh:67-90`
- Modify: `scripts/gen_icon.swift`
- Modify: `.gitignore`
- Delete: abgeleitete Dateien unter `Resources/Assets/`
- Delete or relocate: `import/design_handoff_stasi/icons/anthrazit/`
- Modify: `scripts/smoke-test-app.sh`

**Interfaces:**
- Produces: genau eine eingecheckte 1024×1024-PNG als App-Icon-Quelle.

- [ ] **Step 1: Wähle die bestehende visuell aktive 1024-PNG als Quelle**

Vergleiche die aktuell von `make-app.sh` verwendete Handoff-Datei mit `Resources/Assets`. Kopiere die tatsächlich veröffentlichte 1024-PNG bytegleich nach:

```text
Resources/AppIcon.png
```

Erzeuge kein neues Design.

- [ ] **Step 2: Erweitere den Smoke-Test**

```bash
test -f "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP/icon-check.iconset"
iconutil -c iconset "$APP/Contents/Resources/AppIcon.icns" \
  -o "$TMP/icon-check.iconset"
test -f "$TMP/icon-check.iconset/icon_512x512@2x.png"
```

Repository-Prüfung:

```bash
COUNT="$(git ls-files | grep -E '(^|/)(icon_[^/]+\.png|AppIcon\.icns)$' | wc -l | tr -d ' ')"
test "$COUNT" -eq 0
```

- [ ] **Step 3: Führe den Test aus und bestätige Rot**

```bash
./scripts/smoke-test-app.sh
```

Expected: Repository-Check scheitert wegen eingecheckter Ableitungen.

- [ ] **Step 4: Erzeuge das temporäre Iconset aus `Resources/AppIcon.png`**

`make-app.sh` erzeugt alle benötigten Größen mit `sips` unter dem Build-Ausgabeordner und ruft anschließend `iconutil` auf. Es liest nicht mehr aus `import/design_handoff_stasi` und nutzt keine eingecheckte `.icns` als Fallback.

- [ ] **Step 5: Entferne nur abgeleitete Icon-Dateien**

Lösche eingecheckte `icon_*.png`, `.iconset`-Verzeichnisse und `AppIcon.icns`, nachdem `Resources/AppIcon.png` und der neue Build erfolgreich geprüft wurden. Behalte Laufzeitbilder wie Menüleistenicons.

- [ ] **Step 6: Löse historische Design-Handoffs aus Runtime-Quellen**

Wenn `import/design_handoff_stasi` keine Produktionsabhängigkeit mehr besitzt, entferne es aus dem Runtime-Repo. Falls es als Referenz bleiben soll, verschiebe es in ein eindeutig benanntes Archiv außerhalb der Runtime-Struktur. Vermische keine Designänderung mit diesem Schritt.

- [ ] **Step 7: Führe Smoke-Test aus und committe**

```bash
./scripts/smoke-test-app.sh
git add -A Resources scripts/make-app.sh scripts/gen_icon.swift \
  scripts/smoke-test-app.sh .gitignore import/design_handoff_stasi
git commit -m "chore(assets): App-Icon aus einer Quelle ableiten

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Lokale und öffentliche Signierung klar trennen

**Files:**
- Create: `Release/Stasi.entitlements`
- Create: `docs/release.md`
- Modify: `scripts/make-app.sh:92-101`

**Interfaces:**
- Produces: dokumentierte lokale Build-Strecke und Entitlements-Datei.

- [ ] **Step 1: Dokumentiere die vorhandenen App-Fähigkeiten**

Leite Entitlements nur aus dem tatsächlichen Code ab. Ergänze keine unnötigen Rechte. Mikrofon- und Accessibility-TCC-Beschreibungen bleiben im Info.plist; sie sind keine Entitlements.

- [ ] **Step 2: Erstelle `Release/Stasi.entitlements`**

Beginne mit einer minimalen gültigen Property List. Ergänze nur Rechte, die Build oder Laufzeit nachweislich benötigen.

- [ ] **Step 3: Trenne Signiermodi in `make-app.sh`**

Unterstütze:

```bash
STASI_SIGNING_MODE=local   # bestehendes Dev-Zertifikat, sonst ad hoc
STASI_SIGNING_MODE=none    # nur für lokale Paketdiagnose
```

Ein späterer CI-Modus nutzt nicht die lokale Zertifikatssuche.

- [ ] **Step 4: Dokumentiere Release-Schritte**

`docs/release.md` enthält:

1. Vollständige Tests.
2. Paket-Smoke-Test.
3. Developer-ID-Signierung mit Hardened Runtime.
4. `notarytool submit --wait`.
5. `stapler staple`.
6. `codesign --verify` und `spctl --assess`.
7. Kein Push oder Release ohne menschliche Freigabe.

- [ ] **Step 5: Prüfe lokalen Build und committe**

```bash
./scripts/make-app.sh
codesign --verify --deep --strict --verbose=2 build/Stasi.app
git add Release/Stasi.entitlements docs/release.md scripts/make-app.sh
git commit -m "chore(release): Signier- und Notarisierungsgrenzen dokumentieren

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Manuelle GitHub-Actions-Release-Strecke vorbereiten

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `docs/release.md`

**Interfaces:**
- Produces: ausschließlich manuell startbarer Workflow ohne automatischen Tag, Push oder Release.

- [ ] **Step 1: Erstelle einen `workflow_dispatch`-Workflow**

```yaml
name: Build signed app

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          swift build --build-tests
          xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
      - name: Build app
        run: ./scripts/make-app.sh
      - name: Smoke test
        run: ./scripts/smoke-test-app.sh
```

Verifiziere die aktuell auf GitHub verfügbare Runner-Bezeichnung vor dem Commit. Wenn `macos-26` nicht verfügbar ist, dokumentiere den benötigten self-hosted Runner, statt einen falschen Wert zu committen.

- [ ] **Step 2: Ergänze bedingte Signier- und Notarisierungsschritte**

Secrets werden nur referenziert, nie eingecheckt. Erwartete Namen werden in `docs/release.md` beschrieben. Schritte laufen nur, wenn die nötigen Secrets gesetzt sind.

- [ ] **Step 3: Verhindere Außenwirkungen**

Der Workflow enthält nicht:

- `git push`.
- Tag-Erzeugung.
- `gh release create`.
- automatische Veröffentlichung von Artefakten.

Ein späterer Upload braucht eine eigene Freigabe.

- [ ] **Step 4: Prüfe YAML lokal**

Nutze vorhandenen YAML-Linter, falls im System installiert. Andernfalls prüfe die Datei mit Ruby oder Python gegen einen lokalen YAML-Parser, ohne neue Projektabhängigkeit einzuführen.

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release.yml")'
```

- [ ] **Step 5: Committe die CI-Vorbereitung**

```bash
git add .github/workflows/release.yml docs/release.md
git commit -m "ci: manuelle signierte Release-Strecke vorbereiten

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Repository-Gesamtprüfung

**Files:**
- Verify only.

- [ ] **Step 1: Führe vollständige Tests und Builds aus**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
swift build -c release
./scripts/smoke-test-app.sh
codesign --verify --deep --strict --verbose=2 build/Stasi.app
```

Expected: alles erfolgreich.

- [ ] **Step 2: Führe Hygienechecks aus**

```bash
! git ls-files | grep -E '(^|/)(\.DS_Store|\.build/|build/)'
! git grep -n "$(printf '%s%s' 'arm64-apple-' 'macosx')"
! git grep -n "$(printf '%s%s' 'api.github.com/repos/' 'leomcguire/stasi')"
! git grep -n '<bisherige-private-e-mail>' -- ':!docs/superpowers/**'
! git grep -n 'Mac17,8\|64 GB' -- README.md AGENTS.md
```

Expected: keine Treffer.

- [ ] **Step 3: Prüfe Secrets und private Schlüssel erneut**

```bash
! git grep -nE '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16})'
```

Dieser Check ergänzt, ersetzt aber keinen spezialisierten Secret-Scanner.

- [ ] **Step 4: Prüfe Diff und Arbeitsbaum**

```bash
git diff --check
git status --short
git log --oneline -12
```

Expected: sauberer Arbeitsbaum und kleine thematische Commits.

- [ ] **Step 5: Halte verbleibende Release-Grenzen fest**

Bericht muss klar sagen:

- Ad-hoc-Build ist lokal verifiziert.
- Developer-ID-/Notarisierungsstrecke ist nur vorbereitet, falls keine Secrets vorhanden sind.
- Kein GitHub-Release und kein Push wurde ausgeführt.
- Git-Historie wurde noch nicht umgeschrieben.

---

### Task 9: Git-Historie separat vorbereiten, aber nicht ausführen

**Files:**
- Create: `docs/history-rewrite.md`
- No history mutation.

**Interfaces:**
- Produces: sichere Checkliste für eine spätere bestätigte Operation.

- [ ] **Step 1: Dokumentiere die Voraussetzungen**

```markdown
1. Alle Reparaturcommits und Tests abgeschlossen.
2. Exakten neutralen Ersatznamen und Ersatz-E-Mail bestätigen.
3. Backup-Ref und vollständiges Repository-Backup anlegen.
4. Erneut bestätigen, dass alle Commit-IDs geändert werden.
5. `git filter-repo --mailmap` ausführen.
6. Autoren, Tags, Builds und Diff erneut prüfen.
7. Keinen Force-Push ohne eigene ausdrückliche Freigabe ausführen.
```

- [ ] **Step 2: Dokumentiere nur den geplanten Mailmap-Eintrag**

Verwende noch keinen erfundenen Ersatzwert. Markiere den Wert als Entscheidung, die vor Ausführung interaktiv eingeholt wird. Das ist keine Implementierungs-Lücke, sondern eine zwingende Sicherheitsbestätigung.

- [ ] **Step 3: Committe ausschließlich die Anleitung**

```bash
git add docs/history-rewrite.md
git commit -m "docs: sichere Bereinigung der Git-Autoren vorbereiten

Co-Authored-By: Claude <noreply@anthropic.com>"
```

Die eigentliche Umschreibung ist nicht Teil dieses Plans und darf nicht automatisch folgen.
