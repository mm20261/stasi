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

// MARK: - AudioCapture (Mikrofon-Capture + WAV-Mitschrieb + VU-Level)
// Nimmt im NATIVEN Mikrofon-Format auf und konvertiert zum Wunschformat der
// Engine (SpeechAnalyzer verlangt z. B. Int16 – Float32 füttern killt den
// Prozess mit einer harten Precondition).
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var outputFormat: AVAudioFormat?
    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    private(set) var isRunning = false

    // WAV-Mitschrieb: ausschließlich eigene Puffer, auf serialer Queue.
    private let writeQueue = DispatchQueue(label: "app.stasi.audio.write")
    private nonisolated(unsafe) var outputFile: AVAudioFile?
    private var recordURL: URL?

    // VU-Level: Render-Thread schreibt unter Lock, Main-Poll liest.
    private let lock = NSLock()
    private nonisolated(unsafe) var rawLevel: Double = 0
    var latestLevel: Double {
        lock.lock()
        defer { lock.unlock() }
        return rawLevel
    }

    func start(outputFormat: AVAudioFormat,
               recordTo url: URL?,
               onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws {
        guard !isRunning else { return }
        self.onBuffer = onBuffer
        self.outputFormat = outputFormat

        let input = engine.inputNode
        let native = input.outputFormat(forBus: 0)
        converter = native == outputFormat ? nil : AVAudioConverter(from: native, to: outputFormat)

        recordURL = url
        if let url {
            let file = try? AVAudioFile(
                forWriting: url,
                settings: outputFormat.settings,
                commonFormat: outputFormat.commonFormat,
                interleaved: outputFormat.isInterleaved
            )
            writeQueue.async { self.outputFile = file }
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: native) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
        DebugLog.log("STASI-AUDIO: Capture läuft – nativ \(native.sampleRate) Hz → Engine \(outputFormat.sampleRate) Hz")
    }

    /// Entfernt den Tap, lässt den Mitschrieb ausschreiben, liefert die Datei-URL.
    @discardableResult
    func stop() -> URL? {
        guard isRunning else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        converter = nil
        onBuffer = nil
        lock.lock()
        rawLevel = 0
        lock.unlock()
        // Läuft auf der seriellen Queue NACH allen ausstehenden Writes.
        writeQueue.async { self.outputFile = nil }
        let url = recordURL
        recordURL = nil
        return url
    }

    // MARK: Audio-Thread

    private func handle(_ buffer: AVAudioPCMBuffer) {
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

        if outputFile != nil {
            writeQueue.async { try? self.outputFile?.write(from: owned) }
        }
        onBuffer?(AudioChunk(buffer: owned))
    }

    /// Deep-Copy eines Tap-Puffers in eigenen Speicher.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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

    /// RMS → normalisierter Pegel (0…1). Höherer Gain + steilerer Exponent
    /// (0.6 statt 0.4) spreizt die Dynamik: leise bleibt klein, laut schlägt
    /// deutlich aus – damit die Waveform wirklich auf Lautstärke reagiert.
    nonisolated static func computeLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in stride(from: 0, to: frames, by: 4) {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(frames / 4 + 1))
        return Double(pow(min(rms * 7.0, 1.0), 0.6))
    }
}
