import XCTest
import SwiftUI
@testable import Stasi

// MARK: - Theme v3 Token-Vertrag
// Vertrag aus import/design_handoff_v3/DESIGN.md plus freigegebene A11y-Korrekturen.

final class ThemeV3Tests: XCTestCase {

    // MARK: Flächen (Verlauf-Hintergrund + weiße Karten)

    func testGradientTokens() {
        XCTAssertEqual(Theme.Hex.backgroundTop, 0xF3F6FA)
        XCTAssertEqual(Theme.Hex.backgroundBottom, 0xF8F7F3)
    }

    func testFarbTokens() {
        XCTAssertEqual(Theme.Hex.surface, 0xFFFFFF)
        XCTAssertEqual(Theme.Hex.ink, 0x1A1917)
        XCTAssertEqual(Theme.Hex.sub, 0x6F6C66)
        XCTAssertEqual(Theme.Hex.line, 0xECEAE4)
        XCTAssertEqual(Theme.Hex.hover, 0xF1F4F8)
        XCTAssertEqual(Theme.Hex.rec, 0xFF453A)
        XCTAssertEqual(Theme.Hex.destructive, 0xC8102E)
        XCTAssertEqual(Theme.Hex.success, 0x30A46C)
        XCTAssertEqual(Theme.Hex.successText, 0x1F7A4D)
        XCTAssertEqual(Theme.Hex.warning, 0x8A5500)
    }

    func testTextTokensMeetContrastOnWhite() {
        XCTAssertGreaterThanOrEqual(
            Theme.Contrast.ratio(foreground: Theme.Hex.sub, background: Theme.Hex.surface),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            Theme.Contrast.ratio(foreground: Theme.Hex.successText,
                                 background: Theme.Hex.surface),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            Theme.Contrast.ratio(foreground: Theme.Hex.warning,
                                 background: Theme.Hex.surface),
            4.5
        )
    }

    // MARK: Akzent-Presets (5, dynamisch, Standard Anthrazit)

    func testAccentPresetsMatchV3() {
        let hexes = SettingsStore.accentPresets.map(\.1)
        XCTAssertEqual(hexes.count, 5)
        XCTAssertEqual(hexes, [0x1A1917, 0x1D4E89, 0xD64500, 0x2D6A4F, 0x5B4A8A])
    }

    @MainActor
    func testDefaultAccentIsAnthrazit() {
        // Ohne aktiven Store fällt Theme.accent auf Anthrazit zurück.
        Theme.sharedSettings = nil
        XCTAssertEqual(Theme.accent, Color(stasiHex: 0x1A1917))
    }

    // MARK: Typografie (gebündelt Geist / Geist Mono)

    func testFontRegistrationNames() {
        XCTAssertEqual(Set(FontLoader.fontResourceNames), ["Geist", "GeistMono"])
    }

    // MARK: Raum & Form (v3: Karte r16, Controls r9, Inputs r12, Pill 999)

    func testMetrics() {
        XCTAssertEqual(Theme.Metrics.sidebarWidth, 200)
        XCTAssertEqual(Theme.Metrics.sidebarCollapsed, 64)
        XCTAssertEqual(Theme.Metrics.radiusCard, 16)
        XCTAssertEqual(Theme.Metrics.radiusControl, 9)
        XCTAssertEqual(Theme.Metrics.radiusInput, 12)
        XCTAssertEqual(Theme.Metrics.radiusPill, 999)
        XCTAssertEqual(Theme.Metrics.gridGap, 12)
    }

    // MARK: Wiederverwendung identischer UI-Strukturen

    func testPermissionWarningUsesSharedReduceMotionPulse() throws {
        let dashboard = try source(at: "Sources/Stasi/UI/DashboardView.swift")
        let effects = try source(at: "Sources/Stasi/UI/Effects.swift")

        XCTAssertTrue(dashboard.contains(".pulseForever(intensity: 0.75)"))
        XCTAssertFalse(dashboard.contains("pulseOn"))
        XCTAssertFalse(dashboard.contains("startPulse"))
        XCTAssertTrue(effects.contains("pulsing = !reduced"))
    }

    func testSecondaryCardDelegatesToCardStyle() throws {
        let theme = try source(at: "Sources/Stasi/UI/Theme.swift")

        XCTAssertTrue(theme.contains("typealias SecondaryCardStyle = CardStyle"))
        XCTAssertTrue(theme.contains("func secondaryCard(padding: CGFloat = 16)"))
        XCTAssertTrue(theme.contains("func secondaryCard(insets: EdgeInsets)"))
    }

    private func source(at relativePath: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
