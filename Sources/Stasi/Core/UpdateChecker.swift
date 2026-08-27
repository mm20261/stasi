import Foundation

// MARK: - AppVersion (Anzeige-Konstanten)

enum AppVersion {
    static var display: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "dev"
    }
    static let akte = "001"
}

// MARK: - Release-Quelle

enum ReleaseConfiguration {
    private static let repositoryAPIURLKey = "STASI_RELEASE_API_URL"

    static var repositoryAPIURL: URL? {
        repositoryAPIURL(infoDictionary: Bundle.main.infoDictionary)
    }

    static func repositoryAPIURL(infoDictionary: [String: Any]?) -> URL? {
        guard let rawValue = infoDictionary?[repositoryAPIURLKey] as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

struct ReleaseInfo: Equatable, Sendable {
    /// Roher Versions-Tag der Veröffentlichung („v0.10").
    let version: String
    let url: URL
}

protocol ReleaseFetching: Sendable {
    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo
}

struct GitHubReleaseFetcher: ReleaseFetching {
    struct Payload: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    enum FetchError: Error { case badStatus }

    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo {
        var request = URLRequest(url: repositoryURL)
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

// MARK: - Versionsvergleich (numerisch, nicht lexikografisch!)

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

// MARK: - Expliziter Checkstatus und pure UI-Ableitung

enum UpdateCheckStatus: Equatable {
    case neverChecked
    case checking
    case upToDate(Date)
    case updateAvailable(version: String, url: URL, checkedAt: Date)
    case failed(message: String)
}

struct UpdateStatusPresentation: Equatable {
    enum ColorRole: Equatable {
        case neutral
        case success
        case updateAvailable
        case warning
    }

    let text: String
    let colorRole: ColorRole
    let showsProgress: Bool

    init(text: String, colorRole: ColorRole, showsProgress: Bool) {
        self.text = text
        self.colorRole = colorRole
        self.showsProgress = showsProgress
    }

    init(status: UpdateCheckStatus, now: Date = Date(), calendar: Calendar = .current) {
        switch status {
        case .neverChecked:
            self.init(text: "NOCH NIE GEPRÜFT", colorRole: .neutral, showsProgress: false)
        case .checking:
            self.init(text: "PRÜFUNG LÄUFT …", colorRole: .neutral, showsProgress: true)
        case let .upToDate(checkedAt):
            self.init(
                text: UpdateStatusFormatter.statusText(
                    lastChecked: checkedAt,
                    available: nil,
                    now: now,
                    calendar: calendar
                ),
                colorRole: .success,
                showsProgress: false
            )
        case let .updateAvailable(version, _, checkedAt):
            self.init(
                text: UpdateStatusFormatter.statusText(
                    lastChecked: checkedAt,
                    available: version,
                    now: now,
                    calendar: calendar
                ),
                colorRole: .updateAvailable,
                showsProgress: false
            )
        case let .failed(message):
            self.init(text: message, colorRole: .warning, showsProgress: false)
        }
    }
}

private enum UpdateStatusFormatter {
    static func statusText(
        lastChecked: Date?,
        available: String?,
        now: Date,
        calendar: Calendar
    ) -> String {
        guard let lastChecked else { return "NOCH NIE GEPRÜFT" }

        var text: String
        if calendar.isDate(lastChecked, inSameDayAs: now) {
            text = "ZULETZT GEPRÜFT: HEUTE, \(timeText(lastChecked, timeZone: calendar.timeZone))"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(lastChecked, inSameDayAs: yesterday) {
            text = "ZULETZT GEPRÜFT: GESTERN"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("dd. MMMM")
            text = "ZULETZT GEPRÜFT: \(formatter.string(from: lastChecked).uppercased())"
        }
        if let available {
            text += " · V \(available) LIEGT BEREIT"
        }
        return text
    }

    private static func timeText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Checker

@MainActor
@Observable
final class UpdateChecker {
    struct State: Equatable {
        /// Zeitpunkt des letzten erfolgreichen Checks.
        var lastChecked: Date?
        /// Normalisierte Version (ohne „v"), nil = keine neue verfügbar.
        var availableVersion: String?
        /// Zielseite der verfügbaren Veröffentlichung.
        var releaseURL: URL?
    }

    private(set) var state: State
    private(set) var status: UpdateCheckStatus
    let currentVersion: String

    var isChecking: Bool {
        if case .checking = status { return true }
        return false
    }

    private var fetcher: any ReleaseFetching
    private let repositoryURL: URL?
    private let defaults: UserDefaults
    private let now: () -> Date

    private static let lastCheckedKey = "stasi.update.lastChecked"
    private static let availableKey = "stasi.update.available"
    private static let releaseURLKey = "stasi.update.releaseURL"

    init(
        fetcher: any ReleaseFetching = GitHubReleaseFetcher(),
        repositoryURL: URL? = ReleaseConfiguration.repositoryAPIURL,
        defaults: UserDefaults = .standard,
        currentVersion: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.repositoryURL = repositoryURL
        self.defaults = defaults
        self.currentVersion = currentVersion ?? AppVersion.display
        self.now = now

        let lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
        let available = defaults.string(forKey: Self.availableKey)
        let releaseURL = defaults.string(forKey: Self.releaseURLKey).flatMap(URL.init(string:))
        let initialState = State(
            lastChecked: lastChecked,
            availableVersion: available,
            releaseURL: releaseURL
        )
        state = initialState
        if let lastChecked, let available, let releaseURL {
            status = .updateAvailable(
                version: available,
                url: releaseURL,
                checkedAt: lastChecked
            )
        } else if let lastChecked {
            status = .upToDate(lastChecked)
        } else {
            status = .neverChecked
        }
    }

    func replaceFetcher(_ newFetcher: any ReleaseFetching) {
        fetcher = newFetcher
    }

    func check() async {
        guard !isChecking else { return }
        status = .checking

        guard let repositoryURL else {
            status = .failed(message: "Update-Prüfung nicht konfiguriert.")
            return
        }

        do {
            let release = try await fetcher.fetchLatestRelease(from: repositoryURL)
            let checkedAt = now()
            let newer = VersionComparator.isNewer(release.version, than: currentVersion)

            state.lastChecked = checkedAt
            if newer {
                let version = VersionComparator.display(release.version)
                state.availableVersion = version
                state.releaseURL = release.url
                status = .updateAvailable(
                    version: version,
                    url: release.url,
                    checkedAt: checkedAt
                )
            } else {
                state.availableVersion = nil
                state.releaseURL = nil
                status = .upToDate(checkedAt)
            }
            persistSuccessfulCheck()
        } catch {
            DebugLog.log("STASI-APP: Update-Check fehlgeschlagen: \(error.localizedDescription)")
            status = .failed(message: "Update-Prüfung fehlgeschlagen.")
        }
    }

    private func persistSuccessfulCheck() {
        guard let lastChecked = state.lastChecked else { return }
        defaults.set(lastChecked, forKey: Self.lastCheckedKey)

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

    static func statusText(
        lastChecked: Date?,
        available: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        UpdateStatusFormatter.statusText(
            lastChecked: lastChecked,
            available: available,
            now: now,
            calendar: calendar
        )
    }
}
