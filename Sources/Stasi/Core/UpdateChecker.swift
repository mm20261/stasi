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
        guard let url = URL(string: value), SecureReleaseURL.isValid(url) else {
            return nil
        }
        return url
    }
}

enum SecureReleaseURL {
    static func isValid(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    static func sourceIdentifier(for url: URL) -> String? {
        guard isValid(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = components.host?.lowercased()
        components.fragment = nil
        if components.port == 443 { components.port = nil }
        return components.string
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

    enum FetchError: Error { case badStatus, rateLimited }

    private let session: URLSession
    private let appVersion: String

    init(appVersion: String = AppVersion.display) {
        self.appVersion = appVersion
        session = URLSession(configuration: Self.makeConfiguration())
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        return configuration
    }

    static func makeRequest(repositoryURL: URL, appVersion: String) -> URLRequest {
        var request = URLRequest(url: repositoryURL)
        request.timeoutInterval = 15
        request.setValue("Stasi/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    func fetchLatestRelease(from repositoryURL: URL) async throws -> ReleaseInfo {
        let request = Self.makeRequest(repositoryURL: repositoryURL, appVersion: appVersion)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.badStatus
        }
        if http.statusCode == 403 { throw FetchError.rateLimited }
        guard http.statusCode == 200 else { throw FetchError.badStatus }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return ReleaseInfo(version: payload.tagName, url: payload.htmlURL)
    }
}

// MARK: - Striktes Semantic Versioning

struct SemVer: Comparable, CustomStringConvertible {
    private enum PrereleaseIdentifier: Equatable {
        case numeric(String)
        case alphanumeric(String)
    }

    let major: String
    let minor: String
    let patch: String
    private let prerelease: [PrereleaseIdentifier]
    private let prereleaseText: String?
    private let buildMetadata: String?

    var normalizedCore: String { "\(major).\(minor).\(patch)" }

    var description: String {
        var value = normalizedCore
        if let prereleaseText { value += "-\(prereleaseText)" }
        if let buildMetadata { value += "+\(buildMetadata)" }
        return value
    }

    init?(_ rawValue: String) {
        var value = rawValue
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        guard !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let buildParts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else { return nil }
        let precedencePart = String(buildParts[0])
        let parsedBuild = buildParts.count == 2 ? String(buildParts[1]) : nil
        if let parsedBuild, !Self.validDotIdentifiers(parsedBuild, allowLeadingZeroNumeric: true) {
            return nil
        }

        let precedenceParts = precedencePart.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard !precedenceParts[0].isEmpty else { return nil }
        var coreParts = precedenceParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(coreParts.count) else { return nil }
        while coreParts.count < 3 { coreParts.append("0") }
        guard let major = Self.parseCoreNumber(coreParts[0]),
              let minor = Self.parseCoreNumber(coreParts[1]),
              let patch = Self.parseCoreNumber(coreParts[2]) else {
            return nil
        }

        let parsedPrerelease = precedenceParts.count == 2 ? String(precedenceParts[1]) : nil
        var identifiers: [PrereleaseIdentifier] = []
        if let parsedPrerelease {
            guard Self.validDotIdentifiers(parsedPrerelease, allowLeadingZeroNumeric: false) else {
                return nil
            }
            identifiers = parsedPrerelease.split(separator: ".").map { identifier in
                if identifier.allSatisfy({ $0.isNumber }) {
                    return .numeric(String(identifier))
                }
                return .alphanumeric(String(identifier))
            }
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        prerelease = identifiers
        prereleaseText = parsedPrerelease
        buildMetadata = parsedBuild
    }

    static func == (lhs: SemVer, rhs: SemVer) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        for (left, right) in zip(lhsCore, rhsCore) where left != right {
            return numericIdentifierIsLess(left, than: right)
        }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            if left == right { continue }
            switch (left, right) {
            case let (.numeric(a), .numeric(b)): return numericIdentifierIsLess(a, than: b)
            case (.numeric, .alphanumeric): return true
            case (.alphanumeric, .numeric): return false
            case let (.alphanumeric(a), .alphanumeric(b)): return a < b
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func numericIdentifierIsLess(_ lhs: String, than rhs: String) -> Bool {
        if lhs.count != rhs.count { return lhs.count < rhs.count }
        return lhs < rhs
    }

    private static func parseCoreNumber(_ value: Substring) -> String? {
        guard !value.isEmpty,
              value.allSatisfy({ $0.isASCII && $0.isNumber }),
              value == "0" || value.first != "0" else {
            return nil
        }
        return String(value)
    }

    private static func validDotIdentifiers(
        _ value: String,
        allowLeadingZeroNumeric: Bool
    ) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.allSatisfy({ character in
                      character.isASCII && (character.isLetter || character.isNumber || character == "-")
                  }) else {
                return false
            }
            if !allowLeadingZeroNumeric,
               identifier.allSatisfy({ $0.isNumber }),
               identifier.count > 1,
               identifier.first == "0" {
                return false
            }
            return true
        }
    }
}

enum VersionComparator {
    /// nil bedeutet: Mindestens eine Seite ist kein unterstütztes SemVer.
    static func isNewer(_ candidate: String, than current: String) -> Bool? {
        guard let candidate = SemVer(candidate), let current = SemVer(current) else { return nil }
        return candidate > current
    }

    static func display(_ version: String) -> String? {
        SemVer(version)?.description
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
            dateFormatter.timeZone = calendar.timeZone
            text = "ZULETZT GEPRÜFT: \(dateFormatter.string(from: lastChecked).uppercased())"
        }
        if let available {
            text += " · V \(available) LIEGT BEREIT"
        }
        return text
    }

    private static func timeText(_ date: Date, timeZone: TimeZone) -> String {
        timeFormatter.timeZone = timeZone
        return timeFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.setLocalizedDateFormatFromTemplate("dd. MMMM")
        return formatter
    }()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
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
    private static let sourceKey = "stasi.update.source"

    private enum CheckError: Error {
        case invalidSource
        case invalidReleaseURL
        case invalidVersion
    }

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

        let configuredSource = repositoryURL.flatMap(SecureReleaseURL.sourceIdentifier(for:))
        let persistedSource = defaults.string(forKey: Self.sourceKey)
        let lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
        let available = defaults.string(forKey: Self.availableKey)
        let releaseURL = defaults.string(forKey: Self.releaseURLKey).flatMap(URL.init(string:))
        let persistedUpdateIsCurrent = configuredSource != nil
            && configuredSource == persistedSource
            && lastChecked != nil
            && available.flatMap(SemVer.init) != nil
            && SemVer(self.currentVersion) != nil
            && releaseURL.map(SecureReleaseURL.isValid) == true
            && VersionComparator.isNewer(available ?? "", than: self.currentVersion) == true

        if persistedUpdateIsCurrent,
           let lastChecked,
           let available,
           let releaseURL {
            state = State(
                lastChecked: lastChecked,
                availableVersion: available,
                releaseURL: releaseURL
            )
            status = .updateAvailable(
                version: available,
                url: releaseURL,
                checkedAt: lastChecked
            )
        } else {
            state = State(lastChecked: nil, availableVersion: nil, releaseURL: nil)
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
            guard SecureReleaseURL.sourceIdentifier(for: repositoryURL) != nil else {
                throw CheckError.invalidSource
            }
            let release = try await fetcher.fetchLatestRelease(from: repositoryURL)
            guard SecureReleaseURL.isValid(release.url) else {
                throw CheckError.invalidReleaseURL
            }
            guard let newer = VersionComparator.isNewer(release.version, than: currentVersion),
                  let version = VersionComparator.display(release.version) else {
                throw CheckError.invalidVersion
            }
            let checkedAt = now()

            state.lastChecked = checkedAt
            if newer {
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
            persistSuccessfulCheck(sourceURL: repositoryURL)
        } catch {
            DebugLog.log("STASI-APP: Update-Check fehlgeschlagen: \(error.localizedDescription)")
            status = .failed(message: Self.failureMessage(for: error))
        }
    }

    private static func failureMessage(for error: Error) -> String {
        if let urlError = error as? URLError,
           [
               .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
               .cannotConnectToHost, .dnsLookupFailed, .timedOut,
           ].contains(urlError.code) {
            return "Keine Internetverbindung. Update-Prüfung nicht möglich."
        }
        if let fetchError = error as? GitHubReleaseFetcher.FetchError,
           case .rateLimited = fetchError {
            return "GitHub-Limit erreicht. Bitte später erneut prüfen."
        }
        if let checkError = error as? CheckError,
           case .invalidVersion = checkError {
            return "Ungültige Versionsangabe in der Update-Antwort."
        }
        return "Ungültige Antwort vom Update-Server."
    }

    private func persistSuccessfulCheck(sourceURL: URL) {
        guard let lastChecked = state.lastChecked,
              let sourceIdentifier = SecureReleaseURL.sourceIdentifier(for: sourceURL) else { return }
        defaults.set(lastChecked, forKey: Self.lastCheckedKey)
        defaults.set(sourceIdentifier, forKey: Self.sourceKey)

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
