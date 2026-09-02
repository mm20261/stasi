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
        s.ironyOn ? "Lebenslang geführt. Alle 10.000 Wörter ein neuer Meilenstein."
                  : "Alle diktierten Wörter seit deinem ersten Protokoll."
    }

    static let akteMilestone = "10.000-Wörter-Meilenstein"

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

    // Fehler-Toasts; erfolgreiche/verworfene Aktionen bleiben bewusst still.
    static let toastNothingHeard = "Nichts gehört"
    static let toastTranscriptionAborted = "Transkription abgebrochen – bitte erneut versuchen"

    // Aufnahme-Pill
    static let pillModelLoading = "Modell lädt…"

    // Deterministische Nachbearbeitung
    static let postProcessingTitle = "Nachbearbeitung"
    static let postProcessingOffLabel = "AUS"
    static let postProcessingStandardLabel = "STANDARD"
    static func postProcessingDescription(for level: PolishLevel) -> String {
        switch level {
        case .off: "Nur Wörterbuch-Korrekturen; das Transkript bleibt ansonsten unverändert."
        case .standard: "Entfernt Füllwörter und löst nur eindeutige Selbstkorrekturen."
        }
    }

    // Anleitungsleiste im Bericht
    static let anleitungText = "halten, Startton abwarten, dann sprechen."
    static let anleitungStatusReady = "Bereit"
    static let anleitungStatusBlocked = "Hotkey inaktiv"
    static let hotkeyRestartRequired = "Neustart nötig"

    // Leerzustand erster Start
    static let firstStartTitle = "Noch nichts protokolliert."
    static func firstStartBody(combo: HotkeyEngine.Combo) -> String {
        "Setz den Cursor in ein Textfeld, halte \(VirtualKey.display(combo)), warte den Startton ab und sprich einen Satz. Beim Loslassen steht er da."
    }
    static let onboardingTrialEmpty =
        "Noch nichts erfasst – halte die Taste, warte den Startton ab und sprich einen Satz."
    static let firstStartTryButton = "Jetzt ausprobieren"
    static let firstStartChangeKeyButton = "Taste ändern"

    static let insightsEmpty = "Noch nichts zu zählen – diktiere dein erstes Protokoll."
    static let resetProtocolSearch = "Suche & Filter zurücksetzen"

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
        weekdayFormatter.calendar = calendar
        dayMonthFormatter.calendar = calendar
        let weekday = weekdayFormatter.string(from: date).uppercased()
        let dayMonth = dayMonthFormatter.string(from: date).uppercased()
        return "\(weekday), \(dayMonth)"
    }

    /// Deutsche Tausenderpunkte (1284 → „1.284").
    static func formatGermanNumber(_ n: Int) -> String {
        germanNumberFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()
    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter
    }()
    private static let germanNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()
}
