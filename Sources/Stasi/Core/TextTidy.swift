import Foundation

/// Gemeinsame, sprachneutrale Normalisierung für alle Textregel-Pässe.
enum TextNormalizer {
    private static let whitespaceExpression = try! NSRegularExpression(pattern: "\\s+")
    private static let repeatedCommaExpression = try! NSRegularExpression(
        pattern: ",\\s*,(?:\\s*,)*"
    )
    private static let leadingCommaExpression = try! NSRegularExpression(
        pattern: "^\\s*,(?:\\s*,)*\\s*"
    )
    private static let punctuationWhitespaceExpression = try! NSRegularExpression(
        pattern: "[ \\t]+([,.;:!?])"
    )

    static func collapseWhitespace(_ input: String) -> String {
        replacingAll(in: input, expression: whitespaceExpression, template: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tightenPunctuation(_ input: String) -> String {
        var text = replacingAll(in: input, expression: repeatedCommaExpression, template: ",")
        text = replacingAll(in: text, expression: leadingCommaExpression, template: "")
        text = replacingAll(
            in: text,
            expression: punctuationWhitespaceExpression,
            template: "$1"
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Alle Treffer werden einmal gesammelt und anschließend rückwärts angewandt.
    static func replacingAll(in input: String,
                             expression regex: NSRegularExpression,
                             template: String) -> String {
        let fullRange = NSRange(input.startIndex..., in: input)
        let replacements = regex.matches(in: input, range: fullRange).compactMap {
            match -> (Range<String.Index>, String)? in
            guard let range = Range(match.range, in: input) else { return nil }
            let replacement = regex.replacementString(
                for: match,
                in: input,
                offset: 0,
                template: template
            )
            return (range, replacement)
        }
        var output = input
        for (range, replacement) in replacements.reversed() {
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }
}

/// Abschließende, sprachneutrale Text-Hygiene. Fügt bewusst keinen Punkt an.
enum TextTidy {
    private static let abkuerzungenOhneSatzende: Set<String> = [
        "z.b.", "z. b.", "usw.", "ca.", "bzw.", "dr.", "nr.", "vgl.", "s.",
        "abs.", "etc.", "e.g.", "i.e.", "mr.", "mrs.",
    ]
    private static let sentenceStartExpression = try! NSRegularExpression(
        pattern: "(?:^|[.!?]\\s+)(\\p{L})"
    )

    static func tidy(_ input: String) -> String {
        let text = TextNormalizer.tightenPunctuation(
            TextNormalizer.collapseWhitespace(input)
        )
        return capitalizingSentenceStarts(text)
    }

    private static func capitalizingSentenceStarts(_ input: String) -> String {
        let regex = sentenceStartExpression
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
