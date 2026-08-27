import XCTest
@testable import Stasi

@MainActor
final class UpdateCheckerTests: XCTestCase {

    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!
    private let repositoryURL = URL(string: "https://example.com/repos/stasi/releases/latest")!
    private let releaseURL = URL(string: "https://example.com/releases/v1.0")!
    private let checkedAt = Date(timeIntervalSince1970: 1_777_777_777)

    override func setUp() {
        super.setUp()
        suiteName = "update-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: Release-Konfiguration

    func testReleaseConfigurationReadsValidURLFromInjectedBundleInfo() {
        let info: [String: Any] = [
            "STASI_RELEASE_API_URL": "https://example.com/repos/stasi/releases/latest"
        ]

        XCTAssertEqual(
            ReleaseConfiguration.repositoryAPIURL(infoDictionary: info),
            repositoryURL
        )
    }

    func testReleaseConfigurationRejectsMissingBlankAndInvalidValues() {
        XCTAssertNil(ReleaseConfiguration.repositoryAPIURL(infoDictionary: nil))
        XCTAssertNil(ReleaseConfiguration.repositoryAPIURL(infoDictionary: [:]))
        XCTAssertNil(ReleaseConfiguration.repositoryAPIURL(
            infoDictionary: ["STASI_RELEASE_API_URL": "   "]
        ))
        XCTAssertNil(ReleaseConfiguration.repositoryAPIURL(
            infoDictionary: ["STASI_RELEASE_API_URL": "not a URL"]
        ))
    }

    // MARK: Versionsvergleich

    func testNormalizeStripsPrefixAndSplits() {
        XCTAssertEqual(VersionComparator.components("v0.10"), [0, 10])
        XCTAssertEqual(VersionComparator.components("0.9"), [0, 9])
        XCTAssertEqual(VersionComparator.components("V1.2.3"), [1, 2, 3])
    }

    func testNumericComparisonNotLexicographic() {
        XCTAssertTrue(VersionComparator.isNewer("v0.10", than: "0.9"))
        XCTAssertFalse(VersionComparator.isNewer("0.9", than: "0.10"))
    }

    func testIsNewerVariants() {
        XCTAssertTrue(VersionComparator.isNewer("0.9.1", than: "0.9"))
        XCTAssertFalse(VersionComparator.isNewer("0.8", than: "0.9"))
        XCTAssertFalse(VersionComparator.isNewer("0.9", than: "0.9"))
        XCTAssertTrue(VersionComparator.isNewer("1.0", than: "0.9"))
    }

    func testCheckerDefaultsToDisplayedBundleVersion() {
        let checker = makeChecker(
            fetcher: StubReleaseFetcher(result: .success(
                ReleaseInfo(version: "v1.0", url: releaseURL)
            )),
            currentVersion: nil
        )

        XCTAssertEqual(checker.currentVersion, AppVersion.display)
    }

    func testGitHubPayloadDecodesHTMLURL() throws {
        let data = Data(#"{"tag_name":"v0.10","html_url":"https://example.com/releases/v0.10"}"#.utf8)
        let payload = try JSONDecoder().decode(GitHubReleaseFetcher.Payload.self, from: data)
        XCTAssertEqual(payload.tagName, "v0.10")
        XCTAssertEqual(payload.htmlURL.absoluteString, "https://example.com/releases/v0.10")
    }

    // MARK: Expliziter Checkstatus

    func testMissingReleaseURLIsReportedAsNotConfigured() async {
        let checker = UpdateChecker(
            fetcher: UnexpectedReleaseFetcher(),
            repositoryURL: nil,
            defaults: defaults,
            currentVersion: "0.9",
            now: { self.checkedAt }
        )

        await checker.check()

        XCTAssertEqual(checker.status, .failed(message: "Update-Prüfung nicht konfiguriert."))
        XCTAssertNil(checker.state.lastChecked)
    }

    func testHTTPFailureShowsFailureAndDoesNotStampSuccessfulCheck() async {
        let checker = makeChecker(fetcher: HTTPFailingReleaseFetcher())

        await checker.check()

        XCTAssertEqual(checker.status, .failed(message: "Update-Prüfung fehlgeschlagen."))
        XCTAssertNil(checker.state.lastChecked)
    }

    func testSameVersionShowsUpToDateAndPersistsSuccessfulCheck() async {
        let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
            ReleaseInfo(version: "0.9", url: releaseURL)
        )))

        await checker.check()

        XCTAssertEqual(checker.status, .upToDate(checkedAt))
        XCTAssertEqual(checker.state.lastChecked, checkedAt)
        XCTAssertNil(checker.state.availableVersion)
        XCTAssertNil(checker.state.releaseURL)

