import XCTest
import CoreGraphics
@testable import Stasi

// MARK: - ShortcutDetector (⌃⌘V/⌃⌘C-Chords + Fn-Doppeltipp)

final class ShortcutDetectorTests: XCTestCase {

    private let ctrlCmd: UInt64 = CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue
    private let insertLast = HotkeyEngine.Combo(keyCode: 9, flags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue)
    private let copyLast = HotkeyEngine.Combo(keyCode: 8, flags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue)

    func testChordFiresOnMatchingKeyDown() {
        var d = ShortcutDetector()
        d.chords = [insertLast]
        let events = d.process(kind: .keyDown, keyCode: 9, flags: ctrlCmd)
        XCTAssertEqual(events, [.chord(insertLast)])
    }

    func testChordRequiresAllModifiers() {
        var d = ShortcutDetector()
        d.chords = [insertLast]
        let events = d.process(kind: .keyDown, keyCode: 9, flags: CGEventFlags.maskCommand.rawValue)
        XCTAssertTrue(events.isEmpty)
    }

    func testChordIgnoresAutorepeat() {
        var d = ShortcutDetector()
        d.chords = [copyLast]
        let events = d.process(kind: .keyDown, keyCode: 8, flags: ctrlCmd, isRepeat: true)
        XCTAssertTrue(events.isEmpty)
    }

    func testChordDoesNotFireOnKeyUp() {
        var d = ShortcutDetector()
        d.chords = [insertLast]
        let events = d.process(kind: .keyUp, keyCode: 9, flags: ctrlCmd)
        XCTAssertTrue(events.isEmpty)
    }

    func testDistinguishesChordsByKeyCode() {
        var d = ShortcutDetector()
        d.chords = [insertLast, copyLast]
        let events = d.process(kind: .keyDown, keyCode: 8, flags: ctrlCmd)
        XCTAssertEqual(events, [.chord(copyLast)])
    }

    func testAppCommandsMapCopyAndInsertChords() {
        XCTAssertEqual(AppState.hotkeyCommand(for: AppState.copyLastChord), .copyLast)
        XCTAssertEqual(AppState.hotkeyCommand(for: AppState.insertLastChord), .insertLast)
        XCTAssertNil(AppState.hotkeyCommand(for: .defaultPTT))
    }

    func testFnSingleTapDoesNotFire() {
        var d = ShortcutDetector()
        d.handsFreeEnabled = true
        let t0 = Date(timeIntervalSince1970: 0)
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                      flags: ShortcutDetector.secondaryFn, now: t0)
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                      flags: 0, now: t0.addingTimeInterval(0.1))
        let events = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                               flags: ShortcutDetector.secondaryFn, now: t0.addingTimeInterval(10))
        XCTAssertTrue(events.isEmpty)
    }

    func testFnDoubleTapFires() {
        var d = ShortcutDetector()
        d.handsFreeEnabled = true
        let t0 = Date(timeIntervalSince1970: 0)
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                      flags: ShortcutDetector.secondaryFn, now: t0)
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                      flags: 0, now: t0.addingTimeInterval(0.15))
        let events = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                               flags: ShortcutDetector.secondaryFn, now: t0.addingTimeInterval(0.25))
        XCTAssertEqual(events, [.handsFreeTap])
    }

    func testFnDoubleTapTooSlowDoesNotFire() {
        var d = ShortcutDetector()
        d.handsFreeEnabled = true
        let t0 = Date(timeIntervalSince1970: 0)
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                      flags: ShortcutDetector.secondaryFn, now: t0)
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                      flags: 0, now: t0.addingTimeInterval(0.2))
        let events = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                               flags: ShortcutDetector.secondaryFn, now: t0.addingTimeInterval(0.6))
        XCTAssertTrue(events.isEmpty)
    }

    func testHandsFreeDisabledSuppressesFnEvents() {
        var d = ShortcutDetector()
        d.handsFreeEnabled = false
        let t0 = Date(timeIntervalSince1970: 0)
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                      flags: ShortcutDetector.secondaryFn, now: t0)
        let events = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode,
                               flags: ShortcutDetector.secondaryFn, now: t0.addingTimeInterval(0.1))
        XCTAssertTrue(events.isEmpty)
    }

    func testFnDoubleTapConsumedOnlyOnce() {
        var d = ShortcutDetector()
        d.handsFreeEnabled = true
        let t0 = Date(timeIntervalSince1970: 0)
        // Doppeltipp → feuert
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode, flags: ShortcutDetector.secondaryFn, now: t0)
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode, flags: 0, now: t0.addingTimeInterval(0.1))
        let fired = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode, flags: ShortcutDetector.secondaryFn, now: t0.addingTimeInterval(0.2))
        XCTAssertEqual(fired, [.handsFreeTap])
        // Loslassen + einzelner neuer Tap → kein weiteres Fire
        _ = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode, flags: 0, now: t0.addingTimeInterval(0.3))
        let single = d.process(kind: .flagsChanged, keyCode: ShortcutDetector.fnKeyCode, flags: ShortcutDetector.secondaryFn, now: t0.addingTimeInterval(0.4))
        XCTAssertTrue(single.isEmpty)
    }
}
