#!/bin/bash
# Baut die doppelklickbare Stasi.app (Release-Build + Bundle + Ad-hoc-Signatur).
# Aufruf: ./scripts/make-app.sh [Ausgabeordner]
set -euo pipefail

OUT_DIR="${1:-build}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Stasi"
BUNDLE_ID="app.stasi.macos"
VERSION="0.1.0"

APP="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "▸ Swift-Build (release)…"
cd "$ROOT"
swift build -c release 2>&1 | tail -2

BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "▸ Bundle-Struktur…"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BINARY" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

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

echo "▸ Icon…"
ICON_PNG_DIR="$ROOT/Import/design_handoff_stasi/icons/AppIcon"
if [ -d "$ICON_PNG_DIR" ]; then
    # Handoff-Icon nutzen
    ICONSET="$ROOT/build/icon.iconset"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    cp "$ICON_PNG_DIR/icon_16x16.png"   "$ICONSET/icon_16x16.png"
    cp "$ICON_PNG_DIR/icon_32x32.png"   "$ICONSET/icon_32x32.png"
    cp "$ICON_PNG_DIR/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"
    cp "$ICON_PNG_DIR/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"
    cp "$ICON_PNG_DIR/icon_128x128.png" "$ICONSET/icon_128x128.png"
    cp "$ICON_PNG_DIR/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
    cp "$ICON_PNG_DIR/icon_256x256.png" "$ICONSET/icon_256x256.png"
    cp "$ICON_PNG_DIR/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
    cp "$ICON_PNG_DIR/icon_512x512.png" "$ICONSET/icon_512x512.png"
    cp "$ICON_PNG_DIR/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
else
    if [ ! -f "Resources/Assets/AppIcon.icns" ]; then
        echo "  generiere Icon…"
        swift scripts/gen_icon.swift Resources/Assets >/dev/null
    fi
    cp "Resources/Assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

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
