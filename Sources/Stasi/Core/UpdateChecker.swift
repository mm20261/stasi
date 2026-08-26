import Foundation

// MARK: - AppVersion (Anzeige-Konstanten)

enum AppVersion {
    static var display: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "dev"
    }
    static let akte = "001"
}

// MARK: - UpdateChecker (v4)
// Ersetzt den GitHub-Link in „Über": „Aktuelle Version prüfen" fragt die
// Release-Quelle ab, schreibt Zeitstempel und Ergebnis in die Statuszeile.
// Persistiert über UserDefaults (injizierbar für Tests).

// MARK: Release-Quelle

struct ReleaseInfo: Equatable, Sendable {
    /// Roher Versions-Tag der Veröffentlichung („v0.10").
    let version: String
    let url: URL
}

protocol ReleaseFetching: Sendable {
    func fetchLatestRelease() async throws -> ReleaseInfo
}

struct GitHubReleaseFetcher: ReleaseFetching {
    let url: URL

    init(repoAPIURL: URL = URL(string: "https://api.github.com/repos/leomcguire/stasi/releases/latest")!) {
        self.url = repoAPIURL
    }

    struct Payload: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
    enum FetchError: Error { case badStatus }

    func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.badStatus
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return ReleaseInfo(version: payload.tagName, url: payload.htmlURL)
    }
}

// MARK: Versionsvergleich (numerisch, nicht lexikografisch!)

enum VersionComparator {
    /// „v0.10" → [0, 10]; „V1.2.3" → [1, 2, 3]
    static func components(_ version: String) -> [Int] {
        version.trimmingCharacters(in: .whitespaces)
            .dropFirst(version.hasPrefix("v") || version.hasPrefix("V") ? 1 : 0)
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    /// true, wenn candidate strikt neuer ist als current.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let left = i < a.count ? a[i] : 0
            let right = i < b.count ? b[i] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Anzeigbare Form ohne Präfix: „v0.10" → „0.10"
    static func display(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespaces)
            .dropFirst(version.hasPrefix("v") || version.hasPrefix("V") ? 1 : 0)
            .description
    }
}

// MARK: Checker

@MainActor
@Observable
final class UpdateChecker {
    struct State: Equatable {
        var lastChecked: Date?
        /// Normalisierte Version (ohne „v"), nil = keine neue verfügbar.
        var availableVersion: String?
        /// Zielseite der verfügbaren GitHub-Veröffentlichung.
        var releaseURL: URL?

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.availableVersion == rhs.availableVersion
                && lhs.releaseURL == rhs.releaseURL
                && (lhs.lastChecked.map { $0.timeIntervalSince1970 } ?? -1
                    == rhs.lastChecked.map { $0.timeIntervalSince1970 } ?? -1)
        }
    }

    private(set) var state: State
    private(set) var isChecking = false
    let currentVersion: String
    private var fetcher: ReleaseFetching
    private let defaults: UserDefaults

    private static let lastCheckedKey = "stasi.update.lastChecked"
    private static let availableKey = "stasi.update.available"
    private static let releaseURLKey = "stasi.update.releaseURL"

    init(fetcher: ReleaseFetching = GitHubReleaseFetcher(),
         defaults: UserDefaults = .standard,
         currentVersion: String? = nil) {
        self.fetcher = fetcher
        self.defaults = defaults
        self.currentVersion = currentVersion ?? AppVersion.display
        let lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
        let available = defaults.string(forKey: Self.availableKey)
        let releaseURL = defaults.string(forKey: Self.releaseURLKey).flatMap(URL.init(string:))
        state = State(lastChecked: lastChecked,
                      availableVersion: available,
                      releaseURL: releaseURL)
    }

    func replaceFetcher(_ newFetcher: ReleaseFetching) {
        fetcher = newFetcher
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let release = try await fetcher.fetchLatestRelease()
            let newer = VersionComparator.isNewer(release.version, than: currentVersion)
            state.availableVersion = newer ? VersionComparator.display(release.version) : nil
            state.releaseURL = newer ? release.url : nil
        } catch {
            // Netz-/API-Fehler: Zeitstempel setzen, letztes Ergebnis behalten.
            DebugLog.log("STASI-APP: Update-Check fehlgeschlagen: \(error.localizedDescription)")
        }
        state.lastChecked = Date()
        persist()
    }

    private func persist() {
        if let lastChecked = state.lastChecked {
            defaults.set(lastChecked, forKey: Self.lastCheckedKey)
        }
        if let available = state.availableVersion {
            defaults.set(available, forKey: Self.availableKey)
        } else {
            defaults.removeObject(forKey: Self.availableKey)
        }
        if let releaseURL = state.releaseURL {
            defaults.set(releaseURL.absoluteString, forKey: Self.releaseURLKey)
        } else {
            defaults.removeObject(forKey: Self.releaseURLKey)
        }
    }

    // MARK: Statuszeile

    /// „ZULETZT GEPRÜFT: HEUTE, 09:12 · V 0.10 LIEGT BEREIT"
    static func statusText(lastChecked: Date?, available: String?,
                           now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let lastChecked else { return "NOCH NIE GEPRÜFT" }
        var text: String
        if calendar.isDateInToday(lastChecked) {
            text = "ZULETZT GEPRÜFT: HEUTE, \(timeText(lastChecked))"
        } else if calendar.isDateInYesterday(lastChecked) {
            text = "ZULETZT GEPRÜFT: GESTERN"
        } else {
            formatter.locale = Locale(identifier: "de_DE")
            formatter.setLocalizedDateFormatFromTemplate("dd. MMMM")
            text = "ZULETZT GEPRÜFT: \(formatter.string(from: lastChecked).uppercased())"
        }
        if let available {
            text += " · V \(available) LIEGT BEREIT"
        }
        return text
    }

    private static var formatter = DateFormatter()

    private static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return f.string(from: date)
    }
}
