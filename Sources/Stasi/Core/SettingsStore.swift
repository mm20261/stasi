import Foundation
import SwiftUI
import ServiceManagement
import AVFoundation

// MARK: - SettingsStore
// Alle Präferenzen. WICHTIG: gespeicherte @Observable-Properties mit didSet-
// Persistenz – berechnete Properties über UserDefaults werden vom Observable-
// Makro NICHT getrackt (Views würden bei Änderung nicht neu zeichnen).

/// Aufbewahrungsdauer für Aufnahmen/Protokolle.
enum Retention: String, CaseIterable, Identifiable {
    case forever, oneDay, oneWeek, twoWeeks, oneMonth
    var id: String { rawValue }

    /// Tage; nil = nie löschen.
    var days: Int? {
        switch self {
        case .forever: nil
        case .oneDay: 1
        case .oneWeek: 7
        case .twoWeeks: 14
        case .oneMonth: 30
        }
    }

    var label: String {
        switch self {
        case .forever: "Nie löschen"
        case .oneDay: "1 Tag"
        case .oneWeek: "1 Woche"
        case .twoWeeks: "2 Wochen"
        case .oneMonth: "1 Monat"
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { switch self { case .system: "System"; case .light: "Hell"; case .dark: "Dunkel" } }
    }

    enum HotkeyMode: String, CaseIterable, Identifiable {
        case pushToTalk, toggle
        var id: String { rawValue }
        var label: String { self == .pushToTalk ? "Push-to-talk" : "Umschalten" }
    }

    static let accentPresets: [(String, UInt32)] = [
        ("Anthrazit", 0x1A1917), ("Blau", 0x1D4E89), ("Orange", 0xD64500),
        ("Grün", 0x2D6A4F), ("Violett", 0x5B4A8A),
    ]

    private let d: UserDefaults

    /// `defaults` ist für Tests injizierbar (eigene Suite).
    init(defaults: UserDefaults = .standard) {
        self.d = defaults
        if let raw = defaults.string(forKey: "stasi.appearance"),
           let a = Appearance(rawValue: raw) { appearance = a }
        if let n = defaults.object(forKey: "stasi.accentHex") as? Int { accentHex = UInt32(n) }
        userName = defaults.string(forKey: "stasi.userName") ?? ""
        avatarPath = defaults.string(forKey: "stasi.avatarPath")
        if let raw = defaults.string(forKey: "stasi.hotkeyMode"),
           let m = HotkeyMode(rawValue: raw) { hotkeyMode = m }
        language = defaults.string(forKey: "stasi.langChoice") ?? "auto"
        soundOn = defaults.object(forKey: "stasi.soundOn") as? Bool ?? true
        aiPostProcess = defaults.object(forKey: "stasi.aiOn") as? Bool ?? false
        ironyOn = defaults.object(forKey: "stasi.ironyOn") as? Bool ?? false
        autostartOn = defaults.object(forKey: "stasi.autostartOn") as? Bool ?? false
        if let raw = defaults.string(forKey: "stasi.retention"),
           let r = Retention(rawValue: raw) { retention = r }

        Theme.sharedSettings = self
    }

    // MARK: Gespeicherte, beobachtbare Properties

    var appearance: Appearance = .system {
        didSet { d.set(appearance.rawValue, forKey: "stasi.appearance") }
    }

    var accentHex: UInt32 = 0x1A1917 {
        didSet { d.set(Int(accentHex), forKey: "stasi.accentHex") }
    }

    /// Beobachtbar: Views über Theme.accent tracken automatisch mit.
    var accentColor: Color { Color(stasiHex: accentHex) }

    var accentPressedColor: Color {
        let r = max(((accentHex >> 16) & 0xFF) * 80 / 100, 0)
        let g = max(((accentHex >> 8) & 0xFF) * 80 / 100, 0)
        let b = max((accentHex & 0xFF) * 80 / 100, 0)
        return Color(stasiHex: (r << 16) | (g << 8) | b)
    }

    var userName: String = "" {
        didSet { d.set(userName, forKey: "stasi.userName") }
    }

    var avatarPath: String? {
        didSet { d.set(avatarPath, forKey: "stasi.avatarPath") }
    }

    var hotkeyMode: HotkeyMode = .pushToTalk {
        didSet { d.set(hotkeyMode.rawValue, forKey: "stasi.hotkeyMode") }
    }

    var language: String = "auto" {   // "auto" | "de_DE" | "en_US"
        didSet { d.set(language, forKey: "stasi.langChoice") }
    }

    var soundOn: Bool = true {
        didSet { d.set(soundOn, forKey: "stasi.soundOn") }
    }

    var aiPostProcess: Bool = false {
        didSet { d.set(aiPostProcess, forKey: "stasi.aiOn") }
    }

    var ironyOn: Bool = true {
        didSet { d.set(ironyOn, forKey: "stasi.ironyOn") }
    }

    var autostartOn: Bool = false {
        didSet {
            d.set(autostartOn, forKey: "stasi.autostartOn")
            try? autostartOn ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    var retention: Retention = .forever {
        didSet { d.set(retention.rawValue, forKey: "stasi.retention") }
    }

    // MARK: Init – Zustand aus Defaults laden

    // MARK: Abgeleitetes

    /// Locale für SpeechTranscriber; „Automatisch" nutzt die Systemsprache.
    var transcriptionLocale: Locale {
        switch language {
        case "de_DE": Locale(identifier: "de_DE")
        case "en_US": Locale(identifier: "en_US")
        default: Locale.current
        }
    }

    var avatarImage: NSImage? {
        guard let avatarPath, let img = NSImage(contentsOfFile: avatarPath) else { return nil }
        return img
    }

    func copyAvatarToAppSupport(from url: URL) {
        let dest = DictionaryStore.appSupportDirectory
            .appendingPathComponent("avatar.\(url.pathExtension.isEmpty ? "png" : url.pathExtension)")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
        avatarPath = dest.path
    }
}

// MARK: - Ironie-Schalter (Copy app-weit)

enum Copy {
    @MainActor
    static func tagline(_ s: SettingsStore) -> String { s.ironyOn ? "Wir hören zu." : "Lokales Diktat." }
    @MainActor
    static func protocolsSubtitle(_ s: SettingsStore, count: Int) -> String {
        let n = "\(count) Protokolle"
        return s.ironyOn ? "\(n) · alles dokumentiert, nichts vergessen."
                         : "\(n)"
    }
    @MainActor
    static func emptyProtocols(_ s: SettingsStore) -> String {
        s.ironyOn ? "Die Akte ist leer. Das kommt selten vor." : "Noch keine Protokolle."
    }
    @MainActor
    static func privacyFootnote(_ s: SettingsStore) -> String {
        s.ironyOn
            ? "Alle Aufnahmen werden lokal auf deinem Mac verarbeitet. Niemand hört mit. Ehrlich. Das wäre ja auch ironisch."
            : "Alle Aufnahmen werden ausschließlich lokal auf deinem Mac verarbeitet."
    }
}