        let reloaded = makeChecker(fetcher: UnexpectedReleaseFetcher())
        XCTAssertEqual(reloaded.status, .upToDate(checkedAt))
    }

    func testNewerVersionShowsUpdateActionAndPersistsReleaseInfo() async {
        let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
            ReleaseInfo(version: "v1.0", url: releaseURL)
        )))

        await checker.check()

        XCTAssertEqual(
            checker.status,
            .updateAvailable(version: "1.0", url: releaseURL, checkedAt: checkedAt)
        )
        XCTAssertEqual(checker.state.lastChecked, checkedAt)
        XCTAssertEqual(checker.state.availableVersion, "1.0")
        XCTAssertEqual(checker.state.releaseURL, releaseURL)

        let reloaded = makeChecker(fetcher: UnexpectedReleaseFetcher())
        XCTAssertEqual(
            reloaded.status,
            .updateAvailable(version: "1.0", url: releaseURL, checkedAt: checkedAt)
        )
    }

    func testFailurePreservesPriorReleaseInfoButKeepsVisibleStatusFailed() async {
        let firstCheck = Date(timeIntervalSince1970: 1_700_000_000)
        var clock = SequenceClock(values: [firstCheck, checkedAt])
        let checker = UpdateChecker(
            fetcher: StubReleaseFetcher(result: .success(
                ReleaseInfo(version: "v1.0", url: releaseURL)
            )),
            repositoryURL: repositoryURL,
            defaults: defaults,
            currentVersion: "0.9",
            now: { clock.next() }
        )
        await checker.check()

        checker.replaceFetcher(HTTPFailingReleaseFetcher())
        await checker.check()

        XCTAssertEqual(checker.status, .failed(message: "Update-Prüfung fehlgeschlagen."))
        XCTAssertEqual(checker.state.lastChecked, firstCheck)
        XCTAssertEqual(checker.state.availableVersion, "1.0")
        XCTAssertEqual(checker.state.releaseURL, releaseURL)
    }

    func testStatusIsCheckingWhileFetchIsInFlight() async {
        let fetcher = ControlledReleaseFetcher()
        let checker = makeChecker(fetcher: fetcher)

        let task = Task { await checker.check() }
        await fetcher.waitUntilStarted()
        XCTAssertEqual(checker.status, .checking)

        await fetcher.succeed(with: ReleaseInfo(version: "0.9", url: releaseURL))
        await task.value
        XCTAssertEqual(checker.status, .upToDate(checkedAt))
    }

    // MARK: Pure UI-Ableitung

    func testStatusPresentationExhaustivelyMapsTextProgressAndColorRole() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let updateURL = URL(string: "https://example.com/releases/v1.0")!

        let cases: [(UpdateCheckStatus, UpdateStatusPresentation)] = [
            (
                .neverChecked,
                UpdateStatusPresentation(
                    text: "NOCH NIE GEPRÜFT",
                    colorRole: .neutral,
                    showsProgress: false
                )
            ),
            (
                .checking,
                UpdateStatusPresentation(
                    text: "PRÜFUNG LÄUFT …",
                    colorRole: .neutral,
                    showsProgress: true
                )
            ),
            (
                .upToDate(checkedAt),
                UpdateStatusPresentation(
                    text: "ZULETZT GEPRÜFT: HEUTE, 03:09",
                    colorRole: .success,
                    showsProgress: false
                )
            ),
            (
                .updateAvailable(version: "1.0", url: updateURL, checkedAt: checkedAt),
                UpdateStatusPresentation(
                    text: "ZULETZT GEPRÜFT: HEUTE, 03:09 · V 1.0 LIEGT BEREIT",
                    colorRole: .updateAvailable,
                    showsProgress: false
                )
            ),
            (
                .failed(message: "Update-Prüfung nicht konfiguriert."),
                UpdateStatusPresentation(
                    text: "Update-Prüfung nicht konfiguriert.",
                    colorRole: .warning,
                    showsProgress: false
                )
            ),
        ]

        for (status, expected) in cases {
            XCTAssertEqual(
                UpdateStatusPresentation(status: status, now: checkedAt, calendar: calendar),
                expected
            )
        }
    }

    // MARK: Helpers

    private func makeChecker(
        fetcher: some ReleaseFetching,
        currentVersion: String? = "0.9"
    ) -> UpdateChecker {
        UpdateChecker(
            fetcher: fetcher,
            repositoryURL: repositoryURL,
            defaults: defaults,
            currentVersion: currentVersion,
            now: { self.checkedAt }
        )
    }
}

private struct StubReleaseFetcher: ReleaseFetching {
    let result: Result<ReleaseInfo, Error>

    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo {
        try result.get()
    }
}

private struct UnexpectedReleaseFetcher: ReleaseFetching {
    struct UnexpectedCall: Error {}

    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo {
        throw UnexpectedCall()
    }
}

private struct HTTPFailingReleaseFetcher: ReleaseFetching {
    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo {
        throw GitHubReleaseFetcher.FetchError.badStatus
    }
}

private actor ControlledReleaseFetcher: ReleaseFetching {
    private var continuation: CheckedContinuation<ReleaseInfo, Error>?

    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func succeed(with release: ReleaseInfo) {
        continuation?.resume(returning: release)
        continuation = nil
    }
}

private struct SequenceClock {
    private var values: [Date]

    init(values: [Date]) {
        self.values = values
    }

    mutating func next() -> Date {
        values.removeFirst()
    }
}
