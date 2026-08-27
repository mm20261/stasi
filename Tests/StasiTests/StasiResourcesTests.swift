import Foundation
import XCTest
@testable import Stasi

final class StasiResourcesTests: XCTestCase {
    func testResolvePrefersPackagedBundleFromMainBundleResources() throws {
        let fixture = try makeMainBundleFixture(includeResourceBundle: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var fallbackRequested = false
        func fallbackBundle() -> Bundle {
            fallbackRequested = true
            return Bundle(for: Self.self)
        }

        let resolved = StasiResources.resolve(
            mainBundle: fixture.mainBundle,
            moduleBundle: fallbackBundle()
        )

        XCTAssertEqual(
            resolved.bundleURL.standardizedFileURL,
            fixture.resourceBundleURL.standardizedFileURL
        )
        XCTAssertFalse(fallbackRequested)
    }

    func testResolveFallsBackToModuleBundleOutsidePackagedApp() throws {
        let fixture = try makeMainBundleFixture(includeResourceBundle: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let fallback = Bundle(for: Self.self)
        let resolved = StasiResources.resolve(
            mainBundle: fixture.mainBundle,
            moduleBundle: fallback
        )

        XCTAssertEqual(
            resolved.bundleURL.standardizedFileURL,
            fallback.bundleURL.standardizedFileURL
        )
    }

    private func makeMainBundleFixture(
        includeResourceBundle: Bool
    ) throws -> (root: URL, mainBundle: Bundle, resourceBundleURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StasiResourcesTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let resourceBundleURL = resourcesURL
            .appendingPathComponent("Stasi_Stasi.bundle", isDirectory: true)

        try FileManager.default.createDirectory(
            at: includeResourceBundle ? resourceBundleURL : resourcesURL,
            withIntermediateDirectories: true
        )

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "app.stasi.tests.fixture",
            "CFBundleName": "Fixture",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        guard let mainBundle = Bundle(url: appURL) else {
            throw NSError(domain: "StasiResourcesTests", code: 1)
        }
        return (root, mainBundle, resourceBundleURL)
    }
}
