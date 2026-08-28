# Signierter Release und Homebrew-Vorbereitung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Einen lokal prüfbaren Tag-Release-Workflow vorbereiten, der Stasi mit kontrollierter Version baut, Developer-ID-signiert, notarisiert und als GitHub-Release für Homebrew veröffentlicht.

**Architecture:** `scripts/make-app.sh` bleibt die einzige Bundle-Erzeugung. Release-Version und Update-Endpunkt kommen über kontrollierte Umgebungsvariablen und werden im Smoke-Test geprüft. GitHub Actions trennt weiterhin den secretlosen Verify-Job vom geschützten Publish-Job. Die eigentliche öffentliche Ausführung, Secrets, der erste Tag und das Tap gehören erst zum separaten Veröffentlichungsplan.

**Tech Stack:** Bash, Swift Package Manager, GitHub Actions YAML, Apple `codesign`, `notarytool`, `stapler`, `spctl`, GitHub CLI, Homebrew Cask

**Spec:** `docs/superpowers/specs/2026-08-28-transkript-release-und-autorenbereinigung-design.md`

## Global Constraints

- Erste öffentliche Version: Apple Silicon und macOS 26.
- Bundle-ID bleibt `app.stasi.macos`.
- Release-Tags verwenden exakt `vMAJOR.MINOR.PATCH`; Bundle-Version verwendet `MAJOR.MINOR.PATCH` ohne `v`.
- Release-Endpunkt ist `https://api.github.com/repos/mm20261/stasi/releases/latest`.
- Developer-ID- und Notarisierungswerte bleiben ausschließlich GitHub-Environment-Secrets.
- Fehlende Secrets sind im Publish-Job ein harter Fehler.
- Global bleibt `contents: read`; nur der Publish-Job erhält `contents: write`.
- GitHub Release enthält nur das geprüfte `Stasi.zip` und `Stasi.zip.sha256`.
- Kein DMG, PKG, Sparkle oder Quarantäne-Bypass.
- Keine öffentliche Aktion in diesem Plan: kein Tag-Push, kein Release, keine Sichtbarkeitsänderung und kein Tap-Push.
- Voraussetzung: `docs/superpowers/plans/2026-08-28-transkript-neustartbereinigung.md` ist umgesetzt und grün.

---

### Task 1: Bundle-Version kontrollieren und im Smoke-Test prüfen

**Files:**
- Modify: `scripts/make-app.sh:6-11,57-109,156-159`
- Modify: `scripts/smoke-test-app.sh:11-14,66-94`

**Interfaces:**
- Consumes: `STASI_APP_OUTPUT_DIR`, `STASI_SIGNING_MODE`, `STASI_RELEASE_API_URL`
- Produces: `STASI_VERSION` im Format `MAJOR.MINOR.PATCH`; optionaler `STASI_EXPECTED_ARCH`; geprüfte Bundle-Metadaten

- [ ] **Step 1: Aktuelles Fehlverhalten mit ungültiger Version bestätigen**

Run:

```bash
rm -rf .build/test-artifacts/invalid-version
STASI_VERSION=v0.9.0 \
STASI_SIGNING_MODE=none \
STASI_APP_OUTPUT_DIR=.build/test-artifacts/invalid-version \
./scripts/make-app.sh
```

Expected before implementation: der Build akzeptiert den ungültigen Wert, weil `STASI_VERSION` noch ignoriert wird. Das ist der rote Nachweis.

- [ ] **Step 2: Version vor jedem Swift-Build validieren**

Ersetze in `scripts/make-app.sh`:

```bash
VERSION="0.9.0"
```

mit:

```bash
VERSION="${STASI_VERSION:-0.9.0}"

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf 'Ungültige STASI_VERSION: %s; erwartet MAJOR.MINOR.PATCH ohne v-Präfix.\n' \
        "$VERSION" >&2
    exit 2
fi
```

Die Prüfung muss vor `echo "▸ Swift-Build (release)…"` liegen.

Ersetze die Abschlussausgabe:

