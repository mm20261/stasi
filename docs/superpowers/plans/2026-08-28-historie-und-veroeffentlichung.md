# Git-Historie und öffentliche Veröffentlichung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den final geprüften lokalen Stand ohne Claude-Co-Author-Zuordnung und ohne öffentliche persönliche Commit-E-Mail auf GitHub veröffentlichen, anschließend `v0.10.0` signiert releasen und über Homebrew installierbar machen.

**Architecture:** Alle fachlichen Änderungen werden zuerst lokal abgeschlossen. Danach folgt ein Freeze. Ein separater Bare-Clone wird mit `git-filter-repo` umgeschrieben und objektgenau gegen ein lokales Backup geprüft. Force-Push, öffentliche Sichtbarkeit, Release-Tag und Homebrew-Tap sind vier getrennte Außenwirkungs-Gates. Kein Schritt kombiniert diese Aktionen.

**Tech Stack:** Git, `git-filter-repo`, Python 3, gitleaks, GitHub CLI, GitHub Actions, Apple Developer ID, Homebrew Cask

**Spec:** `docs/superpowers/specs/2026-08-28-transkript-release-und-autorenbereinigung-design.md`

## Global Constraints

- Voraussetzung: `docs/superpowers/plans/2026-08-28-transkript-neustartbereinigung.md` und `docs/superpowers/plans/2026-08-28-release-vorbereitung.md` sind vollständig umgesetzt, reviewt und grün.
- Ausgangsremote ist `https://github.com/mm20261/stasi.git`.
- Es wird ausschließlich der finale lokale `main` umgeschrieben.
- Commit-Anzahl wird am Freeze dynamisch ermittelt; sie ist nicht auf 98 fest verdrahtet.
- Author- und Committer-Name bleiben `Philipp Meder`.
- Author- und Committer-E-Mail werden `260910895+mm20261@users.noreply.github.com`.
- Nur Claude-/Anthropic-`Co-Authored-By`-Trailer werden entfernt; normale Textnennungen bleiben unberührt, sofern der öffentliche Audit sie nicht separat beanstandet.
- Tree, Parent-Reihenfolge, Topologie und Author-/Committer-Zeitstempel jedes Commits bleiben gleich.
- Kein `git push --mirror`, kein ungeschütztes `--force`, kein Branch- oder Tag-Sammelpush.
- Ein veränderter Remote-Tip beendet den Ablauf. Die Lease wird niemals still aktualisiert.
- Erster öffentlicher Release ist `v0.10.0` und nur `arm64` für macOS 26.
- Release-Freigabe erfolgt durch GitHub-Benutzer `mm20261` selbst; `prevent_self_review` bleibt deshalb `false`.
- Secrets werden interaktiv über `gh secret set` eingelesen und nie in Argumenten, Dateien, Logs oder Chat gespeichert.
- Vor jeder Außenwirkung muss der Executor den aktuellen Zustand zeigen und eine ausdrückliche Bestätigung für genau diese Aktion einholen.
- Claude Code erhält Shell-Variablen nicht zwischen Tool-Aufrufen. Tasks 4–13 speichern deshalb alle Operationswerte in `/private/tmp/stasi-publication.env`. Jeder spätere Shellblock beginnt mit `source /private/tmp/stasi-publication.env`.

---

### Task 1: Öffentlichen Repository-Audit abschließen

**Files:**
- Create: `docs/history-rewrite.md`
- Stop and create a separate reviewed follow-up plan if the audit finds publish-blocking content

**Interfaces:**
- Consumes: finalen Feature-Branch nach beiden vorherigen Plänen
- Produces: dokumentierten grünen Audit oder kleine separat getestete Fix-Commits; blockiert bei historischem echtem Secret

- [ ] **Step 1: Arbeitsbaum und vollständige Tests prüfen**

```bash
git status --short --branch
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
STASI_VERSION=0.10.0 \
STASI_RELEASE_API_URL=https://api.github.com/repos/mm20261/stasi/releases/latest \
STASI_EXPECTED_ARCH=arm64 \
STASI_SIGNING_MODE=local \
STASI_APP_OUTPUT_DIR=build-public-audit \
./scripts/smoke-test-app.sh
```

Expected: sauberer Arbeitsbaum vor dem Audit und alle Prüfungen Exitcode 0.

- [ ] **Step 2: Gitleaks installieren und vollständige Historie prüfen**

Falls `gitleaks` fehlt:

```bash
brew install gitleaks
```

Dann:

```bash
gitleaks version
gitleaks git --source . --redact --verbose
```

Expected: keine echten Secrets. Jeder Treffer wird einzeln klassifiziert:

1. False Positive mit Begründung in `docs/history-rewrite.md`.
2. Nur aktueller Inhalt: normaler Fix-Commit vor dem Freeze.
3. Historischer echter Secret-Wert: **sofort stoppen**, Secret rotieren und einen separaten Inhaltsrewrite entwerfen. Dieser Plan darf dann nicht fortgesetzt werden.

- [ ] **Step 3: Aktuellen und historischen Inhalt auf private Daten prüfen**

```bash
git grep -nI -E \
  '/Users/|/private/tmp|/var/folders/|serial|Serial|Team ID|Apple ID|Issuer ID|Key ID' \
  -- . ':!docs/superpowers/plans/*'

git rev-list --all | while read -r commit; do
  git grep -nI -E \
    '/Users/|/private/tmp|/var/folders/|serial|Serial|Team ID|Apple ID|Issuer ID|Key ID' \
    "$commit" -- . ':!docs/superpowers/plans/*' || true
done | sort -u
```

Expected: keine realen privaten Pfade, Hardwarekennungen oder Account-IDs in veröffentlichbarem Inhalt. Dokumentationsbeispiele werden nur behalten, wenn sie eindeutig künstlich sind.

- [ ] **Step 4: Große und binäre Objekte prüfen**

```bash
git rev-list --objects --all \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
  | sort -k3nr \
  | head -100
```

Prüfe insbesondere auf `.p8`, `.p12`, Schlüsselbunddateien, Audioaufnahmen, ZIP/DMG/PKG und Build-Artefakte. Kein solches privates Artefakt darf in der Historie bleiben.

- [ ] **Step 5: Claude-Nennungen nach Attribution und normalem Inhalt trennen**

