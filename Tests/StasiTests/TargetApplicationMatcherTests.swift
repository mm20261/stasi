import XCTest
@testable import Stasi

final class TargetApplicationMatcherTests: XCTestCase {
    private let slack = TargetApplication(
        localizedName: "Slack",
        bundleIdentifier: "com.tinyspeck.slackmacgap",
        processIdentifier: 42
    )

    func testSameBundleAndProcessMatches() {
        XCTAssertTrue(TargetApplicationMatcher.matches(captured: slack, current: slack))
    }

    func testSameBundleWithDifferentProcessDoesNotMatch() {
        let relaunchedSlack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 43
        )

        XCTAssertFalse(TargetApplicationMatcher.matches(captured: slack, current: relaunchedSlack))
    }

    func testMissingCurrentApplicationDoesNotMatch() {
        XCTAssertFalse(TargetApplicationMatcher.matches(captured: slack, current: nil))
    }

    func testCapturedApplicationWithoutBundleIdentifierMatchesByProcessOnly() {
        let captured = TargetApplication(
            localizedName: "Unknown",
            bundleIdentifier: nil,
            processIdentifier: 42
        )
        let current = TargetApplication(
            localizedName: "Renamed",
            bundleIdentifier: "com.example.current",
            processIdentifier: 42
        )

        XCTAssertTrue(TargetApplicationMatcher.matches(captured: captured, current: current))
    }

    func testCapturedApplicationWithoutBundleIdentifierRejectsDifferentProcess() {
        let captured = TargetApplication(
            localizedName: "Unknown",
            bundleIdentifier: nil,
            processIdentifier: 42
        )
        let current = TargetApplication(
            localizedName: "Unknown",
            bundleIdentifier: nil,
            processIdentifier: 43
        )

        XCTAssertFalse(TargetApplicationMatcher.matches(captured: captured, current: current))
    }

    func testSameNameAloneDoesNotMatch() {
        let notesNamedSlack = TargetApplication(
            localizedName: "Slack",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 42
        )

        XCTAssertFalse(TargetApplicationMatcher.matches(captured: slack, current: notesNamedSlack))
    }
}
