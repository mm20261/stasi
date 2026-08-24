import AppKit
import SwiftUI

// MARK: - Stasi – Push-to-Talk-Diktat für macOS

@main
struct StasiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var appState: AppState
    @State private var selection = AppSelection.shared

    init() {
        FontLoader.registerBundledFonts()
        let s = SettingsStore()
        _settings = State(initialValue: s)
        _appState = State(initialValue: AppState(settings: s))
    }

    var body: some Scene {
        WindowGroup("Stasi") {
            RootView()
                .environment(settings)
                .environment(appState)
                .environment(selection)
                .onAppear {
                    appDelegate.wireUp(app: appState, settings: settings, selection: selection)
                    Task { await Permissions.requestMicrophone() }
                    appState.accessibilityGranted = Permissions.accessibilityGranted
                }
        }
        .defaultSize(width: 1080, height: 700)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Einstellungen…") {
                    selection.section = .einstellungen
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    for window in NSApplication.shared.windows where window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .keyboardShortcut(",")
            }
        }
    }
}

// MARK: - StatusBarController (klassisch: NSStatusItem + NSMenu)
// Bewusst KEIN SwiftUI MenuBarExtra: dessen Inhalt wird teils außerhalb
// des Main-Actors ausgewertet und crashte bei @Environment-Zugriffen.

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var languageItems: [NSMenuItem] = []
    private weak var app: AppState?
    private weak var settings: SettingsStore?
    private weak var selection: AppSelection?

    func install(app: AppState, settings: SettingsStore, selection: AppSelection) {
        guard statusItem == nil else { return }
        self.app = app
        self.settings = settings
        self.selection = selection

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.icon(forPhase: .idle)
        rebuildMenu()
        statusItem = item
    }

    private var lastPhase: AppState.Phase = .idle
    /// Icons werden EINMAL geladen und gecacht – 20 Neuladungen/Sekunde aus
    /// dem Poll-Timer hatten den Main-Thread zu Boden gerissen.
    private static let iconCache: [AppState.Phase: NSImage] = {
        var cache: [AppState.Phase: NSImage] = [:]
        for phase in [AppState.Phase.idle, .recording, .transcribing, .injecting] {
            let name = phase == .recording ? "menubar-recording" : "menubar"
            if let url = Bundle.module.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = phase != .recording
                image.size = NSSize(width: 18, height: 18)
                cache[phase] = image
            }
        }
        return cache
    }()

    /// Icon + Statuszeile aktualisieren (aus dem Poll-Timer) – nur bei Änderung.
    func refresh() {
        guard let app else { return }
        if app.phase != lastPhase {
            lastPhase = app.phase
            statusItem?.button?.image = Self.iconCache[app.phase]
            statusMenuItem?.title = "  \(app.phase.rawValue)"
            syncLanguageChecks()
        }
    }

    // MARK: Aufbau

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let status = NSMenuItem(title: "  BEREIT", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)
        menu.addItem(.separator())

        let langHeader = NSMenuItem(title: "Sprache", action: nil, keyEquivalent: "")
        langHeader.isEnabled = false
        menu.addItem(langHeader)

        for option in [("auto", "Automatisch"), ("de_DE", "Deutsch"), ("en_US", "Englisch")] {
            let langItem = NSMenuItem(title: option.1,
                                      action: #selector(changeLanguage(_:)),
                                      keyEquivalent: "")
            langItem.target = self
            langItem.representedObject = option.0
            languageItems.append(langItem)
            menu.addItem(langItem)
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Stasi öffnen", action: #selector(openApp), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: "Stasi beenden", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        syncLanguageChecks()
    }

    private func syncLanguageChecks() {
        let current = settings?.language ?? "auto"
        for item in languageItems {
            item.state = item.representedObject as? String == current ? .on : .off
        }
    }

    // MARK: Aktionen

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        settings?.language = sender.representedObject as? String ?? "auto"
        syncLanguageChecks()
    }

    @objc private func openApp() {
        selection?.section = .bericht
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: Icons

    static func icon(forPhase phase: AppState.Phase) -> NSImage {
        iconCache[phase] ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Stasi")!
    }
}

// MARK: - AppDelegate (Statusbar + Pill-Sync)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var app: AppState?
    private let statusBar = StatusBarController()
    private weak var settingsRef: SettingsStore?
    private weak var selectionRef: AppSelection?

    func wireUp(app: AppState, settings: SettingsStore, selection: AppSelection) {
        guard self.app == nil else { return } // nur beim ersten Erscheinen verdrahten
        self.app = app
        self.settingsRef = settings
        self.selectionRef = selection

        app.startCommandLoop()
        app.onToast = { message, success in
            PillController.shared.showToast(message, success: success)
        }
        PillController.shared.app = app
        statusBar.install(app: app, settings: settings, selection: selection)
        poll()
    }

    /// Sync: Statusbar-Icon/-Status und Pill folgen Phase/Level/Timer.
    private func poll() {
        // Timer-Block erbt MainActor-Isolation statisch → direkter Aufruf,
        // KEIN Task { @MainActor } (Task-Churn aus GCD-Kontext korruptiert
        // unter macOS 26.6 die Executor-Metadaten → SwiftUI-Crashes).
        var tickCount = 0
        var lastFire = Date()
        Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
            // Stall-Watchdog: main thread hängt? → logarithmisch sichtbar machen
            let now = Date()
            let gap = now.timeIntervalSince(lastFire)
            lastFire = now
            if gap > 1.0 {
                NSLog("STASI-WATCH: Main-Thread-Stall %.2fs", gap)
            }

            guard let self, let app = self.app else { return }
            tickCount += 1
            app.ingestLevelFromPoll()
            statusBar.refresh()
            PillController.shared.sync(
                phase: app.phase,
                partialText: app.partialText,
                elapsed: app.elapsed,
                level: app.displayLevel
            )
            if tickCount % 20 == 0, app.accessibilityGranted {
                // NUR mit Eingabe-Überwachungs-Recht reaktivieren: einen von
                // TCC deaktivierten Tap wieder einzuschalten kostet den
                // Prozess sämtliche Maus-Events (Klick-Blackhole).
                app.hotkey?.ensureEnabled()
            }
            if tickCount % 40 == 0 {
                app.refreshPermissionStateAsync() // alle 2 s, TCC-XPC im Hintergrund
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Aktivierungs-Policy kommt aus der Info.plist (kein LSUIElement).
        // Ein nachträgliches setActivationPolicy(.regular) aus onAppear hat
        // das Fenster sichtbar-aber-nicht-key gemacht → Klicks versackten.
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // App lebt in der Menüleiste weiter; Dock-Icon bleibt aktiv.
    }
}
