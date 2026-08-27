import XCTest
import CoreGraphics
@testable import Stasi

final class HotkeyCaptureDraftTests: XCTestCase {
    func testCompleteComboSurvivesModifierRelease() {
        let combo = HotkeyEngine.Combo(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )
        var draft = HotkeyCaptureDraft()

        draft.process(.modifier(.init(keyCode: 55, flags: 0)))
        draft.process(.key(combo))
        draft.process(.modifierReleased(keyCode: 55))

        XCTAssertEqual(draft.combo, combo)
        XCTAssertTrue(draft.isComplete)
    }

    func testModifierOnlyDraftRemainsValidAfterRelease() {
        let commandOnly = HotkeyEngine.Combo(keyCode: 55, flags: 0)
        var draft = HotkeyCaptureDraft()

        draft.process(.modifier(commandOnly))
        draft.process(.modifierReleased(keyCode: 55))

        XCTAssertEqual(draft.combo, commandOnly)
        XCTAssertFalse(draft.isComplete)
        XCTAssertTrue(draft.isValidSelection)
    }

    func testFunctionModifierRemainsAValidFinalSelectionAfterRelease() {
        let function = HotkeyEngine.Combo(keyCode: 63, flags: 0)
        var draft = HotkeyCaptureDraft()

        draft.process(.modifier(function))
        draft.process(.modifierReleased(keyCode: 63))

        XCTAssertEqual(draft.combo, function)
        XCTAssertFalse(draft.isComplete)
    }

    func testCancelClearsCompleteCombo() {
        var draft = HotkeyCaptureDraft()
        draft.process(.key(.init(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )))

        draft.process(.cancel)

        XCTAssertNil(draft.combo)
        XCTAssertFalse(draft.isComplete)
    }

    func testRepeatedModifierEventDoesNotReplaceCompleteCombo() {
        let combo = HotkeyEngine.Combo(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )
        var draft = HotkeyCaptureDraft()
        draft.process(.key(combo))

        draft.process(.modifier(.init(keyCode: 55, flags: 0)))

        XCTAssertEqual(draft.combo, combo)
        XCTAssertTrue(draft.isComplete)
    }

    func testRepeatedKeyEventKeepsCompleteCombo() {
        let combo = HotkeyEngine.Combo(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )
        var draft = HotkeyCaptureDraft()

        draft.process(.key(combo))
        draft.process(.key(combo))

        XCTAssertEqual(draft.combo, combo)
        XCTAssertTrue(draft.isComplete)
    }

    func testCompleteComboWithModifierIsValidSelection() {
        var draft = HotkeyCaptureDraft()

        draft.process(.key(.init(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )))

        XCTAssertTrue(draft.isValidSelection)
    }

    func testModifierOnlyDraftIsValidWhileCaptured() {
        var draft = HotkeyCaptureDraft()

        draft.process(.modifier(.init(keyCode: 55, flags: 0)))

        XCTAssertTrue(draft.isValidSelection)
    }

    func testBareKeyIsNotAValidSelection() {
        var draft = HotkeyCaptureDraft()

        draft.process(.key(.init(keyCode: 40, flags: 0)))

        XCTAssertFalse(draft.isValidSelection)
    }

    func testInitialCompleteComboCanBeReplacedByFirstCapturedModifier() {
        let initialCombo = HotkeyEngine.Combo(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )
        let replacement = HotkeyEngine.Combo(keyCode: 55, flags: 0)
        var draft = HotkeyCaptureDraft(combo: initialCombo)
        XCTAssertTrue(draft.isComplete)

        draft.process(.modifier(replacement))

        XCTAssertEqual(draft.combo, replacement)
        XCTAssertFalse(draft.isComplete)
        XCTAssertTrue(draft.isValidSelection)
    }

