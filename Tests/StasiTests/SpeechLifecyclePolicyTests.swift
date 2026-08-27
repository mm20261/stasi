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
            try SpeechLocaleResolution.appleResolvedLocale(
                requested: Locale(identifier: "fr-FR"),
                appleEquivalent: nil
            )
        ) { error in
            guard case TranscriptionError.unsupportedLocale(let identifier) = error else {
                return XCTFail("Unerwarteter Fehler: \(error)")
            }
            XCTAssertEqual(identifier, "fr-FR")
        }
    }

    func testSupportedEquivalentBecomesResolvedLocale() throws {
        let resolved = try SpeechLocaleResolution.appleResolvedLocale(
            requested: Locale(identifier: "de-CH"),
            appleEquivalent: Locale(identifier: "de-DE")
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

    func testStartFailureRunsFinalizeAndHoldsSlotWhenResultsEndFirst() async throws {
        let limiter = SpeechRetirementLimiter(limit: 1)
        let finalizeGate = CompletionGate()
        let resultsGate = CompletionGate()
        try await limiter.reserve()

        let (finalizeStarted, finalizeStartedContinuation) = AsyncStream<Bool>.makeStream()
        var finalizeStartedIterator = finalizeStarted.makeAsyncIterator()
        let resultsTask = Task { await resultsGate.wait() }
        let tasks = SpeechRetirementTasks.afterStartFailure(
            resultsTask: resultsTask
        ) {
            finalizeStartedContinuation.yield(true)
            finalizeStartedContinuation.finish()
            await finalizeGate.wait()
            return true
        }
        let retirementTask = Task {
            await limiter.releaseAfterNaturalCompletion(
                finalizeTask: tasks.finalizeTask,
                resultsTask: tasks.resultsTask
            )
        }

        let didStartFinalize = await finalizeStartedIterator.next()
        XCTAssertEqual(didStartFinalize, true, "Der echte Finalize-Vorgang muss laufen")

        await resultsGate.open()
        do {
            try await limiter.reserve()
            XCTFail("Der Slot darf bei noch laufendem Finalize nicht frei sein")
        } catch TranscriptionError.tooManyRetiredAnalyzers {
            // Erwartet.
        }

        await finalizeGate.open()
        await retirementTask.value
        try await limiter.reserve()
    }
}