```bash
echo "✓ Fertig: $APP"
echo "  Version:  $VERSION"
echo "  Starten:  open \"$APP\""
echo "  Install.: ditto \"$APP\" /Applications/Stasi.app"
```

- [ ] **Step 3: Ungültige Werte ohne Build ablehnen**

Run:

```bash
for invalid in v0.9.0 0.9 01.2.3 1.2.3-beta $'1.2.3\n4.5.6'; do
  output="$(mktemp)"
  if STASI_VERSION="$invalid" \
      STASI_SIGNING_MODE=none \
      STASI_APP_OUTPUT_DIR=.build/test-artifacts/invalid-version \
      ./scripts/make-app.sh >"$output" 2>&1; then
    printf 'Unerwartet akzeptiert: %q\n' "$invalid" >&2
    exit 1
  fi
  grep -q 'Ungültige STASI_VERSION' "$output"
  if grep -q 'Swift-Build' "$output"; then
    printf 'Ungültige Version startete unerwartet den Build: %q\n' "$invalid" >&2
    exit 1
  fi
  rm -f "$output"
done
```

Expected: Exitcode 0; jeder ungültige Wert wird vor dem Swift-Build abgelehnt.

- [ ] **Step 4: Smoke-Test um Bundle-Metadaten erweitern**

Ergänze nach der `APP`-Definition in `scripts/smoke-test-app.sh`:

```bash
INFO_PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/Stasi"
```

Ergänze direkt nach dem Aufruf von `make-app.sh`:

```bash
plutil -lint "$INFO_PLIST"

test "$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST"
)" = "app.stasi.macos"

test "$(
    /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST"
)" = "26.0"

if [[ -n "${STASI_VERSION:-}" ]]; then
    test "$(
        /usr/libexec/PlistBuddy \
            -c 'Print :CFBundleShortVersionString' \
            "$INFO_PLIST"
    )" = "$STASI_VERSION"

    test "$(
        /usr/libexec/PlistBuddy \
            -c 'Print :CFBundleVersion' \
            "$INFO_PLIST"
    )" = "$STASI_VERSION"
fi

if [[ -n "${STASI_RELEASE_API_URL:-}" ]]; then
    test "$(
        /usr/libexec/PlistBuddy \
            -c 'Print :STASI_RELEASE_API_URL' \
            "$INFO_PLIST"
    )" = "$STASI_RELEASE_API_URL"
fi

if [[ -n "${STASI_EXPECTED_ARCH:-}" ]]; then
    test "$(lipo -archs "$EXECUTABLE")" = "$STASI_EXPECTED_ARCH"
fi
```

- [ ] **Step 5: Shellsyntax prüfen**

```bash
bash -n scripts/make-app.sh scripts/smoke-test-app.sh
```

Expected: Exitcode 0.

- [ ] **Step 6: Release-Metadaten Ende-zu-Ende prüfen**

```bash
rm -rf build-release-metadata
STASI_VERSION=0.10.0 \
STASI_RELEASE_API_URL=https://api.github.com/repos/mm20261/stasi/releases/latest \
STASI_EXPECTED_ARCH=arm64 \
STASI_SIGNING_MODE=local \
STASI_APP_OUTPUT_DIR=build-release-metadata \
./scripts/smoke-test-app.sh
```

Expected: Smoke-Test besteht. Danach:

```bash
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  build-release-metadata/Stasi.app/Contents/Info.plist
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleVersion' \
  build-release-metadata/Stasi.app/Contents/Info.plist
/usr/libexec/PlistBuddy \
  -c 'Print :STASI_RELEASE_API_URL' \
  build-release-metadata/Stasi.app/Contents/Info.plist
lipo -archs build-release-metadata/Stasi.app/Contents/MacOS/Stasi
```

Expected:

```text
0.10.0
0.10.0
https://api.github.com/repos/mm20261/stasi/releases/latest
arm64
```

- [ ] **Step 7: Commit erstellen**

