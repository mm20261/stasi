import AppKit
import XCTest
@testable import Stasi

@MainActor
final class SoundFeedbackTests: XCTestCase {
    func testSystemFeedbackMapsExistingStartAndStopSoundsOnly() async {
        var names: [NSSound.Name] = []
        let feedback = SystemSoundFeedback { name in
            names.append(name)
        }

        await feedback.play(.recordingStarted)
        await feedback.play(.recordingStopped)
        await feedback.play(.processingCompleted)
        await feedback.play(.failed)

        XCTAssertEqual(names, [NSSound.Name("Tink"), NSSound.Name("Pop")])
    }

    func testPlayAwaitsUnderlyingSoundCompletion() async {
        var timeline: [String] = []
        let feedback = SystemSoundFeedback { _ in
            timeline.append("sound.started")
            await Task.yield()
            timeline.append("sound.finished")
        }

        await feedback.play(.recordingStarted)
        timeline.append("caller.resumed")

        XCTAssertEqual(timeline, ["sound.started", "sound.finished", "caller.resumed"])
    }
}
