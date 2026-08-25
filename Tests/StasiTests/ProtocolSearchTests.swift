import XCTest
@testable import Stasi

// MARK: - ProtocolSearch (v4: Suche über alle Protokolle, ⌘F)
// Reine Filterlogik laut Handoff Abschnitt 3: Volltext über alle Protokolle,
// Trefferzähler, Filter Alle / 7 Tage / 30 Tage. Plus Tagesgruppierung,
// Aktenzeichen und Sammelexport.

final class ProtocolSearchTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func record(_ text: String, raw: String? = nil, app: String = "",
                        daysAgo: Double = 0) -> TranscriptionRecord {
        TranscriptionRecord(
            date: Date().addingTimeInterval(-daysAgo * 86_400),
            localeID: "de_DE",
            rawText: raw ?? text,
            correctedText: text,
            corrections: [],
            durationSecs: 10,
            targetApp: app
        )
    }

    // MARK: Query-Matching

    func testEmptyQueryMatchesEverything() {
        let records = [record("Hallo Welt"), record("Zweiter Eintrag")]
        XCTAssertEqual(ProtocolSearch.filter(records, query: "   ",
                                             filter: .all, calendar: calendar).count, 2)
    }

    func testQueryMatchesCorrectedTextCaseInsensitive() {
        let records = [record("Das Diktat läuft"), record("Kaffee kochen")]
        let hits = ProtocolSearch.filter(records, query: "diktat", filter: .all,
                                         calendar: calendar)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.correctedText, "Das Diktat läuft")
    }

    func testQueryMatchesRawTextToo() {
        let records = [record("Anthropic", raw: "anthropische KI"),
                       record("Unrelated")]
        XCTAssertTrue(ProtocolSearch.matches(records[0], query: "anthropische"))
        XCTAssertFalse(ProtocolSearch.matches(records[1], query: "anthropische"))
    }

    func testQueryMatchesTargetApp() {
        let r = record("Notiz", app: "Mail")
        XCTAssertTrue(ProtocolSearch.matches(r, query: "mail"))
        XCTAssertFalse(ProtocolSearch.matches(r, query: "slack"))
    }

    // MARK: Datumsfilter

    func testFilterLast7DaysExcludesOlder() {
        let recent = record("neu", daysAgo: 2)
        let borderline = record("grenze", daysAgo: 6.9)
        let old = record("alt", daysAgo: 9)
        let hits = ProtocolSearch.filter([recent, borderline, old], query: "",
                                         filter: .last7Days, calendar: calendar)
        XCTAssertEqual(Set(hits.map(\.correctedText)), ["neu", "grenze"])
    }

    func testFilterLast30DaysIncludesWeekOldButNotMonthOld() {
        let week = record("woche", daysAgo: 7)
        let ancient = record("uralt", daysAgo: 40)
        let hits = ProtocolSearch.filter([week, ancient], query: "",
                                         filter: .last30Days, calendar: calendar)
        XCTAssertEqual(hits.map(\.correctedText), ["woche"])
    }

    func testFilterAllKeepsEverything() {
        let hits = ProtocolSearch.filter([record("a", daysAgo: 100)], query: "",
                                         filter: .all, calendar: calendar)
        XCTAssertEqual(hits.count, 1)
    }

    func testQueryAndFilterIntersect() {
        let matchingRecent = record("Meeting Notiz", daysAgo: 1)
        let matchingOld = record("Meeting Protokoll", daysAgo: 20)
        let otherRecent = record("Einkauf", daysAgo: 1)
        let hits = ProtocolSearch.filter([matchingRecent, matchingOld, otherRecent],
                                         query: "meeting", filter: .last7Days,
                                         calendar: calendar)
        XCTAssertEqual(hits.map(\.correctedText), ["Meeting Notiz"])
    }

    // MARK: Trefferzähler

    func testHitCountEqualsFilteredCount() {
        let records = [record("eins zwei"), record("zwei drei"), record("vier")]
        let hits = ProtocolSearch.filter(records, query: "zwei", filter: .all,
                                         calendar: calendar)
        XCTAssertEqual(ProtocolSearch.hitCount(in: hits), 2)
    }

    // MARK: Tagesgruppierung

    func testGroupByDaySortsDescendingAndGroups() {
        var cal = calendar
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let morningToday = record("früh")
        let lateToday = record("spät")
        let oldOne = record("gestern")

        // Daten gezielt setzen
        let r1 = TranscriptionRecord(date: cal.date(bySettingHour: 9, minute: 0, second: 0,
                                                    of: today)!,
                                     localeID: "de", rawText: "", correctedText: "früh",
                                     corrections: [])
        let r2 = TranscriptionRecord(date: cal.date(bySettingHour: 18, minute: 0, second: 0,
                                                    of: today)!,
                                     localeID: "de", rawText: "", correctedText: "spät",
                                     corrections: [])
        let r3 = TranscriptionRecord(date: cal.date(bySettingHour: 12, minute: 0, second: 0,
                                                    of: yesterday)!,
                                     localeID: "de", rawText: "", correctedText: "gestern",
                                     corrections: [])

        _ = morningToday; _ = lateToday; _ = oldOne

        let groups = ProtocolSearch.groupByDay([r2, r3, r1], calendar: cal)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].day, today)
        // Innerhalb des Tages chronologisch (älteste zuerst)
        XCTAssertEqual(groups[0].records.map(\.correctedText), ["früh", "spät"])
        XCTAssertEqual(groups[1].day, yesterday)
    }

    // MARK: Aktenzeichen

    func testFileNumberDeterministicAndFormatted() {
        let id = UUID(uuidString: "A3F21B2C-0000-0000-0000-000000000000")!
        let az = FileNumber.forRecord(id: id)
        XCTAssertEqual(az, FileNumber.forRecord(id: id))
        XCTAssertTrue(az.hasPrefix("AZ "))
        XCTAssertEqual(az.count, 7) // „AZ " + 4 Zeichen
        XCTAssertEqual(az, "AZ A3F2")
    }

    // MARK: Sammelexport

    func testMarkdownAllContainsHeaderAndEntries() {
        var cal = calendar
        let today = cal.startOfDay(for: Date())
        let r1 = TranscriptionRecord(date: cal.date(bySettingHour: 14, minute: 32, second: 0,
                                                    of: today)!,
                                     localeID: "de", rawText: "", correctedText: "Erster Satz",
                                     corrections: [], targetApp: "Mail")
        let r2 = TranscriptionRecord(date: cal.date(bySettingHour: 9, minute: 5, second: 0,
                                                    of: today)!,
                                     localeID: "de", rawText: "", correctedText: "Früher Satz",
                                     corrections: [])
        _ = cal

        let md = ProtocolExporter.markdownAll([r1, r2])
        XCTAssertTrue(md.contains("# Protokolle"))
        XCTAssertTrue(md.contains("Erster Satz"))
        XCTAssertTrue(md.contains("Früher Satz"))
        XCTAssertTrue(md.contains("→ Mail"))
        // Sortierung innerhalb des Tages: älteste zuerst
        let earlierIndex = try! XCTUnwrap(md.range(of: "Früher Satz")).lowerBound
        let laterIndex = try! XCTUnwrap(md.range(of: "Erster Satz")).lowerBound
        XCTAssertLessThan(earlierIndex, laterIndex)
    }
}
