import Foundation

/// Abschließende, sprachneutrale Text-Hygiene. Fügt bewusst keinen Punkt an.
enum TextTidy {
    private static let abkuerzungenOhneSatzende: Set<String> = [
        "z.b.", "z. b.", "usw.", "ca.", "bzw.", "dr.", "nr.", "vgl.", "s.",
        "abs.", "etc.", "e.g.", "i.e.", "mr.", "mrs.",
    ]

    static func tidy(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        text = replacingAll(in: text, pattern: "\\s+", template: " ")
        text = replacingAll(in: text, pattern: ",\\s*,(?:\\s*,)*", template: ",")
        text = replacingAll(in: text, pattern: "^\\s*,(?:\\s*,)*\\s*", template: "")
        text = replacingAll(in: text, pattern: "[ \\t]+([,.;:!?])", template: "$1")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return capitalizingSentenceStarts(text)
    }

    /// Alle Treffer werden einmal auf dem unveränderten Stand gesammelt und
    /// anschließend rückwärts angewandt (Regel 4).
    private static func replacingAll(in input: String, pattern: String,
                                     template: String,
                                     options: NSRegularExpression.Options = []) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return input
        }
        let fullRange = NSRange(input.startIndex..., in: input)
        let replacements = regex.matches(in: input, range: fullRange).compactMap { match -> (Range<String.Index>, String)? in
            guard let range = Range(match.range, in: input) else { return nil }
            let replacement = regex.replacementString(for: match, in: input,
                                                      offset: 0, template: template)
            return (range, replacement)
        }
        var output = input
        for (range, replacement) in replacements.reversed() {
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }

    private static func capitalizingSentenceStarts(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?:^|[.!?]\\s+)(\\p{L})"
        ) else { return input }
        let fullRange = NSRange(input.startIndex..., in: input)
        let replacements = regex.matches(in: input, range: fullRange).compactMap { match -> (Range<String.Index>, String)? in
            guard let range = Range(match.range(at: 1), in: input) else { return nil }
            guard isSentenceStart(in: input, at: range.lowerBound) else { return nil }
            guard !containsUppercaseAfterFirstLetter(in: input, startingAt: range.lowerBound) else {
                return nil
            }
            return (range, String(input[range]).uppercased())
        }
        var output = input
        for (range, replacement) in replacements.reversed() {
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }

    private static func isSentenceStart(in input: String, at letter: String.Index) -> Bool {
        var cursor = letter
        while cursor > input.startIndex {
            let previous = input.index(before: cursor)
            if input[previous].isWhitespace {
                cursor = previous
                continue
            }
            guard input[previous] == "." else { return true }
            return periodEndsSentence(in: input, at: previous)
        }
        return true
    }

    private static func periodEndsSentence(in input: String, at period: String.Index) -> Bool {
        let prefixEnd = input.index(after: period)
        let prefix = String(input[..<prefixEnd]).lowercased()
        if abkuerzungenOhneSatzende.contains(where: { abbreviation in
            guard prefix.hasSuffix(abbreviation) else { return false }
            let start = prefix.index(prefix.endIndex, offsetBy: -abbreviation.count)
            guard start > prefix.startIndex else { return true }
            let characterBefore = prefix[prefix.index(before: start)]
            return !characterBefore.isLetter && !characterBefore.isNumber
        }) {
            return false
        }

        var tokenStart = period
        while tokenStart > input.startIndex {
            let previous = input.index(before: tokenStart)
            guard !input[previous].isWhitespace else { break }
            tokenStart = previous
        }
        let tokenWithoutFinalPeriod = input[tokenStart..<period]
        let letterCount = tokenWithoutFinalPeriod.filter(\.isLetter).count
        return letterCount > 1 && !tokenWithoutFinalPeriod.contains(".")
    }

    private static func containsUppercaseAfterFirstLetter(
        in input: String,
        startingAt firstLetter: String.Index
    ) -> Bool {
        var index = input.index(after: firstLetter)
        while index < input.endIndex, input[index].isLetter {
            if input[index].isUppercase { return true }
            index = input.index(after: index)
        }
        return false
    }
}
