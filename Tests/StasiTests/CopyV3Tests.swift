import XCTest
@testable import Stasi

// MARK: - Copy (Ironie schaltbar) + feste Texte
// Ironie-Tabelle und feste Texte bleiben für den v3-Look unverändert erhalten.

@MainActor
final class CopyV3Tests: XCTestCase {

    private func makeSettings(irony: Bool) -> SettingsStore {
        let d = UserDefaults(suiteName: "copy-v3-tests-\(UUID().uuidString)")!
        let s = SettingsStore(defaults: d)
        s.ironyOn = irony
        return s
    }

    // MARK: Ironie-Tabelle

    func testTagline() {
        XCTAssertEqual(Copy.tagline(makeSettings(irony: true)), "Wir hören zu.")
        XCTAssertEqual(Copy.tagline(makeSettings(irony: false)), "Lokales Diktat.")
    }

    func testAkteNote() {
        XCTAssertEqual(Copy.akteNote(makeSettings(irony: true)),
                       "Lebenslang geführt. Alle 10.000 Wörter ein neuer Meilenstein.")
        XCTAssertEqual(Copy.akteNote(makeSettings(irony: false)),
                       "Alle diktierten Wörter seit deinem ersten Protokoll.")
        XCTAssertEqual(Copy.akteMilestone, "10.000-Wörter-Meilenstein")
    }

    func testInsightsSubtitle() {
        XCTAssertEqual(Copy.insightsSubtitle(makeSettings(irony: true)),
                       "Der Überwachungsbericht. Lückenlos, versteht sich.")
        XCTAssertEqual(Copy.insightsSubtitle(makeSettings(irony: false)),
                       "Deine Diktier-Statistik.")
    }

    func testProtocolsSubtitle() {
        let ironic = Copy.protocolsSubtitle(makeSettings(irony: true), count: 1284)
        XCTAssertEqual(ironic, "1.284 Protokolle · alles dokumentiert, nichts vergessen.")
        XCTAssertEqual(Copy.protocolsSubtitle(makeSettings(irony: false), count: 1284),
                       "1.284 Protokolle")
    }

    func testAccountSubtitle() {
        XCTAssertEqual(Copy.accountSubtitle(makeSettings(irony: true)),
                       "Deine Akte. Ausnahmsweise führst du sie selbst.")
        XCTAssertEqual(Copy.accountSubtitle(makeSettings(irony: false)),
                       "Dein Profil — lokal gespeichert.")
    }

    func testEmptyProtocols() {
        XCTAssertEqual(Copy.emptyProtocols(makeSettings(irony: true)),
                       "Die Akte ist leer. Das kommt selten vor.")
        XCTAssertEqual(Copy.emptyProtocols(makeSettings(irony: false)),
                       "Noch keine Protokolle.")
        XCTAssertEqual(Copy.insightsEmpty,
                       "Noch nichts zu zählen – diktiere dein erstes Protokoll.")
        XCTAssertEqual(Copy.resetProtocolSearch, "Suche & Filter zurücksetzen")
    }

    func testPrivacyFootnote() {
        XCTAssertTrue(Copy.privacyFootnote(makeSettings(irony: true))
            .contains("Das wäre ja auch ironisch"))
        XCTAssertFalse(Copy.privacyFootnote(makeSettings(irony: false))
            .contains("Niemand hört mit"))
    }

    // MARK: Feste Texte (nicht von der Ironie abhängig)

    func testToastTexts() {
        XCTAssertEqual(Copy.toastLogged, "Protokolliert")
        XCTAssertEqual(Copy.toastCopied, "Kopiert — ⌘V")
        XCTAssertEqual(Copy.toastDiscarded, "Verworfen")
        XCTAssertEqual(Copy.toastNothingHeard, "Nichts gehört")
        XCTAssertEqual(Copy.toastTranscriptionAborted,
                       "Transkription abgebrochen – bitte erneut versuchen")
    }

    func testPillStatusTexts() {
        XCTAssertEqual(Copy.pillTranscribing, "Transkribiere…")
        XCTAssertEqual(Copy.pillPolishing, "Poliere…")
        XCTAssertEqual(Copy.pillInjecting, "Füge ein…")
        XCTAssertEqual(Copy.pillModelLoading, "Modell lädt…")
    }

    func testGreetingByHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func date(hour: Int) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        }
        XCTAssertEqual(Copy.greeting(for: date(hour: 6)), "Guten Morgen")
        XCTAssertEqual(Copy.greeting(for: date(hour: 12)), "Guten Tag")
        XCTAssertEqual(Copy.greeting(for: date(hour: 15)), "Guten Nachmittag")
        XCTAssertEqual(Copy.greeting(for: date(hour: 21)), "Guten Abend")

        let named = Copy.greetingLine(for: date(hour: 9), name: "Philipp")
        XCTAssertEqual(named, "Guten Morgen, Philipp.")
        XCTAssertEqual(Copy.greetingLine(for: date(hour: 9), name: ""), "Guten Morgen.")
    }

    func testAnleitungBar() {
        XCTAssertEqual(Copy.anleitungText, "halten und sprechen.")
        XCTAssertEqual(Copy.anleitungStatusReady, "Bereit")
        XCTAssertEqual(Copy.anleitungStatusBlocked, "Hotkey inaktiv")
        XCTAssertEqual(Copy.hotkeyRestartRequired, "Neustart nötig")
    }

    func testFirstStartEmptyState() {
        XCTAssertEqual(Copy.firstStartTitle, "Noch nichts protokolliert.")
        let combo = HotkeyEngine.Combo(
            keyCode: 8,
            flags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue
        )
        XCTAssertTrue(Copy.firstStartBody(combo: combo).contains(VirtualKey.display(combo)))
        XCTAssertFalse(Copy.firstStartBody(combo: combo).contains("⌘ rechts"))
        XCTAssertEqual(Copy.firstStartTryButton, "Jetzt ausprobieren")
        XCTAssertEqual(Copy.firstStartChangeKeyButton, "Taste ändern")
    }

    func testWarningCard() {
        XCTAssertEqual(Copy.permissionWarningTitle, "Der Hotkey funktioniert noch nicht.")
        XCTAssertEqual(Copy.permissionWarningBody,
                       "macOS muss Stasi erlauben, in Textfelder zu schreiben. Ein Klick, dann läuft es.")
        XCTAssertEqual(Copy.permissionWarningButton, "Erlauben")
    }

    func testDateLineUppercase() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let comps = DateComponents(year: 2026, month: 8, day: 24) // Montag
        let monday = cal.date(from: comps)!
        XCTAssertEqual(Copy.dateLine(monday, calendar: cal), "MONTAG, 24. AUGUST")
    }
}
