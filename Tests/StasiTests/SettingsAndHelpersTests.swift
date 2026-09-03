import XCTest
import AVFoundation
import CoreGraphics
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
        XCTAssertEqual(settings.accentHex, 0x1A1917)
        XCTAssertEqual(settings.hotkeyMode, .pushToTalk)
        XCTAssertTrue(settings.handsFreeOn)
        XCTAssertEqual(settings.handsFreeKeyCode, 63)
        XCTAssertTrue(settings.soundOn)
        XCTAssertFalse(settings.ironyOn)
        XCTAssertFalse(settings.autostartOn)
        XCTAssertEqual(settings.postProcessing, .standard)
    }

    func testPostProcessingPersists() {
        let settings = SettingsStore(defaults: defaults)
        settings.postProcessing = .off

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.postProcessing, .off)
        XCTAssertEqual(defaults.string(forKey: "stasi.postProcess"), "off")
    }

    func testLegacyAISettingIsRemovedWithoutMigration() {
        defaults.set(true, forKey: "stasi.aiOn")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.postProcessing, .standard)
        XCTAssertNil(defaults.object(forKey: "stasi.aiOn"))
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

    func testAccentPresetsContainV3Colors() {
        let hexes = SettingsStore.accentPresets.map(\.1)
        XCTAssertEqual(hexes, [0x1A1917, 0x1D4E89, 0xD64500, 0x2D6A4F, 0x5B4A8A])
    }

    func testHotkeyModePersistence() {
        let settings = SettingsStore(defaults: defaults)
        settings.hotkeyMode = .toggle
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotkeyMode, .toggle)
    }

    func testHotkeyPersistsInInjectedSettingsStore() throws {
        let combo = HotkeyEngine.Combo(
            keyCode: 49,
            flags: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
        )
        let settings = SettingsStore(defaults: defaults)

        settings.hotkeyCombo = combo

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotkeyCombo, combo)
        XCTAssertEqual(
            try JSONDecoder().decode(
                HotkeyEngine.Combo.self,
                from: XCTUnwrap(defaults.data(forKey: "stasi.hotkey.combo"))
            ),
            combo
        )
    }

    func testInvalidStoredHotkeyFallsBackToDefault() {
        defaults.set(Data("bad".utf8), forKey: "stasi.hotkey.combo")

        XCTAssertEqual(SettingsStore(defaults: defaults).hotkeyCombo, .defaultPTT)
    }

    func testHandsFreePersistence() {
        let settings = SettingsStore(defaults: defaults)
        settings.handsFreeOn = false
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.handsFreeOn)
    }

    func testHandsFreeKeyCodePersists() {
        let settings = SettingsStore(defaults: defaults)
        settings.handsFreeKeyCode = 62

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.handsFreeKeyCode, 62)
        XCTAssertEqual(defaults.object(forKey: "stasi.handsFree.keyCode") as? Int, 62)
    }

    func testHandsFreeKeyCodeRejectsRegularKeys() {
        let settings = SettingsStore(defaults: defaults)
        settings.handsFreeKeyCode = 0

        XCTAssertEqual(settings.handsFreeKeyCode, 63)
        XCTAssertEqual(defaults.object(forKey: "stasi.handsFree.keyCode") as? Int, 63)
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

    func testUILanguagePersistsAndUpdatesLocalizationOverride() {
        L10n.languageOverride = "de"
        defer { L10n.languageOverride = "de" }
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.uiLanguage, "auto")
        settings.uiLanguage = "en"

        XCTAssertEqual(defaults.string(forKey: "stasi.uiLanguage"), "en")
        XCTAssertEqual(L10n.languageOverride, "en")
        XCTAssertEqual(SettingsStore(defaults: defaults).uiLanguage, "en")

        settings.uiLanguage = "auto"
        XCTAssertNil(L10n.languageOverride)
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

    func testRetentionUsesFullLabels() {
        XCTAssertEqual(Retention.allCases.map(\.label), [
            "Nie löschen", "1 Tag", "1 Woche", "2 Wochen", "1 Monat",
        ])
    }

    func testAutostartFailureResetsToggle() {
        struct RegistrationError: Error {}
        let settings = SettingsStore(defaults: defaults) { enabled in
            if enabled { throw RegistrationError() }
        }

        settings.autostartOn = true

        XCTAssertFalse(settings.autostartOn)
        XCTAssertFalse(defaults.bool(forKey: "stasi.autostartOn"))
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

    func testPostProcessingCopy() {
        XCTAssertEqual(Copy.postProcessingTitle, "Nachbearbeitung")
        XCTAssertEqual(Copy.postProcessingOffLabel, "AUS")
        XCTAssertEqual(Copy.postProcessingStandardLabel, "STANDARD")
        XCTAssertFalse(Copy.postProcessingDescription(for: .off).isEmpty)
        XCTAssertFalse(Copy.postProcessingDescription(for: .standard).isEmpty)
    }
}

// MARK: - VirtualKey-Namen

final class VirtualKeyTests: XCTestCase {

    func testKnownKeys() {
        XCTAssertEqual(VirtualKey.name(for: 54), "Rechte ⌘ halten")
        XCTAssertEqual(VirtualKey.name(for: 55), "Linke ⌘ halten")
        XCTAssertEqual(VirtualKey.name(for: 49), "Space halten")
        XCTAssertEqual(VirtualKey.name(for: 96), "F5 halten")
        XCTAssertEqual(VirtualKey.keySymbol(62), "⌃ Rechts")
    }

    func testHandsFreeAllowsOnlyRequestedModifierKeys() {
        XCTAssertEqual(VirtualKey.handsFreeModifierKeyCodes,
                       [63, 55, 54, 58, 61, 59, 62, 56, 60])
        XCTAssertFalse(VirtualKey.isHandsFreeModifier(0))
        XCTAssertFalse(VirtualKey.isHandsFreeModifier(57))
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
        XCTAssertTrue(TextInjector.isEditableRole("AXTextField", valueSettable: false))
        XCTAssertTrue(TextInjector.isEditableRole("AXTextArea", valueSettable: false))
        XCTAssertTrue(TextInjector.isEditableRole("AXComboBox", valueSettable: false))
        XCTAssertTrue(TextInjector.isEditableRole("AXWebArea", valueSettable: true))
        XCTAssertFalse(TextInjector.isEditableRole("AXWebArea", valueSettable: false))
    }

    func testNonEditableRoles() {
        XCTAssertFalse(TextInjector.isEditableRole("AXButton", valueSettable: true))
        XCTAssertFalse(TextInjector.isEditableRole("AXWindow", valueSettable: true))
        XCTAssertFalse(TextInjector.isEditableRole("AXGroup", valueSettable: true))
        XCTAssertFalse(TextInjector.isEditableRole("", valueSettable: true))
    }
}

// MARK: - Diktatdauer-Formatierung

final class DurationFormatterTests: XCTestCase {
    func testFormatsRoundedMinutesAndSecondsAtBoundaries() {
        let cases: [(input: TimeInterval, expected: String)] = [
            (0.0, "0:00"),
            (59.4, "0:59"),
            (59.6, "1:00"),
            (60.0, "1:00"),
            (119.6, "2:00"),
            (-1.0, "0:00"),
        ]

        for testCase in cases {
            XCTAssertEqual(
                DurationFormatter.minutesAndSeconds(testCase.input),
                testCase.expected,
                "input=\(testCase.input)"
            )
        }
    }
}

// MARK: - DebugLog-Rotation

final class DebugLogTests: XCTestCase {
    func testOversizedLogIsRotated() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug-log-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("debug.log")
        try Data(repeating: 0x41, count: 11).write(to: logURL)

        try DebugLog.rotateIfNeeded(at: logURL, maxBytes: 10)

        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("debug.log.1")).count, 11)
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
        XCTAssertLessThan(level, 0.05)
    }

    func testQuietSignalRemainsBelowRoomLevel() {
        let level = AudioCapture.computeLevel(of: buffer(withAmplitude: 0.005))
        XCTAssertTrue((0.3...0.5).contains(level), "level=\(level)")
    }

    func testRoomVolumeUsesMostOfMeterRange() {
        let level = AudioCapture.computeLevel(of: buffer(withAmplitude: 0.04))
        XCTAssertTrue((0.8...0.95).contains(level), "level=\(level)")
    }

    func testLoudSpeechStaysNormalizedAndAboveRoomVolume() {
        let room = AudioCapture.computeLevel(of: buffer(withAmplitude: 0.04))
        let loud = AudioCapture.computeLevel(of: buffer(withAmplitude: 0.08))
        XCTAssertGreaterThan(loud, room)
        XCTAssertLessThanOrEqual(loud, 1.0)
    }

    func testLevelIsNormalized() {
        let level = AudioCapture.computeLevel(of: buffer(withAmplitude: 10.0))
        XCTAssertLessThanOrEqual(level, 1.0)
    }
}

// MARK: - Permissions: tccutil-Argumente

final class PermissionsResetArgumentsTests: XCTestCase {
    func testArgumenteFuerEigeneBundleID() {
        XCTAssertEqual(
            Permissions.tccutilResetArguments(service: "Accessibility", bundleID: "app.stasi.macos"),
            ["reset", "Accessibility", "app.stasi.macos"]
        )
    }

    func testOhneBundleIDKeinReset() {
        XCTAssertNil(Permissions.tccutilResetArguments(service: "Accessibility", bundleID: nil))
        XCTAssertNil(Permissions.tccutilResetArguments(service: "Accessibility", bundleID: ""))
    }
}

