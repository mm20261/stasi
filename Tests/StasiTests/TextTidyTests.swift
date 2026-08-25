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

    func testCapitalizesAfterPeriod() {
        XCTAssertEqual(TextTidy.tidy("erster satz. zweiter satz"),
                       "Erster satz. Zweiter satz")
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
}