```bash
git add scripts/make-app.sh scripts/smoke-test-app.sh
git commit -m $'build(release): prüfe Bundle-Metadaten\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 2: Tag und exakten Release-Commit im Verify-Job auflösen

**Files:**
- Modify: `.github/workflows/release.yml:1-70`

**Interfaces:**
- Consumes: Push-Tag oder manueller Input `release_tag`
- Produces: Job-Outputs `release_tag`, `release_version`, `release_sha`

- [ ] **Step 1: Trigger und Job-Outputs definieren**

Ersetze den Workflow-Kopf bis einschließlich `verify.timeout-minutes` mit:

```yaml
name: Build, sign, notarize, and release app

on:
  push:
    tags:
      - "v*"
  workflow_dispatch:
    inputs:
      release_tag:
        description: Existing release tag in vMAJOR.MINOR.PATCH format
        required: true
        type: string

permissions:
  contents: read

concurrency:
  group: release-${{ github.ref }}-${{ inputs.release_tag }}
  cancel-in-progress: false

jobs:
  verify:
    runs-on: macos-26
    timeout-minutes: 60
    outputs:
      release_tag: ${{ steps.release.outputs.tag }}
      release_version: ${{ steps.release.outputs.version }}
      release_sha: ${{ steps.release.outputs.sha }}
```

- [ ] **Step 2: Checkout-Schritt durch strikte Tag-Auflösung ersetzen**

Der erste Schritt des Verify-Jobs lautet vollständig:

```yaml
      - name: Resolve and check out release tag
        id: release
        shell: bash
        env:
          EVENT_NAME: ${{ github.event_name }}
          PUSH_TAG: ${{ github.ref_name }}
          MANUAL_TAG: ${{ inputs.release_tag }}
          GITHUB_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail

          if [[ "$EVENT_NAME" == "push" ]]; then
            release_tag="$PUSH_TAG"
          else
            release_tag="$MANUAL_TAG"
          fi

          if [[ ! "$release_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
            printf 'Invalid release tag: %s\n' "$release_tag" >&2
            exit 1
          fi
          release_version="${release_tag#v}"

          askpass="$(mktemp "${RUNNER_TEMP}/stasi-askpass.XXXXXX")"
          cleanup_checkout() {
            rm -f "$askpass"
          }
          trap cleanup_checkout EXIT

          cat >"$askpass" <<'ASKPASS'
          #!/bin/bash
          case "$1" in
            *Username*) printf '%s\n' 'x-access-token' ;;
            *Password*) printf '%s\n' "$GITHUB_TOKEN" ;;
            *) exit 1 ;;
          esac
          ASKPASS
          chmod 700 "$askpass"

          repository_url="https://github.com/${GITHUB_REPOSITORY}.git"
          git init --quiet "$GITHUB_WORKSPACE"
          GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 \
            git -C "$GITHUB_WORKSPACE" \
              -c credential.helper= \
              fetch --quiet --no-tags --depth=1 \
              "$repository_url" \
              "refs/tags/${release_tag}:refs/tags/${release_tag}"

          release_sha="$(
            git -C "$GITHUB_WORKSPACE" \
              rev-parse "refs/tags/${release_tag}^{commit}"
          )"

          if [[ "$EVENT_NAME" == "push" ]]; then
            event_sha="$(
              git -C "$GITHUB_WORKSPACE" rev-parse "${GITHUB_SHA}^{commit}"
            )"
            if [[ "$event_sha" != "$release_sha" ]]; then
              printf '%s\n' 'Event SHA and release-tag commit differ.' >&2
              exit 1
            fi
          fi

          git -C "$GITHUB_WORKSPACE" checkout --quiet --detach "$release_sha"

          printf 'tag=%s\n' "$release_tag" >>"$GITHUB_OUTPUT"
          printf 'version=%s\n' "$release_version" >>"$GITHUB_OUTPUT"
          printf 'sha=%s\n' "$release_sha" >>"$GITHUB_OUTPUT"
