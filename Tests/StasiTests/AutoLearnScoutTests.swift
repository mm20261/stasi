import XCTest
@testable import Stasi

final class AutoLearnScoutTests: XCTestCase {
    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")

    private func record(_ text: String, locale: String = "de_DE") -> TranscriptionRecord {
        TranscriptionRecord(
            date: Date(),
            localeID: locale,
            rawText: text,
            correctedText: text,
            corrections: []
        )
    }

    private func candidates(
        _ text: String,
        history: [TranscriptionRecord] = [],
        dictionary: [DictionaryEntry] = [],
        ignored: [String] = [],
        locale: Locale? = nil,
        known: @escaping (String) -> Bool = { _ in false }
    ) -> [DictionaryEntry] {
        AutoLearnScout.candidates(
            newRecord: record(text, locale: (locale ?? german).identifier),
            historyExcludingNew: history,
            dictionary: dictionary,
            ignored: ignored,
            locale: locale ?? german,
            isKnownWord: known,
            options: .init()
        )
    }

    func testTermInTwoProtocolsBecomesCandidate() {
        let result = candidates(
            "Wir verwenden Frobulator heute",
            history: [record("Der Frobulator hilft täglich")]
        )

        XCTAssertEqual(result.map(\.value), ["Frobulator"])
        XCTAssertEqual(result.first?.type, .learned)
        XCTAssertEqual(result.first?.note, "2× diktiert")
    }

    func testTermInOneProtocolIsNotCandidate() {
        XCTAssertTrue(candidates("Wir verwenden Frobulator heute").isEmpty)
    }

    func testKnownWordIsExcluded() {
        let result = candidates(
            "Wir verwenden Frobulator heute",
            history: [record("Der Frobulator hilft")],
            known: { $0.caseInsensitiveCompare("Frobulator") == .orderedSame }
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testCommonWordsAreExcluded() {
        let result = candidates(
            "Wir öffnen Cloud heute",
            history: [record("Die Cloud bleibt erreichbar")]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testDictionarySourcesAndTargetsAreExcluded() {
        let dictionary = [
            DictionaryEntry(type: .correction, from: "frobulator", to: "Frobulator"),
        ]
        let result = candidates(
            "Wir verwenden Frobulator heute",
            history: [record("Der Frobulator hilft")],
            dictionary: dictionary
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testIgnoredWordIsExcludedCaseInsensitively() {
        let result = candidates(
            "Wir verwenden Frobulator heute",
            history: [record("Der Frobulator hilft")],
            ignored: ["fRoBuLaToR"]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testSentenceInitialCapitalizationAloneIsInsufficientInGerman() {
        let result = candidates(
            "Frobulator hilft täglich",
            history: [record("Frobulator hilft erneut")]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testEnglishUnknownLowercaseWordIsEligible() {
        let result = candidates(
            "we use frobulator daily",
            history: [record("the frobulator works", locale: "en_US")],
            locale: english
        )

        XCTAssertEqual(result.map(\.value), ["frobulator"])
        XCTAssertEqual(result.first?.note, "2× diktiert")
    }

    func testRepeatedOccurrencesInNewRecordCountAsOneProtocol() {
        let result = candidates("Wir nutzen Frobulator Frobulator Frobulator heute")

        XCTAssertTrue(result.isEmpty)
    }

    func testRepeatedOccurrencesInHistoryCountAsOneProtocol() {
        let result = candidates(
            "Wir nutzen Frobulator heute",
            history: [record("Frobulator Frobulator Frobulator bleibt")]
        )

        XCTAssertEqual(result.first?.note, "2× diktiert")
    }

    func testLocaleFillerCalendarAndNumberWordsAreExcluded() {
        let result = candidates(
            "Wir sagen Ähm Montag und Zwanzig",
            history: [record("Ähm Montag Zwanzig")]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testCandidateLimitAppliesBeforeHistoryCounting() {
        let result = AutoLearnScout.candidates(
            newRecord: record("Wir nennen Alphafoo Betabar Gammabaz heute"),
            historyExcludingNew: [record("Alphafoo Betabar Gammabaz")],
            dictionary: [],
            ignored: [],
            locale: german,
            isKnownWord: { _ in false },
            options: .init(maxCandidatesBeforeCounting: 2)
        )

        XCTAssertEqual(result.map(\.value), ["Alphafoo", "Betabar"])
    }

    func testMostFrequentSpellingWins() {
        let result = candidates(
            "Wir verwenden Frobulator heute",
            history: [
                record("Der FROBULATOR hilft"),
                record("Wir prüfen FROBULATOR erneut"),
            ]
        )

        XCTAssertEqual(result.first?.value, "FROBULATOR")
        XCTAssertEqual(result.first?.note, "3× diktiert")
    }
}
