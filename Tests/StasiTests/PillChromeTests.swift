import XCTest
@testable import Stasi

// MARK: - Pill-Chrome (v4.1)
// ✕ und ✓ sind IMMER klickbar – auch im gelockten Modus (Hands-free),
// wie bei Wispr: Aufnahme stoppen (✓) oder verwerfen (✕) per Pill.

final class PillChromeTests: XCTestCase {

    func testPushToTalkShowsDiscardAndCommit() {
        XCTAssertTrue(PillChrome.showsButtons(for: .pushToTalk))
    }

    func testLockedModeAlsoShowsDiscardAndCommit() {
        // Wispr-Stil: Auch hands-free (gelockt) lässt sich per Pill
        // bestätigen (✓) oder verwerfen (✕).
        XCTAssertTrue(PillChrome.showsButtons(for: .handsFree))
    }

    func testPillWidthIdenticalForBothSources() {
        XCTAssertEqual(PillChrome.pillWidth(for: .pushToTalk), 160)
        XCTAssertEqual(PillChrome.pillWidth(for: .handsFree), 160)
    }
}

// MARK: - Echter Live-Pegel (Mic-Popover)

final class MicLevelBarTests: XCTestCase {

    func testSilenceStaysAtMinimum() {
        XCTAssertEqual(MicLevelBars.height(level: 0, jitter: 0), 2)
    }

    func testLoudLevelReachesMaximum() {
        XCTAssertEqual(MicLevelBars.height(level: 1, jitter: 0), 16)
    }

    func testMidLevelIsBetween() {
        let h = MicLevelBars.height(level: 0.5, jitter: 0)
        XCTAssertGreaterThan(h, 2)
        XCTAssertLessThan(h, 16)
    }

    func testLevelIsClamped() {
        XCTAssertEqual(MicLevelBars.height(level: -1, jitter: 0), 2)
        XCTAssertEqual(MicLevelBars.height(level: 5, jitter: 0), 16)
    }

    func testJitterOnlyModulatesWithinBounds() {
        for jitter in stride(from: -1.0, through: 1.0, by: 0.25) {
            let h = MicLevelBars.height(level: 0.4, jitter: jitter)
            XCTAssertTrue((2...16).contains(h), "h=\(h) außerhalb für jitter=\(jitter)")
        }
    }
}
