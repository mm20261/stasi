import Foundation
import XCTest
@testable import Stasi

final class SpeechLifecyclePolicyTests: XCTestCase {
    private actor CompletionGate {
        private var isOpen = false
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            isOpen = true
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    func testUnsupportedLocaleDoesNotFallBackToEnglish() {
        XCTAssertThrowsError(
            try SpeechLocaleResolution.resolve(
                requested: Locale(identifier: "fr-FR"),
                supportedEquivalent: nil
            )
        ) { error in
            guard case TranscriptionError.unsupportedLocale(let identifier) = error else {
                return XCTFail("Unerwarteter Fehler: \(error)")
            }
            XCTAssertEqual(identifier, "fr-FR")
        }
    }

    func testSupportedEquivalentBecomesResolvedLocale() throws {
        let resolved = try SpeechLocaleResolution.resolve(
            requested: Locale(identifier: "de-CH"),
            supportedEquivalent: Locale(identifier: "de-DE")
        )

        XCTAssertEqual(resolved.identifier, "de-DE")
    }

    func testLimiterBlocksWhenRetiredAnalyzerLimitIsReached() async throws {
        let limiter = SpeechRetirementLimiter(limit: 2)
        try await limiter.reserve()
        try await limiter.reserve()

        do {
            try await limiter.reserve()
            XCTFail("Ein dritter Retiree-Slot muss abgelehnt werden")
        } catch TranscriptionError.tooManyRetiredAnalyzers {
            // Erwartet.
        } catch {
            XCTFail("Unerwarteter Fehler: \(error)")
        }
    }

    func testSlotIsReleasedOnlyAfterFinalizeAndResultStreamEndNaturally() async throws {
        let limiter = SpeechRetirementLimiter(limit: 1)
        let finalizeGate = CompletionGate()
        let resultsGate = CompletionGate()
        try await limiter.reserve()

        let finalizeTask = Task {
            await finalizeGate.wait()
            return true
        }
        let resultsTask = Task { await resultsGate.wait() }
        let retirementTask = Task {
            await limiter.releaseAfterNaturalCompletion(
                finalizeTask: finalizeTask,
                resultsTask: resultsTask
            )
        }

        await finalizeGate.open()
        do {
            try await limiter.reserve()
            XCTFail("Der Slot darf bei offenem Resultstream nicht frei sein")
        } catch TranscriptionError.tooManyRetiredAnalyzers {
            // Erwartet.
        }

        await resultsGate.open()
        await retirementTask.value
        try await limiter.reserve()
    }
}
