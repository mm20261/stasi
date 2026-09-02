import Foundation
import XCTest
@testable import Stasi

final class L10nTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.languageOverride = "de"
    }

    override func tearDown() {
        L10n.languageOverride = "de"
        super.tearDown()
    }

    func testGermanAndEnglishCatalogsContainTheSameKeys() throws {
        let german = try catalog(language: "de")
        let english = try catalog(language: "en")

        XCTAssertEqual(Set(german.keys), Set(english.keys))
    }

    func testGermanAndEnglishFormatsUseMatchingPlaceholders() throws {
        let german = try catalog(language: "de")
        let english = try catalog(language: "en")

        for key in german.keys.sorted() {
            XCTAssertEqual(
                placeholders(in: german[key, default: ""]),
                placeholders(in: english[key, default: ""]),
                "Abweichende Format-Platzhalter für \(key)"
            )
        }
    }

    func testEnglishOverrideReturnsEnglishSamples() {
        L10n.languageOverride = "en"

        XCTAssertEqual(L10n.text("dashboard.title"), "The Report")
        XCTAssertEqual(L10n.text("sidebar.tagline.ironic"), "We're listening.")
        XCTAssertEqual(L10n.text("toast.microphoneMissing"), "Microphone access is missing.")
    }

    func testUnknownOverrideFallsBackToGerman() {
        L10n.languageOverride = "fr"

        XCTAssertEqual(L10n.text("dashboard.title"), "Der Bericht")
    }

    func testViewsContainNoGermanTextLiteralWithUmlauts() throws {
        let uiDirectory = repositoryRoot.appendingPathComponent("Sources/Stasi/UI")
        let files = try FileManager.default.contentsOfDirectory(
            at: uiDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let pattern = #"Text\s*\(\s*\"[^\"]*[ÄÖÜäöüß][^\"]*\""#
        let regex = try NSRegularExpression(pattern: pattern)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            if regex.firstMatch(in: source, range: range) != nil {
                violations.append(file.lastPathComponent)
            }
        }

        XCTAssertEqual(violations, [], "Deutsche Text-Literale in Views: \(violations)")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func catalog(language: String) throws -> [String: String] {
        let url = repositoryRoot
            .appendingPathComponent("Sources/Stasi/Resources")
            .appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+#0 ]*(?:\d+)?(?:\.\d+)?(?:hh|h|ll|l|L|z|j|t)?(?:@|d|i|u|o|x|X|f|F|e|E|g|G|a|A|c|C|s|S|p)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let unescaped = value.replacingOccurrences(of: "%%", with: "")
        let range = NSRange(unescaped.startIndex..<unescaped.endIndex, in: unescaped)
        return regex.matches(in: unescaped, range: range).compactMap { match in
            Range(match.range, in: unescaped).map { String(unescaped[$0]) }
        }
    }
}
