import Foundation

// MARK: - BiasProvider
// Mechanik 1: Engine-VOR der Transkription mit Wörterbuch-Kontext füttern.
//
// Stand macOS 26: `SpeechTranscriber` bietet keine öffentliche Vocabulary-Biasing-
// Schnittstelle (anders als z. B. Googles speechContext). Dieser Layer bleibt als
// Hook bestehen:
//   · Falls Apple später Biasing liefert, ist die Anbindung vorbereitet.
//   · whisper.cpp (möglicher Fallback) unterstützt Initial-Prompt-Biasing nativ –
//     dort würde `vocabularyContext()` direkt als Prompt einfließen.
// Die garantierte Korrektur läuft unabhängig davon über CorrectionEngine.

protocol BiasingHook {
    /// Kurze, priorisierte Wortliste für den Engine-Kontext.
    /// Bewusst limitiert: langer Kontext lässt STT-Modelle bei leiser Audio-
    /// Eingabe driften und Wörter erfinden.
    func vocabularyContext(limit: Int) -> [String]
}

struct DictionaryBiaser: BiasingHook {
    let entries: [DictionaryEntry]

    func vocabularyContext(limit: Int = 12) -> [String] {
        var seen = Set<String>()
        let words = entries
            .filter { $0.type != .learned }
            .map(\.replacementTarget)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        // Kurze, prägnante Begriffe zuerst – maximale Wirkung pro Kontext-Token.
        // Bei gleicher Länge bleibt die Wörterbuch-Reihenfolge stabil.
        let sorted = words.enumerated().sorted {
            $0.element.count == $1.element.count
                ? $0.offset < $1.offset
                : $0.element.count < $1.element.count
        }.map(\.element)
        return Array(sorted.prefix(limit))
    }
}
