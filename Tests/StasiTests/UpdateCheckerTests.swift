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
        let fetcher = MockReleaseFetcher(result: .success("v0.10"))
        let checker = UpdateChecker(fetcher: fetcher, defaults: defaults,
                                    currentVersion: "0.9")
        await checker.check()

        XCTAssertEqual(checker.state.availableVersion, "0.10")
        XCTAssertNotNil(checker.state.lastChecked)

        // Persistenz: Neue Instanz liest denselben Stand
        let reloaded = UpdateChecker(fetcher: fetcher, defaults: defaults,
                                     currentVersion: "0.9")
        XCTAssertEqual(reloaded.state.availableVersion, "0.10")
        XCTAssertEqual(reloaded.state.lastChecked, checker.state.lastChecked)
    }

    func testCheckWithSameVersionLeavesNoUpdateAvailable() async {
        let fetcher = MockReleaseFetcher(result: .success("0.9"))
        let checker = UpdateChecker(fetcher: fetcher, defaults: defaults,
                                    currentVersion: "0.9")
        await checker.check()
        XCTAssertNil(checker.state.availableVersion)
        XCTAssertNotNil(checker.state.lastChecked)
    }

    func testCheckFailureKeepsLastResultButStampsTime() async {
        let ok = MockReleaseFetcher(result: .success("v0.11"))
        let checker = UpdateChecker(fetcher: ok, defaults: defaults,
                                    currentVersion: "0.9")
        await checker.check()
        XCTAssertEqual(checker.state.availableVersion, "0.11")
        let stamp = checker.state.lastChecked

        let failing = FailingReleaseFetcher()
        checker.replaceFetcher(failing)
        await checker.check()
        XCTAssertNotNil(checker.state.lastChecked)
        XCTAssertGreaterThanOrEqual(checker.state.lastChecked!, stamp!)
        // Letztes bekanntes Ergebnis bleibt stehen
        XCTAssertEqual(checker.state.availableVersion, "0.11")
    }
}

// MARK: - Mocks

struct MockReleaseFetcher: ReleaseFetching {
    let result: Result<String, Error>
    func fetchLatestVersion() async throws -> String {
        try result.get()
    }
}

struct FailingReleaseFetcher: ReleaseFetching {
    struct Boom: Error {}
    func fetchLatestVersion() async throws -> String { throw Boom() }
}
