import Foundation

final class DictationSessionHealth: @unchecked Sendable {
    enum Failure: Equatable, Sendable {
        case speechBufferOverflow
        case speechStreamTerminated
        case audioRuntimeFailure
    }

    private let lock = NSLock()
    private var failureStorage: Failure?
    private var speechIngressClosed = false

    var failure: Failure? {
        lock.lock()
        defer { lock.unlock() }
        return failureStorage
    }

    func record(_ result: AsyncStream<AudioChunk>.Continuation.YieldResult) {
        let newFailure: Failure?
        switch result {
        case .enqueued:
            newFailure = nil
        case .dropped:
            newFailure = .speechBufferOverflow
        case .terminated:
            newFailure = .speechStreamTerminated
        @unknown default:
            newFailure = .speechStreamTerminated
        }

        guard let newFailure else { return }
        lock.lock()
        defer { lock.unlock() }
        if failureStorage == nil {
            failureStorage = newFailure
        }
    }

    func recordAudioRuntimeFailure() {
        lock.lock()
        defer { lock.unlock() }
        if failureStorage == nil {
            failureStorage = .audioRuntimeFailure
        }
    }

    /// Gated den Speech-Zulauf am ersten Drop atomar. Die WAV-Pipeline läuft
    /// unabhängig weiter; spätere Chunks erreichen den Speech-Stream nicht mehr.
    func ingest(_ chunk: AudioChunk,
                into continuation: AsyncStream<AudioChunk>.Continuation) {
        lock.lock()
        guard !speechIngressClosed else {
            lock.unlock()
            return
        }
        let result = continuation.yield(chunk)
        switch result {
        case .enqueued:
            lock.unlock()
        case .dropped:
            if failureStorage == nil {
                failureStorage = .speechBufferOverflow
            }
            speechIngressClosed = true
            lock.unlock()
            continuation.finish()
        case .terminated:
            if failureStorage == nil {
                failureStorage = .speechStreamTerminated
            }
            speechIngressClosed = true
            lock.unlock()
        @unknown default:
            if failureStorage == nil {
                failureStorage = .speechStreamTerminated
            }
            speechIngressClosed = true
            lock.unlock()
        }
    }

    /// Geplanter Stop: schließt den Zulauf, bevor ein verspäteter Callback noch
    /// yielden kann. Ein solcher Callback ist kein `.terminated`-Fehler.
    func closeSpeechIngress(_ continuation: AsyncStream<AudioChunk>.Continuation?) {
        lock.lock()
        let shouldFinish = !speechIngressClosed
        speechIngressClosed = true
        lock.unlock()
        if shouldFinish {
            continuation?.finish()
        }
    }
}
