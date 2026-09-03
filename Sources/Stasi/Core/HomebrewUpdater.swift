import Foundation
import Observation

enum HomebrewInstallation: Equatable, Sendable {
    case notInstalled
    case brewWithoutCask
    case caskInstalled(brewPath: String)
}

struct HomebrewEnvironment: Sendable {
    typealias FileExists = @Sendable (String) -> Bool

    private static let brewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    private let fileExists: FileExists

    init(fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0) }) {
        self.fileExists = fileExists
    }

    func installation() -> HomebrewInstallation {
        guard let brewPath = Self.brewPaths.first(where: fileExists) else {
            return .notInstalled
        }

        let prefix = URL(fileURLWithPath: brewPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let caskPath = URL(fileURLWithPath: prefix)
            .appendingPathComponent("Caskroom/stasi", isDirectory: true)
            .path

        guard fileExists(caskPath) else { return .brewWithoutCask }
        return .caskInstalled(brewPath: brewPath)
    }
}

struct ProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol ProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessResult
}

enum ProcessRunnerError: Error, Equatable, Sendable {
    case timedOut
    case launchFailed(String)
}

struct FoundationProcessRunner: ProcessRunning {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            try Self.runSynchronously(
                executable: executable,
                arguments: arguments,
                environment: environment,
                timeout: timeout
            )
        }.value
    }

    private static func runSynchronously(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("stasi-homebrew-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: outputDirectory) }

        let stdoutURL = outputDirectory.appendingPathComponent("stdout")
        let stderrURL = outputDirectory.appendingPathComponent("stderr")
        guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
              fileManager.createFile(atPath: stderrURL.path, contents: nil) else {
            throw ProcessRunnerError.launchFailed(
                L10n.text("update.install.error.tempFiles")
            )
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(max(0, timeout))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard !process.isRunning else {
            process.terminate()
            throw ProcessRunnerError.timedOut
        }

        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()
        let stdout = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
        let stderr = String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

enum HomebrewUpdateError: Error, Equatable, Sendable, LocalizedError {
    case failed(details: String)
    case passwordRequired(details: String)
    case timedOut
    case launchFailed(details: String)

    var errorDescription: String? {
        switch self {
        case let .failed(details):
            guard !details.isEmpty else { return L10n.text("update.install.error.failedWithoutDetails") }
            return L10n.text("update.install.error.failed", details)
        case let .passwordRequired(details):
            return L10n.text("update.install.error.password", details)
        case .timedOut:
            return L10n.text("update.install.error.timeout")
        case let .launchFailed(details):
            return L10n.text("update.install.error.launch", details)
        }
    }
}

enum HomebrewUpdater {
    private static let commandEnvironment = [
        "HOMEBREW_NO_ENV_HINTS": "1",
        "HOMEBREW_NO_INSTALL_CLEANUP": "1",
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
        "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
    ]

    static func upgrade(
        runner: any ProcessRunning,
        brewPath: String
    ) async -> Result<Void, HomebrewUpdateError> {
        let commands: [([String], TimeInterval)] = [
            (["update"], 120),
            (["upgrade", "--cask", "stasi"], 300),
        ]

        for (arguments, timeout) in commands {
            do {
                let result = try await runner.run(
                    executable: brewPath,
                    arguments: arguments,
                    environment: commandEnvironment,
                    timeout: timeout
                )
                guard result.exitCode == 0 || isNoOpSuccess(result.stderr) else {
                    let details = stderrExcerpt(result.stderr)
                    if details.localizedCaseInsensitiveContains("password") {
                        return .failure(.passwordRequired(details: details))
                    }
                    return .failure(.failed(details: details))
                }
            } catch ProcessRunnerError.timedOut {
                return .failure(.timedOut)
            } catch let ProcessRunnerError.launchFailed(message) {
                return .failure(.launchFailed(details: stderrExcerpt(message)))
            } catch {
                return .failure(.launchFailed(details: stderrExcerpt(error.localizedDescription)))
            }
        }

        return .success(())
    }

    static func relaunchCommand(appPath: String) -> (executable: String, arguments: [String]) {
        let installedPath = "/Applications/Stasi.app"
        let targetPath = appPath == installedPath ? appPath : installedPath
        let quotedPath = "'\(targetPath.replacingOccurrences(of: "'", with: "'\\''"))'"
        return (
            executable: "/bin/sh",
            arguments: ["-c", "sleep 1; /usr/bin/open \(quotedPath)"]
        )
    }

    private static func isNoOpSuccess(_ stderr: String) -> Bool {
        let value = stderr.lowercased()
        return value.contains("already installed") || value.contains("not outdated")
    }

    private static func stderrExcerpt(_ stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.suffix(300))
    }
}

enum UpdateInstallState: Equatable {
    case idle
    case installing
    case failed(String)
    case installedAwaitingRelaunch
}

/// UI-nahe Zustandsmaschine; die Prozessarbeit selbst bleibt außerhalb des MainActors.
@MainActor
@Observable
final class UpdateInstaller {
    private(set) var installState: UpdateInstallState = .idle
    let installation: HomebrewInstallation

    private let runner: any ProcessRunning

    init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        environment: HomebrewEnvironment = HomebrewEnvironment()
    ) {
        self.runner = runner
        installation = environment.installation()
    }

    func install() async {
        guard installState != .installing,
              case let .caskInstalled(brewPath) = installation else { return }

        installState = .installing
        let result = await HomebrewUpdater.upgrade(runner: runner, brewPath: brewPath)
        switch result {
        case .success:
            installState = .installedAwaitingRelaunch
        case let .failure(error):
            DebugLog.log("STASI-APP: Homebrew-Update fehlgeschlagen: \(error.localizedDescription)")
            installState = .failed(error.localizedDescription)
        }
    }

    func reportRelaunchFailure(_ details: String) {
        installState = .failed(L10n.text("update.install.error.relaunch", details))
    }
}