```

- [ ] **Step 3: Verify-Builds mit Releasewerten ausführen**

Behalte den vorhandenen Testschritt. Ersetze Build- und Smoke-Schritt durch:

```yaml
      - name: Build local app
        shell: bash
        env:
          STASI_VERSION: ${{ steps.release.outputs.version }}
          STASI_RELEASE_API_URL: https://api.github.com/repos/mm20261/stasi/releases/latest
        run: |
          set -euo pipefail
          STASI_SIGNING_MODE=local ./scripts/make-app.sh

      - name: Run smoke test
        shell: bash
        env:
          STASI_VERSION: ${{ steps.release.outputs.version }}
          STASI_RELEASE_API_URL: https://api.github.com/repos/mm20261/stasi/releases/latest
          STASI_EXPECTED_ARCH: arm64
        run: |
          set -euo pipefail
          STASI_SIGNING_MODE=local ./scripts/smoke-test-app.sh
```

- [ ] **Step 4: YAML lokal parsen**

```bash
ruby -e 'require "yaml"; YAML.parse_file(ARGV.fetch(0))' \
  .github/workflows/release.yml
```

Expected: Exitcode 0.

- [ ] **Step 5: Actionlint ausführen**

Falls `actionlint` fehlt:

```bash
brew install actionlint
```

Danach:

```bash
actionlint .github/workflows/release.yml
```

Expected: keine Findings.

---

### Task 3: Geschützten Publish-Job fail-closed machen

**Files:**
- Modify: `.github/workflows/release.yml:71-207`

**Interfaces:**
- Consumes: `needs.verify.outputs.release_tag`, `release_version`, `release_sha`; sechs bestehende Environment-Secrets
- Produces: Developer-ID-signiertes, notarisiertes und geprüftes `build/Stasi.zip` plus `build/Stasi.zip.sha256`

- [ ] **Step 1: Job umbenennen und Rechte begrenzen**

Ersetze den bisherigen Jobkopf:

```yaml
  publish:
    needs: verify
    environment: release
    runs-on: macos-26
    timeout-minutes: 60
    permissions:
      contents: write
```

Die bisherige Branch-Bedingung `if: github.ref == 'refs/heads/main'` entfällt.

- [ ] **Step 2: Exakten verifizierten Commit frisch auschecken**

Verwende denselben temporären `GIT_ASKPASS`-Mechanismus wie im Verify-Job. Der Fetch lädt ausschließlich:

```bash
git -C "$GITHUB_WORKSPACE" \
  -c credential.helper= \
  fetch --quiet --no-tags --depth=1 \
  "$repository_url" \
  "${{ needs.verify.outputs.release_sha }}"
git -C "$GITHUB_WORKSPACE" checkout --quiet --detach FETCH_HEAD

test "$(git -C "$GITHUB_WORKSPACE" rev-parse HEAD)" \
  = "${{ needs.verify.outputs.release_sha }}"
```

Der Step-Name lautet `Check out verified release commit`.

- [ ] **Step 3: Unsigned App mit Releasewerten bauen und prüfen**

```yaml
      - name: Build unsigned release app
        shell: bash
        env:
          STASI_VERSION: ${{ needs.verify.outputs.release_version }}
          STASI_RELEASE_API_URL: https://api.github.com/repos/mm20261/stasi/releases/latest
        run: |
          set -euo pipefail
          STASI_SIGNING_MODE=none ./scripts/make-app.sh

          test "$(
            /usr/libexec/PlistBuddy \
              -c 'Print :CFBundleShortVersionString' \
              build/Stasi.app/Contents/Info.plist
          )" = "$STASI_VERSION"

          test "$(
            /usr/libexec/PlistBuddy \
              -c 'Print :CFBundleVersion' \
              build/Stasi.app/Contents/Info.plist
          )" = "$STASI_VERSION"

          test "$(
            /usr/libexec/PlistBuddy \
              -c 'Print :STASI_RELEASE_API_URL' \
              build/Stasi.app/Contents/Info.plist
          )" = "$STASI_RELEASE_API_URL"

          test "$(lipo -archs build/Stasi.app/Contents/MacOS/Stasi)" = "arm64"
