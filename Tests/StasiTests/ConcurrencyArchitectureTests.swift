import Foundation
import XCTest

final class ConcurrencyArchitectureTests: XCTestCase {
    func testCallbackFilesAvoidDynamicMainActorChecks() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Sources/Stasi/MainApp.swift",
            "Sources/Stasi/UI/RecordingPill.swift",
            "Sources/Stasi/Core/AppState.swift",
            "Sources/Stasi/UI/SettingsWindowView.swift",
            "Sources/Stasi/UI/OnboardingView.swift",
        ]
        let callbackMarkers = [
            "Timer.scheduledTimer",
            "NSEvent.addLocalMonitorForEvents",
            "DispatchQueue.global",
            "DispatchQueue.main.async",
        ]
        let mainActorTask = try NSRegularExpression(
            pattern: #"Task\s*\{\s*@MainActor"#
        )

        for relativePath in relativePaths {
            let source = try String(
                contentsOf: repository.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains("assumeIsolated"),
                "\(relativePath) darf keinen dynamischen MainActor-Check enthalten"
            )

            for marker in callbackMarkers {
                for callback in callbackBodies(in: source, after: marker) {
                    let range = NSRange(callback.startIndex..., in: callback)
                    XCTAssertNil(
                        mainActorTask.firstMatch(in: callback, range: range),
                        "\(relativePath): \(marker)-Callback darf keinen MainActor-Task starten"
                    )
                }
            }
        }

        for relativePath in [
            "Sources/Stasi/MainApp.swift",
            "Sources/Stasi/UI/RecordingPill.swift",
            "Sources/Stasi/Core/AppState.swift",
        ] {
            let source = try String(
                contentsOf: repository.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains("Timer.scheduledTimer"),
                "\(relativePath) muss ObjC-Target-Timer verwenden"
            )
        }
    }

    private func callbackBodies(in source: String, after marker: String) -> [String] {
        var bodies: [String] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") {
            var depth = 0
            var cursor = openingBrace
            var closingBrace: String.Index?
            while cursor < source.endIndex {
                switch source[cursor] {
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { closingBrace = cursor }
                default: break
                }
                if closingBrace != nil { break }
                cursor = source.index(after: cursor)
            }
            guard let closingBrace else { break }
            bodies.append(String(source[openingBrace...closingBrace]))
            searchStart = source.index(after: closingBrace)
        }
        return bodies
    }
}
