import SwiftUI
import AVFoundation
import AppKit

// MARK: - Einstellungen (v3: 6 Sektionen, Spalte 620)

struct SettingsWindowView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings

    @State private var recordingHotkey = false
    /// Während der Aufnahme erfasste Kombination (Vorschau bis „Übernehmen").
    @State private var draftCombo: HotkeyEngine.Combo?

    // Mikrofon-Popover
    @State private var micPopoverOpen = false
    @State private var availableMics: [MicDevice] = []

    // Update-Prüfung
    @State private var updater = UpdateChecker()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DIENSTVORSCHRIFT")
                        .kicker(Theme.Palette.text3)
                    Text("Einstellungen")
                        .font(Theme.Typo.h1())
                        .tracking(-0.6)
                        .foregroundColor(Theme.Palette.ink)
                }
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 22) {
                    aufnahmeSection
                    eingabeSection
                    verhaltenSection
                    darstellungSection
                    speicherSection
                    ueberSection
                }
            }
            .padding(.horizontal, Theme.Metrics.contentPaddingH)
            .padding(.vertical, Theme.Metrics.contentPaddingTop)
            .frame(maxWidth: 620 + 2 * Theme.Metrics.contentPaddingH, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { app.refreshPermissionState() }
        .onDisappear { cancelHotkeyRecording() }
    }

    // MARK: Sektionen (Mono-Kicker + Hauptkarte, Zeilen 13×16)

    private func section(_ kickerText: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kickerText)
                .kicker(Theme.Palette.text3)
            VStack(alignment: .leading, spacing: 0) { content() }
                .card(padding: 0)
        }
    }

    private func rowDivider() -> some View {
        Divider().overlay(Theme.Palette.linieInnen).padding(.leading, 16)
    }

    // MARK: AUFNAHME

    private var aufnahmeSection: some View {
        section("AUFNAHME") {
            hotkeyRow
            rowDivider()
            handsFreeRow
            rowDivider()
            modeRow
            rowDivider()
            permissionBadgeRow(title: "Eingabe-Überwachung",
                               granted: app.listenEventGranted)
            if !app.listenEventGranted { rowDivider() }
            permissionActionRow(title: "Bedienungshilfen",
                                granted: app.accessibilityGranted)
        }
    }

    private var hotkeyRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push-to-talk")
                        .font(Theme.Typo.zeilenTitel())
                        .foregroundColor(Theme.Palette.ink)
                    Text("Halten zum Sprechen, loslassen zum Einfügen.")
                        .font(Theme.Typo.secondary(size: 11.5))
                        .foregroundColor(Theme.Palette.text2)
                }
                Spacer()
                KeyBadge(recordingHotkey ? "…" : VirtualKey.display(app.currentCombo))
                    .opacity(recordingHotkey ? 0.4 : 1)
                Button("ÄNDERN") {
                    if !recordingHotkey { beginHotkeyRecording() }
                }
                .font(Theme.Typo.kicker(size: 10.5))
                .tracking(0.8)
                .foregroundColor(Theme.Palette.stempelrot)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if recordingHotkey {
                recorderField
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
        }
    }

    /// Aufnahmefeld (recorderFlaeche, 1px dashed stempelrot).
    private var recorderField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JETZT DRÜCKEN")
                .kicker(Theme.Palette.stempelrot, tracking: 1.6)

            HStack(spacing: 6) {
                ForEach(currentDraftSymbols, id: \.self) { symbol in
                    KeyBadge(symbol)
                        .font(Theme.Typo.keycap(14))
                }
                BlinkingCursor()
            }

            Text("Mindestens ein Modifier. Esc bricht ab.")
                .font(Theme.Typo.secondary(size: 11))
                .foregroundColor(Theme.Palette.text3)

            HStack {
                Spacer()
                Button("Abbrechen") { cancelHotkeyRecording() }
                    .buttonStyle(GhostButtonStyle())
                Button("Übernehmen") { commitHotkeyRecording() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(draftCombo == nil || !Self.hasModifier(draftCombo!))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Palette.recorderFlaeche)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.Palette.stempelrot,
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        )
    }

    /// Keycap-Vorschau der aktuell gedrückten Kombination.
    private var currentDraftSymbols: [String] {
        guard let combo = draftCombo else { return [] }
        return VirtualKey.display(combo).split(separator: " ").map(String.init)
    }

    private static func hasModifier(_ combo: HotkeyEngine.Combo) -> Bool {
        combo.flags != 0 || Self.isModifierKey(UInt16(clamping: Int(combo.keyCode)))
    }

    @State private var hotkeyCaptureMonitor: Any?

    private func beginHotkeyRecording() {
        guard hotkeyCaptureMonitor == nil else { return }
        recordingHotkey = true
        draftCombo = app.currentCombo
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .keyDown where event.keyCode == 53:
                // Esc bricht ab – Monitor bleibt aktiv bis „Abbrechen".
                MainActor.assumeIsolated {
                    cancelHotkeyRecording()
                }
                return nil
            case .flagsChanged:
                // Modifier-Taste (z. B. rechte ⌘) als Kandidat zeigen.
                if Self.isModifierKey(event.keyCode),
                   !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    MainActor.assumeIsolated {
                        draftCombo = HotkeyEngine.Combo(keyCode: UInt64(event.keyCode), flags: 0)
                    }
                } else if event.keyCode == 63 {
                    // fn losgelassen → nichts
                } else {
                    MainActor.assumeIsolated {
                        draftCombo = nil // Modifier allein reicht nicht → Anzeige leeren
                    }
                }
                return nil
            case .keyDown:
                let keyCode = UInt64(event.keyCode)
                var flags: UInt64 = 0
                if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
                if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
                if event.modifierFlags.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
                if event.modifierFlags.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
                MainActor.assumeIsolated {
                    draftCombo = HotkeyEngine.Combo(keyCode: keyCode, flags: flags)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func cancelHotkeyRecording() {
        if let monitor = hotkeyCaptureMonitor { NSEvent.removeMonitor(monitor) }
        hotkeyCaptureMonitor = nil
        recordingHotkey = false
        draftCombo = nil
    }

    private func commitHotkeyRecording() {
        guard let combo = draftCombo else { return }
        app.applyHotkey(combo)
        cancelHotkeyRecording()
    }

    nonisolated static func isModifierKey(_ code: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 63].contains(Int(code))
    }

    private var handsFreeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hands-free")
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text("Doppeltipp auf fn startet und stoppt die Aufnahme freihändig.")
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            KeyBadge("fn ×2")
            Text("AKTIV ✓")
                .font(Theme.Typo.kicker(size: 10))
                .tracking(0.8)
                .foregroundColor(Theme.Palette.archivgruen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var modeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modus")
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(settings.hotkeyMode == .pushToTalk
                     ? "Taste halten – klassisches Walkie-Talkie."
                     : "Drücken zum Starten, nochmal drücken zum Stoppen.")
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Picker("", selection: Binding(get: { settings.hotkeyMode },
                                          set: { settings.hotkeyMode = $0 })) {
                ForEach(SettingsStore.HotkeyMode.allCases) { mode in
                    Text(mode.label.uppercased()).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// Erteilte Berechtigung: Badge „ERTEILT ✓" mit grünem Rand.
    private func permissionBadgeRow(title: String, granted: Bool) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typo.zeilenTitel())
                .foregroundColor(Theme.Palette.ink)
            Spacer()
            if granted {
                Text("ERTEILT ✓")
                    .font(Theme.Typo.kicker(size: 10))
                    .tracking(0.8)
                    .foregroundColor(Theme.Palette.archivgruen)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.Palette.archivgruen, lineWidth: Theme.Metrics.hairline))
            } else {
                Button("FREIGEBEN") {
                    Task { @MainActor in app.requestMissingPermissions() }
                }
                .font(Theme.Typo.kicker(size: 10.5))
                .tracking(0.8)
                .foregroundColor(Theme.Palette.papier)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                    .fill(Theme.Palette.stempelrot))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// Fehlende Berechtigung: roter Pulsdot + Freigeben.
    private func permissionActionRow(title: String, granted: Bool) -> some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(granted ? Theme.Palette.archivgruen : Theme.Palette.recRed)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
            }
            Spacer()
            if granted {
                Text("ERTEILT ✓")
                    .font(Theme.Typo.kicker(size: 10))
                    .tracking(0.8)
                    .foregroundColor(Theme.Palette.archivgruen)
            } else {
                Button("FREIGEBEN") {
                    Task { @MainActor in app.requestMissingPermissions() }
                }
                .font(Theme.Typo.kicker(size: 10.5))
                .tracking(0.8)
                .foregroundColor(Theme.Palette.papier)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                    .fill(Theme.Palette.stempelrot))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: EINGABE (Mikrofon-Popover + Sprache)

    private var eingabeSection: some View {
        section("EINGABE") {
            micRow
            rowDivider()
            languageRow
        }
    }

    private var micNameText: String {
        if let uid = settings.preferredMicUID,
           let device = availableMics.first(where: { $0.uid == uid }) {
            return device.name
        }
        return "MacBook Pro Mikrofon"
    }

    private var micRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mikrofon")
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text("Wähle das Eingabegerät für deine Diktate.")
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Button {
                micPopoverOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(micNameText)
                        .font(Theme.Typo.counter(11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                    .fill(Theme.Palette.papier)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                        .strokeBorder(micPopoverOpen ? Theme.accent : Theme.Palette.line,
                                      lineWidth: Theme.Metrics.hairline)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $micPopoverOpen, arrowEdge: .bottom) {
                MicPickerPopover(selection: Binding(
                    get: { settings.preferredMicUID },
                    set: { settings.preferredMicUID = $0 }),
                    devices: $availableMics)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var languageRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sprache")
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text("„Automatisch“ nutzt die Systemsprache.")
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Picker("", selection: Binding(get: { settings.language },
                                          set: { settings.language = $0 })) {
                Text("AUTO").tag("auto")
                Text("DE").tag("de_DE")
                Text("EN").tag("en_US")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: VERHALTEN

    private var verhaltenSection: some View {
        section("VERHALTEN") {
            toggleRow(title: "Ton-Feedback",
                      description: "Kurzer Ton bei Start und Ende der Aufnahme.",
                      isOn: Binding(get: { settings.soundOn }, set: { settings.soundOn = $0 }))
            rowDivider()
            toggleRow(title: "KI-Nachbearbeitung",
                      description: "Entfernt Füllwörter — ähm, äh, quasi. (Noch nicht aktiv)",
                      isOn: Binding(get: { settings.aiPostProcess }, set: { settings.aiPostProcess = $0 }),
                      disabled: true)
            rowDivider()
            toggleRow(title: "Autostart",
                      description: "Stasi beim Anmelden starten.",
                      isOn: Binding(get: { settings.autostartOn }, set: { settings.autostartOn = $0 }))
            rowDivider()
            toggleRow(title: "Ironische Texte",
                      description: "„Wir hören zu.“ & Co. — abschaltbar für Ernsthaftigkeit.",
                      isOn: Binding(get: { settings.ironyOn }, set: { settings.ironyOn = $0 }))
        }
    }

    /// v4-Toggle: 40 × 24, Radius 999, an = stempelrot (Knopf 18 px rechts),
    /// aus = linieInnen.
    private func toggleRow(title: String, description: String,
                           isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(disabled ? Theme.Palette.text3 : Theme.Palette.ink)
                Text(description)
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Button {
                guard !disabled else { return }
                isOn.wrappedValue.toggle()
            } label: {
                ZStack(alignment: .leading) {
                    Capsule().fill(isOn.wrappedValue ? Theme.Palette.stempelrot : Theme.Palette.linieInnen)
                        .frame(width: 40, height: 24)
                    Circle()
                        .fill(Theme.Palette.papier)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                        .offset(x: isOn.wrappedValue ? 19 : 3, y: 0)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(disabled ? 0.45 : 1)
            .animation(reduceMotion ? nil : Theme.Motion.fast, value: isOn.wrappedValue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: DARSTELLUNG (v3: fünf Akzent-Farbkreise)

    private var darstellungSection: some View {
        section("DARSTELLUNG") {
            HStack(spacing: 14) {
                ForEach(SettingsStore.accentPresets, id: \.0) { name, hex in
                    let color = Color(stasiHex: hex)
                    let active = settings.accentHex == hex
                    Button {
                        settings.accentHex = hex
                    } label: {
                        ZStack {
                            if active {
                                Circle()
                                    .strokeBorder(Theme.Palette.ink, lineWidth: 2)
                                    .frame(width: 34, height: 34)
                            }
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                        }
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
                Spacer()
                Text(activeAccentName)
                    .font(Theme.Typo.counter(11))
                    .foregroundColor(Theme.Palette.text3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    private var activeAccentName: String {
        SettingsStore.accentPresets.first(where: { $0.1 == settings.accentHex })?.0
            ?? "Anthrazit"
    }

    // MARK: SPEICHER

    @State private var showDeleteConfirm = false

    private var speicherSection: some View {
        section("SPEICHER") {
            retentionRow
            rowDivider()
            deleteAllRow
        }
        .alert("Akte vernichten?", isPresented: $showDeleteConfirm) {
            Button("Vernichten", role: .destructive) {
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

    private var retentionRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aufnahmen aufbewahren")
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text("Ältere Protokolle und ihre Audio-Aufnahmen werden automatisch gelöscht.")
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Picker("", selection: Binding(get: { settings.retention },
                                          set: { settings.retention = $0 })) {
                Text("NIE").tag(Retention.forever)
                Text("1 T").tag(Retention.oneDay)
                Text("1 W").tag(Retention.oneWeek)
                Text("2 W").tag(Retention.twoWeeks)
                Text("1 MONAT").tag(Retention.oneMonth)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var deleteAllRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Alles löschen")
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text("Entfernt alle Protokolle und Aufnahmen von diesem Mac.")
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Button("AKTE VERNICHTEN") {
                showDeleteConfirm = true
            }
            .font(Theme.Typo.kicker(size: 10.5))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundColor(Theme.Palette.destructive)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(Theme.Palette.warnFlaeche)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Theme.Palette.warnRand, lineWidth: Theme.Metrics.hairline)))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: ÜBER (inkl. Update-Prüfung)

    private var ueberSection: some View {
        section("ÜBER") {
            HStack(spacing: 10) {
                Text("V \(AppVersion.display) · AKTE \(AppVersion.akte)")
                    .font(Theme.Typo.counter(12).weight(.bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundColor(Theme.Palette.ink)
                Spacer()
                Button {
                    Task { await updater.check() }
                } label: {
                    Text(updater.isChecking ? "PRÜFE …" : "AKTUELLE VERSION PRÜFEN")
                        .font(Theme.Typo.kicker(size: 10.5))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundColor(Theme.Palette.text2)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Theme.Palette.linieSidebar, lineWidth: Theme.Metrics.hairline))
                }
                .buttonStyle(.plain)

                if let available = updater.state.availableVersion {
                    Button("UPDATE AUF V \(available)") {
                        if let url = updater.state.releaseURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                        .font(Theme.Typo.kicker(size: 10.5))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundColor(Theme.Palette.papier)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Theme.Palette.stempelrot))
                        .buttonStyle(.plain)
                        .disabled(updater.state.releaseURL == nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            // Statuszeile
            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.Palette.archivgruen)
                    .frame(width: 6, height: 6)
                Text(UpdateChecker.statusText(lastChecked: updater.state.lastChecked,
                                              available: updater.state.availableVersion))
                    .font(Theme.Typo.counter(10))
                    .monospacedDigit()
                    .textCase(.uppercase)
                    .foregroundColor(Theme.Palette.text3)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.Palette.linieInnen).frame(height: Theme.Metrics.hairline)

            Text(Copy.privacyFootnote(settings))
                .font(Theme.Typo.secondary(size: 11.5))
                .foregroundColor(Theme.Palette.text2)
                .lineHeight()
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
        }
    }
}

// MARK: - Blinkender Cursor (Recorder / Inline-Inputs)

struct BlinkingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Theme.Palette.stempelrot)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - Mikrofon-Popover (270 px, STANDARD-Häkchen, Pegel-Fußzeile)

struct MicPickerPopover: View {
    @Binding var selection: String?
    @Binding var devices: [MicDevice]
    @Environment(\.dismiss) private var dismiss
    @State private var levelTick = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let list = devices
            if list.isEmpty {
                Text("Keine Eingabegeräte gefunden.")
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
                    .padding(14)
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, device in
                    micRow(device, isStandard: device.isDefault,
                           isSelected: selection == device.uid || (selection == nil && device.isDefault),
                           indent: index > 0 && !device.isDefault && list[0].isDefault)
                    if index < list.count - 1 {
                        Divider().overlay(Theme.Palette.linieInnen).padding(.leading, index > 0 ? 30 : 12)
                    }
                }
            }

            Rectangle().fill(Theme.Palette.linieInnen).frame(height: Theme.Metrics.hairline)

            // Fußzeile: vierbalkiger Live-Pegel (archivgruen)
            HStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 2.5) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.Palette.archivgruen)
                            .frame(width: 3, height: barHeight(i))
                            .animation(reduceMotion ? nil :
                                    Animation.easeInOut(duration: 0.5 + Double(i) * 0.13)
                                    .repeatForever(autoreverses: true),
                                       value: levelTick)
                    }
                }
                Text("PEGEL WIRD GEPRÜFT")
                    .font(Theme.Typo.kicker(size: 9.5))
                    .tracking(1)
                    .foregroundColor(Theme.Palette.text3)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(width: 270)
        .background(Theme.Palette.papier)
        .onAppear {
            devices = Self.scanDevices()
            levelTick = 1
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func barHeight(_ i: Int) -> CGFloat {
        let phase = levelTick * 2 + Double(i) * 0.9
        return 6 + CGFloat(abs(sin(phase))) * 8
    }

    private static func scanDevices() -> [MicDevice] {
        let defaultUID = MicrophoneScanner.defaultInputTransportUID()
        return MicrophoneCatalog.catalog(from: MicrophoneScanner.scan().map { raw in
            MicDevice(uid: raw.transportUID ?? raw.name,
                      name: raw.name,
                      isDefault: raw.transportUID != nil && raw.transportUID == defaultUID)
        })
    }

    private func micRow(_ device: MicDevice, isStandard: Bool, isSelected: Bool,
                        indent: Bool) -> some View {
        Button {
            selection = device.uid
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Palette.stempelrot)
                    .opacity(isSelected ? 1 : 0)
                Text(device.name)
                    .font(Theme.Typo.secondary(size: 12))
                    .foregroundColor(isSelected ? Theme.Palette.ink : Theme.Palette.text2)
                    .lineLimit(1)
                if isStandard {
                    Text("STANDARD")
                        .font(Theme.Typo.kicker(size: 9))
                        .tracking(0.8)
                        .foregroundColor(Theme.Palette.text3)
                }
                Spacer()
            }
            .padding(.horizontal, indent ? 30 : 12)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.Palette.chip : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
