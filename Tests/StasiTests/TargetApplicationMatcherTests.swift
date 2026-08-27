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

    func testSameBundleAndProcessMatchesDespiteDifferentLocalizedName() {
        let renamedSlack = TargetApplication(
            localizedName: "Slack Beta",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            processIdentifier: 42
        )

        XCTAssertTrue(TargetApplicationMatcher.matches(captured: slack, current: renamedSlack))
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

    func testEveryUnicodeChunkIsBoundToCapturedProcess() {
        let text = String(repeating: "abcdefghijklmnopqrstuvwx", count: 3)
        var deliveries: [(String, pid_t)] = []

        let succeeded = TextInjector.routeChunks(text, targetPID: slack.processIdentifier) { chunk, pid in
            deliveries.append((String(decoding: chunk, as: UTF16.self), pid))
            return true
        }

        XCTAssertTrue(succeeded)
        XCTAssertEqual(deliveries.map(\.0).joined(), text)
        XCTAssertGreaterThan(deliveries.count, 1)
        XCTAssertTrue(deliveries.allSatisfy { $0.1 == slack.processIdentifier })
    }

    func testChunkRoutingAbortsAfterMiddleEventCreationFailure() {
        let text = String(repeating: "abcdefghijklmnopqrstuvwx", count: 3)
        var attemptedChunks: [String] = []

        let succeeded = TextInjector.routeChunks(text, targetPID: slack.processIdentifier) { chunk, _ in
            attemptedChunks.append(String(decoding: chunk, as: UTF16.self))
            return attemptedChunks.count != 2
        }

        XCTAssertFalse(succeeded)
        XCTAssertEqual(attemptedChunks.count, 2)
        XCTAssertEqual(attemptedChunks[0], "abcdefghijklmnopqrstuvwx")
        XCTAssertEqual(attemptedChunks[1], "abcdefghijklmnopqrstuvwx")
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
