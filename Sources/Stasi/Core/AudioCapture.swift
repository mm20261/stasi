import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Synchronization

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
typealias AudioCaptureFactory = @MainActor () -> any AudioCapturing
typealias AudioConverterFactory =
    @Sendable (AVAudioFormat, AVAudioFormat) -> AVAudioConverter?

enum AudioCaptureRuntimeError: Equatable, Sendable {
    case renderFailed(OSStatus)
    case bufferCopyFailed
    case conversionFailed(String)
    case wavWriteFailed(String)
    case processingBacklog
}

enum AudioCaptureError: LocalizedError {
    case alreadyRunning
    case componentUnavailable
    case noInputDevice
    case invalidInputFormat
    case invalidMaximumFrames
    case converterUnavailable(input: AVAudioFormat, output: AVAudioFormat)
    case audioUnit(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Die Audioaufnahme läuft bereits."
        case .componentUnavailable:
            return "Die input-only AUHAL ist nicht verfuegbar."
        case .noInputDevice:
            return "Kein Audio-Eingabegeraet verfuegbar."
        case .invalidInputFormat:
            return "Das Eingabeformat des Mikrofons ist ungueltig."
        case .invalidMaximumFrames:
            return "Die AUHAL meldet keine gueltige maximale Slice-Groesse."
        case let .converterUnavailable(input, output):
            return "Audiokonvertierung nicht verfuegbar (\(input.sampleRate) Hz/"
                + "\(input.channelCount) ch -> \(output.sampleRate) Hz/"
                + "\(output.channelCount) ch)."
        case let .audioUnit(operation, status):
            return "AudioUnit-Fehler bei \(operation) (OSStatus \(status))."
        }
    }
}

protocol AudioCapturing: AnyObject, Sendable {
    var isRunning: Bool { get }
    var latestLevel: Double { get }

