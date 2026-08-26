import Foundation

// MARK: - RecordingSource / Pill-Chrome (v4.1)
// Woher kommt die laufende Aufnahme? Die Pill zeigt ✕/✓ IMMER an –
// auch im gelockten Modus (Hands-free) lässt sich wie bei Wisper per Pill
// bestätigen (✓) oder verwerfen (✕).

enum RecordingSource: Equatable {
    case pushToTalk
    case handsFree
}

enum PillChrome {
    /// ✕ und ✓ immer klickbar (auch gelockt – Wispr-Stil).
    static func showsButtons(for source: RecordingSource) -> Bool {
        true
    }

    /// Panel-Breite: Buttons sind immer da.
    static func pillWidth(for source: RecordingSource, hasPartialText: Bool = false,
                          modelReady: Bool = true) -> CGFloat {
        if hasPartialText { return 320 }
        return modelReady ? 140 : 190
    }

    static func pillHeight(hasPartialText: Bool) -> CGFloat {
        hasPartialText ? 52 : 24
    }
}

// MARK: - Pegelbalken-Mapping (Mic-Popover, echter Live-Level)

enum MicLevelBars {
    static let minHeight: CGFloat = 2
    static let maxHeight: CGFloat = 14

    /// Level (0…1) + kleiner Balken-Jitter → Höhe 2…14 px.
    /// Stille = flach (2 px), laut = voller Ausschlag (14 px).
    static func height(level: Double, jitter: Double) -> CGFloat {
        let clamped = max(0, min(level, 1))
        let jittered = max(0, min(clamped + jitter * 0.15, 1))
        return minHeight + CGFloat(jittered) * (maxHeight - minHeight)
    }
}
