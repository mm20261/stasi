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
    /// Push-to-talk bleibt bis zu dieser Aufnahmedauer komplett unsichtbar.
    /// Hands-free ist ein bewusster Start und erscheint ohne Verzögerung.
    static let presentationDelay: TimeInterval = 0.25

    static func shouldShowRecording(source: RecordingSource,
                                    elapsed: TimeInterval) -> Bool {
        source == .handsFree || elapsed >= presentationDelay
    }

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
    static let minHeight: CGFloat = 4
    static let maxHeight: CGFloat = 20
    static let peakHoldDuration: TimeInterval = 0.15
    private static let fallResponse: CGFloat = 0.22

    /// Level (0…1) + kleiner Balken-Jitter → Gesamthöhe 4…20 px.
    /// Der View zentriert diese Höhe auf der Mittellinie, sodass jeder Balken
    /// gleich weit nach oben und unten wächst.
    static func height(level: Double, jitter: Double) -> CGFloat {
        let clamped = max(0, min(level, 1))
        let jittered = max(0, min(clamped + jitter * 0.15, 1))
        return minHeight + CGFloat(jittered) * (maxHeight - minHeight)
    }

    /// Schneller Anschlag, 150-ms-Peak-Hold, danach weicher exponentieller Fall.
    static func nextPeak(current: CGFloat, target: CGFloat,
                         holdUntil: TimeInterval, now: TimeInterval)
        -> (height: CGFloat, holdUntil: TimeInterval) {
        let boundedTarget = max(minHeight, min(target, maxHeight))
        if boundedTarget >= current {
            return (boundedTarget, now + peakHoldDuration)
        }
        guard now >= holdUntil else { return (current, holdUntil) }
        let falling = current + (boundedTarget - current) * fallResponse
        return (max(boundedTarget, falling), holdUntil)
    }

    /// Stille ist sichtbar, aber zurückgenommen; Peaks sind voll deckend.
    static func opacity(forHeight height: CGFloat) -> CGFloat {
        let progress = max(0, min((height - minHeight) / (maxHeight - minHeight), 1))
        return 0.35 + progress * 0.65
    }
}
