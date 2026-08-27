#!/bin/bash
# Baut die doppelklickbare Stasi.app (Release-Build + Bundle + Ad-hoc-Signatur).
# Aufruf: ./scripts/make-app.sh [Ausgabeordner]
set -euo pipefail

OUT_DIR="${1:-${STASI_APP_OUTPUT_DIR:-build}}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Stasi"
BUNDLE_ID="app.stasi.macos"
VERSION="0.9.0"

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
ICONSET="$OUT_DIR/.stasi-AppIcon.iconset"
test -f "$ICON_SOURCE" || { echo "App-Icon-Quelle fehlt: $ICON_SOURCE" >&2; exit 1; }
rm -rf "$ICONSET"
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
rm -rf "$ICONSET"

# Stabile Signatur: "Stasi Dev Signing" (selbstsigniertes Zertifikat im
# Login-Schlüsselbund) hält die Signatur über Builds konstant → TCC-Rechte
# (Bedienungshilfen etc.) bleiben gültig. Fallback: ad hoc ("-"), dann müssen
# die Rechte nach jedem Build neu erteilt werden (AGENTS.md Regel 9).
SIGN_ID="Stasi Dev Signing"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    SIGN_ID="-"
fi
echo "▸ Signatur ($SIGN_ID)…"
codesign --force --deep --sign "$SIGN_ID" "$APP"

echo ""
echo "✓ Fertig: $APP"
echo "  Starten:  open \"$APP\""
echo "  Install.: cp -r \"$APP\" /Applications/"
