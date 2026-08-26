import AVFoundation
import Foundation

// MARK: - AudioChunk
// Ein Puffer auf dem Weg vom Audio-Thread zur Speech-Engine.
// AVAudioEngine RECYCELT den Tap-Puffer, sobald der Callback zurückkehrt –
// deshalb wird hier IMMER ein eigener Puffer weitergereicht (Kopie oder das
// selbst allozierte Konvertierungs-Ergebnis). Das Weiterreichen des
// geliehenen Tap-Puffers war Heap-Korruption.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Schmale Capture-Schnittstelle, damit der Session-Lebenszyklus ohne echte
/// Mikrofon-Hardware getestet werden kann.
protocol AudioCapturing: AnyObject, Sendable {
    var isRunning: Bool { get }
    var latestLevel: Double { get }

    func start(outputFormat: AVAudioFormat,
               recordTo url: URL?,
               preferredMicUID: String?,
               onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws

    @discardableResult
    func stop() -> URL?
}

// MARK: - AudioCapture (Mikrofon-Capture + WAV-Mitschrieb + VU-Level)
// Nimmt im NATIVEN Mikrofon-Format auf und konvertiert zum Wunschformat der
// Engine (SpeechAnalyzer verlangt z. B. Int16 – Float32 füttern killt den
// Prozess mit einer harten Precondition).
final class AudioCapture: AudioCapturing, @unchecked Sendable {
    /// Schmale Hardware-Naht für Dateilebenszyklus-Tests ohne Mikrofon/TCC.
    struct EngineHooks {
        let prepareInput: @Sendable (_ preferredMicUID: String?,
                                     _ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws -> AVAudioFormat
        let prepareEngine: () -> Void
        let startEngine: () throws -> Void
        let stopEngine: () -> Void
        let removeTap: () -> Void
    }

    private let engine = AVAudioEngine()
    private let engineHooks: EngineHooks?
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var outputFormat: AVAudioFormat?
    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    private(set) var isRunning = false

    // WAV-Mitschrieb: ausschließlich eigene Puffer, auf serialer Queue.
    private let writeQueue = DispatchQueue(label: "app.stasi.audio.write")
    // Zugriff ausschließlich synchron/asynchron auf `writeQueue`.
    private nonisolated(unsafe) var outputFile: AVAudioFile?
    private var recordURL: URL?

    /// Nur für Verifikation des Dateilebenszyklus; liest ebenfalls auf der Queue.
    var hasOpenOutputFile: Bool { writeQueue.sync { outputFile != nil } }

    // VU-Level: Render-Thread schreibt unter Lock, Main-Poll liest.
    private let lock = NSLock()
    private nonisolated(unsafe) var rawLevel: Double = 0
    var latestLevel: Double {
        lock.lock()
        defer { lock.unlock() }
        return rawLevel
    }

    init(engineHooks: EngineHooks? = nil) {
        self.engineHooks = engineHooks
    }

