import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

// MARK: - Permissions
// Drei getrennte Berechtigungen:
//   · Mikrofon            – Aufnahme
//   · Bedienungshilfen    – AXIsProcessTrusted (Text-Einfügen, PostEvent)
//   · Eingabe-Überwachung – CGEventTap listen-only (GlobalHotkey, ListenEvent)!
//     Ohne sie wird der Tap angelegt, aber ES KOMMEN KEINE EVENTS an.

enum Permissions {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Eingabe-Überwachung (für den globalen Hotkey-Tap) – der entscheidende,
    /// oft übersehene zweite Schalter.
    static var listenEventGranted: Bool {
        CGPreflightListenEventAccess()
    }

    /// Fordert Eingabe-Überwachung an (löst beim Fehlen den Systemdialog aus).
    static func requestListenEvent() {
        CGRequestListenEventAccess()
    }

    static func openSystemSettings(_ path: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoring() {
        openSystemSettings("Privacy_ListenEvent")
    }
}
