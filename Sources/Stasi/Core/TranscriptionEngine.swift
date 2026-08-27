import AVFoundation
import Foundation
import Speech

// MARK: - TranscriptionChunk
/// Momentaufnahme des laufenden Transkripts. `text` ist immer das GESAMTE
/// Transkript bis jetzt (kein Delta) – die Engine revidiert frühere Wörter.
struct TranscriptionChunk: Sendable {
    let text: String
    let isFinal: Bool
}

/// Schmale Speech-Schnittstelle für einen austauschbaren Session-Besitzer.
/// Der Produktions-Typ bleibt ein eigener actor; Tests verwenden Fakes.
protocol SpeechEngining: Sendable {
    func resolvedLocale(for requested: Locale) async throws -> Locale
    func preferredInputFormat() async -> AVAudioFormat?
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error>
    func feed(_ chunk: AudioChunk) async
    func finish() async
}

enum SpeechLocaleResolution {
    static func resolve(requested: Locale, supportedEquivalent: Locale?) throws -> Locale {
        guard let supportedEquivalent else {
            throw TranscriptionError.unsupportedLocale(requested.identifier)
        }
        return supportedEquivalent
    }
}

actor SpeechRetirementLimiter {
    private let limit: Int
    private var reservedSlots = 0

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    func reserve() throws {
        guard reservedSlots < limit else {
            throw TranscriptionError.tooManyRetiredAnalyzers
        }
        reservedSlots += 1
    }

    func release() {
        guard reservedSlots > 0 else { return }
        reservedSlots -= 1
    }

    func releaseAfterNaturalCompletion(
        finalizeTask: Task<Bool, Never>,
        resultsTask: Task<Void, Never>?
    ) async {
        _ = await finalizeTask.value
        await resultsTask?.value
        release()
    }
}

