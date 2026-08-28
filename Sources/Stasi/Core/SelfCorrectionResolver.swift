import Foundation

/// Konservativer Resolver für explizite Selbstkorrekturen innerhalb eines Satzes.
enum SelfCorrectionResolver {
    struct Edit: Equatable, Sendable {
        let removed: String
        let kept: String
    }

    struct Result: Equatable, Sendable {
        let text: String
        let resolvedCount: Int
        let edits: [Edit]
    }

    private enum Strength { case strong, weak }
    private enum TokenClass { case number, weekday, month }

    private struct Token {
        let normalized: String
        let range: Range<String.Index>
    }

    private struct Marker {
        let span: Range<Int>
        let strength: Strength
    }

    private struct Sentence {
        let range: Range<String.Index>
        let endsWithQuestion: Bool
    }

    private struct FrameMatch {
        let leftStart: Int
        let length: Int
    }

    private struct Removal {
        let range: Range<String.Index>
        let edit: Edit
    }

    private static let minimumRepeatedPrefixWords = 3
    private static let maximumRepeatedPrefixWords = 12
    private static let maximumRestartWindowWords = 16
    private static let maximumRestartCandidatesPerSentence = 32

    private struct PassResult {
        let text: String
        let edits: [Edit]
    }

    private struct AttemptMatch {
        let leftRange: Range<Int>
        let rightRange: Range<Int>
        let sharedPrefixWords: Int
    }

    static func resolve(_ input: String, locale: PolishLocale) -> Result {
        guard locale != .other, !input.isEmpty else {
            return Result(text: input, resolvedCount: 0, edits: [])
        }

        let explicit = resolveExplicitCorrections(in: input, locale: locale)
        return Result(
            text: explicit.text,
            resolvedCount: explicit.edits.count,
            edits: explicit.edits
        )
    }

    private static func resolveExplicitCorrections(
        in input: String,
        locale: PolishLocale
    ) -> PassResult {
        var removals: [Removal] = []

        for sentence in sentences(in: input) where !sentence.endsWithQuestion {
            let tokens = tokenize(input, in: sentence.range)
            guard tokens.count >= 3 else { continue }
            let markers = findMarkers(in: tokens, locale: locale)
            guard !markers.isEmpty else { continue }

            for (index, marker) in markers.enumerated() {
                let previousBoundary = index == 0 ? 0 : markers[index - 1].span.upperBound
                let nextBoundary = index + 1 == markers.count
                    ? tokens.count : markers[index + 1].span.lowerBound
                let before = previousBoundary..<marker.span.lowerBound
                let after = marker.span.upperBound..<nextBoundary

                guard !before.isEmpty, !after.isEmpty else { continue }

                if let attempt = matchingRepeatedAttempt(
                    tokens: tokens,
                    before: before,
                    after: after,
                    locale: locale
                ) {
                    let removalRange = tokens[attempt.leftRange.lowerBound].range.lowerBound..<tokens[
                        attempt.rightRange.lowerBound
                    ].range.lowerBound
                    removals.append(Removal(
                        range: removalRange,
                        edit: Edit(
                            removed: phrase(tokens: tokens, range: attempt.leftRange, in: input),
                            kept: phrase(tokens: tokens, range: attempt.rightRange, in: input)
                        )
                    ))
                    continue
                }

                guard !startsCompleteSentence(tokens: tokens, range: after, locale: locale) else {
                    continue
                }

                if let frame = matchingFrame(
                    tokens: tokens,
                    before: before,
                    after: after,
                    locale: locale
                ) {
                    let leftRange = frame.leftStart..<marker.span.lowerBound
                    let rightRange = after.startIndex..<(after.startIndex + frame.length)
                    let removalRange = tokens[frame.leftStart].range.lowerBound..<tokens[
                        after.lowerBound
                    ].range.lowerBound
                    removals.append(Removal(
                        range: removalRange,
                        edit: Edit(
                            removed: phrase(tokens: tokens, range: leftRange, in: input),
                            kept: phrase(tokens: tokens, range: rightRange, in: input)
                        )
                    ))
                    continue
                }

                guard marker.strength == .strong,
                      let left = tokens[safe: before.index(before.endIndex, offsetBy: -1)],
                      let right = tokens[safe: after.startIndex],
                      left.normalized != right.normalized,
                      let leftClass = tokenClass(left.normalized, locale: locale),
                      leftClass == tokenClass(right.normalized, locale: locale)
                else { continue }
                removals.append(Removal(
                    range: left.range.lowerBound..<right.range.lowerBound,
                    edit: Edit(removed: String(input[left.range]),
                               kept: String(input[right.range]))
                ))
            }
        }

        return applying(nonOverlapping(removals), to: input)
    }