    func start(outputFormat: AVAudioFormat,
               recordTo url: URL?,
               preferredMicUID: String?,
               captureInitiallyActive: Bool,
               onRuntimeError: @escaping @Sendable (AudioCaptureRuntimeError) -> Void,
               onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws

    @discardableResult
    func activateCapture() -> Bool

    @discardableResult
    func openCapture() -> Bool

    @discardableResult
    func stop() async -> URL?
}

extension AudioCapturing {
    func start(outputFormat: AVAudioFormat,
               recordTo url: URL?,
               preferredMicUID: String? = nil,
               onRuntimeError: @escaping @Sendable (AudioCaptureRuntimeError) -> Void = { _ in },
               onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws {
        try start(outputFormat: outputFormat,
                  recordTo: url,
                  preferredMicUID: preferredMicUID,
                  captureInitiallyActive: true,
                  onRuntimeError: onRuntimeError,
                  onBuffer: onBuffer)
    }
}

private let auhalInputCallback: AURenderCallback = {
    refCon,
    actionFlags,
    timeStamp,
    _,
    frameCount,
    _ in
    let run = Unmanaged<AudioCapture.AudioCaptureRun>
        .fromOpaque(refCon)
        .takeUnretainedValue()
    return run.renderInput(actionFlags: actionFlags,
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

    fileprivate enum CaptureAdmission: UInt64 {
        case suspended
        case activating
        case active
        case failed
        case stopped
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

    typealias RenderOperation = (
        _ audioUnit: AudioUnit?,
        _ actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
        _ timeStamp: UnsafePointer<AudioTimeStamp>,
        _ frameCount: UInt32,
        _ buffer: AVAudioPCMBuffer
    ) -> OSStatus

    /// Unveraenderliche Identitaet eines Hardware-Runs. Der CoreAudio-refCon und
    /// jeder konfigurierte Test-Sink binden direkt dieses Objekt; sie lesen nie den
    /// aktuellen Run des AudioCapture-Control-Planes.
    fileprivate final class AudioCaptureRun: @unchecked Sendable {
        let backlog: ProcessingBacklog
        let reporter: RuntimeErrorReporter
        let renderOperation: RenderOperation
        let afterAdmissionSnapshot: @Sendable () -> Void
        let onDeinit: @Sendable () -> Void
        let admission: Atomic<UInt64>

        nonisolated(unsafe) var audioUnit: AudioUnit?
        nonisolated(unsafe) var inputBuffer: AVAudioPCMBuffer?
        var audioUnitPrepared = false
        var audioUnitInitialized = false
        var audioUnitStarted = false

        private let callbackCount = Atomic<Int>(0)
        private let callbacksClosing = Atomic<Bool>(false)
        private let disposalRequested = Atomic<Bool>(false)
        private let disposalLock = NSLock()
        private var disposalAction: (() -> Void)?

        init(initialAdmission: CaptureAdmission,
             backlog: ProcessingBacklog,
             reporter: RuntimeErrorReporter,
             renderOperation: @escaping RenderOperation,
             afterAdmissionSnapshot: @escaping @Sendable () -> Void,
             onDeinit: @escaping @Sendable () -> Void) {
            self.backlog = backlog
            self.reporter = reporter
            self.renderOperation = renderOperation
            self.afterAdmissionSnapshot = afterAdmissionSnapshot
            self.onDeinit = onDeinit
            admission = Atomic(initialAdmission.rawValue)
        }

        deinit { onDeinit() }

        var phase: CaptureAdmission? {
            CaptureAdmission(rawValue: admission.load(ordering: .acquiring))
        }

        func activate() -> Bool {
            transition(expected: .suspended, desired: .activating)
                || phase == .activating || phase == .active
        }

        func open() -> Bool {
            transition(expected: .activating, desired: .active)
        }

        func stopAdmission() {
            while true {
                let current = admission.load(ordering: .acquiring)
                guard current != CaptureAdmission.stopped.rawValue else { return }
                if admission.compareExchange(
                    expected: current,
                    desired: CaptureAdmission.stopped.rawValue,
                    ordering: .acquiringAndReleasing
                ).exchanged { return }
            }
        }

        private func transition(expected: CaptureAdmission,
                                desired: CaptureAdmission) -> Bool {
            admission.compareExchange(
                expected: expected.rawValue,
                desired: desired.rawValue,
                ordering: .acquiringAndReleasing
            ).exchanged
        }

        func reportRuntimeError(_ error: AudioCaptureRuntimeError) {
            while true {
                let current = admission.load(ordering: .acquiring)
                switch CaptureAdmission(rawValue: current) {
                case .suspended, .activating, .active:
                    if admission.compareExchange(
                        expected: current,
                        desired: CaptureAdmission.failed.rawValue,
                        ordering: .acquiringAndReleasing
                    ).exchanged {
                        reporter.report(error)
                        return
                    }
                case .stopped:
                    reporter.report(error)
                    return
                case .failed, nil:
                    return
                }
            }
        }

        fileprivate func renderInput(
            actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
            timeStamp: UnsafePointer<AudioTimeStamp>,
            frameCount: UInt32
        ) -> OSStatus {
            guard beginCallback() else { return noErr }
            defer { endCallback() }
            let admissionAtEntry = admission.load(ordering: .acquiring)
            afterAdmissionSnapshot()
            guard let inputBuffer else {
                let status = kAudio_ParamError
                reportRuntimeError(.renderFailed(status))
                return status
            }
            let preparationStatus = AudioCapture.prepareRenderBuffer(inputBuffer,
                                                                     frameCount: frameCount)
            guard preparationStatus == noErr else {
                reportRuntimeError(.bufferCopyFailed)
                return preparationStatus
            }
            let status = renderOperation(audioUnit,
                                         actionFlags,
                                         timeStamp,
                                         frameCount,
                                         inputBuffer)
            guard status == noErr else {
                reportRuntimeError(.renderFailed(status))
                return status
            }
            enqueueRenderedBuffer(inputBuffer, admissionAtEntry: admissionAtEntry)
            return noErr
        }

        func acceptRenderedBuffer(_ buffer: AVAudioPCMBuffer) {
            guard beginCallback() else { return }
            defer { endCallback() }
            let admissionAtEntry = admission.load(ordering: .acquiring)
            afterAdmissionSnapshot()
            enqueueRenderedBuffer(buffer, admissionAtEntry: admissionAtEntry)
        }

        private func enqueueRenderedBuffer(_ buffer: AVAudioPCMBuffer,
                                           admissionAtEntry: UInt64) {
            guard admissionAtEntry == CaptureAdmission.active.rawValue,
                  admission.load(ordering: .acquiring) == admissionAtEntry,
                  !reporter.hasReported else { return }
            guard let owned = AudioCapture.copy(buffer) else {
                reportRuntimeError(.bufferCopyFailed)
                return
            }
            switch backlog.tryEnqueue(owned) {
            case .enqueued, .closed:
                return
            case .full:
                reportRuntimeError(.processingBacklog)
            }
        }

        func closeCallbacksAndRequestDisposal(_ action: @escaping () -> Void) {
            callbacksClosing.store(true, ordering: .releasing)
            disposalLock.withLock { disposalAction = action }
            disposalRequested.store(true, ordering: .releasing)
            performDisposalIfQuiescent()
        }

        private func beginCallback() -> Bool {
            guard !callbacksClosing.load(ordering: .acquiring) else { return false }
            incrementCallbackCount()
            guard !callbacksClosing.load(ordering: .acquiring) else {
                endCallback()
                return false
            }
            return true
        }

        private func endCallback() {
            let remaining = decrementCallbackCount()
            if remaining == 0 { performDisposalIfQuiescent() }
        }

        private func incrementCallbackCount() {
            while true {
                let current = callbackCount.load(ordering: .relaxed)
                if callbackCount.compareExchange(
                    expected: current,
                    desired: current + 1,
                    ordering: .acquiringAndReleasing
                ).exchanged { return }
            }
        }

        private func decrementCallbackCount() -> Int {
            while true {
                let current = callbackCount.load(ordering: .relaxed)
                precondition(current > 0)
                if callbackCount.compareExchange(
                    expected: current,
                    desired: current - 1,
                    ordering: .acquiringAndReleasing
                ).exchanged { return current - 1 }
            }
        }

        private func performDisposalIfQuiescent() {
            guard disposalRequested.load(ordering: .acquiring),
                  callbackCount.load(ordering: .acquiring) == 0 else { return }
            let action = disposalLock.withLock { () -> (() -> Void)? in
                let action = disposalAction
                disposalAction = nil
                return action
            }
            action?()
        }
    }

    private static let inputElement: AudioUnitElement = 1
    private static let outputElement: AudioUnitElement = 0
    private static let requestedMaximumFrames: UInt32 = 4_096
    static let defaultBacklogCapacity = 64

    private let audioUnitHooks: AudioUnitHooks?
    private let converterFactory: AudioConverterFactory
    private let renderOperation: RenderOperation
    private let onRunDeinit: @Sendable () -> Void
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var outputFormat: AVAudioFormat?
    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    private let backlogCapacity: Int
    private let beforeBacklogDequeue: @Sendable () -> Void
    private let afterBacklogFinish: @Sendable () -> Void
    private let afterAdmissionSnapshot: @Sendable () -> Void
    private let beforeProcessing: @Sendable () -> Void
    private let processingFailure: @Sendable (AVAudioPCMBuffer) -> AudioCaptureRuntimeError?
    private let processingQueue = DispatchQueue(label: "app.stasi.audio.processing",
                                                qos: .userInitiated)
    private var processingWorkerStarted = false
    private let stateLock = NSLock()
    private var currentRun: AudioCaptureRun?
    private var isRunningStorage = false
    private var isStoppingStorage = false
    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunningStorage
    }

    // WAV-Mitschrieb: ausschliesslich eigene Puffer auf der seriellen
    // Verarbeitungsqueue. Der Lock schuetzt nur Lebenszyklus/Test-Lesezugriffe.
    private let outputFileLock = NSLock()
    private nonisolated(unsafe) var outputFile: AVAudioFile?
    private var recordURL: URL?

    var hasOpenOutputFile: Bool {
        outputFileLock.lock()
        defer { outputFileLock.unlock() }
        return outputFile != nil
    }
    var hasConverter: Bool { converter != nil }

    // VU-Level: Verarbeitungsqueue schreibt unter Lock, Main-Poll liest.
    private let lock = NSLock()
    private nonisolated(unsafe) var rawLevel: Double = 0
    var latestLevel: Double {
        lock.lock()
        defer { lock.unlock() }
        return rawLevel
    }

    init(audioUnitHooks: AudioUnitHooks? = nil,
         converterFactory: @escaping AudioConverterFactory = { input, output in
             AVAudioConverter(from: input, to: output)
         },
         renderOperation: @escaping RenderOperation = { unit, flags, timeStamp, frameCount, buffer in
             guard let unit else { return kAudio_ParamError }
             return AudioUnitRender(unit,
                                    flags,
                                    timeStamp,
                                    AudioCapture.inputElement,
                                    frameCount,
                                    buffer.mutableAudioBufferList)
         },
         backlogCapacity: Int = AudioCapture.defaultBacklogCapacity,
         beforeBacklogDequeue: @escaping @Sendable () -> Void = {},
         afterBacklogFinish: @escaping @Sendable () -> Void = {},
         afterAdmissionSnapshot: @escaping @Sendable () -> Void = {},
         beforeProcessing: @escaping @Sendable () -> Void = {},
         processingFailure: @escaping @Sendable (AVAudioPCMBuffer) -> AudioCaptureRuntimeError? = { _ in nil },
         onRunDeinit: @escaping @Sendable () -> Void = {}) {
        precondition(backlogCapacity > 0)
        self.audioUnitHooks = audioUnitHooks
        self.converterFactory = converterFactory
        self.renderOperation = renderOperation
        self.onRunDeinit = onRunDeinit
        self.backlogCapacity = backlogCapacity
        self.beforeBacklogDequeue = beforeBacklogDequeue
        self.afterBacklogFinish = afterBacklogFinish
        self.afterAdmissionSnapshot = afterAdmissionSnapshot
        self.beforeProcessing = beforeProcessing
        self.processingFailure = processingFailure
    }

    func start(outputFormat: AVAudioFormat,
               recordTo url: URL?,
               preferredMicUID: String?,
               captureInitiallyActive: Bool,
               onRuntimeError: @escaping @Sendable (AudioCaptureRuntimeError) -> Void,
               onBuffer: @escaping @Sendable (AudioChunk) -> Void) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRunningStorage, !isStoppingStorage else {
            throw AudioCaptureError.alreadyRunning
        }
        let initialAdmission: CaptureAdmission = captureInitiallyActive ? .active : .suspended
        let backlog = ProcessingBacklog(
            capacity: backlogCapacity,
            beforeDequeue: beforeBacklogDequeue
        )
        let reporter = RuntimeErrorReporter()
        reporter.reset(callback: onRuntimeError)
        let run = AudioCaptureRun(initialAdmission: initialAdmission,
                                  backlog: backlog,
                                  reporter: reporter,
                                  renderOperation: renderOperation,
                                  afterAdmissionSnapshot: afterAdmissionSnapshot,
                                  onDeinit: onRunDeinit)
        currentRun = run
        self.onBuffer = onBuffer
        self.outputFormat = outputFormat
        recordURL = url

        do {
            // Synchron VOR der Input-Konfiguration: Der erste Render-Puffer
            // darf bereits in eine vollstaendig geoeffnete WAV-Datei laufen.
            if let url {
                let file = try AVAudioFile(
                    forWriting: url,
                    settings: outputFormat.settings,
                    commonFormat: outputFormat.commonFormat,
                    interleaved: outputFormat.isInterleaved
                )
                outputFileLock.withLock { outputFile = file }
            }

            let sink: @Sendable (AVAudioPCMBuffer) -> Void = { [run] buffer in
                run.acceptRenderedBuffer(buffer)
            }
            run.audioUnitPrepared = true
            let native: AVAudioFormat
            if let audioUnitHooks {
                native = try audioUnitHooks.configureInput(.inputOnly,
                                                           preferredMicUID,
                                                           sink)
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: native,
                    frameCapacity: Self.requestedMaximumFrames
                ) else { throw AudioCaptureError.invalidInputFormat }
                run.inputBuffer = inputBuffer
            } else {
                native = try configureAUHAL(run: run, preferredMicUID: preferredMicUID)
            }

            if native == outputFormat {
                converter = nil
            } else {
                guard let converter = converterFactory(native, outputFormat) else {
                    throw AudioCaptureError.converterUnavailable(input: native,
                                                                 output: outputFormat)
                }
                self.converter = converter
            }
            // CoreAudio darf bereits innerhalb von AudioOutputUnitStart rendern.
            // Der Consumer muss deshalb vor Initialize/Start bereitstehen.
            startProcessingWorker(run)
            if let audioUnitHooks {
                try audioUnitHooks.initialize()
            } else {
                try check(AudioUnitInitialize(try requireAudioUnit(run)), operation: "Initialize")
            }
            run.audioUnitInitialized = true

            if let audioUnitHooks {
                try audioUnitHooks.start()
            } else {
                try check(AudioOutputUnitStart(try requireAudioUnit(run)), operation: "Start")
            }
            run.audioUnitStarted = true
            isRunningStorage = true
            DebugLog.log("STASI-AUDIO: Input-only AUHAL laeuft – Client \(native.sampleRate) Hz -> Engine \(outputFormat.sampleRate) Hz")
        } catch {
            run.stopAdmission()
            teardownAudioUnit(run)
            if processingWorkerStarted {
                stopProcessingWorkerAfterStartFailure(run)
            } else {
                run.backlog.discard()
            }
            closeOutputFile()
            converter = nil
            self.outputFormat = nil
            self.onBuffer = nil
            recordURL = nil
            reporter.clearCallback()
            if currentRun === run { currentRun = nil }
            isRunningStorage = false
            throw error
        }
    }

