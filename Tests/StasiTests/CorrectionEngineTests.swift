import XCTest
@testable import Stasi

// MARK: - CorrectionEngine
// Garantierter Korrektur-Pass: Whole-Word, case-insensitive, längste Quelle
// zuerst, flexible Trenner, Schutz von Nachbarwörtern.

final class CorrectionEngineTests: XCTestCase {

    func testBasicReplacement() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        let (text, applied) = CorrectionEngine.correct("ich nutze cloud code täglich", entries: entries)
        XCTAssertEqual(text, "ich nutze Claude Code täglich")
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.matched.lowercased(), "cloud code")
        XCTAssertEqual(applied.first?.target, "Claude Code")
    }

    func testCaseInsensitive() {
        let entries = [DictionaryEntry(type: .correction, from: "Cloud Code", to: "Claude Code")]
        let (text, applied) = CorrectionEngine.correct("CLOUD CODE ist toll", entries: entries)
        XCTAssertEqual(text, "Claude Code ist toll")
        XCTAssertEqual(applied.count, 1)
    }

    func testGluedSpelling() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        let (text, applied) = CorrectionEngine.correct("das ist CloudCode", entries: entries)
        XCTAssertEqual(text, "das ist Claude Code")
        XCTAssertEqual(applied.first?.matched, "CloudCode")
    }

    func testHyphenatedSpelling() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        let (text, applied) = CorrectionEngine.correct("das Cloud-Code Ding", entries: entries)
        XCTAssertEqual(text, "das Claude Code Ding")
        XCTAssertEqual(applied.count, 1)
    }

    func testMultipleSpaces() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        let (text, _) = CorrectionEngine.correct("cloud  code", entries: entries)
        XCTAssertEqual(text, "Claude Code")
    }

    func testDoesNotTouchCloudflare() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        let (text, applied) = CorrectionEngine.correct("Cloudflare ist nicht CloudCode", entries: entries)
        XCTAssertEqual(text, "Cloudflare ist nicht Claude Code")
        XCTAssertEqual(applied.count, 1)
    }

    func testDoesNotTouchPlainCloud() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        let (text, _) = CorrectionEngine.correct("die cloud ist groß", entries: entries)
        XCTAssertEqual(text, "die cloud ist groß")
    }

    func testDoesNotTouchTrailingHyphenWords() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        // "cloud-code" als Teil eines längeren Wortes mit Bindestrich davor
        let (text, _) = CorrectionEngine.correct("x-cloudcode y", entries: entries)
        XCTAssertEqual(text, "x-cloudcode y")
    }

    func testWordEntryReplacement() {
        let entries = [DictionaryEntry(type: .word, value: "Anthropic")]
        let (text, applied) = CorrectionEngine.correct("anthropic macht claude", entries: entries)
        XCTAssertEqual(text, "Anthropic macht claude")
        XCTAssertEqual(applied.count, 1)
    }

    func testLongestSourceWins() {
        let entries = [
            DictionaryEntry(type: .correction, from: "code", to: "Code"),
            DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code"),
        ]
        let (text, _) = CorrectionEngine.correct("cloud code", entries: entries)
        XCTAssertEqual(text, "Claude Code")
    }

    func testMultipleOccurrences() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        let (text, applied) = CorrectionEngine.correct("cloud code und nochmal CloudCode", entries: entries)
        XCTAssertEqual(text, "Claude Code und nochmal Claude Code")
        XCTAssertEqual(applied.count, 1, "Ein Eintrag = eine AppliedCorrection")
    }

    func testGermanUmlautsWordBoundary() {
        let entries = [DictionaryEntry(type: .word, value: "Grüße")]
        let (text, _) = CorrectionEngine.correct("grüße und Grüßchen", entries: entries)
        // "grüße" → "Grüße"; "Grüßchen" bleibt (Wortgrenze)
        XCTAssertEqual(text, "Grüße und Grüßchen")
    }

    func testEmptyInputPassthrough() {
        let entries = [DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")]
        let (text, applied) = CorrectionEngine.correct("", entries: entries)
        XCTAssertEqual(text, "")
        XCTAssertTrue(applied.isEmpty)
    }

    func testLearnedEntriesAreIgnored() {
        let entries = [DictionaryEntry(type: .learned, value: "cloud code", to: "Claude Code")]
        let (text, applied) = CorrectionEngine.correct("cloud code", entries: entries)
        XCTAssertEqual(text, "cloud code")
        XCTAssertTrue(applied.isEmpty)
    }

    func testIdenticalMatchesDoNotCountAsCorrections() {
        let entries = [DictionaryEntry(type: .word, value: "Anthropic")]
        let (text, applied) = CorrectionEngine.correct("Anthropic und anthropic", entries: entries)
        XCTAssertEqual(text, "Anthropic und Anthropic")
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.matched, "anthropic")
    }

    func testOnlyIdenticalMatchesProduceNoAppliedCorrection() {
        let entries = [DictionaryEntry(type: .word, value: "Anthropic")]
        let (text, applied) = CorrectionEngine.correct("Anthropic", entries: entries)
        XCTAssertEqual(text, "Anthropic")
        XCTAssertTrue(applied.isEmpty)
    }
}

