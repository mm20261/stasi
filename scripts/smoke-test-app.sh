#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_HOME="$HOME"
APP_OUTPUT_DIR="${STASI_APP_OUTPUT_DIR:-$ROOT/build}"
if [[ "$APP_OUTPUT_DIR" != /* ]]; then
    APP_OUTPUT_DIR="$ROOT/$APP_OUTPUT_DIR"
fi

APP="$APP_OUTPUT_DIR/Stasi.app"
INFO_PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/Stasi"
RESOURCE_BUNDLE="$APP/Contents/Resources/Stasi_Stasi.bundle"
MIT_FILE="$RESOURCE_BUNDLE/MIT.txt"
OFL_FILE="$RESOURCE_BUNDLE/Geist-OFL-1.1.txt"
ARTIFACT_ROOT="$ROOT/.build/test-artifacts"
CLEAN_ROOM=""
CLEAN_APP=""
LOG=""
PID=""
STOP_STATUS=""
ICON_CHECK_DIR="$APP_OUTPUT_DIR/icon-check.iconset"
REAL_HOME_PROBE=""

stop_process() {
    local status=0

    if [[ -z "$PID" ]]; then
        STOP_STATUS=""
        return
    fi

    if kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" 2>/dev/null || true
        for _ in {1..20}; do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.05
        done
        if kill -0 "$PID" 2>/dev/null; then
            kill -KILL "$PID" 2>/dev/null || true
        fi
    fi

    if wait "$PID" 2>/dev/null; then
        status=0
    else
        status=$?
    fi
    PID=""
    STOP_STATUS="$status"
}

cleanup() {
    stop_process || true
    rm -rf "$ICON_CHECK_DIR"
    if [[ -n "$REAL_HOME_PROBE" && ( -e "$REAL_HOME_PROBE" || -L "$REAL_HOME_PROBE" ) ]]; then
        rm -f -- "$REAL_HOME_PROBE"
    fi
    if [[ -n "$CLEAN_ROOM" ]]; then
        rm -rf "$CLEAN_ROOM"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

STASI_APP_OUTPUT_DIR="$APP_OUTPUT_DIR" "$ROOT/scripts/make-app.sh"

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

test -x "$APP/Contents/MacOS/Stasi"
test -d "$RESOURCE_BUNDLE"
test ! -e "$APP/Stasi_Stasi.bundle"
test -f "$RESOURCE_BUNDLE/Geist.ttf"
test -f "$RESOURCE_BUNDLE/GeistMono.ttf"
test -f "$RESOURCE_BUNDLE/menubar.png"
test -f "$RESOURCE_BUNDLE/menubar-recording.png"
test -f "$MIT_FILE"
test -f "$OFL_FILE"
grep -q 'MIT License' "$MIT_FILE"
grep -q 'SIL OPEN FONT LICENSE Version 1.1' "$OFL_FILE"

test -f "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_CHECK_DIR"
iconutil -c iconset "$APP/Contents/Resources/AppIcon.icns" -o "$ICON_CHECK_DIR"
test -f "$ICON_CHECK_DIR/icon_512x512@2x.png"

TRACKED_ICON_DERIVATIVE_COUNT="$(
    git -C "$ROOT" ls-files \
        | { grep -E '(^|/)(icon_[^/]+\.png|AppIcon\.icns)$' || true; } \
        | wc -l \
        | tr -d ' '
)"
test "$TRACKED_ICON_DERIVATIVE_COUNT" -eq 0

codesign --verify --deep --strict --verbose=2 "$APP"

SANDBOX_EXEC="$(command -v sandbox-exec || true)"
test -x "$SANDBOX_EXEC" || {
    echo "sandbox-exec fehlt; Clean-room-Fallback kann nicht zerstörungsfrei gesperrt werden" >&2
    exit 1
}

BIN_DIR="$(swift build -c release --show-bin-path)"
FALLBACK_BUNDLE="$BIN_DIR/Stasi_Stasi.bundle"
test -f "$FALLBACK_BUNDLE/Geist.ttf"

mkdir -p "$ARTIFACT_ROOT"
CLEAN_ROOM="$(mktemp -d "$ARTIFACT_ROOT/clean-room.XXXXXX")"
CLEAN_APP="$CLEAN_ROOM/Stasi.app"
LOG="$CLEAN_ROOM/clean-room.log"
TEST_HOME="$CLEAN_ROOM/home"
TEST_TMP="$CLEAN_ROOM/tmp"
SANDBOX_PROFILE="$CLEAN_ROOM/clean-room.sb"
mkdir -p \
    "$TEST_HOME/Library/Application Support" \
    "$TEST_HOME/Library/Preferences" \
    "$TEST_HOME/Library/Saved Application State" \
    "$TEST_TMP"
cp -R "$APP" "$CLEAN_APP"
: > "$LOG"

printf '%s\n' \
    '(version 1)' \
    '(allow default)' \
    "(deny file-read* (require-all (subpath \"$ROOT/.build\") (require-not (subpath \"$CLEAN_ROOM\"))))" \
    "(deny file-write* (require-all (subpath \"$DEVELOPER_HOME\") (require-not (subpath \"$CLEAN_ROOM\"))))" \
    > "$SANDBOX_PROFILE"

for _ in {1..20}; do
    candidate="$DEVELOPER_HOME/.stasi-sandbox-write-probe.$$.$RANDOM.$RANDOM"
    if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
        REAL_HOME_PROBE="$candidate"
        break
    fi
done
test -n "$REAL_HOME_PROBE"
test ! -e "$REAL_HOME_PROBE" && test ! -L "$REAL_HOME_PROBE"
if "$SANDBOX_EXEC" -f "$SANDBOX_PROFILE" /usr/bin/touch "$REAL_HOME_PROBE" 2>/dev/null; then
    echo "Sandbox erlaubt unerwartet einen Schreibzugriff im echten HOME: $REAL_HOME_PROBE" >&2
    exit 1
fi
test ! -e "$REAL_HOME_PROBE" && test ! -L "$REAL_HOME_PROBE"

"$SANDBOX_EXEC" -f "$SANDBOX_PROFILE" /usr/bin/cksum \
    "$CLEAN_APP/Contents/Resources/Stasi_Stasi.bundle/Geist.ttf" \
    "$CLEAN_APP/Contents/Resources/Stasi_Stasi.bundle/MIT.txt" \
    "$CLEAN_APP/Contents/Resources/Stasi_Stasi.bundle/Geist-OFL-1.1.txt" >/dev/null
"$SANDBOX_EXEC" -f "$SANDBOX_PROFILE" /usr/bin/touch \
    "$TEST_HOME/.sandbox-write-probe"
if "$SANDBOX_EXEC" -f "$SANDBOX_PROFILE" /usr/bin/cksum \
    "$FALLBACK_BUNDLE/Geist.ttf" >/dev/null 2>&1; then
    echo "Sandbox erlaubt unerwartet den SwiftPM-Build-Fallback: $FALLBACK_BUNDLE" >&2
    exit 1
fi

pushd "$CLEAN_ROOM" >/dev/null
HOME="$TEST_HOME" \
CFFIXED_USER_HOME="$TEST_HOME" \
TMPDIR="$TEST_TMP/" \
STASI_NO_TAP=1 \
"$SANDBOX_EXEC" -f "$SANDBOX_PROFILE" \
    "$CLEAN_APP/Contents/MacOS/Stasi" >"$LOG" 2>&1 &
PID=$!
popd >/dev/null

for _ in {1..20}; do
    if ! kill -0 "$PID" 2>/dev/null; then
        stop_process
        printf 'Clean-room executable exited early with status %s\n' "$STOP_STATUS" >&2
        test ! -s "$LOG" || grep -v '^$' "$LOG" >&2 || true
        exit 1
    fi
    sleep 0.1
done

stop_process
if [[ "$STOP_STATUS" -ne 0 && "$STOP_STATUS" -ne 137 && "$STOP_STATUS" -ne 143 ]]; then
    printf 'Clean-room executable stopped with unexpected status %s\n' "$STOP_STATUS" >&2
    test ! -s "$LOG" || grep -v '^$' "$LOG" >&2 || true
    exit 1
fi

if grep -Eiq 'fatal error|could not load resource bundle|resource(s)? (missing|not found)' "$LOG"; then
    printf 'Clean-room resource failure detected:\n' >&2
    grep -Ei 'fatal error|could not load resource bundle|resource(s)? (missing|not found)' "$LOG" >&2 || true
    exit 1
fi
if ! grep -q 'STASI-HK: Tap übersprungen' "$LOG"; then
    printf 'Clean-room launch did not reach the STASI_NO_TAP guard:\n' >&2
    test ! -s "$LOG" || grep -v '^$' "$LOG" >&2 || true
    exit 1
fi

printf 'Smoke test passed: %s\n' "$APP"
