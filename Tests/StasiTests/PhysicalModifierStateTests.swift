import XCTest
@testable import Stasi

final class PhysicalModifierStateTests: XCTestCase {
    private let leftCommand: UInt64 = 55
    private let rightCommand: UInt64 = 54
    private let leftShift: UInt64 = 56
    private let rightShift: UInt64 = 60
    private let leftOption: UInt64 = 58
    private let rightOption: UInt64 = 61
    private let leftControl: UInt64 = 59
    private let rightControl: UInt64 = 62

    func testReleasingRightCommandWhileLeftCommandRemainsPressedReleasesRight() {
        assertRightReleaseWhileLeftRemainsPressed(left: leftCommand, right: rightCommand)
    }

    func testReleasingRightShiftWhileLeftShiftRemainsPressedReleasesRight() {
        assertRightReleaseWhileLeftRemainsPressed(left: leftShift, right: rightShift)
    }

    func testReleasingRightOptionWhileLeftOptionRemainsPressedReleasesRight() {
        assertRightReleaseWhileLeftRemainsPressed(left: leftOption, right: rightOption)
    }

    func testReleasingRightControlWhileLeftControlRemainsPressedReleasesRight() {
        assertRightReleaseWhileLeftRemainsPressed(left: leftControl, right: rightControl)
    }

    func testDuplicateReleaseEventsDoNotChangeStateTwice() {
        var state = PhysicalModifierState()

        XCTAssertFalse(state.processFlagsChanged(keyCode: rightCommand, familyFlagIsSet: false))
        XCTAssertFalse(state.processFlagsChanged(keyCode: rightCommand, familyFlagIsSet: false))
        XCTAssertTrue(state.pressedKeyCodes.isEmpty)

        XCTAssertTrue(state.processFlagsChanged(keyCode: rightCommand, familyFlagIsSet: true))
        XCTAssertFalse(state.processFlagsChanged(keyCode: rightCommand, familyFlagIsSet: false))
        XCTAssertFalse(state.processFlagsChanged(keyCode: rightCommand, familyFlagIsSet: false))
        XCTAssertTrue(state.pressedKeyCodes.isEmpty)
    }

    private func assertRightReleaseWhileLeftRemainsPressed(left: UInt64, right: UInt64) {
        var state = PhysicalModifierState()

        XCTAssertTrue(state.processFlagsChanged(keyCode: right, familyFlagIsSet: true))
        XCTAssertTrue(state.processFlagsChanged(keyCode: left, familyFlagIsSet: true))
        XCTAssertFalse(state.processFlagsChanged(keyCode: right, familyFlagIsSet: true))
        XCTAssertTrue(state.pressedKeyCodes.contains(left))
        XCTAssertFalse(state.pressedKeyCodes.contains(right))
    }
}