```bash
git log --all \
  --regexp-ignore-case \
  --extended-regexp \
  --grep='^Co-Authored-By:.*(Claude|Anthropic)' \
  --format='%H %s'

git grep -nI -i -E 'claude|anthropic' || true
```

Der erste Befehl dokumentiert den Rewrite-Scope. Der zweite beeinflusst Contributor-Zuordnung nicht. Normale Texte werden nur entfernt, wenn sie intern, unnötig oder irreführend sind.

- [ ] **Step 6: Rewrite-Dokumentation erstellen**

`docs/history-rewrite.md` enthält:

```markdown
# Git-Historienbereinigung

## Zweck

Vor der öffentlichen Veröffentlichung werden ausschließlich Claude- und
Anthropic-Co-Author-Trailer entfernt. Author und Committer bleiben Philipp
Meder. Ihre E-Mail wird auf
`260910895+mm20261@users.noreply.github.com` gesetzt.

## Unverändert

- jeder Datei-Tree
- Parent-Reihenfolge und Merge-Topologie
- Author- und Committer-Zeitstempel
- Betreff und übriger Nachrichtentext

## Sicherheitsgrenzen

- dynamische Commit-Anzahl am Freeze
- Remote- und lokales Mirror-Backup
- objektgenaue Prüfung über die `git-filter-repo`-Commit-Map
- `--force-with-lease` nur für `refs/heads/main`
- kein `git push --mirror`
- Abbruch bei neuem Remote-Tip, Tag, Release, Branch oder Pull Request

## Öffentlicher Audit

Dokumentiere gitleaks-Version, Ergebnis, geprüfte große Objekte und jede
begründete False-Positive-Entscheidung. Echte Secrets stoppen den Ablauf.
```

- [ ] **Step 7: Bei veröffentlichungsblockierenden Befunden stoppen**

Wenn der Audit eine zu ändernde Datei oder einen historischen echten Secret-Wert findet, wird dieser Plan nicht fortgesetzt. Dokumentiere den Befund, rotiere betroffene Secrets sofort und erstelle einen eigenen freigegebenen Folgeplan mit den dann exakt bekannten Pfaden. Ohne Befund geht es direkt weiter.

- [ ] **Step 8: Audit-Dokumentation committen**

```bash
git add docs/history-rewrite.md
git commit -m $'docs(git): dokumentiere Historienbereinigung\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 2: Objektgenauen Rewrite-Verifier hinzufügen

**Files:**
- Create: `scripts/verify-history-rewrite.py`

**Interfaces:**
- Consumes: `--before "$LOCAL_BACKUP"`, `--after "$REWRITE_REPO"`, `--commit-map "$COMMIT_MAP"`
- Produces: Exitcode 0 nur bei vollständiger, ausschließlich erlaubter Transformation

- [ ] **Step 1: Verifier-Skript erstellen**

Erstelle `scripts/verify-history-rewrite.py` exakt mit diesem Inhalt:

```python
#!/usr/bin/env python3

import argparse
import pathlib
import re
import subprocess
import sys

EXPECTED_NAME = b"Philipp Meder"
EXPECTED_EMAIL = b"260910895+mm20261@users.noreply.github.com"
TRAILER_PATTERN = re.compile(
    br"(?i)^Co-Authored-By[ \t]*:[ \t]*(.*?)[ \t]*$"
)


def git(repo: str, *args: str) -> bytes:
    return subprocess.check_output(
        ["git", "-C", repo, *args],
        stderr=subprocess.STDOUT,
    )


def commits(repo: str) -> list[str]:
    output = git(
        repo,
        "rev-list",
        "--topo-order",
        "--reverse",
        "refs/heads/main",
    )
    return output.decode("ascii").splitlines()


def metadata(repo: str, sha: str) -> list[bytes]:
    output = git(
        repo,
        "show",
        "-s",
        (
            "--format="
            "%T%x00%P%x00"
            "%an%x00%ae%x00"
            "%cn%x00%ce%x00"
            "%aI%x00%cI"
        ),
        sha,
    ).rstrip(b"\n")
    fields = output.split(b"\x00")
    if len(fields) != 8:
        raise RuntimeError(f"unexpected metadata field count for {sha}")
    return fields


def raw_message(repo: str, sha: str) -> bytes:
    raw_commit = git(repo, "cat-file", "commit", sha)
    _, separator, message = raw_commit.partition(b"\n\n")
    if not separator:
        raise RuntimeError(f"commit {sha} has no header/message separator")
    return message


def clean_message(message: bytes) -> bytes:
    kept_lines: list[bytes] = []
    removed_target = False

    for line in message.splitlines(keepends=True):
        logical_line = line.rstrip(b"\r\n")
        match = TRAILER_PATTERN.fullmatch(logical_line)
        if match:
            value = match.group(1).lower()
            if b"claude" in value or b"anthropic" in value:
                removed_target = True
                continue
        kept_lines.append(line)

    rewritten = b"".join(kept_lines)
    if removed_target:
        rewritten = rewritten.rstrip(b"\r\n") + b"\n"
    return rewritten


def contains_target_trailer(message: bytes) -> bool:
    for line in message.splitlines():
        match = TRAILER_PATTERN.fullmatch(line.rstrip(b"\r\n"))
        if not match:
            continue
        value = match.group(1).lower()
        if b"claude" in value or b"anthropic" in value:
            return True
    return False


