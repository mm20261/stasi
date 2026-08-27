import CoreAudio
import XCTest
@testable import Stasi

// MARK: - Mikrofon-Auswahl (v4)
// Reine Katalog-Logik (Sortierung/Dedup) + SettingsStore-Persistenz.
// Die CoreAudio-Erkennung selbst braucht Hardware und wird manuell getestet.

final class MicrophoneCatalogTests: XCTestCase {

    private func device(_ uid: String,
                        _ name: String,
                        isDefault: Bool = false,
                        transport: MicrophoneTransport = .builtIn,
                        inputChannels: Int = 1,
                        isSupportedForSpeech: Bool = true) -> MicDevice {
        MicDevice(uid: uid,
                  name: name,
                  isDefault: isDefault,
                  transport: transport,
                  inputChannels: inputChannels,
                  isSupportedForSpeech: isSupportedForSpeech)
    }

    func testSortPutsDefaultFirstThenAlphabetical() {
        let sorted = MicrophoneCatalog.sort([
            device("3", "Zoom Mic"),
            device("2", "AirPods"),
            device("1", "MacBook Pro", isDefault: true),
        ])
        XCTAssertEqual(sorted.map(\.name), ["MacBook Pro", "AirPods", "Zoom Mic"])
        XCTAssertTrue(sorted[0].isDefault)
    }

    func testSortWithoutDefaultIsAlphabetical() {
        let sorted = MicrophoneCatalog.sort([
            device("b", "Zoom"),
            device("a", "AirPods"),
        ])
        XCTAssertEqual(sorted.map(\.name), ["AirPods", "Zoom"])
    }

    func testDedupeKeepsFirstPerUID() {
        let deduped = MicrophoneCatalog.dedupe([
            device("x", "Erster"),
            device("y", "Anders"),
            device("x", "Zweiter"),
        ])
        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(deduped.first?.name, "Erster")
    }

    func testEmptyNamesAreDropped() {
        let cleaned = MicrophoneCatalog.sanitize([
            device("1", ""),
            device("2", "Gültig"),
            device("", "Ohne UID"),
        ])
        XCTAssertEqual(cleaned.count, 1)
        XCTAssertEqual(cleaned.first?.name, "Gültig")
    }

    func testInputChannelCountReadsEveryBufferInVariableAudioBufferList() {
        let list = AudioBufferList.allocate(maximumBuffers: 3)
        defer { free(list.unsafeMutablePointer) }
        list.unsafeMutablePointer.pointee.mNumberBuffers = 3
        list[0].mNumberChannels = 1
        list[1].mNumberChannels = 2
        list[2].mNumberChannels = 3

        XCTAssertEqual(MicrophoneScanner.inputChannelCount(from: list.unsafeMutablePointer), 6)
    }

    func testTransportTypeMapsKnownCoreAudioTransports() {
        XCTAssertEqual(MicrophoneScanner.microphoneTransport(from: kAudioDeviceTransportTypeBuiltIn), .builtIn)
        XCTAssertEqual(MicrophoneScanner.microphoneTransport(from: kAudioDeviceTransportTypeUSB), .wired)
        XCTAssertEqual(MicrophoneScanner.microphoneTransport(from: kAudioDeviceTransportTypeThunderbolt), .wired)
        XCTAssertEqual(MicrophoneScanner.microphoneTransport(from: kAudioDeviceTransportTypeBluetooth), .bluetooth)
        XCTAssertEqual(MicrophoneScanner.microphoneTransport(from: kAudioDeviceTransportTypeBluetoothLE), .bluetooth)
        XCTAssertEqual(MicrophoneScanner.microphoneTransport(from: kAudioDeviceTransportTypeVirtual), .virtual)
        XCTAssertEqual(MicrophoneScanner.microphoneTransport(from: 0xDEAD_BEEF), .unknown(0xDEAD_BEEF))
    }

    func testAutomaticDefaultPrefersBuiltInOverBluetoothSystemDefault() {
        let bluetoothDefault = device("bluetooth", "AirPods",
                                      isDefault: true,
                                      transport: .bluetooth)
        let builtIn = device("built-in", "MacBook Mikrofon", transport: .builtIn)

        let selected = MicrophoneCatalog.automaticDefault(from: [bluetoothDefault, builtIn])

        XCTAssertEqual(selected?.uid, builtIn.uid)
    }

    func testAutomaticDefaultPrefersWiredOverBluetoothWhenBuiltInIsUnavailable() {
        let bluetoothDefault = device("bluetooth", "AirPods",
                                      isDefault: true,
                                      transport: .bluetooth)
        let wired = device("usb", "USB Mikrofon", transport: .wired)

        let selected = MicrophoneCatalog.automaticDefault(from: [bluetoothDefault, wired])

        XCTAssertEqual(selected?.uid, wired.uid)
    }

    func testExplicitSupportedBluetoothSelectionIsRespected() {
        let bluetooth = device("bluetooth", "AirPods", transport: .bluetooth)
        let builtIn = device("built-in", "MacBook Mikrofon", transport: .builtIn)

        let selected = MicrophoneCatalog.resolve(preferredUID: bluetooth.uid,
                                                 devices: [bluetooth, builtIn])

        XCTAssertEqual(selected?.uid, bluetooth.uid)
    }

    func testUnsupportedExplicitSelectionFallsBackToSupportedAutomaticDefault() {
        let unsupported = device("unsupported", "Defektes Gerät",
                                 isDefault: true,
                                 transport: .bluetooth,
                                 inputChannels: 0,
                                 isSupportedForSpeech: false)
        let builtIn = device("built-in", "MacBook Mikrofon", transport: .builtIn)

        let selected = MicrophoneCatalog.resolve(preferredUID: unsupported.uid,
                                                 devices: [unsupported, builtIn])

        XCTAssertEqual(selected?.uid, builtIn.uid)
    }

    // MARK: Persistenz der Auswahl

    @MainActor
    func testMicSelectionPersists() {
        let suite = "mic-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertNil(settings.preferredMicUID)
        settings.preferredMicUID = "apple-built-in"
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferredMicUID, "apple-built-in")
    }

    @MainActor
    func testNilMicSelectionMeansSystemDefault() {
        let suite = "mic-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        settings.preferredMicUID = "irgendwas"
        settings.preferredMicUID = nil
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertNil(reloaded.preferredMicUID)
    }
}
