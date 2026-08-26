import AppKit

enum HotkeyCaptureEvent: Sendable {
    case cancel
    case modifier(HotkeyEngine.Combo)
    case modifierReleased(keyCode: UInt16)
    case key(HotkeyEngine.Combo)

    nonisolated static func parse(_ event: NSEvent) -> HotkeyCaptureEvent? {
        switch event.type {
        case .keyDown where event.keyCode == 53:
            return .cancel
        case .flagsChanged:
            if isModifierKey(event.keyCode),
               (!event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                || (event.keyCode == 63 && event.modifierFlags.contains(.function))) {
                return .modifier(HotkeyEngine.Combo(keyCode: UInt64(event.keyCode), flags: 0))
            }
            return .modifierReleased(keyCode: event.keyCode)
        case .keyDown:
            var flags: UInt64 = 0
            if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
            if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
            if event.modifierFlags.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
            if event.modifierFlags.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
            return .key(HotkeyEngine.Combo(keyCode: UInt64(event.keyCode), flags: flags))
        default:
            return nil
        }
    }

    private nonisolated static func isModifierKey(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
}

private final class HotkeyCaptureEventBox: NSObject, @unchecked Sendable {
    let event: HotkeyCaptureEvent

    init(_ event: HotkeyCaptureEvent) {
        self.event = event
    }
}

/// NSEvent liefert eine nicht-isolierte Closure. Der SwiftUI-Zustand wird
/// deshalb ausschließlich über ObjC-Dispatch auf dem Main-Thread verändert.
@MainActor
final class HotkeyCaptureMonitorTarget: NSObject {
    private let handler: (HotkeyCaptureEvent) -> Void

    init(handler: @escaping (HotkeyCaptureEvent) -> Void) {
        self.handler = handler
    }

    nonisolated func send(_ event: HotkeyCaptureEvent) {
        performSelector(
            onMainThread: #selector(deliver(_:)),
            with: HotkeyCaptureEventBox(event),
            waitUntilDone: true
        )
    }

    @objc private func deliver(_ box: HotkeyCaptureEventBox) {
        handler(box.event)
    }
}
