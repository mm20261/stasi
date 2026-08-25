import Foundation

enum PolishLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case standard

    var id: String { rawValue }
}

struct PolishChange: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case hesitation
        case stutter
        case selfCorrection
        case discourseFiller
        case textTidy
    }

    let kind: Kind
    let count: Int
}

struct PolishSummary: Codable, Equatable, Sendable {
    let level: PolishLevel
    let changes: [PolishChange]

    var changedAnything: Bool { !changes.isEmpty }
    var hesitationWordsRemoved: Int { count(.hesitation) }
    var stutterWordsRemoved: Int { count(.stutter) }
    var selfCorrectionsResolved: Int { count(.selfCorrection) }
    var discourseFillerWordsRemoved: Int { count(.discourseFiller) }
    var fillerWordsRemoved: Int {
        hesitationWordsRemoved + discourseFillerWordsRemoved
    }

    private func count(_ kind: PolishChange.Kind) -> Int {
        changes.first(where: { $0.kind == kind })?.count ?? 0
    }
}

struct PolishOutcome: Equatable, Sendable {
    let text: String
    let corrections: [AppliedCorrection]
    let summary: PolishSummary
}

enum TranscriptPolisher {
    static func effectiveLevel(configured: PolishLevel,
                               environment: [String: String] = ProcessInfo.processInfo.environment)
        -> PolishLevel {
        environment["STASI_POLISH"]?.lowercased() == "off" ? .off : configured
    }

    static func polishSync(_ rawText: String, locale: Locale,
                           entries: [DictionaryEntry], level: PolishLevel) -> PolishOutcome {
        guard level == .standard else {
            let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let corrected = CorrectionEngine.correct(trimmedRaw, entries: entries)
            return PolishOutcome(
                text: corrected.text.trimmingCharacters(in: .whitespacesAndNewlines),
                corrections: corrected.applied,
                summary: PolishSummary(level: .off, changes: [])
            )
        }

        let polishLocale = PolishLocale(locale: locale)
        var text = rawText
        var changes: [PolishChange] = []

        let hesitation = FillerFilter.removeHesitations(text, locale: polishLocale)
        text = hesitation.text
        add(.hesitation, count: hesitation.removedWords, to: &changes)

        let stutter = FillerFilter.collapseStutters(text, locale: polishLocale)
        text = stutter.text
        add(.stutter, count: stutter.removedWords, to: &changes)

        let selfCorrection = SelfCorrectionResolver.resolve(text, locale: polishLocale)
        text = selfCorrection.text
        add(.selfCorrection, count: selfCorrection.resolvedCount, to: &changes)

        let discourse = FillerFilter.removeDiscourseFillers(text, locale: polishLocale)
        text = discourse.text
        add(.discourseFiller, count: discourse.removedWords, to: &changes)

        let firstTidy = TextTidy.tidy(text)
        if firstTidy != text { add(.textTidy, count: 1, to: &changes) }
        let corrected = CorrectionEngine.correct(firstTidy, entries: entries)
        let finalText = TextTidy.tidy(corrected.text)
        if finalText != corrected.text { add(.textTidy, count: 1, to: &changes) }

        return PolishOutcome(
            text: finalText,
            corrections: corrected.applied,
            summary: PolishSummary(level: .standard, changes: changes)
        )
    }

    private static func add(_ kind: PolishChange.Kind, count: Int,
                            to changes: inout [PolishChange]) {
        guard count > 0 else { return }
        if let index = changes.firstIndex(where: { $0.kind == kind }) {
            changes[index] = PolishChange(kind: kind, count: changes[index].count + count)
        } else {
            changes.append(PolishChange(kind: kind, count: count))
        }
    }
}
