import SwiftUI
import CoreText

// MARK: - Design-System v2 „Stasi v2 Handoff"
// Tokens 1:1 aus Import/design_handoff_stasi/Stasi v2.dc.html übernommen.
// Kein Dark Mode (laut v2 maßgeblich), Akzent user-wählbar (Standard Anthrazit).

enum FontLoader {
    nonisolated static func registerBundledFonts() {
        for name in ["Geist", "GeistMono"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(stasiHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// v2 kennt keinen Dark Mode – der Aufhellungs-Hook bleibt als Identität
    /// erhalten, damit bestehende Aufrufe unverändert funktionieren.
    func brightenedForDarkMode() -> Color { self }
}

enum Theme {
    // MARK: Farbe (Light – v2 kennt kein Dark Mode)
    enum Palette {
        /// Fensterhintergrund als Verlauf (160deg #F3F6FA → #F8F7F3)
        static let backgroundTop   = Color(stasiHex: 0xF3F6FA)
        static let backgroundBottom = Color(stasiHex: 0xF8F7F3)
        static let background      = Color(stasiHex: 0xF6F6F4) // solide Fallbackfarbe
        static let surface         = Color(stasiHex: 0xFFFFFF)
        static let ink             = Color(stasiHex: 0x1A1917)
        static let sub             = Color(stasiHex: 0x8A8780)
        static let line            = Color(stasiHex: 0xECEAE4)
        static let hover           = Color(stasiHex: 0xF1F4F8)

        static let recRed          = Color(stasiHex: 0xFF453A)
        static let destructive     = Color(stasiHex: 0xC8102E)
        static let successColor    = Color(stasiHex: 0x30A46C)
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [Palette.backgroundTop, Palette.backgroundBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Akzent-Tint (aktive Flächen, Badge-Hintergründe): accent 12 %.
    static func tint(_ accent: Color) -> Color {
        accent.opacity(0.12)
    }

    /// Kartenschatten: `0 2px 8px color-mix(accent 12%, transparent)`.
    static func shadow(_ accent: Color) -> Color {
        accent.opacity(0.12)
    }

    /// Akzent kommt aus dem beobachtbaren SettingsStore – Views, die
    /// Theme.accent im Body lesen, tracken damit accentHex automatisch.
    nonisolated(unsafe) static weak var sharedSettings: SettingsStore?

    @MainActor static var accent: Color { sharedSettings?.accentColor ?? Color(stasiHex: 0x1A1917) }
    @MainActor static var accentPressed: Color { sharedSettings?.accentPressedColor ?? Color(stasiHex: 0x141311) }

    // MARK: Raum & Form (v2: Karten r16 ohne Border + Schatten, Controls r9/r12, Pill 999)
    enum Metrics {
        static let sidebarWidth: CGFloat = 200
        static let sidebarCollapsed: CGFloat = 64
        static let radiusCard: CGFloat = 16
        static let radiusControl: CGFloat = 9
        static let radiusInput: CGFloat = 12
        static let radiusPill: CGFloat = 999
        static let hairline: CGFloat = 1
        static let gridGap: CGFloat = 12
    }

    // MARK: Typografie – Geist / Geist Mono (Fallback: System)
    enum Typo {
        static let ui = Font.custom("Geist", size: 13)
        static let mono = Font.custom("Geist Mono", size: 11)

        static func h1() -> Font { .custom("Geist", size: 27).weight(.bold) }
        static func stat() -> Font { .custom("Geist", size: 24).weight(.semibold) }
        static func bigStat() -> Font { .custom("Geist", size: 28).weight(.bold) }
        static func body() -> Font { ui }
        static func secondary() -> Font { .custom("Geist", size: 12) }
        static func kicker(size: CGFloat = 10) -> Font {
            .custom("Geist Mono", size: size).weight(.medium)
        }
        static func counter(_ size: CGFloat = 13) -> Font {
            .custom("Geist Mono", size: size)
        }
        static func nav() -> Font { .custom("Geist", size: 13) }
        static func wordmark() -> Font { .custom("Geist Mono", size: 15).weight(.semibold) }
    }

    // MARK: Bewegung
    enum Motion {
        static let fast = Animation.easeOut(duration: 0.15)
        static let panel = Animation.smooth(duration: 0.25)
        static let micro = Animation.easeInOut(duration: 0.18)
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

/// v2-Karte: radius 16, KEINE Border, Akzent-Schatten `0 2px 8px`.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard))
            .shadow(color: Theme.shadow(Theme.accent), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

/// v2-Mikrointeraktion: Karte bei Hover leicht anheben (translateY −3px).
struct LiftOnHover: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .offset(y: hovered ? -3 : 0)
            .shadow(color: Theme.shadow(Theme.accent),
                    radius: hovered ? 12 : 8, x: 0, y: hovered ? 6 : 2)
            .onHover { hovered = $0 }
            .animation(Theme.Motion.micro, value: hovered)
    }
}

/// v2-Mikrointeraktion: Nav-Zeile bei Hover nach rechts rücken (translateX 3px).
struct SlideOnHover: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .offset(x: hovered ? 3 : 0)
            .onHover { hovered = $0 }
            .animation(Theme.Motion.micro, value: hovered)
    }
}

/// v2-Mikrointeraktion: Icon-Button bei Hover skalieren (1.1).
struct ScaleOnHover: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? 1.1 : 1)
            .onHover { hovered = $0 }
            .animation(Theme.Motion.micro, value: hovered)
    }
}

extension View {
    func liftOnHover() -> some View { modifier(LiftOnHover()) }
    func slideOnHover() -> some View { modifier(SlideOnHover()) }
    func scaleOnHover() -> some View { modifier(ScaleOnHover()) }
}

/// Key-Badge (Tastenkürzel-Chip, z. B. „⌥ Leertaste“)
struct KeyBadge: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Typo.kicker(size: 11.5))
            .tracking(0.5)
            .foregroundColor(Theme.Palette.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.Palette.hover)
            .cornerRadius(7)
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

/// v2-Input: surface-Hintergrund, radius 12, kein Border, Akzent-Schatten.
struct StasiInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Font.custom("Geist", size: 13.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput))
            .shadow(color: Theme.shadow(Theme.accent), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func stasiInput() -> some View { modifier(StasiInputStyle()) }
}

/// v2-Akzent-Button (radius 12, Akzent, weiß, Hover −2px).
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Geist", size: 13).weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                    .fill(configuration.isPressed ? Theme.accentPressed : Theme.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.fast, value: configuration.isPressed)
    }
}
