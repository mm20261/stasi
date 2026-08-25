import XCTest
import AVFoundation
import SwiftUI
@testable import Stasi

// MARK: - SettingsStore (Persistenz, Akzent, Modi)

@MainActor
final class SettingsStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "stasi-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsOnFirstLaunch() {
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.accentHex, 0x1A1917)
        XCTAssertEqual(settings.hotkeyMode, .pushToTalk)
        XCTAssertTrue(settings.soundOn)
        XCTAssertFalse(settings.ironyOn)
        XCTAssertFalse(settings.autostartOn)
    }

    func testAccentPersistenceAndThemeSync() {
        let settings = SettingsStore(defaults: defaults)
        settings.accentHex = 0x2D6A4F

        // Theme übernimmt sofort
        XCTAssertEqual(Theme.accent, Color(stasiHex: 0x2D6A4F))

        // Neue Instanz liest denselben Wert
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.accentHex, 0x2D6A4F)
    }

    func testAccentPressedIsDarker() {
        let settings = SettingsStore(defaults: defaults)
        settings.accentHex = 0xFFFFFF // weiß → pressed = 80 % = 0xCCCCCC
        XCTAssertEqual(settings.accentPressedColor, Color(stasiHex: 0xCCCCCC))
    }

    func testHotkeyModePersistence() {
        let settings = SettingsStore(defaults: defaults)
        settings.hotkeyMode = .toggle
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotkeyMode, .toggle)
    }

    func testTranscriptionLocale() {
        let settings = SettingsStore(defaults: defaults)
        settings.language = "de_DE"
        XCTAssertEqual(settings.transcriptionLocale.identifier, "de_DE")
        settings.language = "en_US"
        XCTAssertEqual(settings.transcriptionLocale.identifier, "en_US")
        settings.language = "auto"
        XCTAssertEqual(settings.transcriptionLocale.identifier, Locale.current.identifier)
    }

    func testUserNamePersistence() {
        let settings = SettingsStore(defaults: defaults)
        settings.userName = "Phil"
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.userName, "Phil")
    }

    func testRetentionDefaultAndPersistence() {
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.retention, .forever)
        settings.retention = .oneMonth
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.retention, .oneMonth)
    }

    func testRetentionDaysMapping() {
        XCTAssertNil(Retention.forever.days)
        XCTAssertEqual(Retention.oneDay.days, 1)
        XCTAssertEqual(Retention.oneWeek.days, 7)
        XCTAssertEqual(Retention.twoWeeks.days, 14)
        XCTAssertEqual(Retention.oneMonth.days, 30)
    }
}

// MARK: - Ironie-Copy

@MainActor
final class CopyTests: XCTestCase {

    private func makeSettings(irony: Bool) -> SettingsStore {
        let d = UserDefaults(suiteName: "copy-tests-\(UUID().uuidString)")!
        let s = SettingsStore(defaults: d)
        s.ironyOn = irony
        return s
    }

    func testTaglineIronic() {
        XCTAssertEqual(Copy.tagline(makeSettings(irony: true)), "Wir hören zu.")
    }

    func testTaglineNeutral() {
        XCTAssertEqual(Copy.tagline(makeSettings(irony: false)), "Lokales Diktat.")
    }

    func testPrivacyFootnoteDiffers() {
        XCTAssertNotEqual(Copy.privacyFootnote(makeSettings(irony: true)),
                          Copy.privacyFootnote(makeSettings(irony: false)))
    }
}

// MARK: - VirtualKey-Namen

final class VirtualKeyTests: XCTestCase {

    func testKnownKeys() {
        XCTAssertEqual(VirtualKey.name(for: 54), "Rechte ⌘ halten")
        XCTAssertEqual(VirtualKey.name(for: 55), "Linke ⌘ halten")
        XCTAssertEqual(VirtualKey.name(for: 49), "Space halten")
        XCTAssertEqual(VirtualKey.name(for: 96), "F5 halten")
    }

    func testLetterKeys() {
        XCTAssertEqual(VirtualKey.name(for: 0), "A")
        XCTAssertEqual(VirtualKey.name(for: 16), "Y")
    }

    func testUnknownKeyFallsBack() {
        XCTAssertEqual(VirtualKey.name(for: 999), "Taste 999")
    }

    func testComboDisplayModifierOnly() {
        XCTAssertEqual(VirtualKey.display(HotkeyEngine.Combo(keyCode: 54, flags: 0)), "⌘ Rechts")
    }

    func testComboDisplayKeyWithModifiers() {
        let flags = CGEventFlags.maskAlternate.rawValue
        XCTAssertEqual(VirtualKey.display(HotkeyEngine.Combo(keyCode: 49, flags: flags)), "⌥ Leertaste")
    }

    func testComboDisplayLetter() {
        XCTAssertEqual(VirtualKey.display(HotkeyEngine.Combo(keyCode: 0, flags: 0)), "A")
    }

    func testComboDisplayMultiModifiers() {
        let flags = CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue
        XCTAssertEqual(VirtualKey.display(HotkeyEngine.Combo(keyCode: 8, flags: flags)), "⌃⌘ C")
    }

    func testModifierSymbolsOrder() {
        let flags = CGEventFlags.maskShift.rawValue | CGEventFlags.maskAlternate.rawValue
        XCTAssertEqual(VirtualKey.modifierSymbols(flags), "⌥⇧")
    }

    func testEditableRoles() {
        XCTAssertTrue(TextInjector.isEditableRole("AXTextField"))
        XCTAssertTrue(TextInjector.isEditableRole("AXTextArea"))
        XCTAssertTrue(TextInjector.isEditableRole("AXWebArea"))
        XCTAssertTrue(TextInjector.isEditableRole("AXComboBox"))
    }

    func testNonEditableRoles() {
        XCTAssertFalse(TextInjector.isEditableRole("AXButton"))
        XCTAssertFalse(TextInjector.isEditableRole("AXWindow"))
        XCTAssertFalse(TextInjector.isEditableRole("AXGroup"))
        XCTAssertFalse(TextInjector.isEditableRole(""))
    }
}

// MARK: - AudioCapture-Level-Berechnung

final class AudioLevelTests: XCTestCase {

    private func buffer(withAmplitude amplitude: Float, sampleRate: Double = 48_000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        buffer.frameLength = 4096
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(buffer.frameLength) {
            data[i] = amplitude * sin(Float(i) * 0.1)
        }
        return buffer
    }

    func testSilenceGivesZero() {
        let level = AudioCapture.computeLevel(of: buffer(withAmplitude: 0))
        XCTAssertEqual(level, 0, accuracy: 0.0001)
    }

    func testLoudSignalGivesHighLevel() {
        let level = AudioCapture.computeLevel(of: buffer(withAmplitude: 0.5))
        XCTAssertGreaterThan(level, 0.5)
    }

    func testQuietSignalGivesLowerLevel() {
        let loud = AudioCapture.computeLevel(of: buffer(withAmplitude: 0.5))
        let quiet = AudioCapture.computeLevel(of: buffer(withAmplitude: 0.05))
        XCTAssertLessThan(quiet, loud)
    }

    func testLevelIsNormalized() {
        let level = AudioCapture.computeLevel(of: buffer(withAmplitude: 10.0))
        XCTAssertLessThanOrEqual(level, 1.0)
    }
}
