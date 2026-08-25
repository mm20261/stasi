import XCTest
@testable import Stasi

// MARK: - Onboarding (v4: 4 Schritte, erster Start)
// State-Maschine: Willkommen → Befugnisse → Tastenkombination → Probediktat.

@MainActor
final class OnboardingTests: XCTestCase {

    func testStartsAtStepOne() {
        let model = OnboardingModel()
        XCTAssertEqual(model.step, 1)
        XCTAssertFalse(model.isFinished)
    }

    func testNextAdvancesToFourAndClamps() {
        let model = OnboardingModel()
        model.next()
        XCTAssertEqual(model.step, 2)
        model.next(); model.next()
        XCTAssertEqual(model.step, 4)
        model.next() // Klemmt bei 4
        XCTAssertEqual(model.step, 4)
        XCTAssertFalse(model.isFinished)
    }

    func testBackDecreasesAndClamps() {
        let model = OnboardingModel(step: 2)
        model.back()
        XCTAssertEqual(model.step, 1)
        model.back() // Klemmt bei 1
        XCTAssertEqual(model.step, 1)
    }

    func testFinishMarksDone() {
        let model = OnboardingModel()
        model.finish()
        XCTAssertTrue(model.isFinished)
    }

    func testProgressLabel() {
        XCTAssertEqual(OnboardingModel.progressLabel(step: 3), "AKTE WIRD ANGELEGT · 3/4")
    }

    // MARK: Persistenz (erster Start)

    func testOnboardingDonePersists() {
        let suite = "onboarding-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.onboardingDone) // erster Start

        settings.onboardingDone = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.onboardingDone)
    }
}