def read_commit_map(path: pathlib.Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for index, line in enumerate(path.read_text(encoding="ascii").splitlines()):
        if index == 0 and line.strip() == "old                                      new":
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        old_sha, new_sha = parts
        if new_sha == "0" * 40:
            raise RuntimeError(f"commit was deleted: {old_sha}")
        mapping[old_sha] = new_sha
    return mapping


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--commit-map", required=True)
    args = parser.parse_args()

    before_commits = commits(args.before)
    after_commits = commits(args.after)
    mapping = read_commit_map(pathlib.Path(args.commit_map))

    if len(before_commits) != len(after_commits):
        fail(
            f"commit count changed: "
            f"{len(before_commits)} -> {len(after_commits)}"
        )

    missing = [sha for sha in before_commits if sha not in mapping]
    if missing:
        fail(f"commit map misses {len(missing)} reachable commits")

    mapped_commits = [mapping[sha] for sha in before_commits]
    if set(mapped_commits) != set(after_commits):
        fail("mapped commit set differs from rewritten reachable set")

    for old_sha in before_commits:
        new_sha = mapping[old_sha]
        old_meta = metadata(args.before, old_sha)
        new_meta = metadata(args.after, new_sha)

        if old_meta[0] != new_meta[0]:
            fail(f"tree changed: {old_sha} -> {new_sha}")

        old_parents = old_meta[1].decode("ascii").split()
        new_parents = new_meta[1].decode("ascii").split()
        expected_parents = [mapping[parent] for parent in old_parents]
        if expected_parents != new_parents:
            fail(f"parent topology changed: {old_sha} -> {new_sha}")

        if new_meta[2] != EXPECTED_NAME:
            fail(f"unexpected author name at {new_sha}")
        if new_meta[3] != EXPECTED_EMAIL:
            fail(f"unexpected author email at {new_sha}")
        if new_meta[4] != EXPECTED_NAME:
            fail(f"unexpected committer name at {new_sha}")
        if new_meta[5] != EXPECTED_EMAIL:
            fail(f"unexpected committer email at {new_sha}")
        if old_meta[6] != new_meta[6]:
            fail(f"author timestamp changed at {old_sha}")
        if old_meta[7] != new_meta[7]:
            fail(f"committer timestamp changed at {old_sha}")

        old_message = raw_message(args.before, old_sha)
        new_message = raw_message(args.after, new_sha)
        if new_message != clean_message(old_message):
            fail(f"unexpected message change at {old_sha}")
        if contains_target_trailer(new_message):
            fail(f"target co-author trailer remains at {new_sha}")

    old_tip = git(
        args.before,
        "rev-parse",
        "refs/heads/main",
    ).decode("ascii").strip()
    new_tip = git(
        args.after,
        "rev-parse",
        "refs/heads/main",
    ).decode("ascii").strip()
    if mapping[old_tip] != new_tip:
        fail("rewritten main tip does not match commit map")

    print(f"PASS: {len(before_commits)} commits verified")
    print(f"old tip: {old_tip}")
    print(f"new tip: {new_tip}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Syntax und CLI-Vertrag prüfen**

```bash
chmod +x scripts/verify-history-rewrite.py
python3 -m py_compile scripts/verify-history-rewrite.py
scripts/verify-history-rewrite.py --help
```

Expected: kein Syntaxfehler; Hilfe nennt `--before`, `--after`, `--commit-map`.

- [ ] **Step 3: Commit erstellen**

```bash
git add scripts/verify-history-rewrite.py
git commit -m $'test(git): prüfe Attribution-Rewrite\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 3: Feature-Branch integrieren und Freeze setzen

**Files:**
- No file changes

**Interfaces:**
- Consumes: vollständig grünen `feature/transcript-release-cleanup`
- Produces: finalen lokalen `main`, dessen dynamische Baseline umgeschrieben wird

- [ ] **Step 1: Feature-Branch erneut vollständig prüfen**

```bash
git status --short --branch
git log --oneline main..feature/transcript-release-cleanup
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
STASI_VERSION=0.10.0 \
STASI_RELEASE_API_URL=https://api.github.com/repos/mm20261/stasi/releases/latest \
STASI_EXPECTED_ARCH=arm64 \
STASI_SIGNING_MODE=local \
STASI_APP_OUTPUT_DIR=build-final-freeze \
./scripts/smoke-test-app.sh
```

Expected: sauberer Arbeitsbaum und alle Prüfungen Exitcode 0.

- [ ] **Step 2: `main` unverändert gegen Remote prüfen**

```bash
git fetch origin main --prune
git rev-parse main
git rev-parse origin/main
git log --oneline --left-right main...origin/main
```

Expected vor Integration: `main` und `origin/main` sind identisch. Bei Abweichung stoppen und Herkunft der neuen Commits prüfen.

- [ ] **Step 3: Lokal fast-forward integrieren**

```bash
git switch main
git merge --ff-only feature/transcript-release-cleanup
```

Expected: Fast-forward. Bei Fehlschlag nicht rebasen oder mergen; stoppen und neu planen.

- [ ] **Step 4: Freeze-Werte protokollieren**

```bash
SOURCE_REPO="/Users/philippmeder/Downloads/AI_Code/Anwendungen/Stasi"
SOURCE_TIP="$(git -C "$SOURCE_REPO" rev-parse refs/heads/main)"
SOURCE_TREE="$(git -C "$SOURCE_REPO" rev-parse 'refs/heads/main^{tree}')"
SOURCE_COUNT="$(git -C "$SOURCE_REPO" rev-list --count refs/heads/main)"
printf 'SOURCE_TIP=%s\nSOURCE_TREE=%s\nSOURCE_COUNT=%s\n' \
  "$SOURCE_TIP" "$SOURCE_TREE" "$SOURCE_COUNT"
```

Ab jetzt bis zum Force-Push: keine Commits, Amends, Rebases, Tags, Branch-Pushes oder GitHub-Änderungen.

---

### Task 4: Dynamische Backups und eng begrenzten Rewrite-Klon erstellen

**Files:**
- External operations directory only; no repository changes

**Interfaces:**
- Consumes: gefrorenen lokalen `main`, unveränderten Remote-Tip
- Produces: Remote-Backup, lokales Final-Backup und Bare-Rewrite-Repo

- [ ] **Step 1: Operations-Verzeichnis und Variablen erstellen**

```bash
ENV_FILE=/private/tmp/stasi-publication.env
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OPS_ROOT="/Users/philippmeder/Downloads/AI_Code/Anwendungen/stasi-publication-${RUN_ID}"
SOURCE_REPO="/Users/philippmeder/Downloads/AI_Code/Anwendungen/Stasi"
REMOTE_URL="https://github.com/mm20261/stasi.git"
REMOTE_BACKUP="${OPS_ROOT}/remote-before-rewrite.git"
LOCAL_BACKUP="${OPS_ROOT}/local-before-rewrite.git"
REWRITE_REPO="${OPS_ROOT}/rewrite-main.git"
VALIDATION_CLONE="${OPS_ROOT}/validation-clone"
mkdir -p "$OPS_ROOT"
printf 'export %s=%q\n' \
  ENV_FILE "$ENV_FILE" \
  RUN_ID "$RUN_ID" \
  OPS_ROOT "$OPS_ROOT" \
  SOURCE_REPO "$SOURCE_REPO" \
  REMOTE_URL "$REMOTE_URL" \
  REMOTE_BACKUP "$REMOTE_BACKUP" \
  LOCAL_BACKUP "$LOCAL_BACKUP" \
  REWRITE_REPO "$REWRITE_REPO" \
  VALIDATION_CLONE "$VALIDATION_CLONE" \
  >"$ENV_FILE"
source "$ENV_FILE"
```

- [ ] **Step 2: Baseline dynamisch erfassen**

```bash
source /private/tmp/stasi-publication.env
SOURCE_TIP="$(git -C "$SOURCE_REPO" rev-parse refs/heads/main)"
SOURCE_TREE="$(git -C "$SOURCE_REPO" rev-parse 'refs/heads/main^{tree}')"
SOURCE_COUNT="$(git -C "$SOURCE_REPO" rev-list --count refs/heads/main)"
REMOTE_TIP="$(git ls-remote "$REMOTE_URL" refs/heads/main | cut -f1)"

git -C "$SOURCE_REPO" merge-base --is-ancestor "$REMOTE_TIP" "$SOURCE_TIP"
printf 'export %s=%q\n' \
  SOURCE_TIP "$SOURCE_TIP" \
  SOURCE_TREE "$SOURCE_TREE" \
  SOURCE_COUNT "$SOURCE_COUNT" \
  REMOTE_TIP "$REMOTE_TIP" \
  >>"$ENV_FILE"
printf '%s\n' \
  "SOURCE_TIP=$SOURCE_TIP" \
  "SOURCE_TREE=$SOURCE_TREE" \
  "SOURCE_COUNT=$SOURCE_COUNT" \
  "REMOTE_TIP=$REMOTE_TIP" \
  | tee "$OPS_ROOT/baseline.txt"
```

Expected: Remote-Tip ist Vorfahr des finalen lokalen Tips. `SOURCE_COUNT` umfasst alle neuen Commits.

- [ ] **Step 3: Zwei unabhängige Mirror-Backups erstellen**

```bash
source /private/tmp/stasi-publication.env
git clone --mirror "$REMOTE_URL" "$REMOTE_BACKUP"
git -C "$REMOTE_BACKUP" fsck --full

git clone --mirror "$SOURCE_REPO" "$LOCAL_BACKUP"
git -C "$LOCAL_BACKUP" fsck --full
```

Expected: beide `fsck`-Läufe ohne Fehler.

- [ ] **Step 4: Nur finalen lokalen `main` klonen**

```bash
source /private/tmp/stasi-publication.env
git clone --bare --single-branch --branch main \
  "$SOURCE_REPO" "$REWRITE_REPO"

test "$(git -C "$REWRITE_REPO" rev-parse refs/heads/main)" = "$SOURCE_TIP"
test "$(git -C "$REWRITE_REPO" rev-list --count refs/heads/main)" = "$SOURCE_COUNT"
git -C "$REWRITE_REPO" show-ref
```

Expected: nur beabsichtigter `main`; keine lokalen Nebenbranches oder Tags.

---

### Task 5: Attribution und E-Mail in einem kontrollierten Lauf umschreiben

**Files:**
- External bare repository: `$REWRITE_REPO`

**Interfaces:**
- Consumes: Rewrite-Repo und Backups aus Task 4
- Produces: neuen `main` mit gleicher Struktur, Noreply-E-Mail und ohne Claude-/Anthropic-Trailer

- [ ] **Step 1: `git-filter-repo` installieren und Version protokollieren**

Falls nicht vorhanden:

```bash
brew install git-filter-repo
```

Dann:

```bash
source /private/tmp/stasi-publication.env
git filter-repo --version | tee "$OPS_ROOT/git-filter-repo-version.txt"
```

- [ ] **Step 2: Rewrite exakt ausführen**

```bash
source /private/tmp/stasi-publication.env
git -C "$REWRITE_REPO" filter-repo \
  --force \
  --refs refs/heads/main \
  --message-callback '
import re

trailer_pattern = re.compile(
    br"(?i)^Co-Authored-By[ \t]*:[ \t]*(.*?)[ \t]*$"
)
kept_lines = []
removed_target = False
for line in message.splitlines(keepends=True):
    logical_line = line.rstrip(b"\r\n")
    match = trailer_pattern.fullmatch(logical_line)
    if match:
        trailer_value = match.group(1).lower()
        if b"claude" in trailer_value or b"anthropic" in trailer_value:
            removed_target = True
            continue
    kept_lines.append(line)
rewritten = b"".join(kept_lines)
if removed_target:
    rewritten = rewritten.rstrip(b"\r\n") + b"\n"
return rewritten
' \
  --commit-callback '
expected_name = b"Philipp Meder"
expected_email = b"260910895+mm20261@users.noreply.github.com"
if commit.author_name != expected_name:
    raise RuntimeError("unexpected author name; aborting rewrite")
if commit.committer_name != expected_name:
    raise RuntimeError("unexpected committer name; aborting rewrite")
commit.author_name = expected_name
commit.committer_name = expected_name
commit.author_email = expected_email
commit.committer_email = expected_email
'
```

Expected: kein unerwarteter Name; Rewrite endet erfolgreich.

- [ ] **Step 3: Objektgenauen Verifier ausführen**

```bash
source /private/tmp/stasi-publication.env
COMMIT_MAP="$(
  git -C "$REWRITE_REPO" rev-parse --git-path filter-repo/commit-map
)"

python3 "$SOURCE_REPO/scripts/verify-history-rewrite.py" \
  --before "$LOCAL_BACKUP" \
  --after "$REWRITE_REPO" \
  --commit-map "$COMMIT_MAP" \
  | tee "$OPS_ROOT/rewrite-verification.txt"
```

Expected:

Expected: Die Ausgabe beginnt mit `PASS:` und nennt exakt den Wert aus `$SOURCE_COUNT`.

- [ ] **Step 4: Dynamische Gesamtwerte und Integrität prüfen**

```bash
source /private/tmp/stasi-publication.env
REWRITTEN_TIP="$(git -C "$REWRITE_REPO" rev-parse refs/heads/main)"
REWRITTEN_TREE="$(git -C "$REWRITE_REPO" rev-parse 'refs/heads/main^{tree}')"
REWRITTEN_COUNT="$(git -C "$REWRITE_REPO" rev-list --count refs/heads/main)"
printf 'export %s=%q\n' \
  REWRITTEN_TIP "$REWRITTEN_TIP" \
  REWRITTEN_TREE "$REWRITTEN_TREE" \
  REWRITTEN_COUNT "$REWRITTEN_COUNT" \
  >>"$ENV_FILE"

test "$REWRITTEN_TREE" = "$SOURCE_TREE"
test "$REWRITTEN_COUNT" = "$SOURCE_COUNT"
git -C "$REWRITE_REPO" fsck --full
git -C "$REWRITE_REPO" show-ref
```

Expected: Tree und Count gleich; nur `main`; keine beschädigten Objekte.

---

### Task 6: Frischen lokalen Clone des Rewrites testen

**Files:**
- External validation clone only

**Interfaces:**
- Consumes: vollständig verifiziertes Rewrite-Repo
- Produces: Build- und Testnachweis ohne Änderung des GitHub-Remotes

- [ ] **Step 1: Frischen Clone erstellen**

```bash
source /private/tmp/stasi-publication.env
git clone "$REWRITE_REPO" "$VALIDATION_CLONE"
git -C "$VALIDATION_CLONE" status --short --branch
test "$(git -C "$VALIDATION_CLONE" rev-parse HEAD)" = "$REWRITTEN_TIP"
test "$(git -C "$VALIDATION_CLONE" rev-parse 'HEAD^{tree}')" = "$SOURCE_TREE"
```

- [ ] **Step 2: Vollständige Tests aus diesem Clone ausführen**

```bash
source /private/tmp/stasi-publication.env
cd "$VALIDATION_CLONE"
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

Expected: Exitcode 0.

- [ ] **Step 3: App und Smoke-Test aus diesem Clone ausführen**

```bash
source /private/tmp/stasi-publication.env
cd "$VALIDATION_CLONE"
STASI_VERSION=0.10.0 \
STASI_RELEASE_API_URL=https://api.github.com/repos/mm20261/stasi/releases/latest \
STASI_EXPECTED_ARCH=arm64 \
STASI_SIGNING_MODE=local \
./scripts/smoke-test-app.sh
```

Expected: Exitcode 0.

---

### Task 7: Force-Push von `main` separat freigeben und durchführen

**Files:**
- Remote ref only after confirmation

**Interfaces:**
- Consumes: grünen Validation-Clone, ursprünglichen `REMOTE_TIP`, neuen `REWRITTEN_TIP`
- Produces: bereinigten privaten GitHub-`main`

- [ ] **Step 1: Remotezustand unmittelbar vorher vollständig prüfen**

```bash
source /private/tmp/stasi-publication.env
git ls-remote --symref "$REMOTE_URL"
git ls-remote --heads "$REMOTE_URL"
git ls-remote --tags "$REMOTE_URL"
gh repo view mm20261/stasi \
  --json nameWithOwner,visibility,defaultBranchRef,url
gh pr list --repo mm20261/stasi --state all --limit 100 \
  --json number,title,state,headRefName,baseRefName,url
gh release list --repo mm20261/stasi --limit 100
CURRENT_REMOTE_TIP="$(git ls-remote "$REMOTE_URL" refs/heads/main | cut -f1)"
test "$CURRENT_REMOTE_TIP" = "$REMOTE_TIP"
```

Stoppe bei neuem Commit, Branch, Tag, Release, PR oder unerwarteter Sichtbarkeit. Die Lease darf nicht auf einen neuen Wert angepasst werden.

- [ ] **Step 2: Benutzerbestätigung für genau den Force-Push einholen**

Zeige:

```text
Remote: mm20261/stasi
Ref: refs/heads/main
Alter Tip: $REMOTE_TIP
Neuer Tip: $REWRITTEN_TIP
Commit-Anzahl: $SOURCE_COUNT
Tree unverändert: $SOURCE_TREE
Backups: $REMOTE_BACKUP und $LOCAL_BACKUP
```

Frage ausdrücklich, ob genau dieser geschützte Force-Push jetzt ausgeführt werden soll. Ohne neues Ja stoppen.

- [ ] **Step 3: Nur `main` mit exakter Lease pushen**

Nach Bestätigung:

```bash
source /private/tmp/stasi-publication.env
git -C "$REWRITE_REPO" remote add publish "$REMOTE_URL"
git -C "$REWRITE_REPO" push \
  --force-with-lease="refs/heads/main:${REMOTE_TIP}" \
  publish \
  refs/heads/main:refs/heads/main
```

- [ ] **Step 4: Veröffentlichten Tip prüfen**

```bash
source /private/tmp/stasi-publication.env
PUBLISHED_TIP="$(git ls-remote "$REMOTE_URL" refs/heads/main | cut -f1)"
test "$PUBLISHED_TIP" = "$REWRITTEN_TIP"
```

Expected: exakter neuer Tip.

---

### Task 8: Frischen GitHub-Clone und Attribution prüfen

**Files:**
- External fresh clone only

**Interfaces:**
- Consumes: erfolgreich bereinigten privaten Remote
- Produces: GitHub- und Git-Nachweis, dass nur Philipp zugeordnet wird

- [ ] **Step 1: Frischen Remote-Clone erstellen und lokale Identität setzen**

```bash
source /private/tmp/stasi-publication.env
FRESH_CLONE="${OPS_ROOT}/fresh-github-clone"
printf 'export FRESH_CLONE=%q\n' "$FRESH_CLONE" >>"$ENV_FILE"
git clone "$REMOTE_URL" "$FRESH_CLONE"
git -C "$FRESH_CLONE" config --local user.name "Philipp Meder"
git -C "$FRESH_CLONE" config --local \
  user.email "260910895+mm20261@users.noreply.github.com"
```

- [ ] **Step 2: Lokale Attribution prüfen**

```bash
source /private/tmp/stasi-publication.env
git -C "$FRESH_CLONE" shortlog -sne --all
git -C "$FRESH_CLONE" log --all --format='%cn <%ce>' | sort -u
git -C "$FRESH_CLONE" log --all \
  --regexp-ignore-case \
  --extended-regexp \
  --grep='^Co-Authored-By:.*(Claude|Anthropic)' \
  --format='%H %s'
```

Expected: nur `Philipp Meder <260910895+mm20261@users.noreply.github.com>`; letzter Befehl ohne Ausgabe.

- [ ] **Step 3: GitHub-Konto und Contributors prüfen**

```bash
source /private/tmp/stasi-publication.env
gh api user --jq '{login: .login, id: .id}'
gh api --method GET repos/mm20261/stasi/contributors -f anon=1
```

Expected: Login `mm20261`, ID `260910895`, Contributors-Liste nur mit `mm20261`.

- [ ] **Step 4: Root und Tip über GraphQL prüfen**

```bash
source /private/tmp/stasi-publication.env
ROOT_SHA="$(git -C "$FRESH_CLONE" rev-list --max-parents=0 HEAD)"
TIP_SHA="$(git -C "$FRESH_CLONE" rev-parse HEAD)"
for oid in "$ROOT_SHA" "$TIP_SHA"; do
  gh api graphql \
    -f owner=mm20261 \
    -f name=stasi \
    -f oid="$oid" \
    -f query='query($owner:String!,$name:String!,$oid:GitObjectID!){repository(owner:$owner,name:$name){object(oid:$oid){... on Commit{oid authors(first:10){nodes{name email user{login}}}}}}}'
done
```

Expected: je Commit genau Philipp/`mm20261`; kein Claude-Knoten.

---

### Task 9: Hauptrepository separat öffentlich schalten und schützen

**Files:**
- GitHub repository settings only after confirmation

**Interfaces:**
- Consumes: grünen privaten Remote und grünen öffentlichen Audit
- Produces: öffentliches, gegen Löschung und Force-Push geschütztes `mm20261/stasi`

- [ ] **Step 1: Letzte Vorbedingungen zeigen**

Prüfe erneut:

```bash
source /private/tmp/stasi-publication.env
gh repo view mm20261/stasi --json visibility,defaultBranchRef,url
gh release list --repo mm20261/stasi
git ls-remote --tags "$REMOTE_URL"
git -C "$FRESH_CLONE" status --short --branch
```

Expected: weiterhin `PRIVATE`, keine Tags, keine Releases, sauberer Clone.

- [ ] **Step 2: Benutzerbestätigung für genau die Sichtbarkeitsänderung einholen**

Frage ausdrücklich, ob `https://github.com/mm20261/stasi` jetzt vollständig öffentlich werden soll. Nenne, dass Quellcode und bereinigte gesamte Historie danach für alle sichtbar sind. Ohne neues Ja stoppen.

- [ ] **Step 3: Repository öffentlich schalten**

Nach Bestätigung:

```bash
gh repo edit mm20261/stasi \
  --visibility public \
  --accept-visibility-change-consequences
```

- [ ] **Step 4: `main` gegen Löschung und Force-Push schützen**

```bash
gh api --method PUT repos/mm20261/stasi/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": true
}
JSON
```

- [ ] **Step 5: Sichtbarkeit und Schutz prüfen**

```bash
gh repo view mm20261/stasi --json visibility,defaultBranchRef,url
gh api repos/mm20261/stasi/branches/main/protection
```

Expected: `PUBLIC`, Force-Push und Löschung nicht erlaubt.

---

### Task 10: Release-Environment und Secrets einrichten

**Files:**
- GitHub environment settings only

**Interfaces:**
- Consumes: öffentlichen geschützten `main`; GitHub-User-ID `260910895`; sechs echte Apple-Werte
- Produces: Environment `release`, Selbstfreigabe durch `mm20261`, begrenzte Deploymentquellen

- [ ] **Step 1: Environment mit eigenem Reviewer erstellen**

```bash
gh api --method PUT repos/mm20261/stasi/environments/release \
  --input - <<'JSON'
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [
    {
      "type": "User",
      "id": 260910895
    }
  ],
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
JSON
```

- [ ] **Step 2: Deployment-Quellen auf `main` und Release-Tags begrenzen**

```bash
gh api --method POST \
  repos/mm20261/stasi/environments/release/deployment-branch-policies \
  -f name='main' \
  -f type='branch'

gh api --method POST \
  repos/mm20261/stasi/environments/release/deployment-branch-policies \
  -f name='v*' \
  -f type='tag'
```

Falls die GitHub-API den `type=tag`-Vertrag für das Konto ablehnt, **stoppen** und dieselbe Regel über **Settings → Environments → release → Deployment branches and tags** einrichten. Nicht auf uneingeschränkte Tags ausweichen.

- [ ] **Step 3: Sechs Secrets interaktiv setzen**

Jeder Befehl liest den Wert verdeckt aus der Standardeingabe. Werte niemals in die Befehlszeile einfügen:

```bash
gh secret set STASI_DEVELOPER_ID_CERTIFICATE_BASE64 \
  --repo mm20261/stasi --env release
gh secret set STASI_DEVELOPER_ID_CERTIFICATE_PASSWORD \
  --repo mm20261/stasi --env release
gh secret set STASI_DEVELOPER_ID_APPLICATION \
  --repo mm20261/stasi --env release
gh secret set STASI_NOTARY_PRIVATE_KEY_BASE64 \
  --repo mm20261/stasi --env release
gh secret set STASI_NOTARY_KEY_ID \
  --repo mm20261/stasi --env release
gh secret set STASI_NOTARY_ISSUER_ID \
  --repo mm20261/stasi --env release
```

Wenn ein Wert aus einer lokalen Datei erzeugt werden muss, bereitet die Benutzerperson den Base64-Wert außerhalb des Repositorys vor und fügt ihn verdeckt in die interaktive Eingabe von `gh secret set` ein. Lokale Pfade werden nicht gespeichert oder protokolliert.

- [ ] **Step 4: Environment und Secret-Namen prüfen**

```bash
gh api repos/mm20261/stasi/environments/release
gh secret list --repo mm20261/stasi --env release
```

Expected: genau sechs erwartete Namen; keine Werte werden angezeigt.

---

### Task 11: Ersten Release-Tag separat freigeben und veröffentlichen

**Files:**
- Git tag and GitHub release only after confirmation

**Interfaces:**
- Consumes: öffentlichen geschützten `main`, eingerichtetes Environment, Release-Version `0.10.0`
- Produces: `v0.10.0`, erfolgreichen Workflow, `Stasi.zip`, `Stasi.zip.sha256`

- [ ] **Step 1: Release-SHA und Version lokal verifizieren**

```bash
source /private/tmp/stasi-publication.env
cd "$FRESH_CLONE"
git fetch origin main --prune
git switch main
git reset --hard origin/main
VERIFIED_SHA="$(git rev-parse origin/main)"

rm -rf build-release-final
STASI_VERSION=0.10.0 \
STASI_RELEASE_API_URL=https://api.github.com/repos/mm20261/stasi/releases/latest \
STASI_EXPECTED_ARCH=arm64 \
STASI_SIGNING_MODE=local \
STASI_APP_OUTPUT_DIR=build-release-final \
./scripts/smoke-test-app.sh

test "$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    build-release-final/Stasi.app/Contents/Info.plist
)" = "0.10.0"
```

- [ ] **Step 2: Annotierten Tag nur lokal erstellen und prüfen**

```bash
git tag -a v0.10.0 "$VERIFIED_SHA" -m 'Stasi 0.10.0'
git show --no-patch --decorate v0.10.0
test "$(git rev-parse 'v0.10.0^{commit}')" = "$VERIFIED_SHA"
```

- [ ] **Step 3: Benutzerbestätigung für genau den Tag-Push einholen**

Zeige Zielrepo, Tag `v0.10.0`, `VERIFIED_SHA` und Hinweis: Der Push startet den signierten Publish-Workflow und kann ein öffentliches Release erzeugen. Ohne neues Ja stoppen.

- [ ] **Step 4: Nur den geprüften Tag pushen**

```bash
git push origin refs/tags/v0.10.0
```

- [ ] **Step 5: Workflow beobachten und selbst freigeben**

```bash
gh run list --repo mm20261/stasi --workflow release.yml --limit 10
gh run watch --repo mm20261/stasi --exit-status
```

Wenn GitHub das Environment-Gate zeigt, genehmigt `mm20261` den Lauf bewusst in GitHub. Bei Signier-, Notarisierungs- oder Gatekeeper-Fehlern nichts umgehen; Lauf bleibt fehlgeschlagen.

- [ ] **Step 6: Release und Assets prüfen**

```bash
source /private/tmp/stasi-publication.env
gh release view v0.10.0 --repo mm20261/stasi \
  --json tagName,isDraft,isPrerelease,url,assets
mkdir -p "$OPS_ROOT/release-check"
gh release download v0.10.0 --repo mm20261/stasi \
  --pattern 'Stasi.zip*' \
  --dir "$OPS_ROOT/release-check"
cd "$OPS_ROOT/release-check"
shasum -a 256 -c Stasi.zip.sha256
ditto -x -k Stasi.zip extracted
codesign --verify --deep --strict --verbose=2 extracted/Stasi.app
xcrun stapler validate extracted/Stasi.app
spctl --assess --type execute --verbose=4 extracted/Stasi.app
test "$(lipo -archs extracted/Stasi.app/Contents/MacOS/Stasi)" = "arm64"
```

Expected: genau zwei Assets, korrekte SHA, gültige Signatur, Staple und Gatekeeper-Akzeptanz.

---

### Task 12: Homebrew-Cask aus dem echten Release erzeugen

**Files:**
- New external repository: `mm20261/homebrew-tap`
- Create there: `Casks/stasi.rb`

**Interfaces:**
- Consumes: öffentliches geprüftes `v0.10.0`-Asset und seine echte SHA-256
- Produces: `brew install --cask mm20261/tap/stasi`

- [ ] **Step 1: Echte SHA aus dem Release lesen**

```bash
source /private/tmp/stasi-publication.env
cd "$OPS_ROOT/release-check"
ZIP_SHA="$(awk 'NR == 1 { print $1 }' Stasi.zip.sha256)"
test "${#ZIP_SHA}" -eq 64
printf '%s\n' "$ZIP_SHA"
```

- [ ] **Step 2: Lokales Tap-Repository vorbereiten**

```bash
source /private/tmp/stasi-publication.env
TAP_ROOT="$OPS_ROOT/homebrew-tap"
printf 'export TAP_ROOT=%q\n' "$TAP_ROOT" >>"$ENV_FILE"
mkdir -p "$TAP_ROOT/Casks"
git -C "$TAP_ROOT" init -b main
git -C "$TAP_ROOT" config user.name 'Philipp Meder'
git -C "$TAP_ROOT" config user.email \
  '260910895+mm20261@users.noreply.github.com'
```

- [ ] **Step 3: Cask mit echter SHA erzeugen**

```bash
source /private/tmp/stasi-publication.env
ZIP_SHA="$(awk 'NR == 1 { print $1 }' "$OPS_ROOT/release-check/Stasi.zip.sha256")"
cat >"$TAP_ROOT/Casks/stasi.rb" <<RUBY
cask "stasi" do
  version "0.10.0"
  sha256 "${ZIP_SHA}"

  url "https://github.com/mm20261/stasi/releases/download/v#{version}/Stasi.zip"
  name "Stasi"
  desc "On-device push-to-talk dictation for macOS"
  homepage "https://github.com/mm20261/stasi"

  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "Stasi.app"

  uninstall quit: "app.stasi.macos"

  zap trash: [
    "~/Library/Application Support/Stasi",
    "~/Library/Caches/app.stasi.macos",
    "~/Library/HTTPStorages/app.stasi.macos",
    "~/Library/HTTPStorages/app.stasi.macos.binarycookies",
    "~/Library/Preferences/app.stasi.macos.plist",
    "~/Library/Saved Application State/app.stasi.macos.savedState",
  ]
end
RUBY
```

- [ ] **Step 4: Cask lokal prüfen**

```bash
source /private/tmp/stasi-publication.env
cd "$TAP_ROOT"
brew style --cask Casks/stasi.rb
brew audit --cask --strict Casks/stasi.rb
```

Expected: keine Style- oder Audit-Fehler.

- [ ] **Step 5: Cask lokal committen und Attribution vor Push bereinigen**

```bash
source /private/tmp/stasi-publication.env
cd "$TAP_ROOT"
git add Casks/stasi.rb
git commit -m $'feat(cask): add Stasi\n\nCo-Authored-By: Claude <noreply@anthropic.com>'

git filter-repo --force --message-callback '
import re
pattern = re.compile(br"(?i)^Co-Authored-By[ \t]*:[ \t]*(.*?)[ \t]*$")
kept = []
for line in message.splitlines(keepends=True):
    match = pattern.fullmatch(line.rstrip(b"\r\n"))
    if match and (b"claude" in match.group(1).lower() or b"anthropic" in match.group(1).lower()):
        continue
    kept.append(line)
return b"".join(kept).rstrip(b"\r\n") + b"\n"
'

git log --format=fuller --show-signature -1
git log --regexp-ignore-case --extended-regexp \
  --grep='^Co-Authored-By:.*(Claude|Anthropic)' --format='%H %s'
```

Expected: letzter Befehl ohne Ausgabe; Name und Noreply-E-Mail bleiben Philipp.

- [ ] **Step 6: Benutzerbestätigung für öffentliches Tap einholen**

Zeige den vollständigen Cask, SHA, Release-URL und das Ziel `https://github.com/mm20261/homebrew-tap`. Frage ausdrücklich, ob dieses neue Repository jetzt öffentlich angelegt und der eine bereinigte Commit gepusht werden soll. Ohne neues Ja stoppen.

- [ ] **Step 7: Öffentliches Tap anlegen und nur `main` pushen**

Nach Bestätigung:

```bash
source /private/tmp/stasi-publication.env
cd "$TAP_ROOT"
gh repo create mm20261/homebrew-tap \
  --public \
  --description 'Homebrew tap for Stasi'
git remote add origin https://github.com/mm20261/homebrew-tap.git
git push -u origin refs/heads/main:refs/heads/main
```

- [ ] **Step 8: Online-Audit und Installation prüfen**

```bash
brew untap mm20261/tap 2>/dev/null || true
brew tap mm20261/tap
brew audit --cask --strict --online mm20261/tap/stasi
```

Vor Installation:

```bash
if [[ -e /Applications/Stasi.app ]]; then
  printf '%s\n' '/Applications/Stasi.app existiert bereits; Installationstest stoppen.' >&2
  exit 1
fi
```

Nur auf einem Test-Mac ohne erhaltenswerte bestehende Stasi-Installation:

```bash
brew install --cask mm20261/tap/stasi
test -d /Applications/Stasi.app
codesign --verify --deep --strict --verbose=2 /Applications/Stasi.app
xcrun stapler validate /Applications/Stasi.app
spctl --assess --type execute --verbose=4 /Applications/Stasi.app
test "$(lipo -archs /Applications/Stasi.app/Contents/MacOS/Stasi)" = "arm64"
brew uninstall --cask stasi
```

Expected: Installation, Gatekeeper-Prüfung und normale Deinstallation bestehen. `--zap` wird nur auf einem Mac ohne erhaltenswerte Stasi-Daten separat getestet.

---

### Task 13: Abschlusszustand dokumentieren und Backups behalten

**Files:**
- No repository changes unless verification uncovers a real documentation error

**Interfaces:**
- Consumes: öffentliches Repo, Release und Tap
- Produces: nachweisbar funktionierenden Ein-Befehl-Installationsweg und sichere Rollback-Basis

- [ ] **Step 1: Öffentliche Endpunkte prüfen**

```bash
source /private/tmp/stasi-publication.env
gh repo view mm20261/stasi --json visibility,url
gh release view v0.10.0 --repo mm20261/stasi --json url,assets
gh repo view mm20261/homebrew-tap --json visibility,url
brew info --cask mm20261/tap/stasi
```

Expected: beide Repositories `PUBLIC`; Release-Assets vorhanden; Cask auflösbar.

- [ ] **Step 2: Installationsbefehl als finalen Vertrag melden**

```bash
brew install --cask mm20261/tap/stasi
```

- [ ] **Step 3: Bestätigung für den Austausch des primären Arbeitsclones einholen**

Zeige den alten Pfad `$SOURCE_REPO`, den geplanten Archivpfad `$OPS_ROOT/Stasi.pre-rewrite-working-copy` und den bereits geprüften Remote-Tip. Frage ausdrücklich, ob der alte Clone jetzt archiviert und am ursprünglichen Pfad ein frischer GitHub-Clone angelegt werden soll. Der alte Clone wird nicht gelöscht.

- [ ] **Step 4: Alten Clone archivieren und primären Pfad frisch klonen**

Nach Bestätigung:

```bash
source /private/tmp/stasi-publication.env
ARCHIVED_SOURCE="$OPS_ROOT/Stasi.pre-rewrite-working-copy"
test -z "$(git -C "$SOURCE_REPO" status --short)"
mv "$SOURCE_REPO" "$ARCHIVED_SOURCE"
git clone "$REMOTE_URL" "$SOURCE_REPO"
git -C "$SOURCE_REPO" config --local user.name 'Philipp Meder'
git -C "$SOURCE_REPO" config --local \
  user.email '260910895+mm20261@users.noreply.github.com'
git -C "$ARCHIVED_SOURCE" remote set-url --push \
  origin DISABLED_AFTER_HISTORY_REWRITE
printf 'export ARCHIVED_SOURCE=%q\n' "$ARCHIVED_SOURCE" >>"$ENV_FILE"
test "$(git -C "$SOURCE_REPO" rev-parse HEAD)" = "$REWRITTEN_TIP"
```

Danach sollte die Claude-Code-Session neu am ursprünglichen Pfad gestartet werden, damit ihr Arbeitsverzeichnis sicher auf den frischen Clone zeigt.

Behalte mindestens bis nach einem erfolgreich getesteten Folge-Release:

```text
$REMOTE_BACKUP
$LOCAL_BACKUP
$ARCHIVED_SOURCE
$OPS_ROOT/baseline.txt
$OPS_ROOT/rewrite-verification.txt
```

- [ ] **Step 5: Finalen Bericht erstellen**

Berichte exakt:

- alter und neuer `main`-Tip,
- dynamische Commit-Anzahl,
- unveränderten finalen Tree,
- GitHub-Contributor-Ergebnis,
- öffentliche Repository-URLs,
- Release-URL,
- SHA-256,
- Gatekeeper-Ergebnis,
- Homebrew-Audit und Installationsresultat,
- Pfade der behaltenen Backups,
- jeden übersprungenen oder noch nicht auf sauberem Test-Mac ausgeführten Schritt.
