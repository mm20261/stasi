import Foundation

/// Laufzeit-Lokalisierung für SwiftUI, AppKit und Core-Fehlertexte.
enum L10n {
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        // Der Prozessname ist unter dem CLI-Runner stabiler als eine dynamische
        // XCTestCase-Suche. So bleiben bestehende deutsche Textverträge auch auf
        // englischen Build-Hosts deterministisch.
        private var override: String? = ProcessInfo.processInfo.processName == "xctest"
            ? "de"
            : nil

        func read() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return override
        }

        func write(_ value: String?) {
            lock.lock()
            override = value
            lock.unlock()
        }
    }

    private static let state = State()

    /// `nil` folgt der Systemsprache; unbekannte Codes fallen auf Deutsch zurück.
    static var languageOverride: String? {
        get { state.read() }
        set { state.write(normalizedLanguage(newValue)) }
    }

    static func text(_ key: String, _ args: CVarArg...) -> String {
        let resourceBundle = StasiResources.bundle
        let requestedLanguage = state.read()
            ?? resourceBundle.preferredLocalizations.first
            ?? "de"
        let selectedLanguage = normalizedLanguage(requestedLanguage) ?? "de"
        let selectedBundle = localizedBundle(
            language: selectedLanguage,
            resourceBundle: resourceBundle
        )
        let germanBundle = localizedBundle(
            language: "de",
            resourceBundle: resourceBundle
        )
        let selectedValue = selectedBundle?.localizedString(
            forKey: key,
            value: nil,
            table: nil
        )
        let germanValue = germanBundle?.localizedString(
            forKey: key,
            value: nil,
            table: nil
        )
        let format = selectedValue.flatMap { $0 == key ? nil : $0 }
            ?? germanValue.flatMap { $0 == key ? nil : $0 }
            ?? key

        guard !args.isEmpty else { return format }
        // printf-Platzhalter bleiben technisch stabil: Eine Locale würde etwa
        // OSStatus -10868 als „-10.868“ gruppieren und Fehlerverträge brechen.
        return String(format: format, arguments: args)
    }

    static var activeLanguageCode: String {
        let resourceBundle = StasiResources.bundle
        return state.read()
            ?? resourceBundle.preferredLocalizations.first
            .flatMap(normalizedLanguage)
            ?? "de"
    }

    static var activeLocale: Locale {
        Locale(identifier: activeLanguageCode == "en" ? "en_US" : "de_DE")
    }

    private static func normalizedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let code = language
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased()
        return code == "de" || code == "en" ? code : language.lowercased()
    }

    private static func localizedBundle(
        language: String,
        resourceBundle: Bundle
    ) -> Bundle? {
        guard language == "de" || language == "en",
              let path = resourceBundle.path(forResource: language, ofType: "lproj")
        else { return nil }
        return Bundle(path: path)
    }
}
