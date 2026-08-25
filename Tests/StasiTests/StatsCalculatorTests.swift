import XCTest
@testable import Stasi

// MARK: - StatsCalculator (Insights + Rail-Statistiken)

/// Feste Referenzwoche: Montag, 24. August 2026 (wie im v2-Handoff).
/// Alle Tests rechnen in einer UTC-Gregorianik-Kalender-Umgebung.
@MainActor
final class StatsCalculatorTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        calendar = c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func record(_ date: Date, words: Int, duration: TimeInterval = 0,
                        app: String = "Notizen") -> TranscriptionRecord {
        TranscriptionRecord(date: date, localeID: "de_DE",
                            rawText: String(repeating: "wort ", count: max(words, 1)),
                            correctedText: String(repeating: "wort ",
                                                  count: max(words, 1)).trimmingCharacters(in: .whitespaces),
                            corrections: [], durationSecs: duration, targetApp: app)
    }

    // MARK: Wörter gesamt & WPM

    func testTotalWordsSums() {
        let recs = [record(date(2026, 8, 24), words: 61),
                    record(date(2026, 8, 23), words: 34),
                    record(date(2026, 8, 22), words: 26)]
        XCTAssertEqual(StatsCalculator.totalWords(recs), 121)
    }

    func testWPMComputesFromDurations() {
        // 120 Wörter in 60 s + 60 Wörter in 30 s = 180 Wörter / 1,5 min = 120 WPM
        let recs = [record(date(2026, 8, 24), words: 120, duration: 60),
                    record(date(2026, 8, 23), words: 60, duration: 30)]
        XCTAssertEqual(StatsCalculator.wordsPerMinute(recs)!, 120, accuracy: 0.01)
    }

    func testWPMSkipsZeroDurationsAndReturnsNilIfNoneLeft() {
        XCTAssertNil(StatsCalculator.wordsPerMinute([record(date(2026, 8, 24), words: 50)]))
        let recs = [record(date(2026, 8, 24), words: 120, duration: 60),
                    record(date(2026, 8, 24), words: 10)]
        XCTAssertEqual(StatsCalculator.wordsPerMinute(recs)!, 120, accuracy: 0.01)
    }

    // MARK: Serien (Streaks)

    func testCurrentStreakCountsBackFromToday() {
        let recs = [record(date(2026, 8, 24), words: 10),
                    record(date(2026, 8, 23), words: 10),
                    record(date(2026, 8, 22), words: 10)]
        XCTAssertEqual(StatsCalculator.currentStreak(recs, calendar: calendar,
                                                     today: date(2026, 8, 24)), 3)
    }

    func testCurrentStreakSurvivesQuietToday() {
        // Heute noch nichts diktiert – Serie über yesterday laufen lassen.
        let recs = [record(date(2026, 8, 23), words: 10),
                    record(date(2026, 8, 22), words: 10)]
        XCTAssertEqual(StatsCalculator.currentStreak(recs, calendar: calendar,
                                                     today: date(2026, 8, 24)), 2)
    }

    func testCurrentStreakBreaksAtGap() {
        let recs = [record(date(2026, 8, 24), words: 10),
                    record(date(2026, 8, 21), words: 10),
                    record(date(2026, 8, 20), words: 10)]
        XCTAssertEqual(StatsCalculator.currentStreak(recs, calendar: calendar,
                                                     today: date(2026, 8, 24)), 1)
    }

    func testLongestStreakKeepsHistoricalRecord() {
        // 3er-Serie letzte Woche, heute nur 1 Tag → Rekord bleibt 3.
        let recs = [record(date(2026, 8, 24), words: 10),
                    record(date(2026, 8, 18), words: 10),
                    record(date(2026, 8, 17), words: 10),
                    record(date(2026, 8, 16), words: 10)]
        XCTAssertEqual(StatsCalculator.longestStreak(recs, calendar: calendar), 3)
    }

    // MARK: Wohin diktiert wird

    func testAppUsageGroupsSortsAndBucketsRest() {
        let recs = [
            record(date(2026, 8, 24), words: 46, app: "Notizen"),
            record(date(2026, 8, 24), words: 27, app: "Mail"),
            record(date(2026, 8, 24), words: 18, app: "Slack"),
            record(date(2026, 8, 24), words: 5, app: "Xcode"),
            record(date(2026, 8, 24), words: 4, app: "Terminal"),
            record(date(2026, 8, 24), words: 10, app: ""), // ohne Ziel-App ignorieren
        ]
        let usage = StatsCalculator.appUsage(recs, topN: 3)
        XCTAssertEqual(usage.count, 4) // Top 3 + „Andere“
        XCTAssertEqual(usage[0].app, "Notizen")
        XCTAssertEqual(usage[0].percent, 46.0, accuracy: 0.01)
        XCTAssertEqual(usage[3].app, "Andere")
        XCTAssertEqual(usage[3].words, 9)
        XCTAssertEqual(usage[3].percent, 9.0, accuracy: 0.01)
    }

    // MARK: Zeit gespart

    func testTimeSavedAssumesFortyWPMTyping() {
        // 80 Wörter getippt hätten 120 s gedauert; Aufnahme 0 s → 120 s gespart.
        // 40 Wörter in exakt 60 s → 0 s gespart.
        let recs = [record(date(2026, 8, 24), words: 80, duration: 0),
                    record(date(2026, 8, 24), words: 40, duration: 60)]
        XCTAssertEqual(StatsCalculator.timeSaved(recs), 120, accuracy: 0.5)
    }

    func testTimeSavedClampsNegativeToZero() {
        // Langsame Aufnahme (weniger als 40 WPM) spart nichts.
        let recs = [record(date(2026, 8, 24), words: 20, duration: 120)]
        XCTAssertEqual(StatsCalculator.timeSaved(recs), 0, accuracy: 0.5)
    }

    // MARK: Wochenvergleich

    func testWeekComparisonComputesDelta() {
        // KW 35: Mo 24.8. | Vorwoche KW 34: Mo 17.8.
        let recs = [record(date(2026, 8, 24), words: 118),
                    record(date(2026, 8, 25), words: 82),
                    record(date(2026, 8, 18), words: 100)]
        let cmp = StatsCalculator.weekComparison(recs, calendar: calendar, today: date(2026, 8, 25))
        XCTAssertEqual(cmp.thisWeek, 200)
        XCTAssertEqual(cmp.lastWeek, 100)
        XCTAssertEqual(cmp.deltaPercent!, 100, accuracy: 0.01)
    }

    func testWeekComparisonNilDeltaWhenLastWeekEmpty() {
        let recs = [record(date(2026, 8, 25), words: 50)]
        let cmp = StatsCalculator.weekComparison(recs, calendar: calendar, today: date(2026, 8, 25))
        XCTAssertEqual(cmp.thisWeek, 50)
        XCTAssertNil(cmp.deltaPercent)
    }

    // MARK: Heatmap

    func testHeatmapHasSevenRowsAndSixteenColumns() {
        let heat = StatsCalculator.heatmapWords([], calendar: calendar, today: date(2026, 8, 24))
        XCTAssertEqual(heat.count, 7)
        XCTAssertTrue(heat.allSatisfy { $0.count == 16 })
    }

    func testHeatmapPlacesTodayInLastColumnCorrectRow() {
        // Montag, 24.8. → Zeile 0 (Montag), Spalte 15 (aktuelle Woche).
        let heat = StatsCalculator.heatmapWords([record(date(2026, 8, 24), words: 61)],
                                                calendar: calendar, today: date(2026, 8, 24))
        XCTAssertEqual(heat[0][15], 61)
        // Alles andere leer
        var others = heat.flatMap { $0 }
        others[15] = 0
        XCTAssertTrue(others.allSatisfy { $0 == 0 })
    }

    func testHeatmapFirstColumnIsFifteenWeeksBefore() {
        // Erste Spalte = Woche vom 11.–17. Mai 2026 (15 Wochen vor KW 35).
        let recs = [record(date(2026, 5, 13), words: 12)] // Mittwoch
        let heat = StatsCalculator.heatmapWords(recs, calendar: calendar, today: date(2026, 8, 24))
        XCTAssertEqual(heat[2][0], 12) // Zeile 2 = Mittwoch
    }

    // MARK: Formatierung

    func testCompactCountFormatsGermanStyle() {
        XCTAssertEqual(StatsCalculator.compactCount(980), "980")
        XCTAssertEqual(StatsCalculator.compactCount(328_500), "328,5K")
        XCTAssertEqual(StatsCalculator.compactCount(1_000), "1K")
        XCTAssertEqual(StatsCalculator.compactCount(1_240_000), "1,2M")
    }

    func testTimeSavedTextFormatsHoursAndMinutes() {
        XCTAssertEqual(StatsCalculator.timeSavedText(2 * 3600 + 14 * 60), "2:14 Std")
        XCTAssertEqual(StatsCalculator.timeSavedText(42 * 60), "42 Min")
        XCTAssertEqual(StatsCalculator.timeSavedText(0), "0 Min")
    }
}
