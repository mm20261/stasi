import Foundation

// MARK: - Korrektur-Pass
// Garantierte Nachkorrektur des Transkripts:
//   · Whole-Word-Match (Unicode-Wortgrenzen)
//   · Case-insensitive
//   · Längste Quelle zuerst
//   · Flexible Trenner zwischen Wortteilen: "Claude Code" matcht
//     "CloudCode", "Cloud-Code", "cloud  code" usw.
//   · Wortgrenzen verhindern Kollisionen ("Claude Code" ↔ "Cloudflare")

struct AppliedCorrection: Identifiable, Codable, Equatable {
    var id = UUID()
    let entryID: UUID
    /// Quellmuster des Eintrags ("cloud code")
    let pattern: String
    /// Ersetzte Schreibweise ("Claude Code")
    let target: String
    /// Tatsächlich gefundene Textstelle im Roh-Transkript ("CloudCode")
    let matched: String
}

enum CorrectionEngine {
    static func correct(_ input: String, entries: [DictionaryEntry]) -> (text: String, applied: [AppliedCorrection]) {
        var text = input
        var applied: [AppliedCorrection] = []

        // Längste Quelle zuerst – spezifische Einträge gewinnen.
        let sorted = entries.sorted { $0.matchSource.count > $1.matchSource.count }

        for entry in sorted where !entry.matchSource.isEmpty && entry.type != .learned {
            guard let regex = regex(for: entry.matchSource) else { continue }
            let range = NSRange(text.startIndex..., in: text)

            // ALLE Matches EINMAL sammeln, dann von hinten ersetzen.
            // (Eine While-Schleife mit erneutem Suchen läuft endlos, wenn die
            //  Ersetzung selbst wieder matcht – z. B. "grüße" → "Grüße".)
            let matches = regex.matches(in: text, options: [], range: range)
            guard !matches.isEmpty else { continue }

            var matchedStrings: [String] = []
            for match in matches.reversed() {
                guard let r = Range(match.range(at: 0), in: text) else { continue }
                let matched = String(text[r])
                guard matched != entry.replacementTarget else { continue }
                matchedStrings.append(matched)
                text.replaceSubrange(r, with: entry.replacementTarget)
            }
            matchedStrings.reverse()
            guard !matchedStrings.isEmpty else { continue }

            applied.append(AppliedCorrection(
                entryID: entry.id,
                pattern: entry.matchSource,
                target: entry.replacementTarget,
                matched: matchedStrings.joined(separator: ", ")
            ))
        }
        return (text, applied)
    }

    /// Baut den Regex für eine Quelle:
    /// Teile werden zu Pattern mit optionalem Leerzeichen/Bindewort-Trenner dazwischen,
    /// umgeben von Unicode-Wortgrenzen (Lookarounds statt \b wegen Umlauten & Bindestrichen).
    private static func regex(for source: String) -> NSRegularExpression? {
        let parts = source.split(whereSeparator: { $0 == " " })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !parts.isEmpty else { return nil }
        // Trenner zwischen Teilen: 0–2 Zeichen (Leerzeichen/Tab/Bindestrich) –
        // 0 = zusammengeklebte Form ("CloudCode"), 1–2 = getrennte Formen.
        let joined = parts.joined(separator: "[ \\t\\-\u{2011}]{0,2}")
        let boundary = "(?<![\\p{L}\\p{N}\\p{M}\\-_])"
        let endBoundary = "(?![\\p{L}\\p{N}\\p{M}\\-_])"
        return try? NSRegularExpression(
            pattern: "\(boundary)\(joined)\(endBoundary)",
            options: [.caseInsensitive]
        )
    }
}
