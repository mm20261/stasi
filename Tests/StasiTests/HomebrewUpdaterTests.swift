import Foundation
import XCTest
@testable import Stasi

@MainActor
final class HomebrewUpdaterTests: XCTestCase {
    func testEnvironmentReportsNotInstalledWithoutBrew() {
        let environment = HomebrewEnvironment(fileExists: { _ in false })

        XCTAssertEqual(environment.installation(), .notInstalled)
    }

    func testEnvironmentReportsBrewWithoutStasiCask() {
        let existing = Set(["/opt/homebrew/bin/brew"])
        let environment = HomebrewEnvironment(fileExists: { existing.contains($0) })

        XCTAssertEqual(environment.installation(), .brewWithoutCask)
    }

    func testEnvironmentReportsInstalledCaskAndPrefersAppleSiliconBrew() {
        let existing = Set([
            "/opt/homebrew/bin/brew",
            "/opt/homebrew/Caskroom/stasi",
            "/usr/local/bin/brew",
            "/usr/local/Caskroom/stasi",
        ])
        let environment = HomebrewEnvironment(fileExists: { existing.contains($0) })

        XCTAssertEqual(
            environment.installation(),
            .caskInstalled(brewPath: "/opt/homebrew/bin/brew")
        )
    }

    func testUpgradeRunsUpdateThenCaskUpgradeWithHardenedEnvironment() async {
        let runner = RecordingProcessRunner(outcomes: [
            .success(ProcessResult(exitCode: 0, stdout: "Updated", stderr: "")),
            .success(ProcessResult(exitCode: 0, stdout: "Upgraded", stderr: "")),
        ])

        let result = await HomebrewUpdater.upgrade(
            runner: runner,
            brewPath: "/opt/homebrew/bin/brew"
        )

        assertSuccess(result)
        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.map(\.executable), [
            "/opt/homebrew/bin/brew",
            "/opt/homebrew/bin/brew",
        ])
        XCTAssertEqual(calls.map(\.arguments), [
            ["update"],
            ["upgrade", "--cask", "stasi"],
        ])
        XCTAssertEqual(calls.map(\.timeout), [120, 300])
        XCTAssertEqual(calls[0].environment["HOMEBREW_NO_ENV_HINTS"], "1")
        XCTAssertEqual(calls[0].environment["HOMEBREW_NO_INSTALL_CLEANUP"], "1")
        XCTAssertEqual(calls[0].environment["HOMEBREW_NO_AUTO_UPDATE"], "1")
        XCTAssertEqual(
            calls[0].environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        )
        XCTAssertFalse(calls[0].environment["HOME", default: ""].isEmpty)
        XCTAssertEqual(calls[0].environment, calls[1].environment)
    }

    func testNonzeroExitReturnsFailureWithLast300StderrCharacters() async {
        let stderr = "prefix-" + String(repeating: "x", count: 300)
        let runner = RecordingProcessRunner(outcomes: [
            .success(ProcessResult(exitCode: 1, stdout: "", stderr: stderr)),
        ])

        let result = await HomebrewUpdater.upgrade(
            runner: runner,
            brewPath: "/opt/homebrew/bin/brew"
        )

        XCTAssertEqual(
            failure(of: result),
            .failed(details: String(repeating: "x", count: 300))
        )
    }

    func testAlreadyInstalledMessageMakesNonzeroUpgradeASuccess() async {
        let runner = RecordingProcessRunner(outcomes: [
            .success(ProcessResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ProcessResult(
                exitCode: 1,
                stdout: "",
                stderr: "Warning: stasi 0.10.3 is already installed"
            )),
        ])

        let result = await HomebrewUpdater.upgrade(
            runner: runner,
            brewPath: "/opt/homebrew/bin/brew"
        )

        assertSuccess(result)
    }

    func testNotOutdatedMessageMakesNonzeroUpgradeASuccess() async {
        let runner = RecordingProcessRunner(outcomes: [
            .success(ProcessResult(exitCode: 0, stdout: "", stderr: "")),
            .success(ProcessResult(exitCode: 1, stdout: "", stderr: "stasi is not outdated")),
        ])

        let result = await HomebrewUpdater.upgrade(
            runner: runner,
            brewPath: "/opt/homebrew/bin/brew"
        )

        assertSuccess(result)
    }

    func testRunnerTimeoutIsPropagatedAsUpdateTimeout() async {
        let runner = RecordingProcessRunner(outcomes: [.failure(.timedOut)])

        let result = await HomebrewUpdater.upgrade(
            runner: runner,
            brewPath: "/opt/homebrew/bin/brew"
        )

        XCTAssertEqual(failure(of: result), .timedOut)
    }

    func testPasswordPromptGetsActionableFailure() async {
        let runner = RecordingProcessRunner(outcomes: [
            .success(ProcessResult(
                exitCode: 1,
                stdout: "",
                stderr: "Password required to continue"
            )),
        ])

        let result = await HomebrewUpdater.upgrade(
            runner: runner,
            brewPath: "/opt/homebrew/bin/brew"
        )

        XCTAssertEqual(
            failure(of: result),
            .passwordRequired(details: "Password required to continue")
        )
    }

    func testRelaunchCommandAlwaysTargetsApplicationsInstall() {
        let development = HomebrewUpdater.relaunchCommand(
            appPath: "/Users/test/Stasi/build/Stasi.app"
        )
        let installed = HomebrewUpdater.relaunchCommand(appPath: "/Applications/Stasi.app")

        XCTAssertEqual(development.executable, "/bin/sh")
        XCTAssertEqual(
            development.arguments,
            ["-c", "sleep 1; /usr/bin/open '/Applications/Stasi.app'"]
        )
        XCTAssertEqual(installed.executable, development.executable)
        XCTAssertEqual(installed.arguments, development.arguments)
    }

    func testInstallerTransitionsFromInstallingToAwaitingRelaunch() async {
        let runner = ControlledProcessRunner()
        let installer = UpdateInstaller(
            runner: runner,
            environment: installedEnvironment()
        )

        let task = Task { await installer.install() }
        await runner.waitUntilStarted(callCount: 1)
        XCTAssertEqual(installer.installState, .installing)

        await runner.succeed(ProcessResult(exitCode: 0, stdout: "", stderr: ""))
        await runner.waitUntilStarted(callCount: 2)
        XCTAssertEqual(installer.installState, .installing)

        await runner.succeed(ProcessResult(exitCode: 0, stdout: "", stderr: ""))
        await task.value
        XCTAssertEqual(installer.installState, .installedAwaitingRelaunch)
    }

    func testInstallerTransitionsFromInstallingToLocalizedFailure() async {
        let runner = RecordingProcessRunner(outcomes: [
            .success(ProcessResult(exitCode: 2, stdout: "", stderr: "network unavailable")),
        ])
        let installer = UpdateInstaller(
            runner: runner,
            environment: installedEnvironment()
        )

        await installer.install()

        guard case let .failed(message) = installer.installState else {
            return XCTFail("Fehlerzustand erwartet")
        }
        XCTAssertTrue(message.contains("network unavailable"))
    }

    func testInstallPresentationMapsProgressSuccessAndFailure() {
        let checkStatus = UpdateCheckStatus.updateAvailable(
            version: "0.10.3",
            url: URL(string: "https://example.com/releases/v0.10.3")!,
            checkedAt: Date(timeIntervalSince1970: 1_777_777_777)
        )

        XCTAssertEqual(
            UpdateStatusPresentation(status: checkStatus, installState: .installing),
            UpdateStatusPresentation(
                text: "Installiere über Homebrew…",
                colorRole: .neutral,
                showsProgress: true
            )
        )
        XCTAssertEqual(
            UpdateStatusPresentation(
                status: checkStatus,
                installState: .installedAwaitingRelaunch
            ),
            UpdateStatusPresentation(
                text: "Installiert. Stasi startet neu…",
                colorRole: .success,
                showsProgress: false
            )
        )
        XCTAssertEqual(
            UpdateStatusPresentation(
                status: checkStatus,
                installState: .failed("Netzwerkfehler")
            ),
            UpdateStatusPresentation(
                text: "Netzwerkfehler",
                colorRole: .warning,
                showsProgress: false
            )
        )
    }

    private func installedEnvironment() -> HomebrewEnvironment {
        let existing = Set([
            "/opt/homebrew/bin/brew",
            "/opt/homebrew/Caskroom/stasi",
        ])
        return HomebrewEnvironment(fileExists: { existing.contains($0) })
    }

    private func assertSuccess(
        _ result: Result<Void, HomebrewUpdateError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case let .failure(error) = result {
            XCTFail("Erfolg erwartet, erhalten: \(error)", file: file, line: line)
        }
    }

    private func failure(
        of result: Result<Void, HomebrewUpdateError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> HomebrewUpdateError? {
        guard case let .failure(error) = result else {
            XCTFail("Fehler erwartet", file: file, line: line)
            return nil
        }
        return error
    }
}

private struct ProcessCall: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let timeout: TimeInterval
}

private actor RecordingProcessRunner: ProcessRunning {
    private var outcomes: [Result<ProcessResult, ProcessRunnerError>]
    private var calls: [ProcessCall] = []

    init(outcomes: [Result<ProcessResult, ProcessRunnerError>]) {
        self.outcomes = outcomes
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(ProcessCall(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        ))
        guard !outcomes.isEmpty else { throw ProcessRunnerError.launchFailed("unexpected call") }
        return try outcomes.removeFirst().get()
    }

    func recordedCalls() -> [ProcessCall] {
        calls
    }
}

private actor ControlledProcessRunner: ProcessRunning {
    private var calls: [ProcessCall] = []
    private var continuation: CheckedContinuation<ProcessResult, Error>?

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(ProcessCall(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        ))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted(callCount: Int) async {
        while calls.count < callCount || continuation == nil {
            await Task.yield()
        }
    }

    func succeed(_ result: ProcessResult) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: result)
    }
}
