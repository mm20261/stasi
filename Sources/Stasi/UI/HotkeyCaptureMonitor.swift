import AppKit

enum HotkeyCaptureEvent: Sendable {
    case cancel
    case modifier(HotkeyEngine.Combo)
    case modifierReleased(keyCode: UInt16)
    case key(HotkeyEngine.Combo, isRepeat: Bool = false)

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
            return .key(
                HotkeyEngine.Combo(keyCode: UInt64(event.keyCode), flags: flags),
                isRepeat: event.isARepeat
            )
        default:
            return nil
        }
    }

    private nonisolated static func isModifierKey(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
}

enum HotkeyCaptureEffect: Equatable {
    case none
    case removeMonitor
}

struct HotkeyCaptureState: Equatable {
    private(set) var isRecording = false
    private(set) var draft = HotkeyCaptureDraft()

    mutating func begin(with combo: HotkeyEngine.Combo) {
        isRecording = true
        draft = HotkeyCaptureDraft(combo: combo)
    }

    mutating func process(_ event: HotkeyCaptureEvent) -> HotkeyCaptureEffect {
        draft.process(event)
        guard case .cancel = event else { return .none }
        isRecording = false
        return .removeMonitor
    }

    mutating func stop() {
        isRecording = false
        draft = HotkeyCaptureDraft()
    }
}

struct HotkeyCaptureDraft: Equatable {
    private(set) var combo: HotkeyEngine.Combo?
    private(set) var isComplete: Bool
    private var acceptsInitialReplacement = true

    init(combo: HotkeyEngine.Combo? = nil) {
        self.combo = combo
        self.isComplete = combo.map { $0.flags != 0 } ?? false
    }

    var isValidSelection: Bool {
        guard let combo else { return false }
        if isComplete { return combo.flags != 0 }
        return Self.isModifierKey(combo.keyCode)
    }

    mutating func process(_ event: HotkeyCaptureEvent) {
        switch event {
        case .cancel:
            combo = nil
            isComplete = false
            acceptsInitialReplacement = false
        case .modifier(let combo):
            if isComplete,
               !acceptsInitialReplacement,
               let current = self.combo,
               let modifierFlag = Self.modifierFlag(for: combo.keyCode),
               current.flags & modifierFlag != 0 {
                return
            }
            self.combo = combo
            isComplete = false
            acceptsInitialReplacement = false
        case .modifierReleased:
            guard !isComplete else { return }
            acceptsInitialReplacement = false
            // Ein einzelner Modifier ist eine vollständige, gültige Produktauswahl.
            // Das Loslassen beendet nur die physische Eingabe, nicht den Entwurf.
        case .key(let combo, let isRepeat):
            guard !isRepeat else { return }
            self.combo = combo
            isComplete = true
            acceptsInitialReplacement = false
        }
    }

    private static func isModifierKey(_ keyCode: UInt64) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    private static func modifierFlag(for keyCode: UInt64) -> UInt64? {
        switch keyCode {
        case 54, 55: CGEventFlags.maskCommand.rawValue
        case 56, 60: CGEventFlags.maskShift.rawValue
        case 58, 61: CGEventFlags.maskAlternate.rawValue
        case 59, 62: CGEventFlags.maskControl.rawValue
        case 63: CGEventFlags.maskSecondaryFn.rawValue
        default: nil
        }
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
