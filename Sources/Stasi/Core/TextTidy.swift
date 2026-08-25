import Foundation

/// Abschließende, sprachneutrale Text-Hygiene. Fügt bewusst keinen Punkt an.
enum TextTidy {
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
            return (range, String(input[range]).uppercased())
        }
        var output = input
        for (range, replacement) in replacements.reversed() {
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }
}
