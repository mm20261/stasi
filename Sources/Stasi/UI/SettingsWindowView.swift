import SwiftUI
import AVFoundation
import AppKit

// MARK: - Einstellungen (im Fenster, max-width 600)

struct SettingsWindowView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings

    @State private var recordingHotkey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                VStack(alignment: .leading, spacing: 22) {
                    aufnahmeSection
                    eingabeSection
                    verhaltenSection
                    ueberSection
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // KEIN .onDisappear: SwiftUI feuert Appearance-Closures auch beim
        // App-Beenden (windowWillClose-Teardown) – der Executor-Check im
        // Closure crashte dort (macOS 26.6). Der Monitor-Guard in
        // beginHotkeyRecording reicht gegen Doppel-Monitore.
        .onAppear { app.refreshPermissionState() }
    }

    private var header: some View {
        Text("Einstellungen")
            .font(Theme.Typo.h1())
            .tracking(-0.3)
            .foregroundColor(Theme.Palette.ink)
    }

    // MARK: Aufnahme

    private var aufnahmeSection: some View {
        section("AUFNAHME") {
            shortcutRow(label: "Push-to-talk",
                        description: "Halten zum Sprechen, loslassen zum Einfügen.",
                        badge: comboText) {
                if !recordingHotkey { beginHotkeyRecording() }
            }
            shortcutRow(label: "Hands-free-Modus",
                        description: "Doppeltipp startet die Aufnahme ohne Halten.",
                        badge: "fn ×2", disabled: true) {}
            shortcutRow(label: "Letztes Protokoll einfügen",
                        description: "Tippt das letzte Diktat an der Cursorposition.",
                        badge: "⌃ ⌘ V", disabled: true) {}
            shortcutRow(label: "Letztes Protokoll kopieren",
                        description: "Kopiert das letzte Diktat in die Zwischenablage.",
                        badge: "⌃ ⌘ C", disabled: true) {}

            Divider().overlay(Theme.Palette.line)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modus").font(Theme.Typo.body()).foregroundColor(Theme.Palette.ink)
                    Text(settings.hotkeyMode == .pushToTalk
                         ? "Taste halten – klassisches Walkie-Talkie."
                         : "Drücken zum Starten, nochmal drücken zum Stoppen.")
                        .font(Theme.Typo.secondary())
                        .foregroundColor(Theme.Palette.sub)
                }
                Spacer()
                Picker("", selection: Binding(get: { settings.hotkeyMode },
                                              set: { settings.hotkeyMode = $0 })) {
                    ForEach(SettingsStore.HotkeyMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }

            permissionStatusRow(
                title: "Eingabe-Überwachung",
                subtitle: "Nötig, damit der globale Hotkey Tasten sieht.",
                granted: app.listenEventGranted
            )
            permissionStatusRow(
                title: "Bedienungshilfen",
                subtitle: "Nötig für das Einfügen in andere Apps.",
                granted: app.accessibilityGranted
            )
        }
    }

    @State private var hotkeyCaptureMonitor: Any?

    private func beginHotkeyRecording() {
        guard hotkeyCaptureMonitor == nil else { return } // kein Doppel-Monitor
        recordingHotkey = true
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if let monitor = hotkeyCaptureMonitor { NSEvent.removeMonitor(monitor) }
            hotkeyCaptureMonitor = nil
            recordingHotkey = false
            switch event.type {
            case .keyDown where event.keyCode == 53:
                break // ESC bricht ab
            default:
                app.applyHotkey(HotkeyEngine.Combo(keyCode: UInt64(event.keyCode), flags: 0))
            }
            return nil
        }
    }

    private var comboText: String {
        if recordingHotkey { return "Taste drücken…" }
        let c = app.currentCombo
        let name: String
        switch Int(c.keyCode) {
        case 54: name = "⌘ R"
        case 55: name = "⌘ L"
        case 49: name = "Leertaste"
        case 63: name = "fn"
        default: name = VirtualKey.name(for: Int(c.keyCode)).replacingOccurrences(of: " halten", with: "")
        }
        return name
    }

    // MARK: Eingabe

    private var eingabeSection: some View {
        section("EINGABE") {
            Picker("Mikrofon", selection: .constant("")) {
                Text("Systemstandard (aktives Eingabegerät)").tag("")
            }
            .pickerStyle(.menu)
            settingHint("Stasi nimmt immer das aktive macOS-Eingabegerät auf – wechsle es in den Systemeinstellungen.")

            Divider().overlay(Theme.Palette.line)

            Picker("Sprache", selection: Binding(get: { settings.language },
                                                 set: { settings.language = $0 })) {
                Text("Automatisch erkennen").tag("auto")
                Text("Deutsch").tag("de_DE")
                Text("Englisch").tag("en_US")
            }
            .pickerStyle(.menu)
            settingHint("„Automatisch“ nutzt die Systemsprache. Pro Äußerung umschalten ist geplant.")
        }
    }

    // MARK: Verhalten

    private var verhaltenSection: some View {
        section("VERHALTEN") {
            toggleRow(title: "Ton-Feedback",
                      subtitle: "Kurzer Ton bei Start und Ende der Aufnahme.",
                      isOn: Binding(get: { settings.soundOn }, set: { settings.soundOn = $0 }))
            toggleRow(title: "KI-Nachbearbeitung",
                      subtitle: "Entfernt Füllwörter — ähm, äh, quasi. (Noch nicht aktiv)",
                      isOn: Binding(get: { settings.aiPostProcess }, set: { settings.aiPostProcess = $0 }),
                      disabled: true)
            toggleRow(title: "Autostart",
                      subtitle: "Stasi beim Anmelden starten.",
                      isOn: Binding(get: { settings.autostartOn }, set: { settings.autostartOn = $0 }))
            toggleRow(title: "Ironische Texte",
                      subtitle: "„Wir hören zu.“ & Co. — abschaltbar für Ernsthaftigkeit.",
                      isOn: Binding(get: { settings.ironyOn }, set: { settings.ironyOn = $0 }))
        }
    }

    // MARK: Über

    private var ueberSection: some View {
        section("ÜBER") {
            HStack(spacing: 10) {
                Text("V 0.9 · AKTE 001")
                    .kicker(Theme.Palette.sub)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Palette.hover)
                    .cornerRadius(6)
                Spacer()
                Text("Engine: SpeechTranscriber · on-device")
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.sub)
            }
            Divider().overlay(Theme.Palette.line)
            Text(Copy.privacyFootnote(settings))
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)
                .lineHeight()
        }
    }

    // MARK: Bausteine

    private func section(_ kickerText: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kickerText).kicker(Theme.accent.brightenedForDarkMode())
            VStack(alignment: .leading, spacing: 14) { content() }
                .card(padding: 18)
        }
    }

    private func shortcutRow(label: String, description: String,
                             badge: String, disabled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.Typo.body()).foregroundColor(Theme.Palette.ink)
                Text(description)
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.sub)
            }
            Spacer()
            KeyBadge(badge)
                .opacity(recordingHotkey && label == "Push-to-talk" ? 0.5 : 1)
            Button(disabled ? "Bald" : "Ändern") { action() }
                .font(Theme.Typo.secondary())
                .buttonStyle(GhostButtonStyle())
                .disabled(disabled)
        }
    }

    private func toggleRow(title: String, subtitle: String,
                           isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typo.body()).foregroundColor(Theme.Palette.ink)
                Text(subtitle).font(Theme.Typo.secondary()).foregroundColor(Theme.Palette.sub)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(disabled)
        }
    }

    private func settingHint(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.kicker(size: 10))
            .tracking(0.2)
            .foregroundColor(Theme.Palette.sub.opacity(0.85))
    }
}


// MARK: - Berechtigungs-Zeilen mit exaktem Deep-Link

extension SettingsWindowView {
    fileprivate func permissionStatusRow(title: String, subtitle: String, granted: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(granted ? Theme.Palette.successColor : Theme.Palette.recRed)
                        .frame(width: 7, height: 7)
                    Text(title).font(Theme.Typo.body()).foregroundColor(Theme.Palette.ink)
                }
                Text(subtitle)
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.sub)
            }
            Spacer()
            if granted {
                Label("Erteilt", systemImage: "checkmark")
                    .font(Theme.Typo.secondary())
                    .foregroundStyle(Theme.Palette.successColor)
            } else {
                Button("Freigeben") {
                    Task { @MainActor in app.requestMissingPermissions() }
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
    }
}
