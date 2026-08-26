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
        case dictionary
        case textTidy
    }

    let kind: Kind
    let count: Int
    let removed: String?
    let kept: String?

    init(kind: Kind, count: Int, removed: String? = nil, kept: String? = nil) {
        self.kind = kind
        self.count = count
        self.removed = removed
        self.kept = kept
    }
}

struct PolishDetailSection: Equatable, Sendable {
    let title: String
    let items: [String]
}

struct PolishSummary: Codable, Equatable, Sendable {
    let level: PolishLevel
    let changes: [PolishChange]

    var changedAnything: Bool { !changes.isEmpty }
    var hesitationWordsRemoved: Int { count(.hesitation) }
    var stutterWordsRemoved: Int { count(.stutter) }
    var selfCorrectionsResolved: Int { count(.selfCorrection) }
    var discourseFillerWordsRemoved: Int { count(.discourseFiller) }
    var dictionaryCorrectionsApplied: Int { count(.dictionary) }
    var fillerWordsRemoved: Int {
        hesitationWordsRemoved + discourseFillerWordsRemoved
    }

    /// Kurzes, belastbares UI-Label. Reine Interpunktions-/Whitespace-Glättung
    /// zählt bewusst nicht als sichtbares „Poliert"-Ergebnis.
    func badgeText(correctionCount: Int = 0) -> String? {
        guard level == .standard, !changes.isEmpty else { return nil }
        if fillerWordsRemoved > 0 {
            return "POLIERT · −\(fillerWordsRemoved) FÜLLWÖRTER"
        }
        if stutterWordsRemoved > 0 || selfCorrectionsResolved > 0 {
            return "POLIERT · VERSPRECHER"
        }
        let corrections = dictionaryCorrectionsApplied > 0
            ? dictionaryCorrectionsApplied : correctionCount
        if corrections > 0 {
            let noun = corrections == 1 ? "KORREKTUR" : "KORREKTUREN"
            return "POLIERT · \(corrections) \(noun)"
        }
        return nil
    }

    var compactBadgeText: String? {
        badgeText() == nil ? nil : "POLIERT"
    }

    /// Reine Präsentationslogik für das gemeinsame Detail-Popover.
    /// Reihenfolge bleibt stabil und folgt der Nachbearbeitungs-Pipeline.
    func detailSections(corrections: [AppliedCorrection]) -> [PolishDetailSection] {
        guard level == .standard else { return [] }
        let fillers = changes.compactMap { change -> String? in
            guard change.kind == .hesitation || change.kind == .discourseFiller else {
                return nil
            }
            return change.removed
        }
        let slips = changes.compactMap { change -> String? in
            guard change.kind == .stutter || change.kind == .selfCorrection,
                  let removed = change.removed, let kept = change.kept else { return nil }
            return "„\(removed)“ → „\(kept)“"
        }
        var dictionary = changes.compactMap { change -> String? in
            guard change.kind == .dictionary,
                  let removed = change.removed, let kept = change.kept else { return nil }
            return "„\(removed)“ → „\(kept)“"
        }
        if dictionary.isEmpty {
            dictionary = corrections.map { "„\($0.matched)“ → „\($0.target)“" }
        }

        var sections: [PolishDetailSection] = []
        if !fillers.isEmpty {
            sections.append(PolishDetailSection(title: "Füllwörter entfernt", items: fillers))
        }
        if !slips.isEmpty {
            sections.append(PolishDetailSection(title: "Versprecher", items: slips))
        }
        if !dictionary.isEmpty {
            sections.append(PolishDetailSection(title: "Wörterbuch", items: dictionary))
        }
        return sections
    }

    private func count(_ kind: PolishChange.Kind) -> Int {
        changes.filter { $0.kind == kind }.reduce(0) { $0 + $1.count }
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
        addFillerEdits(.hesitation, result: hesitation, to: &changes)

        let stutter = FillerFilter.collapseStutters(text, locale: polishLocale)
        text = stutter.text
        addFillerEdits(.stutter, result: stutter, to: &changes)

        let selfCorrection = SelfCorrectionResolver.resolve(text, locale: polishLocale)
        text = selfCorrection.text
        if selfCorrection.edits.isEmpty {
            add(.selfCorrection, count: selfCorrection.resolvedCount, to: &changes)
        } else {
            for edit in selfCorrection.edits {
                add(.selfCorrection, count: 1, removed: edit.removed,
                    kept: edit.kept, to: &changes)
            }
        }

        let discourse = FillerFilter.removeDiscourseFillers(text, locale: polishLocale)
        text = discourse.text
        addFillerEdits(.discourseFiller, result: discourse, to: &changes)

        let firstTidy = TextTidy.tidy(text)
        if firstTidy != text { add(.textTidy, count: 1, to: &changes) }
        let corrected = CorrectionEngine.correct(firstTidy, entries: entries)
        for correction in corrected.applied {
            add(.dictionary, count: 1, removed: correction.matched,
                kept: correction.target, to: &changes)
        }
        let finalText = TextTidy.tidy(corrected.text)
        if finalText != corrected.text { add(.textTidy, count: 1, to: &changes) }

        return PolishOutcome(
            text: finalText,
            corrections: corrected.applied,
            summary: PolishSummary(level: .standard, changes: changes)
        )
    }

    private static func addFillerEdits(_ kind: PolishChange.Kind,
                                       result: FillerFilter.Result,
                                       to changes: inout [PolishChange]) {
        guard !result.edits.isEmpty else {
            add(kind, count: result.removedWords, to: &changes)
            return
        }
        for edit in result.edits {
            let removedCount = edit.removed.split(whereSeparator: { $0.isWhitespace }).count
            let keptCount = edit.kept?.split(whereSeparator: { $0.isWhitespace }).count ?? 0
            let count = kind == .stutter
                ? max(1, removedCount - keptCount)
                : max(1, removedCount)
            add(kind, count: count, removed: edit.removed,
                kept: edit.kept, to: &changes)
        }
    }

    private static func add(_ kind: PolishChange.Kind, count: Int,
                            removed: String? = nil, kept: String? = nil,
                            to changes: inout [PolishChange]) {
        guard count > 0 else { return }
        changes.append(PolishChange(kind: kind, count: count,
                                    removed: removed, kept: kept))
    }
}
