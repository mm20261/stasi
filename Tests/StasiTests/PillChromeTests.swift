import AppKit
import XCTest
@testable import Stasi

// MARK: - Pill-Chrome (v4.1)
// ✕ und ✓ sind IMMER klickbar – auch im gelockten Modus (Hands-free),
// wie bei Wispr: Aufnahme stoppen (✓) oder verwerfen (✕) per Pill.

final class PillChromeTests: XCTestCase {

    func testPushToTalkShowsDiscardAndCommit() {
        XCTAssertTrue(PillChrome.showsButtons(for: .pushToTalk))
    }

    func testLockedModeAlsoShowsDiscardAndCommit() {
        // Wispr-Stil: Auch hands-free (gelockt) lässt sich per Pill
        // bestätigen (✓) oder verwerfen (✕).
        XCTAssertTrue(PillChrome.showsButtons(for: .handsFree))
    }

    func testPillWidthIdenticalForBothSources() {
        XCTAssertEqual(PillChrome.pillWidth(for: .pushToTalk), 140)
        XCTAssertEqual(PillChrome.pillWidth(for: .handsFree), 140)
        XCTAssertEqual(PillChrome.pillHeight(hasPartialText: false), 24)
    }

    func testPillGrowsForLiveTranscript() {
        XCTAssertEqual(PillChrome.pillWidth(for: .pushToTalk, hasPartialText: true), 320)
        XCTAssertEqual(PillChrome.pillHeight(hasPartialText: true), 52)
    }

    func testModelLoadingWidthIsCompact() {
        XCTAssertEqual(PillChrome.pillWidth(for: .pushToTalk, modelReady: false), 190)
    }

    func testShortPushToTalkStaysHidden() {
        XCTAssertFalse(PillChrome.shouldShowRecording(source: .pushToTalk, elapsed: 0.249))
    }

    func testPushToTalkAppearsAtThreshold() {
        XCTAssertEqual(PillChrome.presentationDelay, 0.25)
        XCTAssertTrue(PillChrome.shouldShowRecording(source: .pushToTalk, elapsed: 0.25))
    }

    func testHandsFreeAppearsImmediately() {
        XCTAssertTrue(PillChrome.shouldShowRecording(source: .handsFree, elapsed: 0))
    }

    @MainActor
    func testProcessingPhasesUseTextlessSpinner() {
        for phase in [AppState.Phase.transcribing, .polishing, .injecting] {
            XCTAssertTrue(PillChrome.shouldShowSpinner(
                phase: phase,
                processingElapsed: PillChrome.spinnerDelay
            ))
        }
        XCTAssertFalse(PillChrome.shouldShowSpinner(
            phase: .recording,
            processingElapsed: PillChrome.spinnerDelay
        ))
        XCTAssertFalse(PillChrome.shouldShowSpinner(
            phase: .idle,
            processingElapsed: PillChrome.spinnerDelay
        ))

        let animated = SpinnerViewNS(reduceMotion: false)
        let reduced = SpinnerViewNS(reduceMotion: true)
        XCTAssertFalse(animated.subviews.contains { $0 is NSTextField })
        XCTAssertTrue(animated.rotatesForTesting)
        XCTAssertFalse(reduced.rotatesForTesting)
    }

    func testSpinnerWaitsForPresentationThreshold() {
        XCTAssertEqual(PillChrome.spinnerDelay, 0.2)
        XCTAssertFalse(PillChrome.shouldShowSpinner(
            phase: .transcribing,
            processingElapsed: PillChrome.spinnerDelay - 0.001
        ))
        XCTAssertTrue(PillChrome.shouldShowSpinner(
            phase: .transcribing,
            processingElapsed: PillChrome.spinnerDelay
        ))
    }

    @MainActor
    func testPillBackgroundAlwaysUsesInk() throws {
        let suite = "PillChromeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.accentHex = 0x2D6A4F
        let view = RecordingPillView(onDiscard: {}, onCommit: {})

        view.applyChrome(for: .pushToTalk)
        let first = try XCTUnwrap(view.layer?.backgroundColor)
        settings.accentHex = 0x315EA8
        view.applyChrome(for: .pushToTalk)
        let second = try XCTUnwrap(view.layer?.backgroundColor)
        let expected = NSColor(Theme.Palette.ink).cgColor

        XCTAssertEqual(NSColor(cgColor: first), NSColor(cgColor: expected))
        XCTAssertEqual(NSColor(cgColor: second), NSColor(cgColor: expected))
    }

    @MainActor
    func testTickRaisesActuallyDrawnBarHeights() {
        let view = RecordingPillView(onDiscard: {}, onCommit: {})
        view.update(level: 0, secs: 0, partialText: "", modelReady: true)
        view.tick()
        XCTAssertTrue(view.waveformHeightsForTesting.allSatisfy {
            $0 == MicLevelBars.minHeight
        })

        view.update(level: 0.8, secs: 0, partialText: "", modelReady: true)
        view.tick()

        XCTAssertEqual(view.waveformHeightsForTesting.count, 14)
        XCTAssertTrue(view.waveformHeightsForTesting.contains {
            $0 > MicLevelBars.minHeight
        })
    }
}

// MARK: - Echter Live-Pegel (Mic-Popover)

final class MicLevelBarTests: XCTestCase {

    func testSilenceStaysAtMinimum() {
        XCTAssertEqual(MicLevelBars.height(level: 0, jitter: 0), 4)
    }

    func testLoudLevelReachesMaximum() {
        XCTAssertEqual(MicLevelBars.height(level: 1, jitter: 0), 20)
    }

    func testMidLevelIsBetween() {
        let h = MicLevelBars.height(level: 0.5, jitter: 0)
        XCTAssertGreaterThan(h, 4)
        XCTAssertLessThan(h, 20)
    }

    func testLevelIsClamped() {
        XCTAssertEqual(MicLevelBars.height(level: -1, jitter: 0), 4)
        XCTAssertEqual(MicLevelBars.height(level: 5, jitter: 0), 20)
    }

    func testJitterOnlyModulatesWithinBounds() {
        for jitter in stride(from: -1.0, through: 1.0, by: 0.25) {
            let h = MicLevelBars.height(level: 0.4, jitter: jitter)
            XCTAssertTrue((4...20).contains(h), "h=\(h) außerhalb für jitter=\(jitter)")
        }
    }

    func testPeakIsHeldFor150MillisecondsThenFalls() {
        let peak = MicLevelBars.height(level: 0.9, jitter: 0)
        let quiet = MicLevelBars.height(level: 0.1, jitter: 0)
        let attack = MicLevelBars.nextPeak(
            current: MicLevelBars.minHeight,
            target: peak,
            holdUntil: 0,
            now: 1
        )
        let held = MicLevelBars.nextPeak(
            current: attack.height,
            target: quiet,
            holdUntil: attack.holdUntil,
            now: 1.149
        )
        let falling = MicLevelBars.nextPeak(
            current: held.height,
            target: quiet,
            holdUntil: held.holdUntil,
            now: 1.151
        )

        XCTAssertEqual(held.height, peak)
        XCTAssertLessThan(falling.height, peak)
        XCTAssertGreaterThan(falling.height, quiet)
    }

    func testBarOpacityRunsFromDimmedSilenceToOpaquePeak() {
        XCTAssertEqual(MicLevelBars.opacity(forHeight: MicLevelBars.minHeight), 0.35)
        XCTAssertEqual(MicLevelBars.opacity(forHeight: MicLevelBars.maxHeight), 1)
    }
}