    private static func applying(_ removals: [Removal], to input: String) -> PassResult {
        guard !removals.isEmpty else {
            return PassResult(text: input, edits: [])
        }

        var output = input
        for removal in removals.reversed() {
            output.replaceSubrange(removal.range, with: "")
        }
        return PassResult(
            text: compactAfterRemoval(output),
            edits: removals.map(\.edit)
        )
    }

    private static func sentences(in input: String) -> [Sentence] {
        var result: [Sentence] = []
        var start = input.startIndex
        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            let next = input.index(after: index)
            if character == "." || character == "!" || character == "?" {
                result.append(Sentence(range: start..<next,
                                       endsWithQuestion: character == "?"))
                start = next
            }
            index = next
        }
        if start < input.endIndex {
            result.append(Sentence(range: start..<input.endIndex, endsWithQuestion: false))
        }
        return result
    }

    private static func tokenize(_ input: String, in range: Range<String.Index>) -> [Token] {
        let nsRange = NSRange(range, in: input)
        guard let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}\\p{M}]+") else {
            return []
        }
        return regex.matches(in: input, range: nsRange).compactMap { match in
            guard let tokenRange = Range(match.range, in: input) else { return nil }
            let text = String(input[tokenRange])
            return Token(normalized: text.lowercased(), range: tokenRange)
        }
    }

    private static func findMarkers(in tokens: [Token], locale: PolishLocale) -> [Marker] {
        let patterns = locale.strongMarkers.map { ($0, Strength.strong) }
            + locale.weakMarkers.map { ($0, Strength.weak) }
        let sorted = patterns.sorted { $0.0.count > $1.0.count }
        var markers: [Marker] = []
        var cursor = 0

        while cursor < tokens.count {
            guard let found = sorted.first(where: { pattern, _ in
                cursor + pattern.count <= tokens.count
                    && zip(pattern, tokens[cursor..<(cursor + pattern.count)])
                        .allSatisfy { $0 == $1.normalized }
            }) else {
                cursor += 1
                continue
            }

            let markerRange = cursor..<(cursor + found.0.count)
            var lower = markerRange.lowerBound
            var upper = markerRange.upperBound
            while lower > 0,
                  locale.markerModifiers.contains(tokens[lower - 1].normalized) {
                lower -= 1
            }
            while upper < tokens.count,
                  locale.markerModifiers.contains(tokens[upper].normalized) {
                upper += 1
            }
            markers.append(Marker(span: lower..<upper, strength: found.1))
            cursor = upper
        }
        return markers
    }

    private static func matchingRepeatedAttempt(
        tokens: [Token],
        before: Range<Int>,
        after: Range<Int>,
        locale: PolishLocale
    ) -> AttemptMatch? {
        let firstLeftStart = max(before.lowerBound, before.upperBound - maximumRestartWindowWords)
        var best: AttemptMatch?

        for leftStart in firstLeftStart..<before.upperBound {
            let leftCount = before.upperBound - leftStart
            let comparable = min(maximumRepeatedPrefixWords, leftCount, after.count)
            guard comparable >= minimumRepeatedPrefixWords else { continue }

            var prefix = 0
            while prefix < comparable,
                  tokens[leftStart + prefix].normalized
                    == tokens[after.lowerBound + prefix].normalized {
                prefix += 1
            }
            guard prefix >= minimumRepeatedPrefixWords else { continue }

            let exactLeftPrefix = prefix == leftCount
            if exactLeftPrefix {
                guard after.count > leftCount else { continue }
            } else {
                guard after.count > prefix else { continue }
                let comparedRemainder = min(leftCount, after.count)
                let hasProtectedDifference = (prefix..<comparedRemainder).contains { offset in
                    let left = tokens[leftStart + offset].normalized
                    let right = tokens[after.lowerBound + offset].normalized
                    return left != right
                        && (locale.protectedFrameWords.contains(left)
                            || locale.protectedFrameWords.contains(right))
                }
                guard !hasProtectedDifference else { continue }
            }

            let keptLength = min(
                after.count,
                max(leftCount, prefix + 1)
            )
            let candidate = AttemptMatch(
                leftRange: leftStart..<before.upperBound,
                rightRange: after.lowerBound..<(after.lowerBound + keptLength),
                sharedPrefixWords: prefix
            )

            if let current = best {
                if candidate.sharedPrefixWords > current.sharedPrefixWords
                    || (candidate.sharedPrefixWords == current.sharedPrefixWords
                        && candidate.leftRange.lowerBound > current.leftRange.lowerBound) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    private static func matchingFrame(tokens: [Token], before: Range<Int>,
                                      after: Range<Int>, locale: PolishLocale)
        -> FrameMatch? {
        let maximum = min(6, before.count, after.count)
        guard maximum >= 2 else { return nil }

        for length in stride(from: maximum, through: 2, by: -1) {
            let leftStart = before.endIndex - length
            var differingPosition: Int?
            var valid = true
            for offset in 0..<length {
                let left = tokens[leftStart + offset].normalized
                let right = tokens[after.startIndex + offset].normalized
                guard left != right else { continue }
                if differingPosition != nil
                    || locale.protectedFrameWords.contains(left)
                    || locale.protectedFrameWords.contains(right) {
                    valid = false
                    break
                }
                differingPosition = offset
            }
            if valid, differingPosition != nil {
                return FrameMatch(leftStart: leftStart, length: length)
            }
        }
        return nil
    }

    private static func startsCompleteSentence(tokens: [Token], range: Range<Int>,
                                               locale: PolishLocale) -> Bool {
        guard range.count >= 2 else { return false }
        return locale.subjectPronouns.contains(tokens[range.startIndex].normalized)
            && locale.commonVerbs.contains(tokens[range.startIndex + 1].normalized)
    }

    private static func tokenClass(_ token: String, locale: PolishLocale) -> TokenClass? {
        if token.allSatisfy(\.isNumber) || locale.numberWords.contains(token) { return .number }
        if locale.weekdays.contains(token) { return .weekday }
        if locale.months.contains(token) { return .month }
        return nil
    }

    private static func nonOverlapping(_ removals: [Removal]) -> [Removal] {
        let sorted = removals.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result: [Removal] = []
        for removal in sorted {
            guard result.last.map({ $0.range.upperBound > removal.range.lowerBound }) != true
            else { continue }
            result.append(removal)
        }
        return result
    }

    private static func phrase(tokens: [Token], range: Range<Int>,
                               in input: String) -> String {
        range.compactMap { index in
            tokens[safe: index].map { String(input[$0.range]) }
        }.joined(separator: " ")
    }

    private static func compactAfterRemoval(_ input: String) -> String {
        var text = replace(input, pattern: "\\s+", with: " ")
        text = replace(text, pattern: "[ \\t]+([,.;:!?])", with: "$1")
        text = replace(text, pattern: ",\\s*,(?:\\s*,)*", with: ",")
        text = replace(text, pattern: "^\\s*,(?:\\s*,)*\\s*", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let matches = regex.matches(in: input,
                                    range: NSRange(input.startIndex..., in: input))
        let replacements = matches.compactMap { match -> (Range<String.Index>, String)? in
            guard let range = Range(match.range, in: input) else { return nil }
            return (range, regex.replacementString(for: match, in: input,
                                                   offset: 0, template: template))
        }
        var output = input
        for (range, replacement) in replacements.reversed() {
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