// MARK: - CommonWords-Warnungen

final class CommonWordsTests: XCTestCase {

    func testWarnsForCloudSource() {
        let entry = DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code")
        let warns = CommonWords.warnings(for: entry)
        XCTAssertTrue(warns.contains { $0.contains("cloud") })
    }

    func testNoWarnForCleanSource() {
        let entry = DictionaryEntry(type: .correction, from: "floop fleex", to: "FloopFleex")
        XCTAssertTrue(CommonWords.warnings(for: entry).isEmpty)
    }

    func testWarnForPlainWordEntry() {
        let entry = DictionaryEntry(type: .word, value: "Cloud")
        XCTAssertFalse(CommonWords.warnings(for: entry).isEmpty)
    }
}

// MARK: - BiasProvider

final class BiasProviderTests: XCTestCase {

    func testShortestFirst() {
        let biaser = DictionaryBiaser(entries: [
            DictionaryEntry(type: .word, value: "Supabase"),
            DictionaryEntry(type: .word, value: "Vercel"),
        ])
        let words = biaser.vocabularyContext()
        XCTAssertEqual(words.first, "Vercel") // 6 Zeichen < 8
    }

    func testLimitIsRespected() {
        let entries = (0..<30).map { DictionaryEntry(type: .word, value: "Begriff\($0)") }
        let biaser = DictionaryBiaser(entries: entries)
        XCTAssertEqual(biaser.vocabularyContext(limit: 12).count, 12)
    }

    func testEmptyEntries() {
        let biaser = DictionaryBiaser(entries: [])
        XCTAssertTrue(biaser.vocabularyContext().isEmpty)
    }

    func testCorrectionsContributeTarget() {
        let biaser = DictionaryBiaser(entries: [
            DictionaryEntry(type: .correction, from: "cloud code", to: "Claude Code"),
        ])
        XCTAssertEqual(biaser.vocabularyContext(), ["Claude Code"])
    }

    func testLearnedExcluded() {
        let biaser = DictionaryBiaser(entries: [
            DictionaryEntry(type: .learned, value: "Geheimbegriff"),
            DictionaryEntry(type: .word, value: "Vercel"),
        ])
        XCTAssertEqual(biaser.vocabularyContext(), ["Vercel"])
    }

    func testDeduplicatedWithStableOrder() {
        let biaser = DictionaryBiaser(entries: [
            DictionaryEntry(type: .word, value: "Vercel"),
            DictionaryEntry(type: .correction, from: "wersell", to: "Vercel"),
            DictionaryEntry(type: .word, value: "Linear"),
        ])
        XCTAssertEqual(biaser.vocabularyContext(), ["Vercel", "Linear"])
    }
}
