import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

// MARK: - AudioChunk
// Ein Puffer auf dem Weg vom Audio-Thread zur Speech-Engine. Die AUHAL rendert
// in einen wiederverwendeten, selbst allozierten Puffer. Deshalb wird hier
// IMMER ein eigener Puffer weitergereicht (Kopie oder das selbst allozierte
// Konvertierungs-Ergebnis).
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

private let auhalInputCallback: AURenderCallback = {
    refCon,
    actionFlags,
    timeStamp,
    _,
    frameCount,
    _ in
    let capture = Unmanaged<AudioCapture>.fromOpaque(refCon).takeUnretainedValue()
    return capture.renderInput(actionFlags: actionFlags,
                               timeStamp: timeStamp,
                               frameCount: frameCount)
}

// MARK: - AudioCapture (input-only AUHAL + WAV-Mitschrieb + VU-Level)
// Nimmt ueber eine eigene AUHAL auf, deren Output-Element deaktiviert bleibt.
// Das System-Ausgabegeraet wird dadurch weder geoeffnet noch neu konfiguriert.
// Der Input laeuft mit nativer Sample-Rate als Float32 non-interleaved und wird
// danach zum Wunschformat der Speech-Engine konvertiert.
final class AudioCapture: AudioCapturing, @unchecked Sendable {
    struct IOConfiguration: Equatable, Sendable {
        let inputEnabled: Bool
        let outputEnabled: Bool

        static let inputOnly = IOConfiguration(inputEnabled: true, outputEnabled: false)
    }

    /// Schmale Hardware-Naht fuer Dateilebenszyklus-Tests ohne Mikrofon/TCC.
    struct AudioUnitHooks {
        let configureInput: @Sendable (
            _ configuration: IOConfiguration,
            _ preferredMicUID: String?,
            _ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void
        ) throws -> AVAudioFormat
        let initialize: () throws -> Void
        let start: () throws -> Void
        let stop: () -> Void
        let uninitialize: () -> Void
        let dispose: () -> Void
    }

