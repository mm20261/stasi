import XCTest
@testable import Stasi

final class FillerFilterTests: XCTestCase {
    func testRemovesGermanHesitation() {
        let result = FillerFilter.removeHesitations("ich ähm komme", locale: .de)
        XCTAssertEqual(result.text, "ich komme")
        XCTAssertEqual(result.removedWords, 1)
    }

    func testRemovesAllListedGermanHesitations() {
        let result = FillerFilter.removeHesitations("äh ähh eh öhm hm mhm fertig", locale: .de)
        XCTAssertEqual(result.text, "fertig")
        XCTAssertEqual(result.removedWords, 6)
    }

    func testRemovesAllListedEnglishHesitations() {
        let result = FillerFilter.removeHesitations("um uh erm hm ready", locale: .en)
        XCTAssertEqual(result.text, "ready")
        XCTAssertEqual(result.removedWords, 4)
    }

    func testGermanUmTimeRemains() {
        let result = FillerFilter.removeHesitations("um neun Uhr", locale: .de)
        XCTAssertEqual(result.text, "um neun Uhr")
        XCTAssertEqual(result.removedWords, 0)
    }

    func testAehmchenRemains() {
        XCTAssertEqual(FillerFilter.removeHesitations("Ähmchen", locale: .de).text, "Ähmchen")
    }

    func testHesitationsAreStrictlyLanguageSpecific() {
        XCTAssertEqual(FillerFilter.removeHesitations("ähm ready", locale: .en).text, "ähm ready")
        XCTAssertEqual(FillerFilter.removeHesitations("um fertig", locale: .de).text, "um fertig")
    }

    func testOtherLocaleRemovesNothing() {
        XCTAssertEqual(FillerFilter.removeHesitations("ähm um", locale: .other).text, "ähm um")
    }

    func testCollapsesGermanStutter() {
        let result = FillerFilter.collapseStutters("wir wir gehen", locale: .de)
        XCTAssertEqual(result.text, "wir gehen")
        XCTAssertEqual(result.removedWords, 1)
    }

    func testCollapsesUpToFourRepeatedWords() {
        let result = FillerFilter.collapseStutters("morgen morgen morgen morgen klappt es", locale: .de)
        XCTAssertEqual(result.text, "morgen klappt es")
        XCTAssertEqual(result.removedWords, 3)
    }

    func testStutterMatchIsCaseInsensitive() {
        XCTAssertEqual(FillerFilter.collapseStutters("Hallo hallo Welt", locale: .de).text,
                       "Hallo Welt")
    }

    func testHadHadRemainsInEnglish() {
        XCTAssertEqual(FillerFilter.collapseStutters("I had had enough", locale: .en).text,
                       "I had had enough")
    }

    func testThatThatRemainsInEnglish() {
        XCTAssertEqual(FillerFilter.collapseStutters("that that works", locale: .en).text,
                       "that that works")
    }

    func testVeryVeryRemainsInEnglish() {
        XCTAssertEqual(FillerFilter.collapseStutters("very very good", locale: .en).text,
                       "very very good")
    }

    func testSoSoRemainsInEnglish() {
        XCTAssertEqual(FillerFilter.collapseStutters("so so far", locale: .en).text,
                       "so so far")
    }

    func testHyphenatedWordsAreNotStutters() {
        XCTAssertEqual(FillerFilter.collapseStutters("test-test bleibt", locale: .de).text,
                       "test-test bleibt")
    }

    func testRemovesGermanDiscourseFillerAtSentenceStart() {
        let result = FillerFilter.removeDiscourseFillers("Also, wir gehen", locale: .de)
        XCTAssertEqual(result.text, "wir gehen")
        XCTAssertEqual(result.removedWords, 1)
    }

    func testRemovesGermanDiscourseFillerBetweenCommas() {
        XCTAssertEqual(FillerFilter.removeDiscourseFillers("Wir, quasi, gehen", locale: .de).text,
                       "Wir gehen")
    }

    func testGermanDiscourseWordOutsideFillerPositionRemains() {
        XCTAssertEqual(FillerFilter.removeDiscourseFillers("Das ist also gut", locale: .de).text,
                       "Das ist also gut")
    }

    func testRemovesEnglishDiscourseFillerAtSentenceStart() {
        XCTAssertEqual(FillerFilter.removeDiscourseFillers("Basically, we agree", locale: .en).text,
                       "we agree")
    }

    func testRemovesEnglishPhraseBetweenCommasAndCountsWords() {
        let result = FillerFilter.removeDiscourseFillers("We, you know, agree", locale: .en)
        XCTAssertEqual(result.text, "We agree")
        XCTAssertEqual(result.removedWords, 2)
    }

    func testLikeOutsideFillerPositionRemains() {
        XCTAssertEqual(FillerFilter.removeDiscourseFillers("I like this", locale: .en).text,
                       "I like this")
    }

    func testSoWithoutCommaRemains() {
        XCTAssertEqual(FillerFilter.removeDiscourseFillers("So far so good", locale: .en).text,
                       "So far so good")
    }

    func testActuallyAtSentenceStartIsDiscourseFiller() {
        XCTAssertEqual(FillerFilter.removeDiscourseFillers("Actually, we agree", locale: .en).text,
                       "we agree")
    }

    func testAdjacentDiscourseFillersAreRemovedWithoutOverlap() {
        let result = FillerFilter.removeDiscourseFillers("Also, quasi, gehen wir", locale: .de)
        XCTAssertEqual(result.text, "gehen wir")
        XCTAssertEqual(result.removedWords, 2)
    }

    func testDoYouKnowItRemains() {
        XCTAssertEqual(FillerFilter.removeDiscourseFillers("Do you know it?", locale: .en).text,
                       "Do you know it?")
    }

    func testDiscourseFillersAreStrictlyLanguageSpecific() {
        XCTAssertEqual(FillerFilter.removeDiscourseFillers("Actually, passt das", locale: .de).text,
                       "Actually, passt das")
    }
}
