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
        case .forever: L10n.text("settings.retention.forever")
        case .oneDay: L10n.text("settings.retention.oneDay")
        case .oneWeek: L10n.text("settings.retention.oneWeek")
        case .twoWeeks: L10n.text("settings.retention.twoWeeks")
        case .oneMonth: L10n.text("settings.retention.oneMonth")
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    enum HotkeyMode: String, CaseIterable, Identifiable {
        case pushToTalk, toggle
        var id: String { rawValue }
        var label: String {
            L10n.text(self == .pushToTalk
                ? "settings.hotkeyMode.pushToTalk"
                : "settings.hotkeyMode.toggle")
        }
    }

    /// v3: fünf Akzent-Presets (Standard Anthrazit), nutzer-wählbar.
    nonisolated static var accentPresets: [(String, UInt32)] { [
        (L10n.text("settings.accent.charcoal"), 0x1A1917),
        (L10n.text("settings.accent.blue"), 0x1D4E89),
        (L10n.text("settings.accent.orange"), 0xD64500),
        (L10n.text("settings.accent.green"), 0x2D6A4F),
        (L10n.text("settings.accent.violet"), 0x5B4A8A),
    ] }

    private static let hotkeyDefaultsKey = "stasi.hotkey.combo"

    private let d: UserDefaults
    private let autostartHandler: (Bool) throws -> Void
    private var isRevertingAutostart = false

    /// `defaults` ist für Tests injizierbar (eigene Suite).
    init(defaults: UserDefaults = .standard,
         autostartHandler: @escaping (Bool) throws -> Void = { enabled in
             if enabled {
                 try SMAppService.mainApp.register()
             } else {
                 try SMAppService.mainApp.unregister()
             }
         }) {
        self.d = defaults
        self.autostartHandler = autostartHandler
        if let n = defaults.object(forKey: "stasi.accentHex") as? Int { accentHex = UInt32(n) }
        userName = defaults.string(forKey: "stasi.userName") ?? ""
        avatarPath = defaults.string(forKey: "stasi.avatarPath")
        if let raw = defaults.string(forKey: "stasi.hotkeyMode"),
           let m = HotkeyMode(rawValue: raw) { hotkeyMode = m }
        if let data = defaults.data(forKey: Self.hotkeyDefaultsKey),
           let combo = try? JSONDecoder().decode(HotkeyEngine.Combo.self, from: data) {
            hotkeyCombo = combo
        }
        handsFreeOn = defaults.object(forKey: "stasi.handsFreeOn") as? Bool ?? true
        if let number = defaults.object(forKey: "stasi.handsFree.keyCode") as? NSNumber,
           VirtualKey.isHandsFreeModifier(number.uint64Value) {
            handsFreeKeyCode = number.uint64Value
        }
        language = defaults.string(forKey: "stasi.langChoice") ?? "auto"
        uiLanguage = defaults.string(forKey: "stasi.uiLanguage") ?? "auto"
        soundOn = defaults.object(forKey: "stasi.soundOn") as? Bool ?? true
        if let raw = defaults.string(forKey: "stasi.postProcess"),
           let level = PolishLevel(rawValue: raw) { postProcessing = level }
        defaults.removeObject(forKey: "stasi.aiOn")
        ironyOn = defaults.object(forKey: "stasi.ironyOn") as? Bool ?? false
        autostartOn = defaults.object(forKey: "stasi.autostartOn") as? Bool ?? false
        if let raw = defaults.string(forKey: "stasi.retention"),
           let r = Retention(rawValue: raw) { retention = r }
        preferredMicUID = defaults.string(forKey: "stasi.micUID")
        onboardingDone = defaults.object(forKey: "stasi.onboardingDone") as? Bool ?? false

        // Bei „auto“ ist `nil` bereits der Produktionsstandard. Ein vorhandener
        // expliziter Override (z. B. der globale XCTest-Vertrag) bleibt intakt.
        if uiLanguage != "auto" { L10n.languageOverride = uiLanguage }
        Theme.sharedSettings = self
    }

    // MARK: Gespeicherte, beobachtbare Properties

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

    var hotkeyCombo: HotkeyEngine.Combo = .defaultPTT {
        didSet {
            if let data = try? JSONEncoder().encode(hotkeyCombo) {
                d.set(data, forKey: Self.hotkeyDefaultsKey)
            }
        }
    }

    var handsFreeOn: Bool = true {
        didSet { d.set(handsFreeOn, forKey: "stasi.handsFreeOn") }
    }

    var handsFreeKeyCode: UInt64 = 63 {
        didSet {
            guard VirtualKey.isHandsFreeModifier(handsFreeKeyCode) else {
                handsFreeKeyCode = oldValue
                return
            }
            d.set(Int(handsFreeKeyCode), forKey: "stasi.handsFree.keyCode")
        }
    }

    var language: String = "auto" {   // "auto" | "de_DE" | "en_US"
        didSet { d.set(language, forKey: "stasi.langChoice") }
    }

    /// Oberflächensprache; Änderungen werden beim nächsten App-Start vollständig sichtbar.
    var uiLanguage: String = "auto" { // "auto" | "de" | "en"
        didSet {
            d.set(uiLanguage, forKey: "stasi.uiLanguage")
            L10n.languageOverride = uiLanguage == "auto" ? nil : uiLanguage
        }
    }

    var soundOn: Bool = true {
        didSet { d.set(soundOn, forKey: "stasi.soundOn") }
    }

    var postProcessing: PolishLevel = .standard {
        didSet { d.set(postProcessing.rawValue, forKey: "stasi.postProcess") }
    }

    var ironyOn: Bool = false {
        didSet { d.set(ironyOn, forKey: "stasi.ironyOn") }
    }

    var autostartOn: Bool = false {
        didSet {
            d.set(autostartOn, forKey: "stasi.autostartOn")
            guard !isRevertingAutostart else { return }
            do {
                try autostartHandler(autostartOn)
            } catch {
                DebugLog.log("STASI-APP: Autostart konnte nicht geändert werden: \(error.localizedDescription)")
                guard autostartOn else { return }
                isRevertingAutostart = true
                autostartOn = false
                isRevertingAutostart = false
            }
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
    static func tagline(_ s: SettingsStore) -> String {
        L10n.text(s.ironyOn ? "sidebar.tagline.ironic" : "sidebar.tagline.standard")
    }

    @MainActor
    static func protocolsSubtitle(_ s: SettingsStore, count: Int) -> String {
        let key = count == 1 ? "protocols.count.one" : "protocols.count.many"
        let countText = L10n.text(key, formatGermanNumber(count))
        return s.ironyOn
            ? L10n.text("protocols.subtitle.ironic", countText)
            : countText
    }

    @MainActor
    static func emptyProtocols(_ s: SettingsStore) -> String {
        L10n.text(s.ironyOn ? "protocols.empty.ironic" : "protocols.empty.standard")
    }

    @MainActor
    static func privacyFootnote(_ s: SettingsStore) -> String {
        L10n.text(s.ironyOn ? "settings.privacy.ironic" : "settings.privacy.standard")
    }

    /// Hinweis auf der Rail-Karte „Deine Akte".
    @MainActor
    static func akteNote(_ s: SettingsStore) -> String {
        L10n.text(s.ironyOn ? "dashboard.fileNote.ironic" : "dashboard.fileNote.standard")
    }

    static var akteMilestone: String { L10n.text("dashboard.milestone") }

    @MainActor
    static func insightsSubtitle(_ s: SettingsStore) -> String {
        L10n.text(s.ironyOn ? "insights.subtitle.ironic" : "insights.subtitle.standard")
    }

    @MainActor
    static func accountSubtitle(_ s: SettingsStore) -> String {
        L10n.text(s.ironyOn ? "account.subtitle.ironic" : "account.subtitle.standard")
    }

    // MARK: Feste Texte (nicht ironie-abhängig)

    // Fehler-Toasts; erfolgreiche/verworfene Aktionen bleiben bewusst still.
    static var toastNothingHeard: String { L10n.text("toast.nothingHeard") }
    static var toastTranscriptionAborted: String { L10n.text("toast.transcriptionAborted") }

    // Aufnahme-Pill
    static var pillModelLoading: String { L10n.text("pill.modelLoading") }

    // Deterministische Nachbearbeitung
    static var postProcessingTitle: String { L10n.text("polish.title") }
    static var postProcessingOffLabel: String { L10n.text("polish.level.off") }
    static var postProcessingStandardLabel: String { L10n.text("polish.level.standard") }
    static func postProcessingDescription(for level: PolishLevel) -> String {
        switch level {
        case .off: L10n.text("polish.description.off")
        case .standard: L10n.text("polish.description.standard")
        }
    }

    // Anleitungsleiste im Bericht
    static var anleitungText: String { L10n.text("dashboard.instruction") }
    static var anleitungStatusReady: String { L10n.text("status.ready") }
    static var anleitungStatusBlocked: String { L10n.text("status.hotkeyInactive") }
    static var hotkeyRestartRequired: String { L10n.text("status.restartRequired") }

    // Leerzustand erster Start
    static var firstStartTitle: String { L10n.text("dashboard.firstStart.title") }
    static func firstStartBody(combo: HotkeyEngine.Combo) -> String {
        L10n.text("dashboard.firstStart.body", VirtualKey.display(combo))
    }
    static var onboardingTrialEmpty: String { L10n.text("onboarding.trial.empty") }
    static var firstStartTryButton: String { L10n.text("dashboard.firstStart.try") }
    static var firstStartChangeKeyButton: String { L10n.text("dashboard.firstStart.changeKey") }

    static var insightsEmpty: String { L10n.text("insights.empty") }
    static var resetProtocolSearch: String { L10n.text("protocols.resetSearch") }

    // Warnkarte „Berechtigung fehlt"
    static var permissionWarningTitle: String { L10n.text("permission.warning.title") }
    static var permissionWarningBody: String { L10n.text("permission.warning.body") }
    static var permissionWarningButton: String { L10n.text("permission.allow") }

    // MARK: Begrüßung

    static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return L10n.text("greeting.morning")
        case 11..<14: return L10n.text("greeting.midday")
        case 14..<18: return L10n.text("greeting.afternoon")
        default: return L10n.text("greeting.evening")
        }
    }

    /// H1-Zeile: „Guten Morgen, Philipp." / „Guten Morgen."
    static func greetingLine(for date: Date, name: String,
                             calendar: Calendar = .current) -> String {
        let base = greeting(for: date, calendar: calendar)
        return name.isEmpty
            ? L10n.text("greeting.line.anonymous", base)
            : L10n.text("greeting.line.named", base, name)
    }

    /// Datumszeile mono; Deutsch nutzt de_DE, Englisch en_US.
    static func dateLine(_ date: Date, calendar: Calendar = .current) -> String {
        // FormatStyle ist ein Wertetyp: thread-sicher und nimmt Zeitzone + Kalender
        // des Aufrufers mit (ein geteilter DateFormatter ignorierte die Zeitzone).
        let style = Date.FormatStyle(
            locale: Locale(identifier: L10n.activeLanguageCode == "en" ? "en_US" : "de_DE"),
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        let weekday = date.formatted(style.weekday(.wide)).uppercased()
        let dayMonth = date.formatted(style.day().month(.wide)).uppercased()
        return "\(weekday), \(dayMonth)"
    }

    /// Lokalisierte Tausendertrennzeichen; der Name bleibt als API-Kompatibilität erhalten.
    static func formatGermanNumber(_ n: Int) -> String {
        n.formatted(.number.locale(Locale(
            identifier: L10n.activeLanguageCode == "en" ? "en_US" : "de_DE"
        )))
    }
}
