#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_OUTPUT_DIR="${STASI_APP_OUTPUT_DIR:-$ROOT/build}"
if [[ "$APP_OUTPUT_DIR" != /* ]]; then
    APP_OUTPUT_DIR="$ROOT/$APP_OUTPUT_DIR"
fi

APP="$APP_OUTPUT_DIR/Stasi.app"
RESOURCE_BUNDLE="$APP/Contents/Resources/Stasi_Stasi.bundle"
ARTIFACT_ROOT="$ROOT/.build/test-artifacts"
CLEAN_ROOM=""
CLEAN_APP=""
LOG="$ARTIFACT_ROOT/clean-room.log"
PID=""

cleanup() {
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    if [[ -n "$CLEAN_ROOM" ]]; then
        rm -rf "$CLEAN_ROOM"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

STASI_APP_OUTPUT_DIR="$APP_OUTPUT_DIR" "$ROOT/scripts/make-app.sh"

test -x "$APP/Contents/MacOS/Stasi"
test -d "$RESOURCE_BUNDLE"
test -f "$RESOURCE_BUNDLE/Geist.ttf"
test -f "$RESOURCE_BUNDLE/GeistMono.ttf"
test -f "$RESOURCE_BUNDLE/menubar.png"
test -f "$RESOURCE_BUNDLE/menubar-recording.png"

codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$ARTIFACT_ROOT"
CLEAN_ROOM="$(mktemp -d "$ARTIFACT_ROOT/clean-room.XXXXXX")"
CLEAN_APP="$CLEAN_ROOM/Stasi.app"
cp -R "$APP" "$CLEAN_APP"
: > "$LOG"

pushd "$CLEAN_ROOM" >/dev/null
STASI_NO_TAP=1 "$CLEAN_APP/Contents/MacOS/Stasi" >"$LOG" 2>&1 &
PID=$!
popd >/dev/null

for _ in {1..20}; do
    if ! kill -0 "$PID" 2>/dev/null; then
        if wait "$PID"; then
            status=0
        else
            status=$?
        fi
        PID=""
        printf 'Clean-room executable exited early with status %s\n' "$status" >&2
        test ! -s "$LOG" || grep -v '^$' "$LOG" >&2 || true
        exit 1
    fi
    sleep 0.1
done

if ! kill "$PID" 2>/dev/null; then
    if wait "$PID"; then
        status=0
    else
        status=$?
    fi
    PID=""
    printf 'Clean-room executable exited before cleanup with status %s\n' "$status" >&2
    test ! -s "$LOG" || grep -v '^$' "$LOG" >&2 || true
    exit 1
fi
if wait "$PID"; then
    status=0
else
    status=$?
fi
PID=""
if [[ "$status" -ne 0 && "$status" -ne 143 ]]; then
    printf 'Clean-room executable stopped with unexpected status %s\n' "$status" >&2
    test ! -s "$LOG" || grep -v '^$' "$LOG" >&2 || true
    exit 1
fi

if grep -Eiq 'fatal error|could not load resource bundle|resource(s)? (missing|not found)' "$LOG"; then
    printf 'Clean-room resource failure detected:\n' >&2
    grep -Ei 'fatal error|could not load resource bundle|resource(s)? (missing|not found)' "$LOG" >&2 || true
    exit 1
fi

printf 'Smoke test passed: %s\n' "$APP"