    func start(outputFormat: AVAudioFormat,
               recordTo url: URL?,
               preferredMicUID: String? = nil,
               onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws {
        guard !isRunning else { return }
        self.onBuffer = onBuffer
        self.outputFormat = outputFormat

        recordURL = url
        do {
            // Synchron VOR installTap: Der erste Tap-Puffer darf bereits in
            // eine vollständig geöffnete WAV-Datei geschrieben werden.
            if let url {
                try writeQueue.sync {
                    outputFile = try AVAudioFile(
                        forWriting: url,
                        settings: outputFormat.settings,
                        commonFormat: outputFormat.commonFormat,
                        interleaved: outputFormat.isInterleaved
                    )
                }
            }

            let sink: @Sendable (AVAudioPCMBuffer) -> Void = { [weak self] buffer in
                self?.handle(buffer)
            }
            let native: AVAudioFormat
            if let engineHooks {
                native = try engineHooks.prepareInput(preferredMicUID, sink)
            } else {
                let input = engine.inputNode
                // Wunsch-Gerät VOR dem Format-Holen setzen – andere Geräte
                // haben andere native Formate. Bei false läuft Standard weiter.
                let micApplied = MicrophoneScanner.apply(preferredMicUID, to: input)
                DebugLog.log("STASI-AUDIO: Mikrofon-Auswahl angewendet=\(micApplied)")
                native = input.outputFormat(forBus: 0)
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 2048, format: native) { buffer, _ in
                    sink(buffer)
                }
            }

            converter = native == outputFormat ? nil : AVAudioConverter(from: native, to: outputFormat)
            if let engineHooks {
                engineHooks.prepareEngine()
                try engineHooks.startEngine()
            } else {
                engine.prepare()
                try engine.start()
            }
            isRunning = true
            DebugLog.log("STASI-AUDIO: Capture läuft – nativ \(native.sampleRate) Hz → Engine \(outputFormat.sampleRate) Hz")
        } catch {
            removeInputTap()
            stopEngine()
            closeOutputFile()
            converter = nil
            self.outputFormat = nil
            self.onBuffer = nil
            recordURL = nil
            isRunning = false
            throw error
        }
    }

    /// Entfernt den Tap, lässt den Mitschrieb ausschreiben, liefert die Datei-URL.
    @discardableResult
    func stop() -> URL? {
        guard isRunning else { return nil }
        removeInputTap()
        stopEngine()
        isRunning = false
        converter = nil
        outputFormat = nil
        onBuffer = nil
        lock.lock()
        rawLevel = 0
        lock.unlock()
        // Synchron NACH allen ausstehenden Writes: Bei Rückkehr ist die Datei
        // garantiert geschlossen und kann sicher gelesen/exportiert werden.
        closeOutputFile()
        let url = recordURL
        recordURL = nil
        return url
    }

    // MARK: Audio-Thread

    nonisolated private func handle(_ buffer: AVAudioPCMBuffer) {
        let level = Self.computeLevel(of: buffer)
        lock.lock()
        rawLevel = level
        lock.unlock()

        guard let outputFormat else { return }

        let owned: AVAudioPCMBuffer?
        if let converter {
            // Ziel-Framezahl skaliert mit dem Sample-Raten-Verhältnis; aufrunden.
            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            nonisolated(unsafe) let input = buffer
            let consumed = Latch()
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                if consumed.take() {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                return input
            }
            guard error == nil, status != .error, converted.frameLength > 0 else { return }
            owned = converted
        } else {
            owned = Self.copy(buffer)
        }
        guard let owned else { return }

        let chunk = AudioChunk(buffer: owned)
        writeQueue.async {
            if let file = self.outputFile {
                try? file.write(from: chunk.buffer)
            }
        }
        onBuffer?(chunk)
    }

    private func removeInputTap() {
        if let engineHooks {
            engineHooks.removeTap()
        } else {
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    private func stopEngine() {
        if let engineHooks {
            engineHooks.stopEngine()
        } else {
            engine.stop()
        }
    }

    private func closeOutputFile() {
        writeQueue.sync { outputFile = nil }
    }

    /// Deep-Copy eines Tap-Puffers in eigenen Speicher.
    nonisolated static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return nil }

        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else {
            return nil
        }
        return copy
    }

    /// Einmal-Flag, nur vom Audio-Thread innerhalb eines synchronen Calls benutzt.
    private final class Latch: @unchecked Sendable {
        private var fired = false
        func take() -> Bool {
            defer { fired = true }
            return fired
        }
    }

    /// RMS → normalisierter Pegel (0…1). Zimmerlautstärke landet bewusst im
    /// oberen Mittelfeld; erst deutlich lautere Sprache nähert sich der Kappe.
    nonisolated static func computeLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in stride(from: 0, to: frames, by: 4) {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(frames / 4 + 1))
        return Double(pow(min(rms * 15.0, 1.0), 0.45))
    }
}
