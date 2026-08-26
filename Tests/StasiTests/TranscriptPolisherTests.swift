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

    func testBadgePrefersRemovedFillerCount() {
        let summary = PolishSummary(level: .standard, changes: [
            PolishChange(kind: .hesitation, count: 1),
            PolishChange(kind: .discourseFiller, count: 1),
        ])

        XCTAssertEqual(summary.badgeText(correctionCount: 3),
                       "POLIERT · −2 FÜLLWÖRTER")
    }

    func testBadgeNamesStutterOrSelfCorrectionAsSlip() {
        let stutter = PolishSummary(level: .standard, changes: [
            PolishChange(kind: .stutter, count: 1),
        ])
        let selfCorrection = PolishSummary(level: .standard, changes: [
            PolishChange(kind: .selfCorrection, count: 1),
        ])

        XCTAssertEqual(stutter.badgeText(), "POLIERT · VERSPRECHER")
        XCTAssertEqual(selfCorrection.badgeText(), "POLIERT · VERSPRECHER")
    }

    func testBadgeNamesDictionaryCorrections() {
        let summary = PolishSummary(level: .standard, changes: [
            PolishChange(kind: .dictionary, count: 3,
                         removed: "cloud code", kept: "Claude Code"),
        ])

        XCTAssertEqual(summary.badgeText(),
                       "POLIERT · 3 KORREKTUREN")
    }

    func testEmptyChangeListNeverProducesBadge() {
        let summary = PolishSummary(level: .standard, changes: [])

        XCTAssertNil(summary.badgeText(correctionCount: 3))
    }

    func testTidyOnlyHasNoBadge() {
        let summary = PolishSummary(level: .standard, changes: [
            PolishChange(kind: .textTidy, count: 1),
        ])

        XCTAssertNil(summary.badgeText())
    }

    func testOffNeverHasPolishBadge() {
        let summary = PolishSummary(level: .off, changes: [])

        XCTAssertNil(summary.badgeText(correctionCount: 3))
    }

    func testRelevantPassesRecordBadgeWorthyChanges() {
        let outcome = TranscriptPolisher.polishSync(
            "ähm wir wir treffen uns Montag nein Dienstag",
            locale: Locale(identifier: "de_DE"), entries: [], level: .standard
        )

        XCTAssertGreaterThan(outcome.summary.hesitationWordsRemoved, 0)
        XCTAssertGreaterThan(outcome.summary.stutterWordsRemoved, 0)
        XCTAssertGreaterThan(outcome.summary.selfCorrectionsResolved, 0)
        XCTAssertNotNil(outcome.summary.badgeText())
    }

    func testDetailSectionsGroupRemovedWordsSlipsAndDictionary() {
        let outcome = TranscriptPolisher.polishSync(
            "ähm wir wir treffen uns am Montag nein am Dienstag, quasi, bei cloud code",
            locale: Locale(identifier: "de_DE"), entries: dictionary, level: .standard
        )

        XCTAssertEqual(outcome.summary.detailSections(corrections: outcome.corrections), [
            PolishDetailSection(title: "Füllwörter entfernt", items: ["ähm", "quasi"]),
            PolishDetailSection(title: "Versprecher", items: [
                "„wir wir“ → „wir“",
                "„am Montag“ → „am Dienstag“",
            ]),
            PolishDetailSection(title: "Wörterbuch", items: [
                "„cloud code“ → „Claude Code“",
            ]),
        ])
    }

    func testCompactBadgeIsAlwaysSingleShortWord() {
        let summary = PolishSummary(level: .standard, changes: [
            PolishChange(kind: .hesitation, count: 2, removed: "ähm"),
        ])

        XCTAssertEqual(summary.compactBadgeText, "POLIERT")
    }

    func testOldPolishChangeJSONWithoutDetailsStillDecodes() throws {
        let data = Data(#"{"level":"standard","changes":[{"kind":"hesitation","count":1}]}"#.utf8)

        let summary = try JSONDecoder().decode(PolishSummary.self, from: data)

        XCTAssertEqual(summary.hesitationWordsRemoved, 1)
        XCTAssertNil(summary.changes.first?.removed)
        XCTAssertNil(summary.changes.first?.kept)
    }

    func testTidyOnlyProducesNoDetails() {
        let outcome = TranscriptPolisher.polishSync(
            "  hallo welt  ", locale: Locale(identifier: "de_DE"),
            entries: [], level: .standard
        )

        XCTAssertTrue(outcome.summary.detailSections(corrections: []).isEmpty)
        XCTAssertNil(outcome.summary.badgeText())
    }
}
