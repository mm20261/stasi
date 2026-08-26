import XCTest
@testable import Stasi

final class SelfCorrectionResolverTests: XCTestCase {
    private func resolve(_ text: String, _ locale: PolishLocale = .de) -> String {
        SelfCorrectionResolver.resolve(text, locale: locale).text
    }

    func testGermanWeekdayFrame() {
        XCTAssertEqual(resolve("am Montag nein am Dienstag"), "am Dienstag")
    }

    func testGermanTimeFrameKeepsFollowingUnit() {
        XCTAssertEqual(resolve("um neun nein um zehn Uhr"), "um zehn Uhr")
    }

    func testGermanAmountFrame() {
        XCTAssertEqual(resolve("zehn Euro nein zwölf Euro"), "zwölf Euro")
    }

    func testGermanModifierBeforeStrongMarkerBelongsToSpan() {
        XCTAssertEqual(resolve("an Peter äh nein an Paul"), "an Paul")
    }

    func testEnglishModifierAfterStrongMarkerBelongsToSpan() {
        XCTAssertEqual(resolve("Friday no wait Thursday", .en), "Thursday")
    }

    func testEnglishFrameIgnoresCommasAroundMarker() {
        XCTAssertEqual(resolve("on Friday, no, on Thursday", .en), "on Thursday")
    }

    func testGermanWeakMarkerUsesMatchingFrame() {
        XCTAssertEqual(resolve("Termin am Montag ich meine Termin am Dienstag"),
                       "Termin am Dienstag")
    }

    func testEnglishWeakMarkerUsesMatchingFrame() {
        XCTAssertEqual(resolve("meeting on Friday i mean meeting on Thursday", .en),
                       "meeting on Thursday")
    }

    func testCorrectionMarkerUsesMatchingFrame() {
        XCTAssertEqual(resolve("das kostet zehn Euro korrektur das kostet zwölf Euro"),
                       "das kostet zwölf Euro")
    }

    func testStrongNumberFallback() {
        XCTAssertEqual(resolve("zehn nein zwölf"), "zwölf")
    }

    func testStrongWeekdayFallback() {
        XCTAssertEqual(resolve("Montag nee Dienstag"), "Dienstag")
    }

    func testStrongMonthFallbackEnglish() {
        XCTAssertEqual(resolve("January nope February", .en), "February")
    }

    func testScratchThatIsStrongEnglishMarker() {
        XCTAssertEqual(resolve("ten scratch that twelve", .en), "twelve")
    }

    func testCorrectionChainTerminatesAtLastValue() {
        let result = SelfCorrectionResolver.resolve("Montag nein Dienstag nein Mittwoch", locale: .de)
        XCTAssertEqual(result.text, "Mittwoch")
        XCTAssertEqual(result.resolvedCount, 2)
    }

    func testMarkerAtSentenceStartDoesNotFire() {
        XCTAssertEqual(resolve("Nein, das passt nicht."), "Nein, das passt nicht.")
    }

    func testGermanReportedNoRemains() {
        XCTAssertEqual(resolve("Ich habe nein gesagt"), "Ich habe nein gesagt")
    }

    func testEnglishNoInPhraseRemains() {
        XCTAssertEqual(resolve("I have no idea", .en), "I have no idea")
    }

    func testEnglishNoAtSentenceEndRemains() {
        XCTAssertEqual(resolve("The answer is no", .en), "The answer is no")
    }

    func testGermanOpenAlternativeIsNotMarker() {
        XCTAssertEqual(resolve("Montag oder eher Dienstag?"), "Montag oder eher Dienstag?")
    }

    func testGermanNumericOpenAlternativeIsNotMarker() {
        XCTAssertEqual(resolve("zehn oder eher zwölf Euro?"), "zehn oder eher zwölf Euro?")
    }

    func testEnglishOpenAlternativeIsNotMarker() {
        XCTAssertEqual(resolve("Monday or rather Tuesday?", .en), "Monday or rather Tuesday?")
    }

    func testGermanOderBesserIsNotMarker() {
        XCTAssertEqual(resolve("Montag oder besser Dienstag"), "Montag oder besser Dienstag")
    }

    func testActuallyIsNotSelfCorrectionMarker() {
        XCTAssertEqual(resolve("ten actually twelve", .en), "ten actually twelve")
    }

    func testCompleteFollowingGermanSentenceSignalBlocksResolution() {
        XCTAssertEqual(resolve("weniger Bürokratie, nein, wir brauchen mehr Bürokratie"),
                       "weniger Bürokratie, nein, wir brauchen mehr Bürokratie")
    }

    func testDifferentEnglishFramesDoNotResolve() {
        XCTAssertEqual(resolve("It was Alice, no, Bob was responsible", .en),
                       "It was Alice, no, Bob was responsible")
    }

    func testNegationStatementDoesNotResolve() {
        XCTAssertEqual(resolve("Ich werde nicht kommen, nein wirklich"),
                       "Ich werde nicht kommen, nein wirklich")
    }

    func testCapitalizedNamesHaveNoFallbackClass() {
        XCTAssertEqual(resolve("Alice nein Bob"), "Alice nein Bob")
    }

    func testCapitalizedNamesHaveNoEnglishFallbackClass() {
        XCTAssertEqual(resolve("Alice no Bob", .en), "Alice no Bob")
    }

    func testCompleteFollowingEnglishSentenceSignalBlocksResolution() {
        XCTAssertEqual(resolve("less process, no, we need more process", .en),
                       "less process, no, we need more process")
    }

    func testWeakMarkerHasNoSingleTokenFallback() {
        XCTAssertEqual(resolve("Montag ich meine Dienstag"), "Montag ich meine Dienstag")
    }

    func testQuestionSentenceNeverResolves() {
        XCTAssertEqual(resolve("Montag nein Dienstag?"), "Montag nein Dienstag?")
    }

    func testMarkerWithoutReplacementDoesNotFire() {
        XCTAssertEqual(resolve("Montag nein"), "Montag nein")
    }

    func testReplacementThatIsAnotherMarkerDoesNotFire() {
        XCTAssertEqual(resolve("Montag nein nein Dienstag"), "Montag nein nein Dienstag")
    }

    func testSentenceBoundaryBlocksResolution() {
        XCTAssertEqual(resolve("Montag nein. Dienstag"), "Montag nein. Dienstag")
    }

    func testProtectedNegationDifferenceBlocksFrame() {
        XCTAssertEqual(resolve("wir werden nicht kommen nein wir werden doch kommen"),
                       "wir werden nicht kommen nein wir werden doch kommen")
    }

    func testProtectedQuantifierDifferenceBlocksFrame() {
        XCTAssertEqual(resolve("wir nehmen alle Akten nein wir nehmen nur Akten"),
                       "wir nehmen alle Akten nein wir nehmen nur Akten")
    }

    func testUnrelatedStrongMarkerTextRemains() {
        XCTAssertEqual(resolve("Das ist Quatsch und bleibt so"),
                       "Das ist Quatsch und bleibt so")
    }
}