    private enum CaptureError: LocalizedError {
        case componentUnavailable
        case noInputDevice
        case invalidInputFormat
        case invalidMaximumFrames
        case audioUnit(operation: String, status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .componentUnavailable:
                return "Die input-only AUHAL ist nicht verfuegbar."
            case .noInputDevice:
                return "Kein Audio-Eingabegeraet verfuegbar."
            case .invalidInputFormat:
                return "Das Eingabeformat des Mikrofons ist ungueltig."
            case .invalidMaximumFrames:
                return "Die AUHAL meldet keine gueltige maximale Slice-Groesse."
            case let .audioUnit(operation, status):
                return "AudioUnit-Fehler bei \(operation) (OSStatus \(status))."
            }
        }
    }

    private static let inputElement: AudioUnitElement = 1
    private static let outputElement: AudioUnitElement = 0
    private static let requestedMaximumFrames: UInt32 = 4_096

    /// Pro Aufnahme neu erzeugt und nach stop() vollstaendig disposed. Output
    /// bleibt ueber den gesamten Lebenszyklus explizit deaktiviert.
    private nonisolated(unsafe) var audioUnit: AudioUnit?
    private nonisolated(unsafe) var inputBuffer: AVAudioPCMBuffer?
    private let audioUnitHooks: AudioUnitHooks?
    private var audioUnitPrepared = false
    private var audioUnitInitialized = false
    private var audioUnitStarted = false
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var outputFormat: AVAudioFormat?
    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    private let renderDiagnostics = RenderDiagnostics()
    private(set) var isRunning = false

    // WAV-Mitschrieb: ausschliesslich eigene Puffer, auf serialer Queue.
    private let writeQueue = DispatchQueue(label: "app.stasi.audio.write")
    // Zugriff ausschliesslich synchron/asynchron auf `writeQueue`.
    private nonisolated(unsafe) var outputFile: AVAudioFile?
    private var recordURL: URL?

    /// Nur fuer Verifikation des Dateilebenszyklus; liest ebenfalls auf der Queue.
    var hasOpenOutputFile: Bool { writeQueue.sync { outputFile != nil } }
    var hasConverter: Bool { converter != nil }

    // VU-Level: Render-Thread schreibt unter Lock, Main-Poll liest.
    private let lock = NSLock()
    private nonisolated(unsafe) var rawLevel: Double = 0
    var latestLevel: Double {
        lock.lock()
        defer { lock.unlock() }
        return rawLevel
    }

    init(audioUnitHooks: AudioUnitHooks? = nil) {
        self.audioUnitHooks = audioUnitHooks
    }

    func start(outputFormat: AVAudioFormat,
               recordTo url: URL?,
               preferredMicUID: String? = nil,
               onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws {
        guard !isRunning else { return }
        self.onBuffer = onBuffer
        self.outputFormat = outputFormat
        recordURL = url
        renderDiagnostics.reset()

        do {
            // Synchron VOR der Input-Konfiguration: Der erste Render-Puffer
            // darf bereits in eine vollstaendig geoeffnete WAV-Datei laufen.
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
            audioUnitPrepared = true
            let native: AVAudioFormat
            if let audioUnitHooks {
                native = try audioUnitHooks.configureInput(.inputOnly,
                                                           preferredMicUID,
                                                           sink)
            } else {
                native = try configureAUHAL(preferredMicUID: preferredMicUID)
            }

            converter = native == outputFormat ? nil : AVAudioConverter(from: native,
                                                                         to: outputFormat)
            if let audioUnitHooks {
                try audioUnitHooks.initialize()
            } else {
                try check(AudioUnitInitialize(try requireAudioUnit()), operation: "Initialize")
            }
            audioUnitInitialized = true

            if let audioUnitHooks {
                try audioUnitHooks.start()
            } else {
                try check(AudioOutputUnitStart(try requireAudioUnit()), operation: "Start")
            }
            audioUnitStarted = true
            isRunning = true
            DebugLog.log("STASI-AUDIO: Input-only AUHAL laeuft – Client \(native.sampleRate) Hz -> Engine \(outputFormat.sampleRate) Hz")
        } catch {
            teardownAudioUnit()
            closeOutputFile()
            converter = nil
            self.outputFormat = nil
            self.onBuffer = nil
            recordURL = nil
            isRunning = false
            throw error
        }
    }

    /// Stoppt und entsorgt nur die input-only AUHAL, laesst den Mitschrieb
    /// ausschreiben und liefert die Datei-URL.
    @discardableResult
    func stop() -> URL? {
        guard isRunning else { return nil }
        teardownAudioUnit()
        isRunning = false
        converter = nil
        outputFormat = nil
        onBuffer = nil
        lock.lock()
        rawLevel = 0
        lock.unlock()
        // Synchron NACH allen ausstehenden Writes: Bei Rueckkehr ist die Datei
        // garantiert geschlossen und kann sicher gelesen/exportiert werden.
        closeOutputFile()
        let url = recordURL
        recordURL = nil
        return url
    }

    // MARK: AUHAL-Konfiguration

    private func configureAUHAL(preferredMicUID: String?) throws -> AVAudioFormat {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw CaptureError.componentUnavailable
        }

        var instance: AudioUnit?
        try check(AudioComponentInstanceNew(component, &instance), operation: "Instanz erzeugen")
        guard let instance else { throw CaptureError.componentUnavailable }
        audioUnit = instance

        // Output zuerst abschalten, solange die Unit noch nicht initialisiert
        // ist. Danach ausschliesslich das Input-Element aktivieren.
        try setIOEnabled(IOConfiguration.inputOnly.outputEnabled,
                         scope: kAudioUnitScope_Output,
                         element: Self.outputElement,
                         operation: "Output deaktivieren")
        try setIOEnabled(IOConfiguration.inputOnly.inputEnabled,
                         scope: kAudioUnitScope_Input,
                         element: Self.inputElement,
                         operation: "Input aktivieren")

        guard let deviceID = MicrophoneScanner.inputDeviceID(preferredUID: preferredMicUID)
        else { throw CaptureError.noInputDevice }
        var selectedDevice = deviceID
        try setProperty(&selectedDevice,
                        id: kAudioOutputUnitProperty_CurrentDevice,
                        scope: kAudioUnitScope_Global,
                        element: Self.outputElement,
                        operation: "Eingabegeraet setzen")

        // Erst NACH der Geraetewahl lesen: Input/1 ist die Hardware-Seite des
        // Mikrofon-Busses, Output/1 die von AudioUnitRender gelieferte Client-Seite.
        let inputFormats = try Self.configureInputFormats(
            readHardwareFormat: { scope, element in
                var description = AudioStreamBasicDescription()
                var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                let status = AudioUnitGetProperty(instance,
                                                  kAudioUnitProperty_StreamFormat,
                                                  scope,
                                                  element,
                                                  &description,
                                                  &size)
                return (status, description)
            },
            setClientFormat: { description, scope, element in
                var mutableDescription = description
                return withUnsafePointer(to: &mutableDescription) { pointer in
                    AudioUnitSetProperty(instance,
                                         kAudioUnitProperty_StreamFormat,
                                         scope,
                                         element,
                                         pointer,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
                }
            }
        )
        let hardwareFormat = inputFormats.hardware
        let clientFormat = inputFormats.client

        let capacity = try Self.configureMaximumFrames(
            requested: Self.requestedMaximumFrames,
            set: { requested in
                var value = requested
                return withUnsafePointer(to: &value) { pointer in
                    AudioUnitSetProperty(instance,
                                         kAudioUnitProperty_MaximumFramesPerSlice,
                                         kAudioUnitScope_Global,
                                         Self.outputElement,
                                         pointer,
                                         UInt32(MemoryLayout<UInt32>.size))
                }
            },
            get: {
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                let status = AudioUnitGetProperty(instance,
                                                  kAudioUnitProperty_MaximumFramesPerSlice,
                                                  kAudioUnitScope_Global,
                                                  Self.outputElement,
                                                  &value,
                                                  &size)
                return (status, value)
            }
        )
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: clientFormat,
                                                 frameCapacity: capacity)
        else { throw CaptureError.invalidInputFormat }
        self.inputBuffer = inputBuffer

        var callback = AURenderCallbackStruct(
            inputProc: auhalInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try setProperty(&callback,
                        id: kAudioOutputUnitProperty_SetInputCallback,
                        scope: kAudioUnitScope_Global,
                        element: Self.outputElement,
                        operation: "Input-Callback setzen")

        DebugLog.log("STASI-AUDIO: AUHAL Input-Geraet \(deviceID), Output deaktiviert, "
                     + "Hardware \(hardwareFormat.sampleRate) Hz/\(hardwareFormat.channelCount) ch, "
                     + "Client \(clientFormat.sampleRate) Hz/\(clientFormat.channelCount) ch, "
                     + "MaximumFramesPerSlice \(capacity)")
        return clientFormat
    }

    /// Liest die Geraeteseite des AUHAL-Input-Busses und setzt dessen Client-Seite
    /// auf Float32 non-interleaved bei unveraenderter Hardware-Rate/Kanalzahl.
    /// Die Closures halten die Scope-/Formatwahl ohne echte AUHAL unit-testbar.
    static func configureInputFormats(
        readHardwareFormat: (
            _ scope: AudioUnitScope,
            _ element: AudioUnitElement
        ) -> (status: OSStatus, description: AudioStreamBasicDescription),
        setClientFormat: (
            _ description: AudioStreamBasicDescription,
            _ scope: AudioUnitScope,
            _ element: AudioUnitElement
        ) -> OSStatus
    ) throws -> (hardware: AVAudioFormat, client: AVAudioFormat) {
        let hardwareResult = readHardwareFormat(kAudioUnitScope_Input, inputElement)
        guard hardwareResult.status == noErr else {
            throw CaptureError.audioUnit(operation: "Natives Hardwareformat lesen",
                                         status: hardwareResult.status)
        }

        var hardwareDescription = hardwareResult.description
        guard let hardwareFormat = AVAudioFormat(streamDescription: &hardwareDescription),
              hardwareFormat.sampleRate > 0,
              hardwareFormat.channelCount > 0,
              let clientFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: hardwareFormat.sampleRate,
                                               channels: hardwareFormat.channelCount,
                                               interleaved: false)
        else { throw CaptureError.invalidInputFormat }

        let setStatus = setClientFormat(clientFormat.streamDescription.pointee,
                                        kAudioUnitScope_Output,
                                        inputElement)
        guard setStatus == noErr else {
            throw CaptureError.audioUnit(operation: "Float32-Clientformat setzen",
                                         status: setStatus)
        }
        return (hardwareFormat, clientFormat)
    }

    /// Setzt die Host-Garantie explizit, liest den effektiven Wert zurueck und
    /// dimensioniert den Render-Puffer fuer den groesseren der beiden Werte.
    /// Damit kann kein gueltiger AUHAL-Slice am lokalen Capacity-Guard scheitern.
    static func configureMaximumFrames(
        requested: UInt32,
        set: (_ requested: UInt32) -> OSStatus,
        get: () -> (status: OSStatus, value: UInt32)
    ) throws -> AVAudioFrameCount {
        guard requested > 0 else { throw CaptureError.invalidMaximumFrames }

        let setStatus = set(requested)
        guard setStatus == noErr else {
            throw CaptureError.audioUnit(operation: "MaximumFramesPerSlice setzen",
                                         status: setStatus)
        }

        let effective = get()
        guard effective.status == noErr else {
            throw CaptureError.audioUnit(operation: "MaximumFramesPerSlice lesen",
                                         status: effective.status)
        }
        guard effective.value > 0 else { throw CaptureError.invalidMaximumFrames }
        return AVAudioFrameCount(max(requested, effective.value))
    }

    private func setIOEnabled(_ enabled: Bool,
                              scope: AudioUnitScope,
                              element: AudioUnitElement,
                              operation: String) throws {
        var value: UInt32 = enabled ? 1 : 0
        try setProperty(&value,
                        id: kAudioOutputUnitProperty_EnableIO,
                        scope: scope,
                        element: element,
                        operation: operation)
    }

    private func setProperty<T>(_ value: inout T,
                                id: AudioUnitPropertyID,
                                scope: AudioUnitScope,
                                element: AudioUnitElement,
                                operation: String) throws {
        let unit = try requireAudioUnit()
        let status = withUnsafePointer(to: &value) { pointer in
            AudioUnitSetProperty(unit,
                                 id,
                                 scope,
                                 element,
                                 pointer,
                                 UInt32(MemoryLayout<T>.size))
        }
        try check(status, operation: operation)
    }

    private func requireAudioUnit() throws -> AudioUnit {
        guard let audioUnit else { throw CaptureError.componentUnavailable }
        return audioUnit
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw CaptureError.audioUnit(operation: operation, status: status)
        }
    }

    /// Reihenfolge ist strikt: stop -> uninitialize -> dispose. Erst danach
    /// duerfen der Render-Puffer und die Unit-Referenz freigegeben werden.
    private func teardownAudioUnit() {
        if audioUnitStarted {
            if let audioUnitHooks {
                audioUnitHooks.stop()
            } else if let audioUnit {
                AudioOutputUnitStop(audioUnit)
            }
        }
        audioUnitStarted = false

        if audioUnitInitialized {
            if let audioUnitHooks {
                audioUnitHooks.uninitialize()
            } else if let audioUnit {
                AudioUnitUninitialize(audioUnit)
            }
        }
        audioUnitInitialized = false

        if audioUnitPrepared {
            if let audioUnitHooks {
                audioUnitHooks.dispose()
            } else if let audioUnit {
                AudioComponentInstanceDispose(audioUnit)
            }
        }
        audioUnitPrepared = false
        inputBuffer = nil
        audioUnit = nil
    }

    // MARK: Audio-Thread

    nonisolated fileprivate func renderInput(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard let audioUnit, let inputBuffer else {
            let status = kAudio_ParamError
            renderDiagnostics.logFirstCallback(frameCount: frameCount, status: status)
            renderDiagnostics.logFailureOnce(
                .missingResources,
                status: status,
                details: "AudioUnit oder Render-Puffer fehlt"
            )
            return status
        }

        let preparationStatus = Self.prepareRenderBuffer(inputBuffer,
                                                         frameCount: frameCount)
        guard preparationStatus == noErr else {
            renderDiagnostics.logFirstCallback(frameCount: frameCount,
                                               status: preparationStatus)
            renderDiagnostics.logFailureOnce(
                .invalidBuffer,
                status: preparationStatus,
                details: "frames=\(frameCount), capacity=\(inputBuffer.frameCapacity)"
            )
            return preparationStatus
        }

        let status = AudioUnitRender(audioUnit,
                                     actionFlags,
                                     timeStamp,
                                     Self.inputElement,
                                     frameCount,
                                     inputBuffer.mutableAudioBufferList)
        renderDiagnostics.logFirstCallback(frameCount: frameCount, status: status)
        guard status == noErr else {
            renderDiagnostics.logFailureOnce(
                .audioUnitRender,
                status: status,
                details: "frames=\(frameCount)"
            )
            return status
        }
        handle(inputBuffer)
        return noErr
    }

    /// Stellt die von AudioUnitRender erwartete ABL-Topologie fuer den aktuellen
    /// non-interleaved Float32-Slice explizit wieder her. AVAudioPCMBuffer setzt
    /// diese Werte mit frameLength ebenfalls; die explizite Validierung verhindert
    /// jedoch, dass ein inkonsistenter oder zu grosser Slice still verschwindet.
    nonisolated static func prepareRenderBuffer(
        _ buffer: AVAudioPCMBuffer,
        frameCount: UInt32
    ) -> OSStatus {
        guard frameCount > 0,
              frameCount <= buffer.frameCapacity,
              buffer.format.commonFormat == .pcmFormatFloat32,
              !buffer.format.isInterleaved
        else { return kAudio_ParamError }

        let channelCount = UInt32(buffer.format.channelCount)
        let bytesPerFrame = buffer.format.streamDescription.pointee.mBytesPerFrame
        let (byteCount, overflow) = frameCount.multipliedReportingOverflow(by: bytesPerFrame)
        guard channelCount > 0, bytesPerFrame > 0, !overflow else {
            return kAudio_ParamError
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let list = buffer.mutableAudioBufferList
        guard list.pointee.mNumberBuffers == channelCount else {
            return kAudio_ParamError
        }
        list.pointee.mNumberBuffers = channelCount
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.count == Int(channelCount) else { return kAudio_ParamError }
        for index in buffers.indices {
            guard buffers[index].mData != nil else { return kAudio_ParamError }
            buffers[index].mNumberChannels = 1
            buffers[index].mDataByteSize = byteCount
        }
        return noErr
    }

    nonisolated private func handle(_ buffer: AVAudioPCMBuffer) {
        let level = Self.computeLevel(of: buffer)
        lock.lock()
        rawLevel = level
        lock.unlock()

        guard let outputFormat else { return }

        let owned: AVAudioPCMBuffer?
        if let converter {
            // Ziel-Framezahl skaliert mit dem Sample-Raten-Verhaeltnis; aufrunden.
            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                   frameCapacity: capacity) else { return }
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

    private func closeOutputFile() {
        writeQueue.sync { outputFile = nil }
    }

    /// Deep-Copy eines Render-Puffers in eigenen Speicher.
    nonisolated static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                          frameCapacity: buffer.frameLength)
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

    private final class RenderDiagnostics: @unchecked Sendable {
        enum Failure: Hashable {
            case missingResources
            case invalidBuffer
            case audioUnitRender
        }

        private let lock = NSLock()
        private var loggedFirstCallback = false
        private var loggedFailures = Set<Failure>()

        func reset() {
            lock.lock()
            loggedFirstCallback = false
            loggedFailures.removeAll(keepingCapacity: true)
            lock.unlock()
        }

        func logFirstCallback(frameCount: UInt32, status: OSStatus) {
            lock.lock()
            let shouldLog = !loggedFirstCallback
            loggedFirstCallback = true
            lock.unlock()
            guard shouldLog else { return }
            DebugLog.log("STASI-AUDIO: Erster Input-Callback – frameCount \(frameCount), "
                         + "AudioUnitRender OSStatus \(status)")
        }

        func logFailureOnce(_ failure: Failure, status: OSStatus, details: String) {
            lock.lock()
            let shouldLog = loggedFailures.insert(failure).inserted
            lock.unlock()
            guard shouldLog else { return }
            DebugLog.log("STASI-AUDIO: Render-Fehler \(failure) – OSStatus \(status), \(details)")
        }
    }

    /// RMS -> normalisierter Pegel (0...1). Die steile Kurve macht leise Sprache
    /// sichtbar und legt Zimmerlautstaerke auf etwa 80-95 % des Bereichs.
    nonisolated static func computeLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in stride(from: 0, to: frames, by: 4) {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(frames / 4 + 1))
        return Double(pow(min(rms * 25.0, 1.0), 0.4))
    }
}
