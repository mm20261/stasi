import XCTest
import AVFoundation
import Speech
@testable import Stasi

// MARK: - TranscriptionEngine-Pipeline-Stresstest
// Stellt den exakten Release-Pfad nach: start → Chunks füttern → finish.
// Mit synthetischen Buffers (kein Mikrofon nötig) und echter on-device Engine.

final class TranscriptionPipelineTests: XCTestCase {

    /// Diese Suite braucht einen App-ähnlichen Prozess mit erteilter
    /// Sprach-Berechtigung. Headless (xctest) trappet Apples Worker.
    /// Manuell: STASI_PIPELINE_E2E=1
    private func skipUnlessE2E() throws {
        if ProcessInfo.processInfo.environment["STASI_PIPELINE_E2E"] != "1" {
            throw XCTSkip("Headless ohne TCC-Consent – Apples Worker trapt. Mit STASI_PIPELINE_E2E=1 in App-Kontext ausführen.")
        }
    }

    /// Synthetischer "Sprach"-Buffer IM Wunschformat der Engine
    /// (Format-Mismatch – z. B. Float32 statt Int16 – lässt Apples Worker trappen!)
    private func speechLikeBuffer(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func noise() -> Double { // schneller xorshift-PRNG
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 10000) / 10000.0 - 0.5
        }
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // Sprachähnlich: Silben-Envelope (~4 Hz), Formant-Frequenzwechsel,
            // Rauschen, Pausen alle ~0,4 s – KEIN degenerierter reiner Sinus.
            let syllable = 0.5 + 0.5 * sin(2 * .pi * 4 * t)
            let pause = sin(2 * .pi * 1.2 * t) > -0.6 ? 1.0 : 0.05
            let carrier = sin(2 * .pi * (160 + 90 * sin(2 * .pi * 0.8 * t)) * t)
            let value = (0.35 * syllable * pause * carrier) + 0.08 * noise()
            if let f32 = buffer.floatChannelData {
                f32[0][i] = Float(value)
            } else if let i16 = buffer.int16ChannelData {
                i16[0][i] = Int16(max(-1, min(1, value)) * 32767)
            }
        }
        return buffer
    }

    /// Eine komplette Diktat-Runde gegen die echte Engine.
    /// Kein Text-Assert (Synthetik ergibt keinen sinnvollen Text) – es geht darum,
    /// dass start/feed/finish OHNE Crash/Hang durchlaufen und sauber aufräumen.
    private func runOneDictationRound(locale: Locale, bias: [String]) async throws {
        let engine = TranscriptionEngine(locale: locale, biasWords: bias)
        let chunks = try await engine.start()
        guard let format = await engine.preferredInputFormat() else {
            throw XCTSkip("Kein Engine-Audio-Format verfügbar")
        }

        let consume = Task {
            var count = 0
            do {
                for try await _ in chunks { count += 1 }
            } catch {}
            return count
        }

        // 2 Sekunden "Audio" in ~85-ms-Blöcken im Engine-Format füttern,
        // in Echtzeit-Takt (wie der AVAudioEngine-Tap es liefert)
        let buffer = speechLikeBuffer(seconds: 0.085, format: format)
        let blocks = Int(2.0 / 0.085)
        for _ in 0..<blocks {
            await engine.feed(AudioChunk(buffer: buffer))
            try await Task.sleep(nanoseconds: 85_000_000)
        }

        await engine.finish()
        _ = await consume.value
    }

    func testSingleDictationRoundEnglish() async throws {
        try skipUnlessE2E()
        try await runOneDictationRound(locale: Locale(identifier: "en_US"),
                                       bias: ["Anthropic", "Claude Code"])
    }

    func testSingleDictationRoundGerman() async throws {
        try skipUnlessE2E()
        try await runOneDictationRound(locale: Locale(identifier: "de_DE"),
                                       bias: [])
    }

    /// 5 Runden hintereinander – genau das Szenario, in dem die GUI gecrasht ist.
    func testFiveConsecutiveRounds() async throws {
        try skipUnlessE2E()
        for round in 1...5 {
            try await runOneDictationRound(locale: Locale(identifier: "en_US"),
                                           bias: ["Testwort\(round)"])
        }
    }

    /// Sofortiges Stoppen (Release ohne Audio) – der "leere Diktat"-Pfad
    func testImmediateFinishWithoutFeeding() async throws {
        try skipUnlessE2E()
        let engine = TranscriptionEngine(locale: Locale(identifier: "en_US"))
        _ = try await engine.start()
        await engine.finish()
    }

    /// Finish ohne start darf nicht crashen
    func testFinishWithoutStart() async throws {
        let engine = TranscriptionEngine(locale: Locale(identifier: "en_US"))
        await engine.finish()
    }

    /// Biasing-Kontext: AnalysisContext nimmt unsere Wörter an
    func testAnalysisContextAcceptsVocabulary() async throws {
        let context = AnalysisContext()
        context.contextualStrings[.general] = ["Anthropic", "Vercel", "Supabase"]
        XCTAssertEqual(context.contextualStrings[.general]?.count, 3)
    }
}
