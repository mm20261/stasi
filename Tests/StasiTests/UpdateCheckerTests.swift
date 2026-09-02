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

    func testReleaseConfigurationRejectsMissingBlankMalformedAndNonHTTPSValues() {
        let rejected = [
            "   ",
            "not a URL",
            "http://example.com/repos/stasi/releases/latest",
            "https:///releases/latest",
            "file:///tmp/release.json",
            "stasi://example.com/releases/latest",
        ]

        XCTAssertNil(ReleaseConfiguration.repositoryAPIURL(infoDictionary: nil))
        XCTAssertNil(ReleaseConfiguration.repositoryAPIURL(infoDictionary: [:]))
        for value in rejected {
            XCTAssertNil(
                ReleaseConfiguration.repositoryAPIURL(
                    infoDictionary: ["STASI_RELEASE_API_URL": value]
                ),
                "Expected rejection for \(value)"
            )
        }
    }

    // MARK: Versionsvergleich

    func testSemVerParserAcceptsExactNumericCoreOptionalVAndMetadata() throws {
        XCTAssertEqual(try XCTUnwrap(SemVer("0.10.0")).description, "0.10.0")
        XCTAssertEqual(try XCTUnwrap(SemVer("v0.10")).description, "0.10.0")
        XCTAssertEqual(try XCTUnwrap(SemVer("1.0")).description, "1.0.0")
        XCTAssertEqual(try XCTUnwrap(SemVer("1")).description, "1.0.0")
        XCTAssertEqual(try XCTUnwrap(SemVer("v1.2.3")).description, "1.2.3")
        XCTAssertEqual(
            try XCTUnwrap(SemVer("V2.0.1-rc.2+build.17")).description,
            "2.0.1-rc.2+build.17"
        )
    }

    func testSemVerParserRejectsMalformedVersions() {
        let invalid = [
            "", " ", "release", "1.2.3.4", ".1.2.3",
            "1.2.3-", "1.2.3+", "1.2.3-alpha..1", "01.2.3", "1.02.3",
            "1.2.03", "1.2.-3", "1.2.3_alpha", "1.2.3+build..1",
        ]

        for version in invalid {
            XCTAssertNil(SemVer(version), "Expected invalid SemVer: \(version)")
        }
    }

    func testSemVerAcceptsArbitrarilyLargeNumericIdentifiers() throws {
        let hugeCore = try XCTUnwrap(SemVer("184467440737095516160.2.3"))
        let hugePrerelease = try XCTUnwrap(SemVer("1.0.0-184467440737095516160"))
        let alphanumericPrerelease = try XCTUnwrap(SemVer("1.0.0-alpha"))

        XCTAssertGreaterThan(hugeCore, try XCTUnwrap(SemVer("999.999.999")))
        XCTAssertLessThan(hugePrerelease, alphanumericPrerelease)
        XCTAssertGreaterThan(
            hugePrerelease,
            try XCTUnwrap(SemVer("1.0.0-184467440737095516159"))
        )
    }

    func testSemVerPrereleaseAndBuildMetadataPrecedence() throws {
        let ordered = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
        ].compactMap(SemVer.init)

        XCTAssertEqual(ordered.count, 8)
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
        XCTAssertEqual(SemVer("1.0.0+first"), SemVer("1.0.0+second"))
        XCTAssertEqual(SemVer("v1.2.3")?.normalizedCore, "1.2.3")
    }

    func testNumericComparisonRequiresTwoValidSemVers() {
        XCTAssertEqual(VersionComparator.isNewer("v0.10.0", than: "0.9.0"), true)
        XCTAssertEqual(VersionComparator.isNewer("0.9.0", than: "0.10.0"), false)
        XCTAssertNil(VersionComparator.isNewer("release", than: "0.9.0"))
        XCTAssertNil(VersionComparator.isNewer("1.0.0", than: "dev"))
    }

    func testCheckerDefaultsToDisplayedBundleVersion() {
        let checker = makeChecker(
            fetcher: StubReleaseFetcher(result: .success(
                ReleaseInfo(version: "v1.0.0", url: releaseURL)
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

    func testGitHubRequestUsesEphemeralConfigurationAndRequiredHeaders() throws {
        let configuration = GitHubReleaseFetcher.makeConfiguration()
        let request = GitHubReleaseFetcher.makeRequest(
            repositoryURL: repositoryURL,
            appVersion: "1.0"
        )

        XCTAssertNil(configuration.urlCache)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Stasi/1.0")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            "application/vnd.github+json"
        )
    }

    // MARK: Expliziter Checkstatus

    func testMissingReleaseURLIsReportedAsNotConfigured() async {
        let checker = UpdateChecker(
            fetcher: UnexpectedReleaseFetcher(),
            repositoryURL: nil,
            defaults: defaults,
            currentVersion: "0.9.0",
            now: { self.checkedAt }
        )

        await checker.check()

        XCTAssertEqual(checker.status, .failed(message: "Update-Prüfung nicht konfiguriert."))
        XCTAssertNil(checker.state.lastChecked)
    }

    func testHTTPFailureShowsFailureAndDoesNotStampSuccessfulCheck() async {
        let checker = makeChecker(fetcher: HTTPFailingReleaseFetcher())

        await checker.check()

        XCTAssertEqual(checker.status, .failed(message: "Ungültige Antwort vom Update-Server."))
        XCTAssertNil(checker.state.lastChecked)
    }

    func testSameVersionShowsUpToDateAndPersistsSuccessfulCheck() async {
        let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
            ReleaseInfo(version: "0.9.0", url: releaseURL)
        )))

        await checker.check()

        XCTAssertEqual(checker.status, .upToDate(checkedAt))
        XCTAssertEqual(checker.state.lastChecked, checkedAt)
        XCTAssertNil(checker.state.availableVersion)
        XCTAssertNil(checker.state.releaseURL)

        let reloaded = makeChecker(fetcher: UnexpectedReleaseFetcher())
        XCTAssertEqual(reloaded.status, .neverChecked)
    }

    func testInvalidRemoteVersionFailsInsteadOfReportingUpToDate() async {
        let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
            ReleaseInfo(version: "release-1", url: releaseURL)
        )))

        await checker.check()

        XCTAssertEqual(checker.status, .failed(message: "Ungültige Versionsangabe in der Update-Antwort."))
        XCTAssertNil(checker.state.lastChecked)
    }

    func testInvalidCurrentVersionFailsInsteadOfReportingUpToDate() async {
        let checker = makeChecker(
            fetcher: StubReleaseFetcher(result: .success(
                ReleaseInfo(version: "1.0.0", url: releaseURL)
            )),
            currentVersion: "dev"
        )

        await checker.check()

        XCTAssertEqual(checker.status, .failed(message: "Ungültige Versionsangabe in der Update-Antwort."))
        XCTAssertNil(checker.state.lastChecked)
    }

    func testEndpointReleaseLinkMustBeHTTPSWithHost() async {
        let invalidURLs = [
            URL(string: "http://example.com/releases/v1.0.0")!,
            URL(fileURLWithPath: "/tmp/release"),
            URL(string: "stasi://example.com/releases/v1.0.0")!,
            URL(string: "https:///releases/v1.0.0")!,
        ]

        for invalidURL in invalidURLs {
            defaults.removePersistentDomain(forName: suiteName)
            let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
                ReleaseInfo(version: "1.0.0", url: invalidURL)
            )))

            await checker.check()

            XCTAssertEqual(
                checker.status,
                .failed(message: "Ungültige Antwort vom Update-Server."),
                "Expected rejection for \(invalidURL)"
            )
            XCTAssertNil(checker.state.lastChecked)
        }
    }

    func testNewerVersionShowsUpdateActionAndPersistsReleaseInfo() async {
        let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
            ReleaseInfo(version: "v1.0.0", url: releaseURL)
        )))

        await checker.check()

        XCTAssertEqual(
            checker.status,
            .updateAvailable(version: "1.0.0", url: releaseURL, checkedAt: checkedAt)
        )
        XCTAssertEqual(checker.state.lastChecked, checkedAt)
        XCTAssertEqual(checker.state.availableVersion, "1.0.0")
        XCTAssertEqual(checker.state.releaseURL, releaseURL)

        XCTAssertEqual(
            defaults.string(forKey: "stasi.update.source"),
            "https://example.com/repos/stasi/releases/latest"
        )

        let reloaded = makeChecker(fetcher: UnexpectedReleaseFetcher())
        XCTAssertEqual(
            reloaded.status,
            .updateAvailable(version: "1.0.0", url: releaseURL, checkedAt: checkedAt)
        )
    }

    func testPersistedUpdateAcceptsEquivalentNormalizedConfiguredSource() async {
        let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
            ReleaseInfo(version: "1.0.0", url: releaseURL)
        )))
        await checker.check()

        let equivalentSource = URL(string: "HTTPS://EXAMPLE.COM/repos/stasi/releases/latest")!
        let reloaded = UpdateChecker(
            fetcher: UnexpectedReleaseFetcher(),
            repositoryURL: equivalentSource,
            defaults: defaults,
            currentVersion: "0.9.0",
            now: { self.checkedAt }
        )

        XCTAssertEqual(
            reloaded.status,
            .updateAvailable(version: "1.0.0", url: releaseURL, checkedAt: checkedAt)
        )
    }

    func testPersistedUpdateFailsClosedWithoutConfiguredOrMatchingSource() async {
        let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
            ReleaseInfo(version: "1.0.0", url: releaseURL)
        )))
        await checker.check()

        let missingSource = UpdateChecker(
            fetcher: UnexpectedReleaseFetcher(),
            repositoryURL: nil,
            defaults: defaults,
            currentVersion: "0.9.0",
            now: { self.checkedAt }
        )
        let changedSource = UpdateChecker(
            fetcher: UnexpectedReleaseFetcher(),
            repositoryURL: URL(string: "https://example.com/repos/other/releases/latest")!,
            defaults: defaults,
            currentVersion: "0.9.0",
            now: { self.checkedAt }
        )

        XCTAssertEqual(missingSource.status, .neverChecked)
        XCTAssertEqual(changedSource.status, .neverChecked)
        XCTAssertNil(missingSource.state.availableVersion)
        XCTAssertNil(changedSource.state.availableVersion)
    }

    func testPersistedUpdateIsHiddenWhenCurrentVersionCaughtUp() async {
        let checker = makeChecker(fetcher: StubReleaseFetcher(result: .success(
            ReleaseInfo(version: "1.0.0", url: releaseURL)
        )))
        await checker.check()

        let equalVersion = makeChecker(
            fetcher: UnexpectedReleaseFetcher(),
            currentVersion: "1.0.0"
        )
        let newerCurrentVersion = makeChecker(
            fetcher: UnexpectedReleaseFetcher(),
            currentVersion: "1.1.0"
        )

        XCTAssertEqual(equalVersion.status, .neverChecked)
        XCTAssertEqual(newerCurrentVersion.status, .neverChecked)
        XCTAssertNil(equalVersion.state.availableVersion)
        XCTAssertNil(newerCurrentVersion.state.availableVersion)
    }

    func testLegacyUnboundPersistedUpdateFailsClosed() {
        defaults.set(checkedAt, forKey: "stasi.update.lastChecked")
        defaults.set("1.0.0", forKey: "stasi.update.available")
        defaults.set(releaseURL.absoluteString, forKey: "stasi.update.releaseURL")

        let checker = makeChecker(fetcher: UnexpectedReleaseFetcher())

        XCTAssertEqual(checker.status, .neverChecked)
        XCTAssertNil(checker.state.availableVersion)
        XCTAssertNil(checker.state.releaseURL)
    }

    func testPersistedMalformedVersionOrUnsafeURLFailsClosed() {
        defaults.set(checkedAt, forKey: "stasi.update.lastChecked")
        defaults.set("release-1", forKey: "stasi.update.available")
        defaults.set("http://example.com/releases/v1.0.0", forKey: "stasi.update.releaseURL")
        defaults.set(repositoryURL.absoluteString, forKey: "stasi.update.source")

        let checker = makeChecker(fetcher: UnexpectedReleaseFetcher())

        XCTAssertEqual(checker.status, .neverChecked)
        XCTAssertNil(checker.state.availableVersion)
        XCTAssertNil(checker.state.releaseURL)
    }

    func testFailurePreservesPriorReleaseInfoButKeepsVisibleStatusFailed() async {
        let firstCheck = Date(timeIntervalSince1970: 1_700_000_000)
        var clock = SequenceClock(values: [firstCheck, checkedAt])
        let checker = UpdateChecker(
            fetcher: StubReleaseFetcher(result: .success(
                ReleaseInfo(version: "v1.0.0", url: releaseURL)
            )),
            repositoryURL: repositoryURL,
            defaults: defaults,
            currentVersion: "0.9.0",
            now: { clock.next() }
        )
        await checker.check()

        checker.replaceFetcher(HTTPFailingReleaseFetcher())
        await checker.check()

        XCTAssertEqual(checker.status, .failed(message: "Ungültige Antwort vom Update-Server."))
        XCTAssertEqual(checker.state.lastChecked, firstCheck)
        XCTAssertEqual(checker.state.availableVersion, "1.0.0")
        XCTAssertEqual(checker.state.releaseURL, releaseURL)
    }

    func testStatusIsCheckingWhileFetchIsInFlight() async {
        let fetcher = ControlledReleaseFetcher()
        let checker = makeChecker(fetcher: fetcher)

        let task = Task { await checker.check() }
        await fetcher.waitUntilStarted()
        XCTAssertEqual(checker.status, .checking)

        await fetcher.succeed(with: ReleaseInfo(version: "0.9.0", url: releaseURL))
        await task.value
        XCTAssertEqual(checker.status, .upToDate(checkedAt))
    }

    func testOfflineAndRateLimitFailuresHaveDistinctMessages() async {
        let offline = makeChecker(fetcher: OfflineReleaseFetcher())
        await offline.check()
        XCTAssertEqual(
            offline.status,
            .failed(message: "Keine Internetverbindung. Update-Prüfung nicht möglich.")
        )

        let rateLimited = makeChecker(fetcher: RateLimitedReleaseFetcher())
        await rateLimited.check()
        XCTAssertEqual(
            rateLimited.status,
            .failed(message: "GitHub-Limit erreicht. Bitte später erneut prüfen.")
        )
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
        currentVersion: String? = "0.9.0"
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

private struct OfflineReleaseFetcher: ReleaseFetching {
    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo {
        throw URLError(.notConnectedToInternet)
    }
}

private struct RateLimitedReleaseFetcher: ReleaseFetching {
    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo {
        throw GitHubReleaseFetcher.FetchError.rateLimited
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
