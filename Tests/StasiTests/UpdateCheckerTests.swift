import XCTest
@testable import Stasi

// MARK: - UpdateChecker (v4)
// „Aktuelle Version prüfen": fragt die Release-Quelle ab, schreibt Zeitstempel
// und Ergebnis in die Statuszeile; neuere Version → Update-Button.

@MainActor
final class UpdateCheckerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "update-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: Versionsvergleich

    func testNormalizeStripsPrefixAndSplits() {
        XCTAssertEqual(VersionComparator.components("v0.10"), [0, 10])
        XCTAssertEqual(VersionComparator.components("0.9"), [0, 9])
        XCTAssertEqual(VersionComparator.components("V1.2.3"), [1, 2, 3])
    }

    func testNumericComparisonNotLexicographic() {
        XCTAssertTrue(VersionComparator.isNewer("v0.10", than: "0.9")) // 10 > 9 numerisch!
        XCTAssertFalse(VersionComparator.isNewer("0.9", than: "0.10"))
    }

    func testIsNewerVariants() {
        XCTAssertTrue(VersionComparator.isNewer("0.9.1", than: "0.9"))
        XCTAssertFalse(VersionComparator.isNewer("0.8", than: "0.9"))
        XCTAssertFalse(VersionComparator.isNewer("0.9", than: "0.9"))
        XCTAssertTrue(VersionComparator.isNewer("1.0", than: "0.9"))
    }

    func testCheckerDefaultsToDisplayedBundleVersion() {
        let fetcher = MockReleaseFetcher(result: .success(
            ReleaseInfo(version: "v1.0", url: URL(string: "https://example.com/releases/v1.0")!)
        ))
        let checker = UpdateChecker(fetcher: fetcher, defaults: defaults)
        XCTAssertEqual(checker.currentVersion, AppVersion.display)
    }

    func testGitHubPayloadDecodesHTMLURL() throws {
        let data = Data(#"{"tag_name":"v0.10","html_url":"https://example.com/releases/v0.10"}"#.utf8)
        let payload = try JSONDecoder().decode(GitHubReleaseFetcher.Payload.self, from: data)
        XCTAssertEqual(payload.tagName, "v0.10")
        XCTAssertEqual(payload.htmlURL.absoluteString, "https://example.com/releases/v0.10")
    }

    // MARK: Statuszeile

    func testStatusTextNeverChecked() {
        XCTAssertEqual(UpdateChecker.statusText(lastChecked: nil,
                                                available: nil, now: Date()),
                       "NOCH NIE GEPRÜFT")
    }

    func testStatusTextCheckedToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let nineTwelve = cal.date(bySettingHour: 9, minute: 12, second: 0, of: Date())!
        let text = UpdateChecker.statusText(lastChecked: nineTwelve,
                                            available: nil, now: Date())
        XCTAssertEqual(text, "ZULETZT GEPRÜFT: HEUTE, 09:12")
    }

    func testStatusTextWithAvailableUpdate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        let text = UpdateChecker.statusText(lastChecked: yesterday,
                                            available: "0.10",
                                            now: Date())
        XCTAssertEqual(text, "ZULETZT GEPRÜFT: GESTERN · V 0.10 LIEGT BEREIT")
    }

    // MARK: Check-Ablauf (Mock-Fetcher)

    func testCheckWithNewerVersionUpdatesStateAndPersists() async {
        let releaseURL = URL(string: "https://example.com/releases/v0.10")!
        let fetcher = MockReleaseFetcher(result: .success(
            ReleaseInfo(version: "v0.10", url: releaseURL)
        ))
        let checker = UpdateChecker(fetcher: fetcher, defaults: defaults,
                                    currentVersion: "0.9")
        await checker.check()

        XCTAssertEqual(checker.state.availableVersion, "0.10")
        XCTAssertEqual(checker.state.releaseURL, releaseURL)
        XCTAssertNotNil(checker.state.lastChecked)

        // Persistenz: Neue Instanz liest denselben Stand
        let reloaded = UpdateChecker(fetcher: fetcher, defaults: defaults,
                                     currentVersion: "0.9")
        XCTAssertEqual(reloaded.state.availableVersion, "0.10")
        XCTAssertEqual(reloaded.state.releaseURL, releaseURL)
        XCTAssertEqual(reloaded.state.lastChecked, checker.state.lastChecked)
    }

    func testCheckWithSameVersionLeavesNoUpdateAvailable() async {
        let fetcher = MockReleaseFetcher(result: .success(
            ReleaseInfo(version: "0.9", url: URL(string: "https://example.com/releases/v0.9")!)
        ))
        let checker = UpdateChecker(fetcher: fetcher, defaults: defaults,
                                    currentVersion: "0.9")
        await checker.check()
        XCTAssertNil(checker.state.availableVersion)
        XCTAssertNotNil(checker.state.lastChecked)
    }

    func testCheckFailureKeepsLastResultButStampsTime() async {
        let releaseURL = URL(string: "https://example.com/releases/v0.11")!
        let ok = MockReleaseFetcher(result: .success(
            ReleaseInfo(version: "v0.11", url: releaseURL)
        ))
        let checker = UpdateChecker(fetcher: ok, defaults: defaults,
                                    currentVersion: "0.9")
        await checker.check()
        XCTAssertEqual(checker.state.availableVersion, "0.11")
        XCTAssertEqual(checker.state.releaseURL, releaseURL)
        let stamp = checker.state.lastChecked

        let failing = FailingReleaseFetcher()
        checker.replaceFetcher(failing)
        await checker.check()
        XCTAssertNotNil(checker.state.lastChecked)
        XCTAssertGreaterThanOrEqual(checker.state.lastChecked!, stamp!)
        // Letztes bekanntes Ergebnis bleibt stehen
        XCTAssertEqual(checker.state.availableVersion, "0.11")
        XCTAssertEqual(checker.state.releaseURL, releaseURL)
    }
}

// MARK: - Mocks

struct MockReleaseFetcher: ReleaseFetching {
    let result: Result<ReleaseInfo, Error>
    func fetchLatestRelease() async throws -> ReleaseInfo {
        try result.get()
    }
}

struct FailingReleaseFetcher: ReleaseFetching {
    struct Boom: Error {}
    func fetchLatestRelease() async throws -> ReleaseInfo { throw Boom() }
}
