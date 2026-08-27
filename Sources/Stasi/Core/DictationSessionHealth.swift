import Foundation

final class DictationSessionHealth: @unchecked Sendable {
    enum Failure: Equatable, Sendable {
        case speechBufferOverflow
        case speechStreamTerminated
    }

    private let lock = NSLock()
    private var failureStorage: Failure?

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
}