```

- [ ] **Step 4: Fehlende Secrets hart ablehnen**

Behalte exakt diese Secret-Namen:

```text
STASI_DEVELOPER_ID_CERTIFICATE_BASE64
STASI_DEVELOPER_ID_CERTIFICATE_PASSWORD
STASI_DEVELOPER_ID_APPLICATION
STASI_NOTARY_PRIVATE_KEY_BASE64
STASI_NOTARY_KEY_ID
STASI_NOTARY_ISSUER_ID
```

Der Signierschritt heißt `Sign and notarize with Developer ID`. Ersetze den bisherigen Skip-Block durch:

```bash
if [[ -z "$STASI_DEVELOPER_ID_CERTIFICATE_BASE64" \
   || -z "$STASI_DEVELOPER_ID_CERTIFICATE_PASSWORD" \
   || -z "$STASI_DEVELOPER_ID_APPLICATION" \
   || -z "$STASI_NOTARY_PRIVATE_KEY_BASE64" \
   || -z "$STASI_NOTARY_KEY_ID" \
   || -z "$STASI_NOTARY_ISSUER_ID" ]]; then
  printf '%s\n' \
    'Required Developer-ID or notarization credentials are absent or incomplete.' \
    >&2
  exit 1
fi
```

- [ ] **Step 5: Vorhandene Signierung und Notarisierung beibehalten und härter prüfen**

Behalte temporären Schlüsselbund, PKCS#12-Import, `.p8`-Profil, Cleanup-Trap, Hardened Runtime, Timestamp und `Release/Stasi.entitlements`.

Ergänze nach dem Developer-ID-`codesign`:

```bash
codesign --verify --deep --strict --verbose=2 build/Stasi.app
codesign -d --verbose=4 build/Stasi.app 2>&1 | grep -Eq 'flags=.*runtime'

test "$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleIdentifier' \
    build/Stasi.app/Contents/Info.plist
)" = "app.stasi.macos"

test "$(lipo -archs build/Stasi.app/Contents/MacOS/Stasi)" = "arm64"
```

Nach erfolgreichem `notarytool submit --wait` bleiben zwingend:

```bash
xcrun stapler staple build/Stasi.app
xcrun stapler validate build/Stasi.app
codesign --verify --deep --strict --verbose=2 build/Stasi.app
spctl --assess --type execute --verbose=4 build/Stasi.app
```

- [ ] **Step 6: Endgültiges ZIP, Prüfsumme und Archivprüfung ergänzen**

Nach dem Packen:

```bash
(
  cd build
  shasum -a 256 Stasi.zip >Stasi.zip.sha256
  shasum -a 256 -c Stasi.zip.sha256
)

archive_check="$(mktemp -d "${RUNNER_TEMP}/stasi-archive-check.XXXXXX")"
ditto -x -k build/Stasi.zip "$archive_check"

test -d "$archive_check/Stasi.app"
test -f \
  "$archive_check/Stasi.app/Contents/Resources/Stasi_Stasi.bundle/MIT.txt"
test -f \
  "$archive_check/Stasi.app/Contents/Resources/Stasi_Stasi.bundle/Geist-OFL-1.1.txt"

codesign --verify --deep --strict --verbose=2 "$archive_check/Stasi.app"
xcrun stapler validate "$archive_check/Stasi.app"
spctl --assess --type execute --verbose=4 "$archive_check/Stasi.app"
test "$(lipo -archs "$archive_check/Stasi.app/Contents/MacOS/Stasi")" = "arm64"
rm -rf "$archive_check"
```

Der bestehende Signier-Cleanup muss auch bei Fehlern weiter Schlüsselbund und temporäre Schlüsseldateien entfernen.

- [ ] **Step 7: YAML und Shellblöcke prüfen**

```bash
ruby -e 'require "yaml"; YAML.parse_file(ARGV.fetch(0))' \
  .github/workflows/release.yml
