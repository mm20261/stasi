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

// MARK: - TranscriptionEngine
// Streaming-Transkription via macOS-26-SpeechAnalyzer/SpeechTranscriber –
// als EIGENER actor, bewusst NICHT @MainActor: Die Speech-Maschinerie auf dem
// MainActor hat sich dort mit SwiftUI verheddert (Executor-Metadaten-
// Korruption, "Arbeit verschwindet"-Hänger). Auf dem eigenen Executor läuft
// sie isoliert auf dem eigenen Executor.
actor TranscriptionEngine {
    private let locale: Locale
    private let biasWords: [String]

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// Von der Engine festgeschriebener Text; volatile Ergebnisse werden nur
    /// zur Anzeige angehängt, nie gespeichert.
    private var finalizedText = ""

    init(locale: Locale, biasWords: [String] = []) {
        self.locale = locale
        // Kurze Liste – lange Kontextlisten lassen die Modelle driften.
        self.biasWords = Array(biasWords.prefix(12))
    }

    /// Wunschformat der Engine – AudioCapture konvertiert dorthin.
    func preferredInputFormat() async -> AVAudioFormat? {
        let module = transcriber ?? Self.makeTranscriber(locale: locale)
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
    }

    /// Modelle vorbereiten, Session öffnen. Liefert Transkript-Schnappschüsse
    /// bis `finish()` gerufen wird.
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.engineUnavailable
        }

        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            ?? Locale(identifier: "en-US")

        let transcriber = Self.makeTranscriber(locale: resolved)
        self.transcriber = transcriber

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

        let (chunks, chunkContinuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()

        // Ergebnis-Strom in unseren einfacheren Chunk-Strom umleiten.
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    let snapshot = await self.absorb(result)
                    chunkContinuation.yield(TranscriptionChunk(text: snapshot, isFinal: false))
                }
                let final = await self?.finalizedText ?? ""
                chunkContinuation.yield(TranscriptionChunk(text: final, isFinal: true))
                chunkContinuation.finish()
            } catch {
                DebugLog.log("STASI-SPEECH: Ergebnis-Strom Fehler: \(error.localizedDescription)")
                chunkContinuation.finish(throwing: error)
            }
        }

        try await analyzer.start(inputSequence: inputStream)
        DebugLog.log("STASI-SPEECH: SpeechAnalyzer läuft (\(resolved.identifier))")
        return chunks
    }

    /// Einen Audio-Puffer (bereits im `preferredInputFormat`) einspeisen.
    func feed(_ chunk: AudioChunk) {
        inputContinuation?.yield(AnalyzerInput(buffer: chunk.buffer))
    }

    /// Session schließen, ausstehende finale Ergebnisse flushen.
    func finish() async {
        inputContinuation?.finish()
        inputContinuation = nil

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            DebugLog.log("STASI-SPEECH: finalize fehlgeschlagen: \(error.localizedDescription)")
            await analyzer?.cancelAndFinishNow()
        }

        analyzer = nil
        transcriber = nil
        resultsTask = nil
    }

    // MARK: Ergebnis-Akkumulation

    private func absorb(_ result: SpeechTranscriber.Result) -> String {
        let text = String(result.text.characters)
        guard result.isFinal else {
            return (finalizedText + text).trimmingCharacters(in: .whitespaces)
        }
        finalizedText += text
        return finalizedText.trimmingCharacters(in: .whitespaces)
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

enum TranscriptionError: LocalizedError {
    case engineUnavailable
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "SpeechTranscriber ist auf diesem Gerät nicht verfügbar."
        case .noAudioFormat:
            return "Kein kompatibles Audio-Format für die Speech-Engine."
        }
    }
}
