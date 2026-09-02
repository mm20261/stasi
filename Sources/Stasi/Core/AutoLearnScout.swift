import Foundation

/// Reine Heuristik für noch unbestätigte Wörterbuch-Vorschläge.
enum AutoLearnScout {
    struct Options: Sendable, Equatable {
        var minimumTokenLength: Int = 4
        var maximumTokenLength: Int = 30
        var maxCandidatesBeforeCounting: Int = 10
        var historyLimit: Int = 200
        var minimumProtocolCount: Int = 2
    }

    private struct Token {
        let spelling: String
        let sentenceInitial: Bool
    }

    struct Candidate: Sendable, Equatable {
        let key: String
        let spelling: String
    }

    static func candidates(
        newRecord: TranscriptionRecord,
        historyExcludingNew: [TranscriptionRecord],
        dictionary: [DictionaryEntry],
        ignored: [String],
        locale: Locale,
        isKnownWord: (String) -> Bool,
        options: Options = .init()
    ) -> [DictionaryEntry] {
        let possible = potentialCandidates(
            newRecord: newRecord,
            dictionary: dictionary,
            ignored: ignored,
            locale: locale,
            options: options
        ).filter { !isKnownWord($0.spelling) }
        return candidates(
            from: possible,
            newRecord: newRecord,
            historyExcludingNew: historyExcludingNew,
            options: options
        )
    }

    /// Reiner, begrenzter Token-Scan. Der Aufrufer kann die kleine Ergebnisliste
    /// anschließend auf dem MainActor mit NSSpellChecker prüfen.
    static func potentialCandidates(
        newRecord: TranscriptionRecord,
        dictionary: [DictionaryEntry],
        ignored: [String],
        locale: Locale,
        options: Options = .init()
    ) -> [Candidate] {
        guard options.maxCandidatesBeforeCounting > 0 else { return [] }
        let polishLocale = PolishLocale(locale: locale)
        let excluded = excludedWords(
            dictionary: dictionary,
            ignored: ignored,
            locale: polishLocale
        )

        var seen: Set<String> = []
        var possible: [Candidate] = []
        for token in tokens(in: newRecord.correctedText) {
            let key = normalized(token.spelling)
            guard token.spelling.count >= options.minimumTokenLength,
                  token.spelling.count <= options.maximumTokenLength,
                  !key.isEmpty,
                  seen.insert(key).inserted,
                  !excluded.contains(key)
            else { continue }

            let eligibleByShape = polishLocale == .en
                || (!token.sentenceInitial && token.spelling.first?.isUppercase == true)
            guard eligibleByShape else { continue }

            possible.append(Candidate(key: key, spelling: token.spelling))
            if possible.count == options.maxCandidatesBeforeCounting { break }
        }
        return possible
    }

    /// Teurer Regex-Scan über die Historie; vollständig frei von AppKit.
    static func candidates(
        from possible: [Candidate],
        newRecord: TranscriptionRecord,
        historyExcludingNew: [TranscriptionRecord],
        options: Options = .init()
    ) -> [DictionaryEntry] {
        let history = historyExcludingNew
            .filter { $0.id != newRecord.id }
            .prefix(max(0, options.historyLimit))
        var result: [DictionaryEntry] = []
        for candidate in possible {
            let expression = wholeWordExpression(for: candidate.spelling)
            var protocolCount = 1
            var spellings: [(value: String, count: Int, firstSeen: Int)] = []
            collectSpellings(in: newRecord.correctedText,
                             matching: expression,
                             into: &spellings)

            for record in history {
                let matches = matches(in: record.correctedText, expression: expression)
                guard !matches.isEmpty else { continue }
                protocolCount += 1
                addSpellings(matches, into: &spellings)
            }

            guard protocolCount >= options.minimumProtocolCount else { continue }
            let preferred = spellings.max {
                if $0.count != $1.count { return $0.count < $1.count }
                return $0.firstSeen > $1.firstSeen
            }?.value ?? candidate.spelling
            result.append(DictionaryEntry(
                type: .learned,
                value: preferred,
                note: "\(protocolCount)× diktiert"
            ))
        }
        return result
    }

    private static func excludedWords(
        dictionary: [DictionaryEntry],
        ignored: [String],
        locale: PolishLocale
    ) -> Set<String> {
        var result = Set(CommonWords.set.map(normalized))
        result.formUnion(locale.hesitations.map(normalized))
        result.formUnion(locale.discourseFillers.flatMap { $0 }.map(normalized))
        result.formUnion(locale.weekdays.map(normalized))
        result.formUnion(locale.months.map(normalized))
        result.formUnion(locale.numberWords.map(normalized))
        result.formUnion(ignored.map(normalized))

        for entry in dictionary {
            for field in [entry.matchSource, entry.replacementTarget] {
                result.insert(normalized(field))
                result.formUnion(tokens(in: field).map { normalized($0.spelling) })
            }
        }
        return result
    }

    private static func tokens(in text: String) -> [Token] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = tokenExpression.matches(in: text, range: range)
        var wasSentenceInitial = true
        var previousEnd = text.startIndex

        return matches.compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let gap = text[previousEnd..<swiftRange.lowerBound]
            if gap.contains(where: { ".!?".contains($0) }) {
                wasSentenceInitial = true
            }
            let token = Token(
                spelling: String(text[swiftRange]),
                sentenceInitial: wasSentenceInitial
            )
            wasSentenceInitial = false
            previousEnd = swiftRange.upperBound
            return token
        }
    }

    private static func wholeWordExpression(for word: String) -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{M}\\p{N}])\(escaped)(?![\\p{L}\\p{M}\\p{N}])",
            options: [.caseInsensitive]
        )
    }

    private static func collectSpellings(
        in text: String,
        matching expression: NSRegularExpression,
        into spellings: inout [(value: String, count: Int, firstSeen: Int)]
    ) {
        addSpellings(matches(in: text, expression: expression), into: &spellings)
    }

    private static func matches(
        in text: String,
        expression: NSRegularExpression
    ) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func addSpellings(
        _ values: [String],
        into spellings: inout [(value: String, count: Int, firstSeen: Int)]
    ) {
        for value in values {
            if let index = spellings.firstIndex(where: {
                $0.value == value
            }) {
                spellings[index].count += 1
            } else {
                spellings.append((value, 1, spellings.count))
            }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let tokenExpression = try! NSRegularExpression(
        pattern: "[\\p{L}\\p{M}]+(?:[’'][\\p{L}\\p{M}]+)?",
        options: []
    )
}
