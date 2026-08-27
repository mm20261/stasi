import AppKit

/// Akustische Lebenszyklus-Ereignisse einer einzelnen Diktat-Session.
enum SoundEvent: Equatable, Hashable, Sendable {
    case recordingStarted
    case recordingStopped
    case processingCompleted
    case failed
}

protocol SoundFeedback: Sendable {
    @MainActor
    func play(_ event: SoundEvent) async
}

struct SystemSoundFeedback: SoundFeedback {
    typealias Player = @MainActor @Sendable (NSSound.Name) async -> Void

    private let player: Player

    init(player: @escaping Player = { name in
        guard let sound = NSSound(named: name) else { return }
        await NSSoundCompletionPlayer.play(sound)
    }) {
        self.player = player
    }

    @MainActor
    func play(_ event: SoundEvent) async {
        let name: NSSound.Name?
        switch event {
        case .recordingStarted:
            name = NSSound.Name("Tink")
        case .recordingStopped:
            name = NSSound.Name("Pop")
        case .processingCompleted, .failed:
            name = nil
        }
        if let name {
            await player(name)
        }
    }
}

@MainActor
final class NSSoundCompletionPlayer: NSObject, NSSoundDelegate {
    typealias Starter = @MainActor (NSSound, NSSoundDelegate) -> Bool

    private var continuation: CheckedContinuation<Void, Never>?
    private var sound: NSSound?
    private var lifetime: NSSoundCompletionPlayer?
    private var cancelled = false

    static func play(_ sound: NSSound,
                     starter: @escaping Starter = { sound, _ in sound.play() }) async {
        let player = NSSoundCompletionPlayer()
        await withTaskCancellationHandler {
            await player.play(sound, starter: starter)
        } onCancel: {
            Task { @MainActor in player.cancel() }
        }
    }

    private func play(_ sound: NSSound, starter: @escaping Starter) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.sound = sound
            lifetime = self
            sound.delegate = self
            if cancelled || Task.isCancelled || !starter(sound, self) {
                finish()
            }
        }
    }

    func sound(_ sound: NSSound, didFinishPlaying finishedPlaying: Bool) {
        finish()
    }

    private func cancel() {
        cancelled = true
        sound?.stop()
        finish()
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        sound?.delegate = nil
        sound = nil
        lifetime = nil
        continuation.resume()
    }
}
