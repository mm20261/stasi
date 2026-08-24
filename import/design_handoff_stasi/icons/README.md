# Stasi — Icon-Export

Alle Icons für die App-Integration. SVG-Master liegen in `svg/`.

## AppIcon/ — macOS Dock-Icon
PNGs in 16–1024 px. Für eine `.icns`-Datei (native macOS-App):

```bash
mkdir AppIcon.iconset
cp icon_16x16.png    AppIcon.iconset/icon_16x16.png
cp icon_32x32.png    AppIcon.iconset/icon_16x16@2x.png
cp icon_32x32.png    AppIcon.iconset/icon_32x32.png
cp icon_64x64.png    AppIcon.iconset/icon_32x32@2x.png
cp icon_128x128.png  AppIcon.iconset/icon_128x128.png
cp icon_256x256.png  AppIcon.iconset/icon_128x128@2x.png
cp icon_256x256.png  AppIcon.iconset/icon_256x256.png
cp icon_512x512.png  AppIcon.iconset/icon_256x256@2x.png
cp icon_512x512.png  AppIcon.iconset/icon_512x512.png
cp icon_1024x1024.png AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset
```

- Electron: `icon_1024x1024.png` an `electron-builder` geben (macht .icns selbst)
- Tauri: `icon_1024x1024.png` in `tauri icon` werfen

## menubar/ — Menüleisten-Icon (22 px / 44 px)
Beim Einbinden die Dateien auf `…Template.png` / `…Template@2x.png` umbenennen
(hier als `-2x` benannt) — der Suffix **Template** im Dateinamen sorgt dafür,
dass macOS das Icon automatisch für helle/dunkle Menüleiste einfärbt.
`StasiMenuBarRecording` ist der Zustand mit rotem Punkt (nicht als Template
einbinden, sonst geht der rote Punkt verloren — stattdessen als normales
Image setzen, solange die Aufnahme läuft).

- Electron: `new Tray(nativeImage.createFromPath('StasiMenuBarTemplate.png'))`
- Swift/AppKit: `NSStatusBar.system.statusItem(...)`, `image.isTemplate = true`

## favicon/ — Web/Browser
- `favicon-16.png`, `favicon-32.png`, `favicon-48.png` für `<link rel="icon">`
- `favicon-180.png` als `apple-touch-icon`
- Modern reicht auch nur das SVG: `<link rel="icon" href="stasi-favicon.svg" type="image/svg+xml">`

## Farben
- Blau (Kachel): `#1D4E89`, Verlauf `#2A63A9 → #163D6B`
- Aufnahme-Rot: `#FF453A`

© meder.dev · Stasi v 0.9
