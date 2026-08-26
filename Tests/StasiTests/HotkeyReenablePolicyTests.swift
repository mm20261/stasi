import XCTest
@testable import Stasi

final class HotkeyReenablePolicyTests: XCTestCase {
    func testEnabledTapNeedsNoAction() {
        var policy = HotkeyReenablePolicy()

        let action = policy.evaluate(isTapEnabled: { true })

        XCTAssertEqual(action, .none)
        XCTAssertEqual(policy.reenableCount, 0)
        XCTAssertFalse(policy.gaveUp)
    }

    func testDisabledTapRequestsFirstReenable() {
        var policy = HotkeyReenablePolicy()

        let action = policy.evaluate(isTapEnabled: { false })

        XCTAssertEqual(action, .reenable(attempt: 1))
        XCTAssertEqual(policy.reenableCount, 1)
    }

    func testThreeDisabledChecksRequestReenable() {
        var policy = HotkeyReenablePolicy()

        let actions = (1...3).map { _ in policy.evaluate(isTapEnabled: { false }) }

        XCTAssertEqual(actions, [
            .reenable(attempt: 1),
            .reenable(attempt: 2),
            .reenable(attempt: 3),
        ])
        XCTAssertFalse(policy.gaveUp)
    }

    func testFourthDisabledCheckGivesUp() {
        var policy = HotkeyReenablePolicy()
        for _ in 0..<3 { _ = policy.evaluate(isTapEnabled: { false }) }

        let action = policy.evaluate(isTapEnabled: { false })

        XCTAssertEqual(action, .giveUp)
        XCTAssertTrue(policy.gaveUp)
    }

    func testEnabledTapResetsConsecutiveCount() {
        var policy = HotkeyReenablePolicy()
        _ = policy.evaluate(isTapEnabled: { false })
        _ = policy.evaluate(isTapEnabled: { false })

        XCTAssertEqual(policy.evaluate(isTapEnabled: { true }), .none)
        XCTAssertEqual(policy.reenableCount, 0)
        XCTAssertEqual(policy.evaluate(isTapEnabled: { false }), .reenable(attempt: 1))
    }

    func testGaveUpStateIsStickyAndSkipsProbe() {
        var policy = HotkeyReenablePolicy(maxReenableAttempts: 1)
        _ = policy.evaluate(isTapEnabled: { false })
        _ = policy.evaluate(isTapEnabled: { false })
        var probeCount = 0

        let action = policy.evaluate(isTapEnabled: {
            probeCount += 1
            return true
        })

        XCTAssertEqual(action, .none)
        XCTAssertEqual(probeCount, 0)
        XCTAssertTrue(policy.gaveUp)
    }

    func testProbeIsInjectedAndCalledOnce() {
        var policy = HotkeyReenablePolicy()
        var probeCount = 0

        _ = policy.evaluate(isTapEnabled: {
            probeCount += 1
            return false
        })

        XCTAssertEqual(probeCount, 1)
    }

    @MainActor
    func testAppStateShowsRestartBlockerAfterPolicyGivesUp() {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-artifacts", isDirectory: true)
            .appendingPathComponent("hotkey-state-\(UUID().uuidString)", isDirectory: true)
        var policy = HotkeyReenablePolicy(maxReenableAttempts: 0)
        XCTAssertEqual(policy.evaluate(isTapEnabled: { false }), .giveUp)
        let defaults = UserDefaults(suiteName: "HotkeyState.\(UUID().uuidString)")!
        let app = AppState(
            settings: SettingsStore(defaults: defaults),
            dictionary: DictionaryStore(directory: directory.appendingPathComponent("dictionary")),
            history: HistoryStore(directory: directory.appendingPathComponent("history")),
            installHotkey: false,
            audioDirectory: directory.appendingPathComponent("audio")
        )
        app.accessibilityGranted = true
        app.hotkey = HotkeyEngine(combo: .defaultPTT, reenablePolicy: policy)

        XCTAssertFalse(app.hotkeyReady)
        XCTAssertEqual(app.hotkeyBlocker, Copy.hotkeyRestartRequired)
    }
}
