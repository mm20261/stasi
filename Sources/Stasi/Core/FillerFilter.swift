import Foundation

enum FillerFilter {
    struct Edit: Equatable, Sendable {
        let removed: String
        let kept: String?
    }

    struct Result: Equatable, Sendable {
        let text: String
        let removedWords: Int
        let edits: [Edit]
    }

    static func removeHesitations(_ input: String, locale: PolishLocale) -> Result {
        let alternatives = locale.hesitations
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
        guard !alternatives.isEmpty,
              let regex = try? NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}\\p{M}\\-_])(?:\(alternatives.joined(separator: "|")))(?![\\p{L}\\p{N}\\p{M}\\-_])",
                options: [.caseInsensitive]
              ) else {
            return Result(text: input, removedWords: 0, edits: [])
        }
        let ranges = matches(regex, in: input).compactMap { Range($0.range, in: input) }
        return Result(text: compactWhitespace(removing: ranges, from: input),
                      removedWords: ranges.count,
                      edits: ranges.map { Edit(removed: String(input[$0]), kept: nil) })
    }

    static func collapseStutters(_ input: String, locale: PolishLocale) -> Result {
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}\\p{M}\\-_])((?:\\p{L}\\p{M}*){2,12})(?:[ \\t]+\\1){1,3}(?![\\p{L}\\p{N}\\p{M}\\-_])",
            options: [.caseInsensitive]
        ) else { return Result(text: input, removedWords: 0, edits: []) }

        let replacements = matches(regex, in: input).compactMap {
            match -> (Range<String.Index>, String, Int, String)? in
            guard let range = Range(match.range, in: input),
                  let wordRange = Range(match.range(at: 1), in: input) else { return nil }
            let word = String(input[wordRange])
            if locale.stutterExceptions.contains(word.lowercased()) { return nil }
            let tokenCount = input[range].split(whereSeparator: { $0 == " " || $0 == "\t" }).count
            return (range, word, max(0, tokenCount - 1), String(input[range]))
        }

        var output = input
        for (range, replacement, _, _) in replacements.reversed() {
            output.replaceSubrange(range, with: replacement)
        }
        return Result(text: compactWhitespace(output),
                      removedWords: replacements.reduce(0) { $0 + $1.2 },
                      edits: replacements.map { Edit(removed: $0.3, kept: $0.1) })
    }

    static func removeDiscourseFillers(_ input: String, locale: PolishLocale) -> Result {
        var removals: [(range: Range<String.Index>, replacement: String,
                        words: Int, phrases: [String])] = []

        for phrase in locale.discourseFillers.sorted(by: { $0.count > $1.count }) {
            let joined = phrase.map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "[ \\t]+")
            guard let regex = try? NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}\\p{M}\\-_])\(joined)(?![\\p{L}\\p{N}\\p{M}\\-_])",
                options: [.caseInsensitive]
            ) else { continue }

            for match in matches(regex, in: input) {
                guard let phraseRange = Range(match.range, in: input),
                      let context = fillerContext(
                        for: phraseRange,
                        filler: phrase,
                        locale: locale,
                        in: input
                      ) else { continue }
                removals.append((context.range, context.replacement, phrase.count,
                                 [String(input[phraseRange])]))
            }
        }

        // Phrasenlisten überlappen derzeit nicht; der Filter schützt trotzdem
        // gegen doppelte identische Spans.
        var seen: Set<NSRange> = []
        let unique = removals.filter { item in
            let nsRange = NSRange(item.range, in: input)
            return seen.insert(nsRange).inserted
        }
        let merged = mergeOverlapping(unique)
        var output = input
        for item in merged.reversed() {
            output.replaceSubrange(item.range, with: item.replacement)
        }
        return Result(text: compactWhitespace(output),
                      removedWords: merged.reduce(0) { $0 + $1.words },
                      edits: merged.flatMap { item in
                          item.phrases.map { Edit(removed: $0, kept: nil) }
                      })
    }

    private static func matches(_ regex: NSRegularExpression,
                                in input: String) -> [NSTextCheckingResult] {
        regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
    }

    private static func mergeOverlapping(
        _ removals: [(range: Range<String.Index>, replacement: String,
                      words: Int, phrases: [String])]
    ) -> [(range: Range<String.Index>, replacement: String,
           words: Int, phrases: [String])] {
        let sorted = removals.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result: [(range: Range<String.Index>, replacement: String,
                      words: Int, phrases: [String])] = []
        for item in sorted {
            guard let previous = result.last,
                  previous.range.upperBound > item.range.lowerBound else {
                result.append(item)
                continue
            }
            result[result.count - 1] = (
                previous.range.lowerBound..<max(previous.range.upperBound, item.range.upperBound),
                previous.replacement.isEmpty || item.replacement.isEmpty ? "" : " ",
                previous.words + item.words,
                previous.phrases + item.phrases
            )
        }
        return result
    }

    private static func compactWhitespace(removing ranges: [Range<String.Index>],
                                          from input: String) -> String {
        var output = input
        for range in ranges.reversed() {
            output.replaceSubrange(range, with: "")
        }
        return compactWhitespace(output)
    }

    private static func compactWhitespace(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\s+") else { return input }
        let matches = matches(regex, in: input).compactMap { Range($0.range, in: input) }
        var output = input
        for range in matches.reversed() {
            output.replaceSubrange(range, with: " ")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fillerContext(
        for phrase: Range<String.Index>,
        filler: [String],
        locale: PolishLocale,
        in input: String
    )
        -> (range: Range<String.Index>, replacement: String)? {
        var before = phrase.lowerBound
        while before > input.startIndex {
            let previous = input.index(before, offsetBy: -1)
            guard input[previous].isWhitespace else { break }
            before = previous
        }
        let leftCharacter: Character? = before > input.startIndex
            ? input[input.index(before, offsetBy: -1)] : nil

        var after = phrase.upperBound
        while after < input.endIndex, input[after].isWhitespace {
            after = input.index(after: after)
        }
        guard after < input.endIndex, input[after] == "," else { return nil }
        let rightComma = after
        var afterComma = input.index(after: rightComma)
        while afterComma < input.endIndex, input[afterComma].isWhitespace {
            afterComma = input.index(after: afterComma)
        }

        let startsSentence = leftCharacter == nil || leftCharacter == "."
            || leftCharacter == "!" || leftCharacter == "?"
        if startsSentence {
            guard filler.count != 1
                    || !locale.sentenceInitialProtectedFillers.contains(filler[0].lowercased())
            else { return nil }
            return (phrase.lowerBound..<afterComma, "")
        }

        guard leftCharacter == "," else { return nil }
        let leftComma = input.index(before, offsetBy: -1)
        return (leftComma..<afterComma, " ")
    }
}
