#!/bin/bash
# Baut die doppelklickbare Stasi.app (Release-Build + Bundle + lokale Signatur).
# Lokale Ausgabe ohne Hardened Runtime und Notarisierung: nicht zur Weitergabe.
# Aufruf: ./scripts/make-app.sh [Ausgabeordner]
set -euo pipefail

OUT_DIR="${1:-${STASI_APP_OUTPUT_DIR:-build}}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Stasi"
BUNDLE_ID="app.stasi.macos"
VERSION_FILE="$ROOT/VERSION"

if [[ -n "${STASI_VERSION:-}" ]]; then
    VERSION="$STASI_VERSION"
elif [[ -s "$VERSION_FILE" ]]; then
    VERSION="$(<"$VERSION_FILE")"
else
    printf '%s\n' \
        'Keine Version gefunden: STASI_VERSION setzen oder VERSION im Repo-Root anlegen.' \
        >&2
    exit 2
fi

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf 'Ungültige Version: %s; erwartet MAJOR.MINOR.PATCH ohne v-Präfix.\n' \
        "$VERSION" >&2
    exit 2
fi

SIGNING_MODE="${STASI_SIGNING_MODE:-local}"
ENTITLEMENTS="$ROOT/Release/Stasi.entitlements"
ICON_WORK_DIR=""
ICONSET=""

cleanup() {
    if [[ -n "$ICON_WORK_DIR" ]]; then
        rm -rf "$ICON_WORK_DIR"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

case "$SIGNING_MODE" in
    local|adhoc|none) ;;
    *)
        echo "Unbekannter STASI_SIGNING_MODE: $SIGNING_MODE (erlaubt: local, adhoc, none)" >&2
        exit 2
        ;;
esac

APP="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "▸ Swift-Build (release)…"
cd "$ROOT"
swift build -c release 2>&1 | tail -2

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BIN_DIR/Stasi_Stasi.bundle"

test -x "$BINARY" || { echo "Stasi binary fehlt: $BINARY" >&2; exit 1; }
test -d "$RESOURCE_BUNDLE" || { echo "Ressourcenbundle fehlt: $RESOURCE_BUNDLE" >&2; exit 1; }

echo "▸ Bundle-Struktur…"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BINARY" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"
cp -R "$RESOURCE_BUNDLE" "$RESOURCES/Stasi_Stasi.bundle"

echo "▸ Info.plist…"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleDevelopmentRegion</key> <string>de</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>de</string>
        <string>en</string>
    </array>
    <key>LSMinimumSystemVersion</key>    <string>26.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key> <false/>
    <key>NSSupportsSuddenTermination</key>   <false/>

    <!-- Echte Mac-App: Dock-Icon + App-Menü (KEIN LSUIElement) -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <!-- Berechtigungen -->
    <key>NSMicrophoneUsageDescription</key>
    <string>Stasi nimmt Sprache auf, um sie lokal in Text zu verwandeln.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Stasi transkribiert deine Sprache vollständig auf dem Gerät.</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026</string>
    <!-- Update-Prüfung (nur auf Klick, siehe UpdateChecker) -->
    <key>STASI_RELEASE_API_URL</key>
    <string>https://api.github.com/repos/mm20261/stasi/releases/latest</string>
</dict>
</plist>
PLIST

