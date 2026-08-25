import SwiftUI
import CoreText

// MARK: - Design-System v3
// Tokens 1:1 aus Import/design_handoff_v3/DESIGN.md übernommen.
// Verlauf-Hintergrund (#F3F6FA → #F8F7F3), weiße Karten (r16, Akzent-Schatten),
// 5 Akzent-Presets (Standard Anthrazit), gebündelt Geist / Geist Mono.
// Kein Dark Mode. Die v4-Aliasse (papier/stempelrot/linie/…) bleiben erhalten,
// damit Features (Suche, Onboarding, Insights, …) unverändert kompilieren.

enum FontLoader {
    static let fontResourceNames = ["Geist", "GeistMono"]

    nonisolated static func registerBundledFonts() {
        for name in fontResourceNames {
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

    /// v3 kennt keinen Dark Mode – der Aufhellungs-Hook bleibt als Identität erhalten.
    func brightenedForDarkMode() -> Color { self }
}

extension NSColor {
    convenience init(stasiHex hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Theme {
    /// Rohtoken-Werte (Test-Vertrag, siehe ThemeV3Tests).
    enum Hex {
        static let backgroundTop: UInt32 = 0xF3F6FA
        static let backgroundBottom: UInt32 = 0xF8F7F3
        static let surface: UInt32 = 0xFFFFFF
        static let ink: UInt32 = 0x1A1917
        static let sub: UInt32 = 0x8A8780
        static let line: UInt32 = 0xECEAE4
        static let hover: UInt32 = 0xF1F4F8
        static let rec: UInt32 = 0xFF453A
        static let destructive: UInt32 = 0xC8102E
        static let success: UInt32 = 0x30A46C
    }

    // MARK: Farbe (Light – v3 kennt kein Dark Mode)
    enum Palette {
        // Primär (v3)
        static let backgroundTop = Color(stasiHex: Hex.backgroundTop)
        static let backgroundBottom = Color(stasiHex: Hex.backgroundBottom)
        /// Solide Fallbackfarbe hinter dem Verlauf.
        static let background = Color(stasiHex: 0xF6F6F4)
        static let surface = Color(stasiHex: Hex.surface)
        static let ink = Color(stasiHex: Hex.ink)
        static let sub = Color(stasiHex: Hex.sub)
        static let line = Color(stasiHex: Hex.line)
        static let hover = Color(stasiHex: Hex.hover)

        static let recRed = Color(stasiHex: Hex.rec)
        static let destructive = Color(stasiHex: Hex.destructive)
        static let successColor = Color(stasiHex: Hex.success)

        // Der eine dynamische Akzent (Nutzer wählt aus 5 Presets).
        @MainActor static var stempelrot: Color { accent }
        @MainActor static var stempelrotDunkel: Color { accentPressed }

        // Status (fest – bleiben von der Akzentwahl unberührt)
        static let archivgruen = Color(stasiHex: Hex.success)
        static let erfolgFlaeche = Color(stasiHex: Hex.success).opacity(0.14)
        static let erfolgText = Color(stasiHex: Hex.success)
        static let warnFlaeche = Color(stasiHex: Hex.rec).opacity(0.12)
        static let warnRand = Color(stasiHex: Hex.rec).opacity(0.30)
        static let recorderFlaeche = Color(stasiHex: Hex.rec).opacity(0.08)

        // Dunkle Flächen (Signaturkarte, Tooltip, Avatar)
        static let dunkelGrund = Color(stasiHex: Hex.ink)
        static let dunkelText = Color(white: 0.95)
        static let dunkelText2 = Color.white.opacity(0.58)
        static let dunkelLink = Color(white: 0.80)

        // v4-Kompatibilitäts-Aliasse (Screens nutzen sie; Werte → v3)
        static let manila = backgroundTop
        static let sidebar = Color.clear
        static let papier = surface
        static let linie = line
        static let linieInnen = line
        static let linieSidebar = line
        static let chip = hover
        static let zeileHover = hover
        static let text2 = sub
        static let text3 = sub
    }

    // MARK: Akzent (dynamisch, 5 Presets, Standard Anthrazit)

    /// Beobachtbarer Store – Views, die Theme.accent im Body lesen, tracken
    /// damit accentHex automatisch (KEIN `.id(epoch)`-Vollneubau).
    nonisolated(unsafe) static weak var sharedSettings: SettingsStore?

    @MainActor static var accent: Color { sharedSettings?.accentColor ?? Color(stasiHex: 0x1A1917) }
    @MainActor static var accentPressed: Color { sharedSettings?.accentPressedColor ?? Color(stasiHex: 0x141311) }

    /// Akzent-Tint (aktive Flächen, Badge-Hintergründe): accent 12 %.
    @MainActor static func tint(_ accent: Color) -> Color { accent.opacity(0.12) }

    /// Kartenschatten: `0 2px 8px` in Akzent bei 12 %.
    @MainActor static func shadow(_ accent: Color) -> Color { accent.opacity(0.12) }

    // MARK: Hintergrund (Verlauf 160°)

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [Palette.backgroundTop, Palette.backgroundBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Fensterhintergrund als Verlauf (RootView nutzt ihn direkt).
    static let background: LinearGradient = LinearGradient(
        colors: [Palette.backgroundTop, Palette.backgroundBottom],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Raum & Form (v3: Karte r16, Controls r9, Inputs r12, Pill 999)
    enum Metrics {
        static let sidebarWidth: CGFloat = 200
        static let sidebarCollapsed: CGFloat = 64
        static let radiusCard: CGFloat = 16
        static let radiusControl: CGFloat = 9
        static let radiusInput: CGFloat = 12
        static let radiusPill: CGFloat = 999
        static let hairline: CGFloat = 1
        static let gridGap: CGFloat = 12
        // v4-Kompatibilität
        static let railWidth: CGFloat = 252
        static let topbarHeight: CGFloat = 42
        static let contentPaddingH: CGFloat = 32
        static let contentPaddingTop: CGFloat = 24
    }

    /// Kartenform v3: abgerundetes Rechteck r16 (kein unregelmäßiger Radius).
    static let cardShape = RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)

    // MARK: Typografie – Geist / Geist Mono (Fallback: System)
    enum Typo {
        static let ui = Font.custom("Geist", size: 13)
        static let mono = Font.custom("Geist Mono", size: 11)

        static func h1() -> Font { .custom("Geist", size: 27).weight(.bold) }
        static func stat() -> Font { .custom("Geist", size: 24).weight(.semibold) }
        static func bigStat() -> Font { .custom("Geist", size: 28).weight(.bold) }
        static func leitzahl() -> Font { .custom("Geist", size: 44).weight(.bold) }
        static func railNumber() -> Font { .custom("Geist", size: 24).weight(.bold) }
        static func nebenZahl() -> Font { .custom("Geist", size: 20).weight(.semibold) }
        static func hero() -> Font { .custom("Geist", size: 15.5) }
        static func body() -> Font { ui }
        static func secondary(size: CGFloat = 12) -> Font { .custom("Geist", size: size) }
        static func zeilenTitel() -> Font { .custom("Geist", size: 13).weight(.medium) }
        static func kartentitel() -> Font { .custom("Geist", size: 14).weight(.semibold) }
        static func kicker(size: CGFloat = 10) -> Font {
            .custom("Geist Mono", size: size).weight(.medium)
        }
        static func counter(_ size: CGFloat = 13) -> Font {
            .custom("Geist Mono", size: size)
        }
        static func nav() -> Font { .custom("Geist", size: 13) }
        static func wordmark() -> Font { .custom("Geist Mono", size: 15).weight(.semibold) }
        static func keycap(_ size: CGFloat = 11) -> Font {
            .custom("Geist Mono", size: size).weight(.bold)
        }
    }

    // MARK: Bewegung (prefers-reduced-motion respektieren)
    enum Motion {
        static let fast = Animation.easeOut(duration: 0.15)
        static let panel = Animation.smooth(duration: 0.25)
        static let micro = Animation.easeInOut(duration: 0.18)

        static func maybe(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    // MARK: Balken-/Heatmap-Opacity (Feature Logik, akzentfarbig angewendet)
    static let appBarOpacities: [Double] = [1.0, 0.66, 0.42, 0.22]
    static let heatmapOpacities: [Double] = [0.08, 0.18, 0.45, 0.75, 1.0]

    static func appBarOpacity(rank: Int) -> Double {
        guard appBarOpacities.indices.contains(rank) else {
            return appBarOpacities[appBarOpacities.count - 1]
        }
        return appBarOpacities[rank]
    }

    static func heatmapOpacity(words: Int, maxDay: Int) -> Double {
        guard words > 0 else { return heatmapOpacities[0] }
        let maxRef = max(maxDay, 1)
        if words >= maxRef { return heatmapOpacities[4] }
        let ratio = Double(words) / Double(maxRef)
        switch ratio {
        case ..<(1.0 / 3.0): return heatmapOpacities[1]
        case ..<(2.0 / 3.0): return heatmapOpacities[2]
        default: return heatmapOpacities[3]
        }
    }
}

// MARK: - Wiederverwendbare Stile

/// Mono-Kicker: UPPERCASE, gesperrt („TAGESBERICHT · …")
struct KickerStyle: ViewModifier {
    var color: Color
    var tracking: CGFloat = 1.4
    func body(content: Content) -> some View {
        content
            .font(Theme.Typo.kicker())
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundColor(color)
            .monospacedDigit()
    }
}

extension View {
    func kicker(_ color: Color, tracking: CGFloat = 1.4) -> some View {
        modifier(KickerStyle(color: color, tracking: tracking))
    }
}

/// v3-Hauptkarte: surface (weiß), Radius 16, keine Border, Akzent-Schatten.
struct CardStyle: ViewModifier {
    var padding: EdgeInsetWrapper

    init(padding: CGFloat = 16) {
        self.padding = .uniform(padding)
    }
    init(insets: EdgeInsets) {
        self.padding = .insets(insets)
    }

    func body(content: Content) -> some View {
        content
            .padding(padding.edgeInsets)
            .background(Theme.Palette.surface)
            .clipShape(Theme.cardShape)
            .shadow(color: Theme.shadow(Theme.accent), radius: 8, x: 0, y: 2)
    }
}

/// v3-Nebenkarte: identisch zur Hauptkarte (kein Unterschied in v3).
struct SecondaryCardStyle: ViewModifier {
    var padding: EdgeInsetWrapper = .uniform(16)

    init(padding: CGFloat = 16) { self.padding = .uniform(padding) }
    init(insets: EdgeInsets) { self.padding = .insets(insets) }

    func body(content: Content) -> some View {
        content
            .padding(padding.edgeInsets)
            .background(Theme.Palette.surface)
            .clipShape(Theme.cardShape)
            .shadow(color: Theme.shadow(Theme.accent), radius: 8, x: 0, y: 2)
    }
}

enum EdgeInsetWrapper {
    case uniform(CGFloat)
    case insets(EdgeInsets)

    var edgeInsets: EdgeInsets {
        switch self {
        case .uniform(let v): EdgeInsets(top: v, leading: v, bottom: v, trailing: v)
        case .insets(let e): e
        }
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
    func card(insets: EdgeInsets) -> some View { modifier(CardStyle(insets: insets)) }
    func secondaryCard(padding: CGFloat = 16) -> some View { modifier(SecondaryCardStyle(padding: padding)) }
    func secondaryCard(insets: EdgeInsets) -> some View { modifier(SecondaryCardStyle(insets: insets)) }
}

/// Keycap (Tastenkürzel-Chip): Geist Mono auf hover-Fläche.
struct KeyBadge: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Typo.keycap(11))
            .tracking(0.3)
            .foregroundColor(Theme.Palette.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.Palette.hover)
            .cornerRadius(7)
    }
}

/// Primärer Button v3: Akzent, weißer Text (Controls-Radius 9).
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Geist", size: 13).weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                    .fill(configuration.isPressed ? Theme.accentPressed : Theme.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.fast, value: configuration.isPressed)
    }
}

/// Sekundärer Button v3: surface + line-Border, gleicher Controls-Radius
/// wie der Primärbutton – keine gemischten Formen mehr in einer Zeile.
struct GhostButtonStyle: ButtonStyle {
    var destructive = false
    var monoCaps = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(monoCaps ? Theme.Typo.kicker(size: 10.5) : Font.custom("Geist", size: 13).weight(.medium))
            .textCase(monoCaps ? .uppercase : nil)
            .tracking(monoCaps ? 1 : 0)
            .foregroundColor(destructive ? Theme.Palette.destructive : Theme.Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                    .fill(configuration.isPressed ? Theme.Palette.hover : Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                    .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Theme.Motion.fast, value: configuration.isPressed)
    }
}

/// v3-Input: surface-Hintergrund, Radius 12, kein Border, Akzent-Schatten.
struct StasiInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Font.custom("Geist", size: 13.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput, style: .continuous))
            .shadow(color: Theme.shadow(Theme.accent), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func stasiInput(border: Color = Theme.Palette.line) -> some View {
        modifier(StasiInputStyle())
    }
}

// MARK: - Mikrointeraktionen (v3: dezent, respektieren reduced motion)

struct LiftOnHover: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .offset(y: hovered && !reduceMotion ? -3 : 0)
            .shadow(color: Theme.shadow(Theme.accent),
                    radius: hovered ? 12 : 8, x: 0, y: hovered ? 6 : 2)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : Theme.Motion.micro, value: hovered)
    }
}

struct SlideOnHover: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .offset(x: hovered && !reduceMotion ? 3 : 0)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : Theme.Motion.micro, value: hovered)
    }
}

struct ScaleOnHover: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered && !reduceMotion ? 1.1 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : Theme.Motion.micro, value: hovered)
    }
}

extension View {
    func liftOnHover() -> some View { modifier(LiftOnHover()) }
    func slideOnHover() -> some View { modifier(SlideOnHover()) }
    func scaleOnHover() -> some View { modifier(ScaleOnHover()) }
}

/// Status-Chip „Bereit"/„Hotkey inaktiv": 999-Pille mit Punkt.
struct StatusChip: View {
    var ok: Bool
    var text: String
    var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            if pulse && !ok {
                Circle()
                    .fill(Theme.Palette.recRed)
                    .frame(width: 6, height: 6)
                    .pulseForever(intensity: 0.55)
            } else {
                Circle()
                    .fill(ok ? Theme.Palette.archivgruen : Theme.Palette.recRed)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(Theme.Typo.secondary(size: 11.5))
                .foregroundColor(ok ? Theme.Palette.erfolgText : Theme.Palette.recRed)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(ok ? Theme.Palette.erfolgFlaeche : Theme.Palette.warnFlaeche))
    }
}