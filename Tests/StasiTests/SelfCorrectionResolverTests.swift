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

    func testStrongMarkerAllowsIdenticalFrameWithRightContinuation() {
        let result = SelfCorrectionResolver.resolve(
            "Hallo, mein Name ist, nein, Hallo, mein Name ist Philipp",
            locale: .de
        )

        XCTAssertEqual(result.text, "Hallo, mein Name ist Philipp")
        XCTAssertEqual(result.resolvedCount, 1)
        XCTAssertEqual(result.edits, [
            SelfCorrectionResolver.Edit(
                removed: "Hallo, mein Name ist",
                kept: "Hallo, mein Name ist Philipp"
            ),
        ])
    }

    func testWeakMarkerAllowsMultiwordReplacementInRepeatedFrame() {
        let result = SelfCorrectionResolver.resolve(
            "Wir treffen uns Montag um zehn, ich meine, Wir treffen uns Dienstag um zwölf",
            locale: .de
        )

        XCTAssertEqual(result.text, "Wir treffen uns Dienstag um zwölf")
        XCTAssertEqual(result.resolvedCount, 1)
        XCTAssertEqual(result.edits, [
            SelfCorrectionResolver.Edit(
                removed: "Wir treffen uns Montag um zehn",
                kept: "Wir treffen uns Dienstag um zwölf"
            ),
        ])
    }

    func testRepeatedAttemptAfterSentenceCandidateBudgetIsNotEvaluated() {
        let firstAttempt = (1...16).map { "alpha\($0)" }.joined(separator: " ")
        let secondAttempt = (1...16).map { "beta\($0)" }.joined(separator: " ")
        let thirdAttempt = (1...16).map { "gamma\($0)" }.joined(separator: " ")
        let input = "\(firstAttempt) ich meine \(secondAttempt) ich meinte "
            + "\(thirdAttempt) korrektur \(thirdAttempt) fortsetzung"

        let result = SelfCorrectionResolver.resolve(input, locale: .de)

        XCTAssertEqual(result.text, input)
        XCTAssertEqual(result.resolvedCount, 0)
        XCTAssertEqual(result.edits, [])
    }

    func testMarkerlessGermanRestartKeepsLaterAttempt() {
        let result = SelfCorrectionResolver.resolve(
            "Hallo, mein Name ist Peter, Hallo, mein Name ist Philipp",
            locale: .de
        )

        XCTAssertEqual(result.text, "Hallo, mein Name ist Philipp")
        XCTAssertEqual(result.resolvedCount, 1)
        XCTAssertEqual(result.edits.first?.removed, "Hallo, mein Name ist Peter")
        XCTAssertEqual(result.edits.first?.kept, "Hallo, mein Name ist Philipp")
    }

    func testMarkerlessExactPrefixRequiresIncompleteFirstAttempt() {
        XCTAssertEqual(
            resolve("Hallo, mein Name ist, Hallo, mein Name ist Philipp"),
            "Hallo, mein Name ist Philipp"
        )
    }

    func testMarkerlessEnglishRestartKeepsLaterAttempt() {
        XCTAssertEqual(
            resolve("We will meet on Friday, We will meet on Thursday", .en),
            "We will meet on Thursday"
        )
    }

    func testMarkerlessRestartAcceptsEmDashSeparator() {
        XCTAssertEqual(
            resolve("Wir treffen uns Montag — Wir treffen uns Dienstag"),
            "Wir treffen uns Dienstag"
        )
    }

    func testTwoMarkerlessRestartsEndAtLastAttempt() {
        let result = SelfCorrectionResolver.resolve(
            "Hallo mein Name ist Peter, Hallo mein Name ist Paul, Hallo mein Name ist Philipp",
            locale: .de
        )

        XCTAssertEqual(result.text, "Hallo mein Name ist Philipp")
        XCTAssertEqual(result.resolvedCount, 2)
        XCTAssertEqual(result.edits.map(\.removed), [
            "Hallo mein Name ist Peter",
            "Hallo mein Name ist Paul",
        ])
        XCTAssertEqual(result.edits.map(\.kept), [
            "Hallo mein Name ist Paul",
            "Hallo mein Name ist Philipp",
        ])
    }

    func testCompleteMarkerlessRepetitionRemains() {
        let text = "Hallo mein Name ist Philipp, Hallo mein Name ist Philipp"
        XCTAssertEqual(resolve(text), text)
    }

    func testCompleteRepetitionWithLaterContinuationRemains() {
        let text = "Hallo mein Name ist Philipp, Hallo mein Name ist Philipp und ich wohne in Berlin"
        XCTAssertEqual(resolve(text), text)
    }

    func testCompleteRepetitionBeyondPrefixCapRemains() {
        for wordCount in 13...16 {
            let attempt = (1...wordCount).map { "wort\($0)" }.joined(separator: " ")
            let text = "\(attempt), \(attempt) und besprechen Details"

            XCTAssertEqual(resolve(text), text, "wordCount=\(wordCount)")
        }
    }

    func testIncompleteGermanSecondAttemptDoesNotReplaceCompleteFirstAttempt() {
        let text = "Hallo mein Name ist Peter und ich wohne in Berlin, Hallo mein Name ist der"
        XCTAssertEqual(resolve(text), text)
    }

    func testIncompleteEnglishSecondAttemptDoesNotReplaceCompleteFirstAttempt() {
        let text = "Hello my name is Peter and I live in Berlin, Hello my name is the"
        XCTAssertEqual(resolve(text, .en), text)
    }

    func testExplicitGermanIncompleteSecondAttemptEndingInArticleRemains() {
        let text = "Ich wohne heute in Berlin und arbeite dort, nein, Ich wohne heute in der"
        XCTAssertEqual(resolve(text), text)
    }

    func testExplicitEnglishIncompleteSecondAttemptEndingInArticleRemains() {
        let text = "I live today in Berlin and work there, no, I live today in the"
        XCTAssertEqual(resolve(text, .en), text)
    }

    func testMarkerlessGermanIncompleteSecondAttemptEndingInConjunctionRemains() {
        let text = "Hallo mein Name ist Peter und ich wohne in Berlin, Hallo mein Name ist Philipp und"
        XCTAssertEqual(resolve(text), text)
    }

    func testMarkerlessEnglishIncompleteSecondAttemptEndingInConjunctionRemains() {
        let text = "Hello my name is Peter and I live in Berlin, Hello my name is Philipp and"
        XCTAssertEqual(resolve(text, .en), text)
    }

    func testLongMarkerlessRestartChainKeepsLastAttemptAndIsIdempotent() {
        let input = (0...10).map { "Ich bin am Ort\($0)" }.joined(separator: ", ")

        let first = SelfCorrectionResolver.resolve(input, locale: .de)
        let second = SelfCorrectionResolver.resolve(first.text, locale: .de)

        XCTAssertEqual(first.text, "Ich bin am Ort10")
        XCTAssertEqual(first.resolvedCount, 10)
        XCTAssertEqual(second.text, first.text)
        XCTAssertEqual(second.resolvedCount, 0)
        XCTAssertTrue(second.edits.isEmpty)
    }

    func testMarkerlessCandidateOverflowLeavesThirtyFourAttemptsUnchangedAndIdempotent() {
        let input = (0...33).map { "Ich bin am Ort\($0)" }.joined(separator: ", ")

        let first = SelfCorrectionResolver.resolve(input, locale: .de)
        let second = SelfCorrectionResolver.resolve(first.text, locale: .de)

        XCTAssertEqual(first.text, input)
        XCTAssertEqual(first.resolvedCount, 0)
        XCTAssertTrue(first.edits.isEmpty)
        XCTAssertEqual(second.text, input)
        XCTAssertEqual(second.resolvedCount, 0)
        XCTAssertTrue(second.edits.isEmpty)
    }

    func testGermanSemicolonParallelClausesRemain() {
        let text = "Ich kaufe rote Äpfel; Ich kaufe rote Birnen."
        XCTAssertEqual(resolve(text), text)
    }

    func testEnglishSemicolonParallelClausesRemain() {
        let text = "I buy red apples; I buy red pears."
        XCTAssertEqual(resolve(text, .en), text)
    }

    func testColonParallelClausesRemain() {
        let text = "Ich kaufe rote Äpfel: Ich kaufe rote Birnen."
        XCTAssertEqual(resolve(text), text)
    }

    func testEmbeddedGermanRepeatedPhraseWithoutClauseBoundaryRemains() {
        let text = "Das Team trifft sich am Montag bevor das Team trifft sich am Dienstag zur Abstimmung."
        XCTAssertEqual(resolve(text), text)
    }

    func testEmbeddedEnglishRepeatedPhraseWithoutClauseBoundaryRemains() {
        let text = "The team will meet on Monday before the team will meet on Tuesday to vote."
        XCTAssertEqual(resolve(text, .en), text)
    }

    func testMarkerlessRestartDoesNotCrossSentenceBoundary() {
        let text = "Hallo mein Name ist Peter. Hallo mein Name ist Philipp."
        XCTAssertEqual(resolve(text), text)
    }

    func testMarkerlessRestartDoesNotModifyQuestion() {
        let text = "Hallo mein Name ist Peter, Hallo mein Name ist Philipp?"
        XCTAssertEqual(resolve(text), text)
    }

    func testQuotedAndAnnouncedRepetitionRemains() {
        let text = "Ich sage „Hallo, mein Name ist Peter“ und wiederhole „Hallo, mein Name ist Philipp“."
        XCTAssertEqual(resolve(text), text)
    }

    func testMarkerlessRestartInsideGermanQuotePairRemains() {
        let text = "„Hallo mein Name ist Peter, Hallo mein Name ist Philipp“."
        XCTAssertEqual(resolve(text), text)
    }

    func testMarkerlessRestartInsideStraightEnglishDoubleQuotesRemains() {
        let text = "\"Hello my name is Peter, Hello my name is Philipp\"."
        XCTAssertEqual(resolve(text, .en), text)
    }

    func testMarkerlessRestartInsideGermanGuillemetsRemains() {
        let text = "»Hallo mein Name ist Peter, Hallo mein Name ist Philipp«."
        XCTAssertEqual(resolve(text), text)
    }

    func testAnnouncementInsideCandidateBlocksRemoval() {
        let text = "Hallo mein Name ist Peter und ich wiederhole Hallo mein Name ist Philipp"
        XCTAssertEqual(resolve(text), text)
    }

    func testTwoCommonWordsAreNotEnoughForMarkerlessRestart() {
        let text = "Mein Name ist Peter, Mein Name lautet Philipp"
        XCTAssertEqual(resolve(text), text)
    }

    func testMarkerlessSearchStopsOutsideFixedWindow() {
        let gap = (0..<20).map { "zwischen\($0)" }.joined(separator: " ")
        let text = "Hallo mein Name ist Peter \(gap) Hallo mein Name ist Philipp"
        XCTAssertEqual(resolve(text), text)
    }

    func testRestartResolutionIsIdempotent() {
        let first = SelfCorrectionResolver.resolve(
            "Hallo mein Name ist Peter, Hallo mein Name ist Philipp",
            locale: .de
        )
        let second = SelfCorrectionResolver.resolve(first.text, locale: .de)

        XCTAssertEqual(second.text, first.text)
        XCTAssertEqual(second.resolvedCount, 0)
        XCTAssertTrue(second.edits.isEmpty)
    }

    func testExplicitRestartAuditKeepsCompleteOriginalRightAttempt() {
        let result = SelfCorrectionResolver.resolve(
            "Hallo, mein Name ist Peter, nein, Hallo, mein Name ist Philipp und ich wohne in Berlin",
            locale: .de
        )

        XCTAssertEqual(result.text, "Hallo, mein Name ist Philipp und ich wohne in Berlin")
        XCTAssertEqual(result.edits, [
            SelfCorrectionResolver.Edit(
                removed: "Hallo, mein Name ist Peter",
                kept: "Hallo, mein Name ist Philipp und ich wohne in Berlin"
            ),
        ])
    }

    func testMarkerlessAuditPreservesStraightApostrophe() {
        let result = SelfCorrectionResolver.resolve(
            "We'll meet on Friday, We'll meet on Thursday",
            locale: .en
        )

        XCTAssertEqual(result.text, "We'll meet on Thursday")
        XCTAssertEqual(result.edits.first?.removed, "We'll meet on Friday")
        XCTAssertEqual(result.edits.first?.kept, "We'll meet on Thursday")
    }

    func testMarkerlessAuditPreservesTypographicApostrophe() {
        let result = SelfCorrectionResolver.resolve(
            "We’ll meet on Friday, We’ll meet on Thursday",
            locale: .en
        )

        XCTAssertEqual(result.text, "We’ll meet on Thursday")
        XCTAssertEqual(result.edits.first?.removed, "We’ll meet on Friday")
        XCTAssertEqual(result.edits.first?.kept, "We’ll meet on Thursday")
    }

    func testMarkerlessAuditPreservesHyphen() {
        let result = SelfCorrectionResolver.resolve(
            "E-Mail schicken wir Montag, E-Mail schicken wir Dienstag",
            locale: .de
        )

        XCTAssertEqual(result.text, "E-Mail schicken wir Dienstag")
        XCTAssertEqual(result.edits.first?.removed, "E-Mail schicken wir Montag")
        XCTAssertEqual(result.edits.first?.kept, "E-Mail schicken wir Dienstag")
    }

    func testNonEmptyRestartNeverBecomesEmpty() {
        let explicit = SelfCorrectionResolver.resolve(
            "Hallo, mein Name ist, nein, Hallo, mein Name ist Philipp",
            locale: .de
        )
        let markerless = SelfCorrectionResolver.resolve(
            "Hallo, mein Name ist Peter, Hallo, mein Name ist Philipp",
            locale: .de
        )

        XCTAssertFalse(explicit.text.isEmpty)
        XCTAssertFalse(markerless.text.isEmpty)
    }
}
