import Foundation

// MARK: - Onboarding (v4: vier Schritte bei erstem Start)
// Willkommen → Befugnisse → Tastenkombination → Probediktat.

@MainActor
@Observable
final class OnboardingModel {
    static let totalSteps = 4

    private(set) var step: Int
    private(set) var isFinished = false

    init(step: Int = 1) {
        self.step = min(max(step, 1), Self.totalSteps)
    }

    func next() {
        step = min(step + 1, Self.totalSteps)
    }

    func back() {
        step = max(step - 1, 1)
    }

    func finish() {
        isFinished = true
    }

    /// Kopfzeile rechts: „AKTE WIRD ANGELEGT · n/4"
    static func progressLabel(step: Int) -> String {
        "AKTE WIRD ANGELEGT · \(step)/\(totalSteps)"
    }
}