    /// Reserviert die Capture-Aktivierung atomar gegen einen Runtimefehler.
    /// Bis `openCapture()` bleiben alle Render-Puffer gesperrt, damit der Cue nicht einfliesst.
    @discardableResult
    func activateCapture() -> Bool {
        stateLock.withLock { currentRun?.activate() ?? false }
    }

    /// Oeffnet nach dem vollstaendigen Cue die eigentliche Render-Zulassung.
    @discardableResult
    func openCapture() -> Bool {
        stateLock.withLock { currentRun?.open() ?? false }
    }

    /// Stoppt und entsorgt nur die input-only AUHAL, laesst den Mitschrieb
    /// ausschreiben und liefert die Datei-URL.
    @discardableResult
    func stop() async -> URL? {
        let stoppingRun = stateLock.withLock { () -> AudioCaptureRun? in
            guard isRunningStorage, let run = currentRun else { return nil }
            currentRun = nil
            run.stopAdmission()
            isRunningStorage = false
            isStoppingStorage = true
            // AudioOutputUnitStop ist die Produktions-Quiescence-Grenze. Fuer
            // injizierte Hooks bleibt Disposal zusaetzlich bis zum letzten bereits
            // eingetretenen Callback aufgeschoben.
            teardownAudioUnit(run)
            return run
        }
        guard let stoppingRun else { return nil }

        // Suspension statt DispatchGroup.wait(): Der serielle Worker leert die
        // feste Queue vollstaendig, ohne den aufrufenden MainActor zu blockieren.
        await stopProcessingWorker(stoppingRun)

        return stateLock.withLock {
            converter = nil
            outputFormat = nil
            onBuffer = nil
            stoppingRun.reporter.clearCallback()
            lock.withLock { rawLevel = 0 }
            closeOutputFile()
            let url = recordURL
            recordURL = nil
            isStoppingStorage = false
            return url
        }
    }