    @MainActor
    func testOnboardingPreviewIsEmptyAfterCancel() {
        var draft = HotkeyCaptureDraft(combo: .init(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        ))
        draft.process(.cancel)

        XCTAssertEqual(OnboardingView.hotkeyPreviewText(for: draft), "")
    }

    @MainActor
    func testOnboardingPreviewRetainsModifierOnlySelectionAfterRelease() {
        let commandOnly = HotkeyEngine.Combo(keyCode: 55, flags: 0)
        var draft = HotkeyCaptureDraft()
        draft.process(.modifier(commandOnly))
        draft.process(.modifierReleased(keyCode: 55))

        XCTAssertEqual(OnboardingView.hotkeyPreviewText(for: draft), VirtualKey.display(commandOnly))
        XCTAssertTrue(draft.isValidSelection)
    }

    func testOnboardingEscapeRequestsMonitorRemoval() {
        var state = HotkeyCaptureState()
        state.begin(with: .defaultPTT)

        let effect = state.process(.cancel)

        XCTAssertEqual(effect, .removeMonitor)
        XCTAssertFalse(state.isRecording)
        XCTAssertNil(state.draft.combo)
    }

    func testSettingsEscapeStopsCaptureUIAndRequestsMonitorRemoval() {
        let currentCombo = HotkeyEngine.Combo(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )
        var state = SettingsHotkeyCaptureState()
        state.begin(with: currentCombo)

        let effect = state.process(.cancel)

        XCTAssertEqual(effect, .removeMonitor)
        XCTAssertFalse(state.isRecording)
        XCTAssertNil(state.draft.combo)
    }

    func testNewOptionPressReplacesCapturedCommandKeyCombo() {
        let optionOnly = HotkeyEngine.Combo(keyCode: 58, flags: 0)
        var draft = HotkeyCaptureDraft()
        draft.process(.key(.init(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )))
        draft.process(.modifierReleased(keyCode: 55))

        draft.process(.modifier(optionOnly))

        XCTAssertEqual(draft.combo, optionOnly)
        XCTAssertFalse(draft.isComplete)
    }

    func testNewCommandPressReplacesBareKeyDraft() {
        let commandOnly = HotkeyEngine.Combo(keyCode: 55, flags: 0)
        var draft = HotkeyCaptureDraft()
        draft.process(.key(.init(keyCode: 40, flags: 0)))

        draft.process(.modifier(commandOnly))

        XCTAssertEqual(draft.combo, commandOnly)
        XCTAssertFalse(draft.isComplete)
        XCTAssertTrue(draft.isValidSelection)
    }

    func testInitialComboReleaseDoesNotConsumeFirstModifierReplacement() {
        let initialCombo = HotkeyEngine.Combo(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )
        let commandOnly = HotkeyEngine.Combo(keyCode: 55, flags: 0)
        var draft = HotkeyCaptureDraft(combo: initialCombo)

        draft.process(.modifierReleased(keyCode: 55))
        draft.process(.modifier(commandOnly))

        XCTAssertEqual(draft.combo, commandOnly)
        XCTAssertFalse(draft.isComplete)
    }

    func testKeyRepeatIsIgnoredWhenDraftIsEmpty() {
        var draft = HotkeyCaptureDraft()

        draft.process(.key(.init(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        ), isRepeat: true))

        XCTAssertNil(draft.combo)
        XCTAssertFalse(draft.isComplete)
    }

    func testBareKeyAutoRepeatDoesNotOverwriteCompletedCombo() {
        let commandK = HotkeyEngine.Combo(
            keyCode: 40,
            flags: CGEventFlags.maskCommand.rawValue
        )
        var draft = HotkeyCaptureDraft()
        draft.process(.key(commandK))
        draft.process(.modifierReleased(keyCode: 55))

        draft.process(.key(.init(keyCode: 40, flags: 0), isRepeat: true))

        XCTAssertEqual(draft.combo, commandK)
        XCTAssertTrue(draft.isComplete)
        XCTAssertTrue(draft.isValidSelection)
    }
}
