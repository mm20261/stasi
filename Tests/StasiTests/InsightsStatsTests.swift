import XCTest
import SwiftUI
@testable import Stasi

// MARK: - StatsCalculator (Insights-Ergänzungen)
// Leitzahl-Karte (Insights): KW-Kicker + Tipzeit-Schätzung; Balken-Farbstufen.

final class InsightsStatsTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 2 // Montag
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: KW-Kicker

    func testWeekKickerLabel() {
        XCTAssertEqual(StatsCalculator.weekKickerLabel(for: date(2026, 8, 25),
                                                       calendar: calendar),
                       "KALENDERWOCHE 35 · 24.–30. AUGUST")
    }

    func testWeekKickerCrossesMonths() {
        let label = StatsCalculator.weekKickerLabel(for: date(2026, 9, 30),
                                                    calendar: calendar)
        XCTAssertTrue(label.contains("SEPTEMBER"))
        XCTAssertTrue(label.contains("OKTOBER"))
    }

    // MARK: Tipzeit-Estimate diese Woche

    func testTypingTimeThisWeekCountsOnlyThisWeeksWords() {
        let today = date(2026, 8, 25) // Dienstag KW 35
        let lastWeek = date(2026, 8, 19)
        func rec(_ d: Date, words: Int) -> TranscriptionRecord {
            TranscriptionRecord(date: d, localeID: "de", rawText: "",
                                correctedText: Array(repeating: "wort",
                                                     count: words).joined(separator: " "),
                                corrections: [])
        }
        let records = [rec(today, words: 80), rec(today, words: 40), rec(lastWeek, words: 1000)]
        // 120 Wörter @ 40 WPM = 3 Minuten
        let seconds = StatsCalculator.typingTimeThisWeek(records,
                                                         calendar: calendar,
                                                         today: today)
        XCTAssertEqual(seconds, 180, accuracy: 0.5)
    }

    func testTypingTimeTextFormat() {
        XCTAssertEqual(StatsCalculator.timeSavedText(180), "3 Min")
        XCTAssertEqual(StatsCalculator.timeSavedText(2 * 3600 + 14 * 60), "2:14 Std")
    }

    // MARK: Farbstufen (Akzent, abgestuft)

    func testAppBarOpacityByRank() {
        XCTAssertEqual(Theme.appBarOpacity(rank: 0), 1.0)
        XCTAssertEqual(Theme.appBarOpacity(rank: 1), 0.66, accuracy: 0.001)
        XCTAssertEqual(Theme.appBarOpacity(rank: 2), 0.42, accuracy: 0.001)
        XCTAssertEqual(Theme.appBarOpacity(rank: 3), 0.22, accuracy: 0.001)
        XCTAssertEqual(Theme.appBarOpacity(rank: 99), 0.22, accuracy: 0.001) // geklemmt
    }

    func testHeatmapOpacityLevels() {
        // Handoff: o ∈ {0,08 · 0,18 · 0,45 · 0,75 · 1}
        XCTAssertEqual(Theme.heatmapOpacity(words: 0, maxDay: 100), 0.08)
        XCTAssertEqual(Theme.heatmapOpacity(words: 100, maxDay: 100), 1.0)
        XCTAssertEqual(Theme.heatmapOpacity(words: 10, maxDay: 100), 0.18)
        XCTAssertEqual(Theme.heatmapOpacity(words: 50, maxDay: 100), 0.45)
        XCTAssertEqual(Theme.heatmapOpacity(words: 90, maxDay: 100), 0.75)
    }
}
