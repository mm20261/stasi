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

    /// Ad-hoc-signierte Builds bekommen mit jedem Update eine neue Code-Signatur.
    /// Der alte Bedienungshilfen-Eintrag zeigt dann „an“, gehört aber zur vorigen
    /// Version; Entfernen/Hinzufügen über die Liste hilft oft nicht. `tccutil reset`
    /// für die eigene Bundle-ID räumt die Karteileiche weg, danach zeigt macOS den
    /// frischen Dialog. Nur sinnvoll, solange das Recht ohnehin fehlt.
    static func tccutilResetArguments(service: String, bundleID: String?) -> [String]? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return ["reset", service, bundleID]
    }

    static func resetStaleAccessibilityEntry(bundleID: String? = Bundle.main.bundleIdentifier) {
        guard !accessibilityGranted,
              let arguments = tccutilResetArguments(service: "Accessibility", bundleID: bundleID)
        else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            DebugLog.log("STASI-APP: tccutil reset Accessibility → Status \(process.terminationStatus)")
        } catch {
            DebugLog.log("STASI-APP: tccutil reset fehlgeschlagen: \(error.localizedDescription)")
        }
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
