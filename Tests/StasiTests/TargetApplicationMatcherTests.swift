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

    func testChunkRoutingDoesNotSplitEmojiAfterTwentyThreeUTF16Units() {
        let text = String(repeating: "a", count: 23) + "😀" + "b"
        var chunks: [[UniChar]] = []

        let succeeded = TextInjector.routeChunks(text, targetPID: slack.processIdentifier) { chunk, _ in
            chunks.append(chunk)
            return true
        }

        XCTAssertTrue(succeeded)
        XCTAssertEqual(chunks.map { String(decoding: $0, as: UTF16.self) }, [
            String(repeating: "a", count: 23),
            "😀b",
        ])
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 24 })
    }

    func testChunkRoutingKeepsNonBMPScalarAtExactBoundary() {
        let text = String(repeating: "a", count: 22) + "😀" + "b"
        var chunks: [[UniChar]] = []

        _ = TextInjector.routeChunks(text, targetPID: slack.processIdentifier) { chunk, _ in
            chunks.append(chunk)
            return true
        }

        XCTAssertEqual(chunks.map { String(decoding: $0, as: UTF16.self) }, [
            String(repeating: "a", count: 22) + "😀",
            "b",
        ])
        XCTAssertEqual(chunks.map(\.count), [24, 1])
    }

    func testChunkRoutingPreservesMultipleNonBMPScalarsAndUTF16Limit() {
        let text = String(repeating: "𐐷", count: 13) + "🧑🏽‍💻" + "Ende"
        var chunks: [[UniChar]] = []

        _ = TextInjector.routeChunks(text, targetPID: slack.processIdentifier) { chunk, _ in
            chunks.append(chunk)
            return true
        }

        XCTAssertEqual(chunks.map { String(decoding: $0, as: UTF16.self) }.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 24 })
        XCTAssertTrue(chunks.allSatisfy { chunk in
            guard let first = chunk.first, let last = chunk.last else { return false }
            return !(0xDC00...0xDFFF).contains(first) && !(0xD800...0xDBFF).contains(last)
        })
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