actionlint .github/workflows/release.yml
```

Expected: keine Fehler.

---

### Task 4: GitHub Release erst nach allen Prüfungen veröffentlichen

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: geprüftes `build/Stasi.zip`, `build/Stasi.zip.sha256`, verifizierten bestehenden Tag
- Produces: GitHub Release `Stasi 0.10.0` mit exakt zwei Assets

- [ ] **Step 1: Finalen Release-Step ergänzen**

Als letzter Step des Publish-Jobs:

```yaml
      - name: Publish GitHub release
        shell: bash
        env:
          GH_TOKEN: ${{ github.token }}
          RELEASE_TAG: ${{ needs.verify.outputs.release_tag }}
          RELEASE_VERSION: ${{ needs.verify.outputs.release_version }}
        run: |
          set -euo pipefail

          gh release create "$RELEASE_TAG" \
            --repo "$GITHUB_REPOSITORY" \
            --verify-tag \
            --title "Stasi $RELEASE_VERSION" \
            --generate-notes \
            build/Stasi.zip \
            build/Stasi.zip.sha256
```

Ein bereits vorhandenes Release muss den Step fehlschlagen lassen; kein `--clobber` und kein stilles Update.

- [ ] **Step 2: Workflow statisch prüfen**

```bash
ruby -e 'require "yaml"; YAML.parse_file(ARGV.fetch(0))' \
  .github/workflows/release.yml
actionlint .github/workflows/release.yml
rg -n 'exit 0|signing and notarization skipped|refs/heads/main' \
  .github/workflows/release.yml
```

Expected: YAML und Actionlint grün; der letzte `rg`-Befehl liefert keine alten Skip-/Branch-Gate-Treffer.

- [ ] **Step 3: Diff auf Token- und Secret-Lecks prüfen**

```bash
git diff --check
git diff -- .github/workflows/release.yml
rg -n 'BEGIN (PRIVATE KEY|CERTIFICATE)|sk-|password:' \
  .github/workflows/release.yml scripts README.md docs || true
```

Expected: keine echten Zertifikate, Schlüssel oder Passwörter.

- [ ] **Step 4: Commit für Tasks 2–4 erstellen**

```bash
git add .github/workflows/release.yml
git commit -m $'ci(release): veröffentliche notarisiertes Tag\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 5: Öffentliche Installation und Release-Betrieb dokumentieren

**Files:**
- Modify: `README.md:8,43-73`
- Modify: `docs/release.md:1-150`

**Interfaces:**
- Consumes: Releasevertrag aus Tasks 1–4
- Produces: klare Endnutzer- und Betreiberanleitung; keine zusätzliche Versionsquelle in README

- [ ] **Step 1: README-Versionsüberschrift entkoppeln**

Ersetze:

```markdown
## Features (v0.9.0)
```

mit:

```markdown
## Features
```

- [ ] **Step 2: Voraussetzungen, Installation, Update und Deinstallation ergänzen**

Füge nach der Einleitung ein:

````markdown
## Voraussetzungen

- Apple Silicon
- macOS 26 oder neuer
- Für die Installation über Homebrew: Homebrew

## Installation

```bash
brew install --cask mm20261/tap/stasi
```

Beim ersten Start fordert macOS die notwendigen Berechtigungen für
Mikrofon und Bedienungshilfen an. Diese Zustimmungen werden nicht durch
Homebrew oder die App umgangen.

## Aktualisieren

```bash
brew upgrade --cask stasi
```

Die integrierte Update-Prüfung informiert über neue GitHub Releases.
Sie installiert Updates nicht selbst.

## Deinstallieren

App entfernen und lokale Daten behalten:

```bash
brew uninstall --cask stasi
```

App einschließlich Verlauf, Wörterbuch und Einstellungen entfernen:

```bash
brew uninstall --cask --zap stasi
```
````

Benenne den bisherigen Abschnitt `Bauen & Starten` in `Aus dem Quellcode bauen` um und kennzeichne ihn als Entwicklerweg.

- [ ] **Step 3: `docs/release.md` auf den Tag-Publish-Vertrag umstellen**

Dokumentiere exakt:

