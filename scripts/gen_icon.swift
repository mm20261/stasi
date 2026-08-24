// App-Icon-Generator für Stasi – „Feldrekorder"-Ästhetik.
// Ausführen: swift scripts/gen_icon.swift <ausgabeordner>
// Erzeugt PNGs (16–1024 px) + icon.icns.

import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/Assets"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return img }
    let s = size

    // Gehäuse: heller Squircle mit sanftem Verlauf
    let bodyRect = CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05)
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: s * 0.20, cornerHeight: s * 0.20, transform: nil)
    ctx.addPath(bodyPath)
    ctx.clip()

    // Heller Verlauf
    let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFFFFFF), color(0xF4F3F0), color(0xE9E7E2)] as CFArray,
        locations: [0, 0.6, 1]
    )!
    ctx.drawLinearGradient(grad, start: CGPoint(x: s / 2, y: 0), end: CGPoint(x: s / 2, y: s), options: [])

    // Dezente Wellenlinien links & rechts (Audio-Hinweis)
    ctx.setStrokeColor(color(0xC9C7C1))
    ctx.setLineWidth(s * 0.02)
    for (x, heights) in [(s * 0.24, [0.06, 0.12, 0.07]), (s * 0.76, [0.08, 0.13, 0.05])] {
        for (i, hh) in heights.enumerated() {
            let barH = s * hh
            let rect = CGRect(x: x - s * 0.008,
                              y: s / 2 - barH / 2 + CGFloat(i) * s * 0.001,
                              width: s * 0.016, height: barH)
            let path = CGPath(roundedRect: rect, cornerWidth: s * 0.008, cornerHeight: s * 0.008, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    // Zentrierter Record-Punkt
    let btnCenter = CGPoint(x: s / 2, y: s / 2)
    let r = s * 0.17
    ctx.setFillColor(color(0xE5484D))
    ctx.fillEllipse(in: CGRect(x: btnCenter.x - r, y: btnCenter.y - r, width: r * 2, height: r * 2))
    // Glanzlicht oben
    ctx.setFillColor(color(0xFFFFFF, 0.35))
    ctx.fillEllipse(in: CGRect(x: btnCenter.x - r * 0.55, y: btnCenter.y + r * 0.15, width: r * 0.7, height: r * 0.45))

    img.unlockFocus()
    return img
}

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
var pngPaths: [String] = []

for px in sizes {
    let img = drawIcon(size: px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let path = "\(outDir)/icon_\(Int(px))x\(Int(px)).png"
    try! png.write(to: URL(fileURLWithPath: path))
    pngPaths.append(path)
    print("✓ \(path)")
}

// iconset → icns
let fm = FileManager.default
let iconset = "\(outDir)/icon.iconset"
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func link(_ src: String, as name: String) {
    try? fm.copyItem(atPath: src, toPath: "\(iconset)/\(name)")
}
link("\(outDir)/icon_16x16.png", as: "icon_16x16.png")
link("\(outDir)/icon_32x32.png", as: "icon_16x16@2x.png")
link("\(outDir)/icon_32x32.png", as: "icon_32x32.png")
link("\(outDir)/icon_64x64.png", as: "icon_32x32@2x.png")
link("\(outDir)/icon_128x128.png", as: "icon_128x128.png")
link("\(outDir)/icon_256x256.png", as: "icon_128x128@2x.png")
link("\(outDir)/icon_256x256.png", as: "icon_256x256.png")
link("\(outDir)/icon_512x512.png", as: "icon_256x256@2x.png")
link("\(outDir)/icon_512x512.png", as: "icon_512x512.png")
link("\(outDir)/icon_1024x1024.png", as: "icon_512x512@2x.png")

print("→ iconutil …")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
try? proc.run()
proc.waitUntilExit()
print("✓ \(outDir)/AppIcon.icns")