if [[ -n "${STASI_RELEASE_API_URL:-}" ]]; then
    if [[ "$STASI_RELEASE_API_URL" == *$'\n'* || "$STASI_RELEASE_API_URL" == *$'\r'* ]]; then
        echo "STASI_RELEASE_API_URL darf keine Zeilenumbrüche enthalten." >&2
        exit 1
    fi

    # PlistBuddy erhält den Wert als ein zitiertes Argument. Backslashes und
    # Anführungszeichen werden für dessen Kommando-Parser separat maskiert.
    PLIST_VALUE=${STASI_RELEASE_API_URL//\\/\\\\}
    PLIST_VALUE=${PLIST_VALUE//\"/\\\"}
    if /usr/libexec/PlistBuddy -c "Print :STASI_RELEASE_API_URL" "$CONTENTS/Info.plist" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :STASI_RELEASE_API_URL \"$PLIST_VALUE\"" "$CONTENTS/Info.plist"
    else
        /usr/libexec/PlistBuddy -c "Add :STASI_RELEASE_API_URL string \"$PLIST_VALUE\"" "$CONTENTS/Info.plist"
    fi
fi

echo "▸ Icon…"
ICON_SOURCE="$ROOT/Resources/AppIcon.png"
test -f "$ICON_SOURCE" || { echo "App-Icon-Quelle fehlt: $ICON_SOURCE" >&2; exit 1; }
ICON_WORK_DIR="$(mktemp -d "$OUT_DIR/.stasi-icon-work.XXXXXX")"
ICONSET="$ICON_WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
while read -r filename pixels; do
    sips -z "$pixels" "$pixels" "$ICON_SOURCE" --out "$ICONSET/$filename" >/dev/null
done <<'ICON_SIZES'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
ICON_SIZES
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
rm -rf "$ICON_WORK_DIR"
ICON_WORK_DIR=""
ICONSET=""

if [[ "$SIGNING_MODE" == "local" || "$SIGNING_MODE" == "adhoc" ]]; then
    test -f "$ENTITLEMENTS" || {
        echo "Entitlements-Datei fehlt: $ENTITLEMENTS" >&2
        exit 1
    }

    if [[ "$SIGNING_MODE" == "adhoc" ]]; then
        # Verteilbarer Build ohne Developer ID: Ad-hoc-Signatur ("-") ist auf
        # fremden Macs gültig, ein lokales Dev-Zertifikat wäre dort unbekannt.
        # Gatekeeper warnt trotzdem (nicht notarisiert), siehe docs/release.md.
        SIGN_ID="-"
    else
        # Stabile lokale Signatur: Das selbstsignierte Zertifikat hält die Code-
        # Identität über Builds konstant. Ohne Zertifikat fällt der lokale Modus auf
        # ad hoc ("-") zurück; nach einem Signaturwechsel sind TCC-Rechte neu zu erteilen.
        SIGN_ID="Stasi Dev Signing"
        if ! security find-identity -v -p codesigning 2>/dev/null \
            | grep -Fq "\"$SIGN_ID\""; then
            SIGN_ID="-"
        fi
    fi
    echo "▸ Lokale Inside-out-Signatur ($SIGN_ID)…"

    # Eingebetteten Mach-O-Code zuerst signieren. Der Haupt-Executable wird beim
    # abschließenden Signieren des App-Bundles erfasst.
    while IFS= read -r -d '' EMBEDDED_BINARY; do
        if [[ "$EMBEDDED_BINARY" == "$MACOS/$APP_NAME" ]]; then
            continue
        fi
        if file -b "$EMBEDDED_BINARY" 2>/dev/null | grep -q '^Mach-O'; then
            echo "  ↳ $(basename "$EMBEDDED_BINARY")"
            codesign --force --sign "$SIGN_ID" "$EMBEDDED_BINARY"
        fi
    done < <(find "$CONTENTS" -type f -print0)

    # Wrapper nach ihren Inhalten signieren. find liefert Eltern vor Kindern;
    # die umgekehrte Array-Reihenfolge signiert daher von innen nach außen.
    EMBEDDED_BUNDLES=()
    while IFS= read -r -d '' EMBEDDED_BUNDLE; do
        EMBEDDED_BUNDLES+=("$EMBEDDED_BUNDLE")
    done < <(
        find "$CONTENTS" -type d \
            \( -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.app' \) \
            -print0
    )
    for ((INDEX=${#EMBEDDED_BUNDLES[@]} - 1; INDEX >= 0; INDEX--)); do
        echo "  ↳ $(basename "${EMBEDDED_BUNDLES[$INDEX]}")"
        codesign --force --sign "$SIGN_ID" "${EMBEDDED_BUNDLES[$INDEX]}"
    done

    codesign --force --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"
else
    echo "▸ Signatur übersprungen (Diagnosemodus none)"
fi

echo ""
echo "✓ Fertig: $APP"
echo "  Version:  $VERSION"
echo "  Starten:  open \"$APP\""
echo "  Install.: ditto \"$APP\" /Applications/Stasi.app"
echo "  Hinweis: Lokaler Build ohne Hardened Runtime und Notarisierung – nicht zur Weitergabe."
