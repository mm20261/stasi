import XCTest
@testable import Stasi

final class TranscriptPolisherTests: XCTestCase {
    private let dictionary = [
        DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code"),
    ]

    func testOffIsBitIdenticalToPreviousCorrectionPath() {
        let raw = "  ich nutze cloud code  "
        let legacy = CorrectionEngine.correct(
            raw.trimmingCharacters(in: .whitespacesAndNewlines),
            entries: dictionary
        )
        let outcome = TranscriptPolisher.polishSync(
            raw, locale: Locale(identifier: "de_DE"), entries: dictionary, level: .off
        )

        XCTAssertEqual(outcome.text,
                       legacy.text.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(outcome.corrections.count, legacy.applied.count)
        XCTAssertEqual(outcome.corrections.first?.entryID, legacy.applied.first?.entryID)
        XCTAssertEqual(outcome.corrections.first?.pattern, legacy.applied.first?.pattern)
        XCTAssertEqual(outcome.corrections.first?.target, legacy.applied.first?.target)
        XCTAssertEqual(outcome.corrections.first?.matched, legacy.applied.first?.matched)
        XCTAssertFalse(outcome.summary.changedAnything)
    }

    func testStandardRunsPassesInSpecifiedOrder() {
        let raw = "ähm wir wir treffen uns am Montag nein am Dienstag, quasi, bei cloud code"
        let outcome = TranscriptPolisher.polishSync(
            raw, locale: Locale(identifier: "de_DE"), entries: dictionary, level: .standard
        )

        XCTAssertEqual(outcome.text, "Wir treffen uns am Dienstag bei Claude Code")
        XCTAssertEqual(outcome.summary.hesitationWordsRemoved, 1)
        XCTAssertEqual(outcome.summary.stutterWordsRemoved, 1)
        XCTAssertEqual(outcome.summary.selfCorrectionsResolved, 1)
        XCTAssertEqual(outcome.summary.discourseFillerWordsRemoved, 1)
        XCTAssertEqual(outcome.summary.fillerWordsRemoved, 2)
        XCTAssertEqual(outcome.corrections.count, 1)
    }

    func testSelfCorrectionRunsBeforeTidy() {
        let outcome = TranscriptPolisher.polishSync(
            "on Friday, no, on Thursday",
            locale: Locale(identifier: "en_US"), entries: [], level: .standard
        )
        XCTAssertEqual(outcome.text, "On Thursday")
        XCTAssertEqual(outcome.summary.selfCorrectionsResolved, 1)
    }

    func testNoPeriodIsAppended() {
        let outcome = TranscriptPolisher.polishSync(
            "ähm hallo welt", locale: Locale(identifier: "de_DE"), entries: [], level: .standard
        )
        XCTAssertEqual(outcome.text, "Hallo welt")
    }

    func testOtherLocaleOnlyTidiesAndCorrects() {
        let outcome = TranscriptPolisher.polishSync(
            "  um cloud code  ", locale: Locale(identifier: "fr_FR"),
            entries: dictionary, level: .standard
        )
        XCTAssertEqual(outcome.text, "Um Claude Code")
        XCTAssertEqual(outcome.summary.fillerWordsRemoved, 0)
    }

    func testUnchangedStandardSummaryIsNotChanged() {
        let outcome = TranscriptPolisher.polishSync(
            "Bereits sauber", locale: Locale(identifier: "de_DE"), entries: [], level: .standard
        )
        XCTAssertFalse(outcome.summary.changedAnything)
        XCTAssertTrue(outcome.summary.changes.isEmpty)
    }

    func testSummaryChangesFollowPassOrder() {
        let outcome = TranscriptPolisher.polishSync(
            "ähm wir wir gehen", locale: Locale(identifier: "de_DE"), entries: [], level: .standard
        )
        XCTAssertEqual(outcome.summary.changes.map(\.kind), [
            .hesitation, .stutter, .textTidy,
        ])
    }

    func testSummaryRoundTripsThroughJSON() throws {
        let outcome = TranscriptPolisher.polishSync(
            "ähm hallo", locale: Locale(identifier: "de_DE"), entries: [], level: .standard
        )
        let data = try JSONEncoder().encode(outcome.summary)
        XCTAssertEqual(try JSONDecoder().decode(PolishSummary.self, from: data), outcome.summary)
    }

    func testEnvironmentCanForceOff() {
        XCTAssertEqual(TranscriptPolisher.effectiveLevel(
            configured: .standard, environment: ["STASI_POLISH": "off"]
        ), .off)
        XCTAssertEqual(TranscriptPolisher.effectiveLevel(
            configured: .standard, environment: [:]
        ), .standard)
    }
}