    // MARK: AUHAL-Konfiguration

    private func configureAUHAL(run: AudioCaptureRun,
                                preferredMicUID: String?) throws -> AVAudioFormat {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioCaptureError.componentUnavailable
        }

        var instance: AudioUnit?
        try check(AudioComponentInstanceNew(component, &instance), operation: "Instanz erzeugen")
        guard let instance else { throw AudioCaptureError.componentUnavailable }
        run.audioUnit = instance

        // Output zuerst abschalten, solange die Unit noch nicht initialisiert
        // ist. Danach ausschliesslich das Input-Element aktivieren.
        try setIOEnabled(IOConfiguration.inputOnly.outputEnabled,
                         run: run,
                         scope: kAudioUnitScope_Output,
                         element: Self.outputElement,
                         operation: "Output deaktivieren")
        try setIOEnabled(IOConfiguration.inputOnly.inputEnabled,
                         run: run,
                         scope: kAudioUnitScope_Input,
                         element: Self.inputElement,
                         operation: "Input aktivieren")

        guard let deviceID = MicrophoneScanner.inputDeviceID(preferredUID: preferredMicUID)
        else { throw AudioCaptureError.noInputDevice }
        var selectedDevice = deviceID
        try setProperty(&selectedDevice,
                        run: run,
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
        else { throw AudioCaptureError.invalidInputFormat }
        run.inputBuffer = inputBuffer

        var callback = AURenderCallbackStruct(
            inputProc: auhalInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(run).toOpaque()
        )
        try setProperty(&callback,
                        run: run,
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

    /// Das AUHAL-Clientformat bleibt auf der nativen Rate, begrenzt die Speech-
    /// Strecke aber unabhaengig von der Hardware-Kanalzahl auf unterstuetztes Mono.
    static func clientInputFormat(for hardwareFormat: AVAudioFormat) throws -> AVAudioFormat {
        guard hardwareFormat.sampleRate > 0,
              hardwareFormat.channelCount > 0,
              let clientFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: hardwareFormat.sampleRate,
                                               channels: 1,
                                               interleaved: false)
        else { throw AudioCaptureError.invalidInputFormat }
        return clientFormat
    }

    /// Liest die Geraeteseite des AUHAL-Input-Busses und setzt dessen Client-Seite
    /// auf Float32 non-interleaved in Mono bei unveraenderter Hardware-Rate.
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
            throw AudioCaptureError.audioUnit(operation: "Natives Hardwareformat lesen",
                                         status: hardwareResult.status)
        }

