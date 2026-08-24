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
        let words = entries.map(\.matchSource).filter { !$0.isEmpty }
        // Kurze, prägnante Begriffe zuerst – maximale Wirkung pro Kontext-Token.
        let sorted = words.sorted { $0.count < $1.count }
        return Array(sorted.prefix(limit))
    }
}
