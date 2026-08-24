import SwiftUI
import CoreText

// MARK: - Design-System v3 „Cloud Design Handoff"
// Tokens 1:1 aus Import/design_handoff_stasi/README.md übernommen.
// Light + Dark Mode via adaptive Farben; Akzent user-wählbar.

enum FontLoader {
    nonisolated static func registerBundledFonts() {
        for name in ["Geist", "GeistMono"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

private func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    })
}

extension Color {
    init(stasiHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Aufhellung für Dark Mode: mix mit hellem Grau-Blau (wie color-mix oklab im Handoff).
    func brightenedForDarkMode() -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let ns = NSColor(self).usingColorSpace(.sRGB) ?? .controlAccentColor
            guard isDark else { return ns }
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a * 0.62 + b * 0.38 }
            return NSColor(red: mix(ns.redComponent, 232 / 255),
                           green: mix(ns.greenComponent, 236 / 255),
                           blue: mix(ns.blueComponent, 242 / 255), alpha: 1)
        })
    }
}

enum Theme {
    // MARK: Farbe (adaptiv Light/Dark laut Handoff)
    enum Palette {
        static let background   = adaptive(light: 0xF4F4F2, dark: 0x252420)
        static let surface      = adaptive(light: 0xFFFFFF, dark: 0x2F2E2A)
        static let ink          = adaptive(light: 0x1A1917, dark: 0xF0EEE9)
        static let sub          = adaptive(light: 0x716E67, dark: 0xA3A099)
        static let line         = adaptive(light: 0xE4E2DC, dark: 0x3D3B36)
        static let hover        = adaptive(light: 0xECEAE5, dark: 0x383631)

        // Aufnahme-Pill (dunkel in beiden Modi)
        static let pill         = Color(stasiHex: 0x1A1917)
        static let pillDark     = Color(stasiHex: 0x403E38)
        static let pillInk      = Color(stasiHex: 0xF4F2ED)

        static let recRed       = Color(stasiHex: 0xFF453A)
        static let destructive  = Color(stasiHex: 0xC8102E)
        static let successColor = Color(stasiHex: 0x30A46C)
    }

    /// Akzent-Tint (aktive Nav, Charts): accent 11 % auf surface.
    static func tint(_ accent: Color) -> Color {
        accent.opacity(0.12)
    }

    /// Akzent kommt aus dem beobachtbaren SettingsStore – Views, die
    /// Theme.accent im Body lesen, tracken damit accentHex automatisch.
    nonisolated(unsafe) static weak var sharedSettings: SettingsStore?

    @MainActor static var accent: Color { sharedSettings?.accentColor ?? Color(stasiHex: 0x1D4E89) }
    @MainActor static var accentPressed: Color { sharedSettings?.accentPressedColor ?? Color(stasiHex: 0x16406F) }

    // MARK: Raum & Form (Handoff: Karten r12 ohne Schatten, Controls r8–9, Pill 999)
    enum Metrics {
        static let sidebarWidth: CGFloat = 212
        static let radiusCard: CGFloat = 12
        static let radiusControl: CGFloat = 9
        static let radiusPill: CGFloat = 999
        static let hairline: CGFloat = 1
        static let gridGap: CGFloat = 12
    }

    // MARK: Typografie – Geist / Geist Mono (Fallback: System)
    enum Typo {
        static let ui = Font.custom("Geist", size: 13.5)
        static let mono = Font.custom("Geist Mono", size: 11)

        static func h1() -> Font { .custom("Geist", size: 28).weight(.semibold) }
        static func stat() -> Font { .custom("Geist", size: 24).weight(.semibold) }
        static func body() -> Font { ui }
        static func secondary() -> Font { .custom("Geist", size: 12.5) }
        static func kicker(size: CGFloat = 10.5) -> Font {
            .custom("Geist Mono", size: size).weight(.medium)
        }
        static func counter(_ size: CGFloat = 13) -> Font {
            .custom("Geist Mono", size: size)
        }
        static func nav() -> Font { .custom("Geist", size: 13.5) }
        static func wordmark() -> Font { .custom("Geist Mono", size: 17).weight(.semibold) }
    }

    // MARK: Bewegung
    enum Motion {
        static let fast = Animation.easeOut(duration: 0.15)
        static let panel = Animation.smooth(duration: 0.25)
    }
}

// MARK: - Wiederverwendbare Stile

/// Mono-Kicker: UPPERCASE, gesperrt („TAGESBERICHT · …")
struct KickerStyle: ViewModifier {
    var color: Color
    func body(content: Content) -> some View {
        content
            .font(Theme.Typo.kicker())
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundColor(color)
            .monospacedDigit()
    }
}

extension View {
    func kicker(_ color: Color) -> some View { modifier(KickerStyle(color: color)) }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.Palette.surface)
            .cornerRadius(Theme.Metrics.radiusCard)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard)
                    .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

/// Key-Badge (Tastenkürzel-Chip, z. B. „⌥ Leertaste“)
struct KeyBadge: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Typo.kicker(size: 11))
            .tracking(0.5)
            .foregroundColor(Theme.Palette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.Palette.hover)
            .cornerRadius(6)
    }
}

/// Primärer Pill-Button (Akzent, radius 999)
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Geist", size: 13).weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(configuration.isPressed
                               ? Theme.accentPressed
                               : Theme.accent.brightenedForDarkMode())
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.fast, value: configuration.isPressed)
    }
}

/// Sekundärer Button (surface, line-Border)
struct GhostButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Geist", size: 13).weight(.medium))
            .foregroundColor(destructive ? Theme.Palette.destructive : Theme.Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.Palette.surface))
            .overlay(Capsule().strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Theme.Motion.fast, value: configuration.isPressed)
    }
}