        var hardwareDescription = hardwareResult.description
        let hardwareFormat: AVAudioFormat?
        if hardwareDescription.mChannelsPerFrame > 2,
           let channelLayout = AVAudioChannelLayout(
               layoutTag: kAudioChannelLayoutTag_DiscreteInOrder
                   | hardwareDescription.mChannelsPerFrame
           ) {
            hardwareFormat = AVAudioFormat(streamDescription: &hardwareDescription,
                                           channelLayout: channelLayout)
        } else {
            hardwareFormat = AVAudioFormat(streamDescription: &hardwareDescription)
        }
        guard let hardwareFormat else { throw AudioCaptureError.invalidInputFormat }
        let clientFormat = try clientInputFormat(for: hardwareFormat)

        let setStatus = setClientFormat(clientFormat.streamDescription.pointee,
                                        kAudioUnitScope_Output,
                                        inputElement)
        guard setStatus == noErr else {
            throw AudioCaptureError.audioUnit(operation: "Float32-Clientformat setzen",
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
        guard requested > 0 else { throw AudioCaptureError.invalidMaximumFrames }

        let setStatus = set(requested)
        guard setStatus == noErr else {
            throw AudioCaptureError.audioUnit(operation: "MaximumFramesPerSlice setzen",
                                         status: setStatus)
        }

        let effective = get()
        guard effective.status == noErr else {
            throw AudioCaptureError.audioUnit(operation: "MaximumFramesPerSlice lesen",
                                         status: effective.status)
        }
        guard effective.value > 0 else { throw AudioCaptureError.invalidMaximumFrames }
        return AVAudioFrameCount(max(requested, effective.value))
    }

    private func setIOEnabled(_ enabled: Bool,
                              run: AudioCaptureRun,
                              scope: AudioUnitScope,
                              element: AudioUnitElement,
                              operation: String) throws {
        var value: UInt32 = enabled ? 1 : 0
        try setProperty(&value,
                        run: run,
                        id: kAudioOutputUnitProperty_EnableIO,
                        scope: scope,
                        element: element,
                        operation: operation)
    }

    private func setProperty<T>(_ value: inout T,
                                run: AudioCaptureRun,
                                id: AudioUnitPropertyID,
                                scope: AudioUnitScope,
                                element: AudioUnitElement,
                                operation: String) throws {
        let unit = try requireAudioUnit(run)
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

    private func requireAudioUnit(_ run: AudioCaptureRun) throws -> AudioUnit {
        guard let audioUnit = run.audioUnit else {
            throw AudioCaptureError.componentUnavailable
        }
        return audioUnit
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioCaptureError.audioUnit(operation: operation, status: status)
        }
    }

    /// Reihenfolge ist strikt: stop -> uninitialize -> dispose. Erst danach
    /// duerfen der Render-Puffer und die Unit-Referenz freigegeben werden.
    private func teardownAudioUnit(_ run: AudioCaptureRun) {
        if run.audioUnitStarted {
            if let audioUnitHooks {
                audioUnitHooks.stop()
            } else if let audioUnit = run.audioUnit {
                // CoreAudio garantiert nach der synchronen Rueckkehr keine weiteren
                // Render-Aufrufe dieser Unit. Bereits eingetretene Callbacks halten
                // den Run dennoch bis zu ihrem defer-Ende stark am Leben.
                AudioOutputUnitStop(audioUnit)
            }
        }
        run.audioUnitStarted = false

        let initialized = run.audioUnitInitialized
        run.audioUnitInitialized = false
        let prepared = run.audioUnitPrepared
        run.audioUnitPrepared = false
        let unit = run.audioUnit
        run.closeCallbacksAndRequestDisposal { [audioUnitHooks] in
            if initialized {
                if let audioUnitHooks {
                    audioUnitHooks.uninitialize()
                } else if let unit {
                    AudioUnitUninitialize(unit)
                }
            }
            guard prepared else { return }
            if let audioUnitHooks {
                audioUnitHooks.dispose()
            } else if let unit {
                AudioComponentInstanceDispose(unit)
            }
        }
    }

    // MARK: Audio-Thread

    /// Control-plane Fehler werden unter dem State-Lock an den zu diesem Zeitpunkt
    /// aktuellen Run gebunden. Render- und Workerfehler rufen dagegen direkt ihren
    /// eigenen Run auf.
    nonisolated func reportRuntimeError(_ error: AudioCaptureRuntimeError) {
        let run = stateLock.withLock { currentRun }
        run?.reportRuntimeError(error)
    }

    /// Testet exakt den produktiven `AudioCaptureRun.renderInput`-Pfad; nur die
    /// eigentliche AudioUnitRender-Operation ist per Initializer injiziert.
    nonisolated func renderCurrentInputForTesting(frameCount: UInt32) -> OSStatus {
        guard let run = stateLock.withLock({ currentRun }) else {
            return kAudio_ParamError
        }
        var timeStamp = AudioTimeStamp()
        return withUnsafePointer(to: &timeStamp) { pointer in
            run.renderInput(actionFlags: nil,
                            timeStamp: pointer,
                            frameCount: frameCount)
        }
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

    private func startProcessingWorker(_ context: AudioCaptureRun) {
        let backlog = context.backlog
        processingWorkerStarted = true
        processingQueue.async { [weak self] in
            while let buffer = backlog.next() {
                guard let self else { return }
                self.process(buffer, context: context)
            }
        }
    }

    private func stopProcessingWorker(_ context: AudioCaptureRun) async {
        let backlog = context.backlog
        backlog.finish()
        afterBacklogFinish()
        await withCheckedContinuation { continuation in
            // Genau ein bounded Drain-Marker pro stop(); er laeuft erst, nachdem
            // die eine langlebige Worker-Closure die Queue verlassen hat.
            processingQueue.async { continuation.resume() }
        }
        processingWorkerStarted = false
    }

    /// `start` ist synchron; sein Fehlerpfad muss den bereits vor Initialize/Start
    /// gestarteten Worker daher synchron beenden. Dieser Pfad ist bounded auf die
    /// feste Queue und wird nur ausgefuehrt, wenn Hardware-Setup fehlschlaegt.
    private func stopProcessingWorkerAfterStartFailure(_ context: AudioCaptureRun) {
        context.backlog.finish()
        processingQueue.sync {}
        processingWorkerStarted = false
    }

    nonisolated private func process(_ buffer: AVAudioPCMBuffer,
                                     context: AudioCaptureRun) {
        beforeProcessing()
        guard !context.reporter.hasReported else { return }
        if let failure = processingFailure(buffer) {
            context.reportRuntimeError(failure)
            return
        }

        let level = Self.computeLevel(of: buffer)
        lock.lock()
        rawLevel = level
        lock.unlock()

        guard let outputFormat else { return }
        let processed: AVAudioPCMBuffer
        if let converter {
            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                   frameCapacity: capacity) else {
                context.reportRuntimeError(.conversionFailed(
                    "Zielpuffer konnte nicht angelegt werden."
                ))
                return
            }
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
            guard error == nil, status != .error, converted.frameLength > 0 else {
                let details = error?.localizedDescription ?? "AVAudioConverter lieferte keine Audiodaten."
                context.reportRuntimeError(.conversionFailed(details))
                return
            }
            processed = converted
        } else {
            processed = buffer
        }

        outputFileLock.lock()
        let file = outputFile
        outputFileLock.unlock()
        if let file {
            do {
                try file.write(from: processed)
            } catch {
                context.reportRuntimeError(.wavWriteFailed(error.localizedDescription))
                return
            }
        }
        onBuffer?(AudioChunk(buffer: processed))
    }

    private func closeOutputFile() {
        outputFileLock.lock()
        outputFile = nil
        outputFileLock.unlock()
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

    /// Lock-freier Single-Producer/Single-Consumer-Ring mit exakt fester
    /// Kapazitaet. Die Slots liegen in explizit verwaltetem Pointer-Speicher;
    /// Swift-Array-Exklusivitaet wird deshalb nicht producer-/consumer-uebergreifend
    /// verletzt. ARC-Besitz wird pro belegtem Slot mit Unmanaged exakt einmal
    /// uebernommen und beim Dequeue, Discard oder Deinit exakt einmal abgegeben.
    final class ProcessingBacklog: @unchecked Sendable {
        enum EnqueueResult: Equatable {
            case enqueued
            case full
            case closed
        }

        private let available = DispatchSemaphore(value: 0)
        private let readIndex = Atomic<UInt64>(0)
        private let writeIndex = Atomic<UInt64>(0)
        private let finishing = Atomic<Bool>(false)
        private let producerActive = Atomic<Bool>(false)
        private let afterProducerAdmissionCheck: @Sendable () -> Void
        private let beforeDequeue: @Sendable () -> Void
        private let capacity: Int
        private let slots: UnsafeMutablePointer<Unmanaged<AVAudioPCMBuffer>?>

        init(capacity: Int,
             afterProducerAdmissionCheck: @escaping @Sendable () -> Void = {},
             beforeDequeue: @escaping @Sendable () -> Void = {}) {
            precondition(capacity > 0)
            self.capacity = capacity
            self.afterProducerAdmissionCheck = afterProducerAdmissionCheck
            self.beforeDequeue = beforeDequeue
            slots = .allocate(capacity: capacity)
            slots.initialize(repeating: nil, count: capacity)
        }

        deinit {
            releaseAllSlots()
            slots.deinitialize(count: capacity)
            slots.deallocate()
        }

        func tryEnqueue(_ buffer: AVAudioPCMBuffer) -> EnqueueResult {
            guard !finishing.load(ordering: .sequentiallyConsistent) else {
                return .closed
            }
            afterProducerAdmissionCheck()
            producerActive.store(true, ordering: .sequentiallyConsistent)
            guard !finishing.load(ordering: .sequentiallyConsistent) else {
                completeProducer()
                return .closed
            }

            let write = writeIndex.load(ordering: .relaxed)
            let read = readIndex.load(ordering: .acquiring)
            guard write &- read < UInt64(capacity) else {
                let result: EnqueueResult = finishing.load(ordering: .sequentiallyConsistent)
                    ? .closed : .full
                completeProducer()
                return result
            }

            let slot = Int(write % UInt64(capacity))
            slots.advanced(by: slot).pointee = Unmanaged.passRetained(buffer)
            writeIndex.store(write &+ 1, ordering: .releasing)
            completeProducer()
            available.signal()
            return .enqueued
        }

        func next() -> AVAudioPCMBuffer? {
            while true {
                available.wait()
                let read = readIndex.load(ordering: .relaxed)
                let write = writeIndex.load(ordering: .acquiring)
                if read != write {
                    beforeDequeue()
                    let slot = Int(read % UInt64(capacity))
                    let pointer = slots.advanced(by: slot)
                    guard let retained = pointer.pointee else {
                        preconditionFailure("Publizierter Audio-Slot ist leer")
                    }
                    pointer.pointee = nil
                    readIndex.store(read &+ 1, ordering: .releasing)
                    return retained.takeRetainedValue()
                }
                if finishing.load(ordering: .sequentiallyConsistent) {
                    // Ein Producer, der die Finish-Grenze gerade kreuzt, publiziert
                    // entweder noch einen Slot oder signalisiert seinen Closed-Abgang.
                    guard !producerActive.load(ordering: .sequentiallyConsistent) else {
                        continue
                    }
                    let finalWrite = writeIndex.load(ordering: .acquiring)
                    if read == finalWrite { return nil }
                }
            }
        }

        func finish() {
            finishing.store(true, ordering: .sequentiallyConsistent)
            available.signal()
        }

        /// Nur im synchronen Start-Fehlerpfad, wenn noch kein Worker existiert.
        func discard() {
            finishing.store(true, ordering: .sequentiallyConsistent)
            releaseAllSlots()
            readIndex.store(writeIndex.load(ordering: .acquiring), ordering: .releasing)
        }

        private func completeProducer() {
            producerActive.store(false, ordering: .sequentiallyConsistent)
            if finishing.load(ordering: .sequentiallyConsistent) {
                available.signal()
            }
        }

        private func releaseAllSlots() {
            for index in 0..<capacity {
                let pointer = slots.advanced(by: index)
                pointer.pointee?.release()
                pointer.pointee = nil
            }
        }
    }

    /// Genau ein Runtimefehler pro Start. Selbst aus dem Render-Callback entsteht
    /// hoechstens eine Dispatch-Closure; der Fehler-Backlog kann daher nicht wachsen.
    fileprivate final class RuntimeErrorReporter: @unchecked Sendable {
        private let reported = Atomic<Bool>(false)
        private let deliveryQueue = DispatchQueue(label: "app.stasi.audio.runtime-error")
        private nonisolated(unsafe) var callback: (@Sendable (AudioCaptureRuntimeError) -> Void)?

        var hasReported: Bool { reported.load(ordering: .acquiring) }

        func reset(callback: @escaping @Sendable (AudioCaptureRuntimeError) -> Void) {
            self.callback = callback
            reported.store(false, ordering: .releasing)
        }

        func report(_ error: AudioCaptureRuntimeError) {
            guard reported.compareExchange(
                expected: false,
                desired: true,
                ordering: .acquiringAndReleasing
            ).exchanged else { return }
            guard let callback else { return }
            deliveryQueue.async { callback(error) }
        }

        func clearCallback() {
            callback = nil
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