// MARK: - TranscriptionEngine
// Streaming-Transkription via macOS-26-SpeechAnalyzer/SpeechTranscriber –
// als EIGENER actor, bewusst NICHT @MainActor: Die Speech-Maschinerie auf dem
// MainActor hat sich dort mit SwiftUI verheddert (Executor-Metadaten-
// Korruption, "Arbeit verschwindet"-Hänger). Auf dem eigenen Executor läuft
// sie isoliert auf dem eigenen Executor.
actor TranscriptionEngine: SpeechEngining {
    private static let retirementLimiter = SpeechRetirementLimiter(limit: 2)

    private struct RetiredAnalyzer {
        let id: UUID
        let analyzer: SpeechAnalyzer
        let transcriber: SpeechTranscriber
        let finalizeTask: Task<Bool, Never>
        let resultsTask: Task<Void, Never>?
    }

    private let locale: Locale
    private let biasWords: [String]

    private var actualLocale: Locale?
    private var ownsRetirementSlot = false
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var outputContinuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var didFinish = false
    private var retiredAnalyzers: [RetiredAnalyzer] = []

    /// Von der Engine festgeschriebener Text; volatile Ergebnisse werden nur
    /// zur Anzeige angehängt, nie gespeichert.
    private var finalizedText = ""
    /// Letzter sichtbarer Stand inklusive volatilem Ergebnis. Bei einem
    /// Finalize-Timeout ist dies der bestmögliche Rückgabewert.
    private var latestText = ""

    init(locale: Locale, biasWords: [String] = []) {
        self.locale = locale
        // Kurze Liste – lange Kontextlisten lassen die Modelle driften.
        self.biasWords = Array(biasWords.prefix(12))
    }

    /// Öffentliche Vorbereitungs-Fassade für AppState. Erzeugt keine Session
    /// und lädt ausschließlich das zur Locale passende Apple-Sprachmodell.
    static func ensureModelInstalled(locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.engineUnavailable
        }
        let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        let resolved = try SpeechLocaleResolution.resolve(
            requested: locale,
            supportedEquivalent: equivalent
        )
        try await ensureModelInstalled(for: makeTranscriber(locale: resolved))
    }

    func resolvedLocale(for requested: Locale) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.engineUnavailable
        }
        if requested.identifier == locale.identifier, let actualLocale {
            return actualLocale
        }
        let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: requested)
        let resolved = try SpeechLocaleResolution.resolve(
            requested: requested,
            supportedEquivalent: equivalent
        )
        if requested.identifier == locale.identifier {
            actualLocale = resolved
        }
        return resolved
    }

    /// Wunschformat der Engine – AudioCapture konvertiert dorthin.
    func preferredInputFormat() async -> AVAudioFormat? {
        let module = transcriber ?? Self.makeTranscriber(locale: actualLocale ?? locale)
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
    }

    /// Modelle vorbereiten, Session öffnen. Liefert Transkript-Schnappschüsse
    /// bis `finish()` gerufen wird.
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.engineUnavailable
        }

        let resolved = try await resolvedLocale(for: locale)
        try await Self.retirementLimiter.reserve()
        ownsRetirementSlot = true

        let transcriber = Self.makeTranscriber(locale: resolved)
        self.transcriber = transcriber

        do {
            try await Self.ensureModelInstalled(for: transcriber)

            let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.inputContinuation = inputContinuation

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            if !biasWords.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = biasWords
                try? await analyzer.setContext(context)
            }
            finalizedText = ""
            latestText = ""
            didFinish = false

            let (chunks, chunkContinuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
            outputContinuation = chunkContinuation

            // Ergebnis-Strom in unseren einfacheren Chunk-Strom umleiten.
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { break }
                        let snapshot = await self.absorb(result)
                        await self.publish(snapshot)
                    }
                    await self?.finishOutput()
                } catch {
                    DebugLog.log("STASI-SPEECH: Ergebnis-Strom Fehler: \(error.localizedDescription)")
                    await self?.finishOutput(throwing: error)
                }
            }

            do {
                try await analyzer.start(inputSequence: inputStream)
            } catch {
                inputContinuation.finish()
                self.inputContinuation = nil
                finishOutput(throwing: error)
                let resultsTask = self.resultsTask
                self.analyzer = nil
                self.transcriber = nil
                self.resultsTask = nil
                retire(
                    analyzer: analyzer,
                    transcriber: transcriber,
                    finalizeTask: Task { true },
                    resultsTask: resultsTask
                )
                throw error
            }
            DebugLog.log("STASI-SPEECH: SpeechAnalyzer läuft (\(resolved.identifier))")
            return chunks
        } catch {
            if ownsRetirementSlot {
                await releaseRetirementSlot()
            }
            self.transcriber = nil
            throw error
        }
    }

    /// Einen Audio-Puffer (bereits im `preferredInputFormat`) einspeisen.
    func feed(_ chunk: AudioChunk) {
        inputContinuation?.yield(AnalyzerInput(buffer: chunk.buffer))
    }

    /// Session schließen, ausstehende finale Ergebnisse flushen.
    func finish() async {
        if didFinish { return }
        if let finishTask {
            await finishTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFinish()
        }
        finishTask = task
        await task.value
        finishTask = nil
        didFinish = true
    }

    private func performFinish() async {
        inputContinuation?.finish()
        inputContinuation = nil

        guard let analyzer, let transcriber else {
            finishOutput()
            if ownsRetirementSlot {
                await releaseRetirementSlot()
            }
            return
        }

        // Alle Speech-Objekte VOR dem await lokal capturen. Dieser
        // unstrukturierte Task entsteht aus dem actor und läuft weiter, wenn
        // unser 3-s-Wartefenster endet. Er wird ausdrücklich nie gecancelt.
        let resultsTask = self.resultsTask
        let finalizeTask = Task { () -> Bool in
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                return true
            } catch {
                DebugLog.log("STASI-SPEECH: finalize fehlgeschlagen: \(error.localizedDescription)")
                return false
            }
        }

        let completed = await Self.waitForFinalize(finalizeTask)
        let succeeded = completed ? await finalizeTask.value : false

        self.analyzer = nil
        self.transcriber = nil
        self.resultsTask = nil

        guard completed && succeeded else {
            if completed {
                DebugLog.log("STASI-SPEECH: finalize beendet mit Fehler – nutze Text-Stand")
            } else {
                DebugLog.log("STASI-SPEECH: finalize Timeout nach 3 s – nutze Text-Stand")
            }
            finishOutput()
            retire(analyzer: analyzer,
                   transcriber: transcriber,
                   finalizeTask: finalizeTask,
                   resultsTask: resultsTask)
            return
        }

        // Finalize war erfolgreich, aber Apples Ergebnis-Strom kann bei sehr
        // kurzen Aufnahmen ohne Resultat offen bleiben. Letzte Resultate kurz
        // abwarten, dann unseren Ausgabe-Strom garantiert schließen. Der
        // resultsTask wird ausdrücklich nicht gecancelt.
        let resultsCompleted: Bool
        if let resultsTask {
            resultsCompleted = await Self.waitForFinalize(
                resultsTask,
                timeoutNanoseconds: 1_000_000_000
            )
        } else {
            resultsCompleted = true
        }
        finishOutput()
        if !resultsCompleted {
            DebugLog.log("STASI-SPEECH: Ergebnis-Strom nach 1 s noch offen – Ausgabe beendet")
            retire(analyzer: analyzer,
                   transcriber: transcriber,
                   finalizeTask: finalizeTask,
                   resultsTask: resultsTask)
        } else {
            await releaseRetirementSlot()
        }
    }

    /// First-wins-Rennen ohne TaskGroup: Ein nicht-kooperativer Task darf den
    /// Scope nach dem Timeout nicht festhalten und wird niemals gecancelt.
    nonisolated static func waitForFinalize<T: Sendable>(
        _ finalizeTask: Task<T, Never>,
        timeoutNanoseconds: UInt64 = 3_000_000_000
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let first = FirstWins(continuation)
            Task {
                _ = await finalizeTask.value
                first.resolve(true)
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                first.resolve(false)
            }
        }
    }

    // MARK: Ergebnis-Akkumulation

    private func absorb(_ result: SpeechTranscriber.Result) -> String {
        let text = String(result.text.characters)
        if result.isFinal {
            finalizedText += text
            latestText = finalizedText.trimmingCharacters(in: .whitespaces)
        } else {
            latestText = (finalizedText + text).trimmingCharacters(in: .whitespaces)
        }
        return latestText
    }

    private func publish(_ text: String) {
        outputContinuation?.yield(TranscriptionChunk(text: text, isFinal: false))
    }

    private func finishOutput(throwing error: Error? = nil) {
        guard let outputContinuation else { return }
        if let error {
            outputContinuation.finish(throwing: error)
        } else {
            outputContinuation.yield(TranscriptionChunk(text: latestText, isFinal: true))
            outputContinuation.finish()
        }
        self.outputContinuation = nil
    }

    private func retire(analyzer: SpeechAnalyzer,
                        transcriber: SpeechTranscriber,
                        finalizeTask: Task<Bool, Never>,
                        resultsTask: Task<Void, Never>?) {
        guard ownsRetirementSlot else { return }
        ownsRetirementSlot = false
        let id = UUID()
        retiredAnalyzers.append(
            RetiredAnalyzer(id: id,
                            analyzer: analyzer,
                            transcriber: transcriber,
                            finalizeTask: finalizeTask,
                            resultsTask: resultsTask)
        )
        // Der Task hält diesen Engine-actor absichtlich stark: Nach dem
        // Session-Ende gäbe es sonst keinen Besitzer mehr für die Retirees.
        Task { [self] in
            await Self.retirementLimiter.releaseAfterNaturalCompletion(
                finalizeTask: finalizeTask,
                resultsTask: resultsTask
            )
            self.removeRetiredAnalyzer(id: id)
        }
    }

    private func releaseRetirementSlot() async {
        guard ownsRetirementSlot else { return }
        ownsRetirementSlot = false
        await Self.retirementLimiter.release()
    }

    private func removeRetiredAnalyzer(id: UUID) {
        retiredAnalyzers.removeAll { $0.id == id }
        DebugLog.log("STASI-SPEECH: ausgeruhter Analyzer freigegeben")
    }

    // MARK: Setup-Helfer

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // `.volatileResults` liefert Live-Text schon während des Sprechens.
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    private static func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let selected = transcriber.selectedLocales
        let alreadyThere = selected.allSatisfy { locale in
            installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        }
        guard !alreadyThere else { return }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            DebugLog.log("STASI-SPEECH: lade Sprachmodell…")
            try await request.downloadAndInstall()
            DebugLog.log("STASI-SPEECH: Sprachmodell installiert")
        }
    }
}

private final class FirstWins: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: Bool) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

enum TranscriptionError: LocalizedError {
    case engineUnavailable
    case noAudioFormat
    case unsupportedLocale(String)
    case tooManyRetiredAnalyzers

    var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "SpeechTranscriber ist auf diesem Gerät nicht verfügbar."
        case .noAudioFormat:
            return "Kein kompatibles Audio-Format für die Speech-Engine."
        case .unsupportedLocale(let identifier):
            return "Die Sprache „\(identifier)“ wird nicht unterstützt. Wähle in den Einstellungen eine unterstützte Sprache."
        case .tooManyRetiredAnalyzers:
            return "Zwei frühere Speech-Analyzer reagieren noch nicht. Bitte starte Stasi neu, bevor du weiter diktierst."
        }
    }
}