```markdown
- Tag: `vMAJOR.MINOR.PATCH`
- Bundle: `MAJOR.MINOR.PATCH`
- Release-Endpunkt: `https://api.github.com/repos/mm20261/stasi/releases/latest`
- Runner: `macos-26`, erste Veröffentlichung nur `arm64`
- Verify-Job: ohne Release-Secrets
- Publish-Job: Environment `release`, `contents: write`
- Fehlende Secrets: Fehler, kein Skip
- Assets: `Stasi.zip`, `Stasi.zip.sha256`
```

Behalte die sechs vorhandenen Secret-Namen unverändert. Ersetze die alte Regel „nur Branch `main` als Deploymentquelle“ durch:

```markdown
Das Environment `release` besitzt einen Required Reviewer. Zulässig sind
der geschützte Branch `main` für kontrollierte manuelle Läufe und eng
begrenzte Release-Tags `v*`. Ein Tag-Ruleset schützt Erstellung und Änderung
dieser Tags. Gleichnamige Repository- oder Organisationssecrets bleiben
verboten.
```

Ersetze jede Aussage, der Workflow könne nichts veröffentlichen oder fehlende Secrets erfolgreich überspringen.

Ergänze den manuellen Notfallpfad:

```bash
STASI_VERSION='0.10.0' \
STASI_RELEASE_API_URL='https://api.github.com/repos/mm20261/stasi/releases/latest' \
STASI_SIGNING_MODE=none \
./scripts/make-app.sh
```

und nach dem finalen ZIP:

```bash
(
  cd build
  shasum -a 256 Stasi.zip >Stasi.zip.sha256
  shasum -a 256 -c Stasi.zip.sha256
)
```

- [ ] **Step 4: Dokumentationsbefehle statisch prüfen**

```bash
rg -n 'workflow_dispatch|signing.*skipped|kein GitHub Release|kein Tag' \
  README.md docs/release.md
rg -n 'brew install --cask mm20261/tap/stasi|Stasi.zip.sha256|vMAJOR.MINOR.PATCH' \
  README.md docs/release.md
```

Expected: keine veralteten Aussagen; alle neuen Verträge sind vorhanden.

- [ ] **Step 5: Commit erstellen**

```bash
git add README.md docs/release.md
git commit -m $'docs(release): erkläre öffentliche Installation\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 6: Release-Vorbereitung vollständig lokal verifizieren

**Files:**
- Verify only: `scripts/make-app.sh`
- Verify only: `scripts/smoke-test-app.sh`
- Verify only: `.github/workflows/release.yml`
- Verify only: `README.md`
- Verify only: `docs/release.md`

**Interfaces:**
- Consumes: Tasks 1–5
- Produces: lokal grüner Release-Code für den separaten Veröffentlichungsplan

- [ ] **Step 1: Shell und Workflow prüfen**

```bash
bash -n scripts/make-app.sh scripts/smoke-test-app.sh
ruby -e 'require "yaml"; YAML.parse_file(ARGV.fetch(0))' \
  .github/workflows/release.yml
actionlint .github/workflows/release.yml
git diff --check main...HEAD
```

Expected: alle Befehle Exitcode 0.

- [ ] **Step 2: Vollständige Swift-Tests ausführen**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

Expected: Exitcode 0.

- [ ] **Step 3: Release-Metadaten-Smoke-Test ausführen**

```bash
rm -rf build-release-check
STASI_VERSION=0.10.0 \
STASI_RELEASE_API_URL=https://api.github.com/repos/mm20261/stasi/releases/latest \
STASI_EXPECTED_ARCH=arm64 \
STASI_SIGNING_MODE=local \
STASI_APP_OUTPUT_DIR=build-release-check \
./scripts/smoke-test-app.sh
```

Expected: Exitcode 0; Bundle-Version `0.10.0`, Update-Endpunkt korrekt, Architektur `arm64`.

- [ ] **Step 4: Arbeitsbaum und geplante Außenwirkungen prüfen**

```bash
git status --short --branch
git log --oneline main..HEAD
gh repo view mm20261/stasi --json visibility
```

Expected: nur geplante lokale Commits; Repository weiterhin `PRIVATE`; keine Tags und kein Release wurden erstellt.

- [ ] **Step 5: Review anfordern**

Nutze `superpowers:requesting-code-review`. Erst nach behobenen Findings und erneuter kompletter Prüfung beginnt `docs/superpowers/plans/2026-08-28-historie-und-veroeffentlichung.md`.
