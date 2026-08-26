import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

// MARK: - Permissions
// Zwei Berechtigungen tragen den Produktionspfad:
//   · Mikrofon            – Aufnahme
//   · Bedienungshilfen    – Session-Tap und Text-Einfügen
// Der ListenEvent-Preflight bleibt nur als Bestands-/Diagnoseanzeige; der
// Session-Tap wird ausschließlich über Bedienungshilfen gegatet.

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

    /// Bestands-/Diagnosewert; der Session-Tap hängt nicht davon ab.
    static var listenEventGranted: Bool {
        CGPreflightListenEventAccess()
    }

    static func openSystemSettings(_ path: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)") {
            NSWorkspace.shared.open(url)
        }
    }
}
