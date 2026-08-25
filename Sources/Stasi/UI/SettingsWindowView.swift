import SwiftUI
import AVFoundation
import AppKit

// MARK: - Einstellungen (v2, max-width 620)

struct SettingsWindowView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings

    @State private var recordingHotkey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                VStack(alignment: .leading, spacing: 24) {
                    aufnahmeSection
                    eingabeSection
                    verhaltenSection
                    darstellungSection
                    speicherSection
                    ueberSection
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
                        badge: comboText, editable: true) {
                if !recordingHotkey { beginHotkeyRecording() }
            }
            shortcutRow(label: "Hands-free-Modus",
                        description: "Doppeltipp auf fn startet und stoppt die Aufnahme freihändig.",
                        badge: "fn ×2")

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
        guard hotkeyCaptureMonitor == nil else { return }
        recordingHotkey = true
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if let monitor = hotkeyCaptureMonitor { NSEvent.removeMonitor(monitor) }
            hotkeyCaptureMonitor = nil
            recordingHotkey = false
            switch event.type {
            case .keyDown where event.keyCode == 53:
                break // ESC bricht ab
            case .flagsChanged:
                // Modifier-Taste (z. B. rechte ⌘) als Hotkey übernehmen.
                if Self.isModifierKey(event.keyCode),
                   !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    app.applyHotkey(HotkeyEngine.Combo(keyCode: UInt64(event.keyCode), flags: 0))
                }
            case .keyDown:
                let keyCode = UInt64(event.keyCode)
                var flags: UInt64 = 0
                if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
                if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
                if event.modifierFlags.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
                if event.modifierFlags.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
                app.applyHotkey(HotkeyEngine.Combo(keyCode: keyCode, flags: flags))
            default:
                break
            }
            return nil
        }
    }

    private static func isModifierKey(_ code: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 63].contains(Int(code))
    }

    private var comboText: String {
        if recordingHotkey { return "Taste drücken…" }
        return VirtualKey.display(app.currentCombo)
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

    // MARK: Darstellung (Akzentfarbe)

    private var darstellungSection: some View {
        section("DARSTELLUNG") {
            HStack(spacing: 10) {
                ForEach(SettingsStore.accentPresets, id: \.1) { name, hex in
                    Button {
                        settings.accentHex = hex
                    } label: {
                        Circle()
                            .fill(Color(stasiHex: hex))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().strokeBorder(
                                    settings.accentHex == hex ? Theme.Palette.ink : Theme.Palette.line,
                                    lineWidth: settings.accentHex == hex ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .scaleOnHover()
                    .help(name)
                }
                Spacer()
            }
            settingHint("Standard ist Anthrazit – die Akzentfarbe zieht sich durch Nav, Charts und die Aufnahme-Pill.")
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

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stasi v 0.9 · Akte 001")
                        .font(Theme.Typo.body().weight(.medium))
                        .foregroundColor(Theme.Palette.ink)
                    Text("Neueste Version im GitHub-Repo")
                        .font(Theme.Typo.secondary())
                        .foregroundColor(Theme.Palette.sub)
                }
                Spacer()
                Link(destination: URL(string: "https://github.com/leomcguire/stasi")!) {
                    Text("Auf GitHub prüfen")
                        .font(.custom("Geist", size: 12).weight(.semibold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.tint(Theme.accent))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
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
            Text(kickerText).kicker(Theme.accent)
            VStack(alignment: .leading, spacing: 14) { content() }
                .card(padding: 18)
        }
    }

    private func shortcutRow(label: String, description: String,
                             badge: String, editable: Bool = false,
                             action: @escaping () -> Void = {}) -> some View {
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
            if editable {
                Button("Ändern") { action() }
                    .font(Theme.Typo.secondary())
                    .buttonStyle(GhostButtonStyle())
            } else {
                Label("Aktiv", systemImage: "checkmark")
                    .font(Theme.Typo.secondary())
                    .foregroundStyle(Theme.Palette.successColor)
            }
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

    // MARK: Speicher (Aufbewahrungsdauer + Alles löschen)

    @State private var showDeleteConfirm = false

    private var speicherSection: some View {
        section("SPEICHER") {
            Picker("Aufnahmen aufbewahren",
                   selection: Binding(get: { settings.retention },
                                      set: { settings.retention = $0 })) {
                ForEach(Retention.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.menu)
            settingHint("Ältere Protokolle und ihre Audio-Aufnahmen werden automatisch von diesem Mac gelöscht.")

            Divider().overlay(Theme.Palette.line)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alles löschen")
                        .font(Theme.Typo.body())
                        .foregroundColor(Theme.Palette.ink)
                    Text("Entfernt alle Protokolle und Aufnahmen von diesem Mac.")
                        .font(Theme.Typo.secondary())
                        .foregroundColor(Theme.Palette.sub)
                }
                Spacer()
                Button("Alles löschen", role: .destructive) {
                    showDeleteConfirm = true
                }
                .buttonStyle(GhostButtonStyle(destructive: true))
            }
        }
        .alert("Alle Daten löschen?", isPresented: $showDeleteConfirm) {
            Button("Alles löschen", role: .destructive) {
                app.history.deleteAll()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Protokolle und Audio-Aufnahmen werden unwiderruflich von diesem Mac entfernt.")
        }
        .onChange(of: settings.retention) { _, _ in
            app.applyRetention()
        }
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
