import XCTest
@testable import Stasi

// MARK: - Mikrofon-Auswahl (v4)
// Reine Katalog-Logik (Sortierung/Dedup) + SettingsStore-Persistenz.
// Die CoreAudio-Erkennung selbst braucht Hardware und wird manuell getestet.

final class MicrophoneCatalogTests: XCTestCase {

    private func device(_ uid: String, _ name: String, isDefault: Bool = false) -> MicDevice {
        MicDevice(uid: uid, name: name, isDefault: isDefault)
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
