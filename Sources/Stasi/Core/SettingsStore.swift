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

    /// v3: fünf Akzent-Presets (Standard Anthrazit), nutzer-wählbar.
    nonisolated static let accentPresets: [(String, UInt32)] = [
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
        preferredMicUID = defaults.string(forKey: "stasi.micUID")
        onboardingDone = defaults.object(forKey: "stasi.onboardingDone") as? Bool ?? false

        Theme.sharedSettings = self
    }

    // MARK: Gespeicherte, beobachtbare Properties

    var appearance: Appearance = .system {
        didSet { d.set(appearance.rawValue, forKey: "stasi.appearance") }
    }

    /// Gewählter Akzent (Hex); v3: fünf Presets, Standard Anthrazit.
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

    /// Gewähltes Eingabegerät (Transport-UID); nil = macOS-Standard.
    var preferredMicUID: String? {
        didSet { d.set(preferredMicUID, forKey: "stasi.micUID") }
    }

    /// Onboarding (vier Schritte) abgeschlossen?
    var onboardingDone: Bool {
        didSet { d.set(onboardingDone, forKey: "stasi.onboardingDone") }
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

// MARK: - Ironie-Schalter (Copy app-weit, v4 „Registratur")

enum Copy {
    @MainActor
    static func tagline(_ s: SettingsStore) -> String { s.ironyOn ? "Wir hören zu." : "Lokales Diktat." }

    @MainActor
    static func protocolsSubtitle(_ s: SettingsStore, count: Int) -> String {
        let n = formatGermanNumber(count) + " Protokolle"
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
            ? "Alle Aufnahmen werden ausschließlich lokal auf diesem Mac verarbeitet. Niemand hört mit. Ehrlich. Das wäre ja auch ironisch."
            : "Alle Aufnahmen werden ausschließlich lokal auf diesem Mac verarbeitet."
    }

    /// Hinweis auf der Rail-Karte „Deine Akte".
    @MainActor
    static func akteNote(_ s: SettingsStore) -> String {
        s.ironyOn ? "Wächst mit jedem Wort. Ohne dein Zutun."
                  : "Dein Diktier-Fortschritt diese Woche."
    }

    @MainActor
    static func insightsSubtitle(_ s: SettingsStore) -> String {
        s.ironyOn ? "Der Überwachungsbericht. Lückenlos, versteht sich."
                  : "Deine Diktier-Statistik."
    }

    @MainActor
    static func accountSubtitle(_ s: SettingsStore) -> String {
        s.ironyOn ? "Deine Akte. Ausnahmsweise führst du sie selbst."
                  : "Dein Profil — lokal gespeichert."
    }

    // MARK: Feste Texte (nicht ironie-abhängig)

    // Toasts (v4: kurz)
    static let toastLogged = "Protokolliert"
    static let toastCopied = "Kopiert — ⌘V"
    static let toastDiscarded = "Verworfen"

    // Anleitungsleiste im Bericht
    static let anleitungText = "halten und sprechen."
    static let anleitungStatusReady = "Bereit"
    static let anleitungStatusBlocked = "Hotkey inaktiv"

    // Leerzustand erster Start
    static let firstStartTitle = "Noch nichts protokolliert."
    static let firstStartBody = "Setz den Cursor in ein Textfeld, halte ⌘ rechts und sprich einen Satz. Beim Loslassen steht er da."
    static let firstStartTryButton = "Jetzt ausprobieren"
    static let firstStartChangeKeyButton = "Taste ändern"

    // Warnkarte „Berechtigung fehlt"
    static let permissionWarningTitle = "Der Hotkey funktioniert noch nicht."
    static let permissionWarningBody = "macOS muss Stasi erlauben, in Textfelder zu schreiben. Ein Klick, dann läuft es."
    static let permissionWarningButton = "Erlauben"

    // MARK: Begrüßung

    static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return "Guten Morgen"
        case 11..<14: return "Guten Tag"
        case 14..<18: return "Guten Nachmittag"
        default: return "Guten Abend"
        }
    }

    /// H1-Zeile: „Guten Morgen, Philipp." / „Guten Morgen."
    static func greetingLine(for date: Date, name: String,
                             calendar: Calendar = .current) -> String {
        let base = greeting(for: date, calendar: calendar)
        return name.isEmpty ? "\(base)." : "\(base), \(name)."
    }

    /// Datumszeile mono: „MONTAG, 24. AUGUST" (fest de_DE – UI ist deutsch).
    static func dateLine(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let weekday = formatter.string(from: date).uppercased()
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        let dayMonth = formatter.string(from: date).uppercased()
        return "\(weekday), \(dayMonth)"
    }

    /// Deutsche Tausenderpunkte (1284 → „1.284").
    static func formatGermanNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
