import XCTest
@testable import Stasi

final class TextTidyTests: XCTestCase {
    func testCollapsesRepeatedSpaces() {
        XCTAssertEqual(TextTidy.tidy("hallo   welt"), "Hallo welt")
    }

    func testCollapsesTabsAndNewlines() {
        XCTAssertEqual(TextTidy.tidy("hallo\t\nwelt"), "Hallo welt")
    }

    func testRemovesSpaceBeforePunctuation() {
        XCTAssertEqual(TextTidy.tidy("hallo , welt !"), "Hallo, welt!")
    }

    func testCollapsesDuplicateCommas() {
        XCTAssertEqual(TextTidy.tidy("hallo, , welt"), "Hallo, welt")
    }

    func testRemovesLeadingComma() {
        XCTAssertEqual(TextTidy.tidy(", , hallo"), "Hallo")
    }

    func testCapitalizesSentenceStart() {
        XCTAssertEqual(TextTidy.tidy("guten morgen"), "Guten morgen")
    }

    func testBewahrtMacOSAmSatzanfang() {
        XCTAssertEqual(TextTidy.tidy("macOS ist neu"), "macOS ist neu")
    }

    func testBewahrtIPhoneAmSatzanfang() {
        XCTAssertEqual(TextTidy.tidy("iPhone geht"), "iPhone geht")
    }

    func testSchreibtGewoehnlichenSatzanfangWeiterhinGross() {
        XCTAssertEqual(TextTidy.tidy("hallo welt"), "Hallo welt")
    }

    func testCapitalizesAfterPeriod() {
        XCTAssertEqual(TextTidy.tidy("erster satz. zweiter satz"),
                       "Erster satz. Zweiter satz")
    }

    func testSchreibtNachZumBeispielNichtGross() {
        XCTAssertEqual(TextTidy.tidy("das ist z.B. der Punkt"),
                       "Das ist z.B. der Punkt")
    }

    func testSchreibtNachUndSoWeiterNichtGross() {
        XCTAssertEqual(TextTidy.tidy("Stühle usw. für das Fest"),
                       "Stühle usw. für das Fest")
    }

    func testCapitalizesAfterQuestionAndExclamation() {
        XCTAssertEqual(TextTidy.tidy("wirklich? ja! natürlich"),
                       "Wirklich? Ja! Natürlich")
    }

    func testDoesNotAppendPeriod() {
        XCTAssertEqual(TextTidy.tidy("kein punkt"), "Kein punkt")
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(TextTidy.tidy("  \n "), "")
    }

    func testKurzesWortVorPunktBleibtSatzende() {
        XCTAssertEqual(TextTidy.tidy("ja. das machen wir"), "Ja. Das machen wir")
        XCTAssertEqual(TextTidy.tidy("ich bin da. er auch"), "Ich bin da. Er auch")
    }

    func testEinzelbuchstabeVorPunktIstKeinSatzende() {
        XCTAssertEqual(TextTidy.tidy("herr s. meier kommt"), "Herr s. meier kommt")
    }
}
