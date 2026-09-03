import SwiftUI
import AVFoundation
import AppKit

// MARK: - Einstellungen (v3: 6 Sektionen, Spalte 620)

typealias SettingsHotkeyCaptureState = HotkeyCaptureState

private enum SettingsRecorder: Equatable {
    case pushToTalk
    case handsFree
}

struct SettingsWindowView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings

    @State private var activeRecorder: SettingsRecorder?

    // Mikrofon-Popover
    @State private var micPopoverOpen = false
    @State private var availableMics: [MicDevice] = []

    // Update-Prüfung
    @State private var updater = UpdateChecker()
    @State private var updateInstaller = UpdateInstaller()
    @State private var checkRequested = false
    @State private var installRequested = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("settings.kicker"))
                        .kicker(Theme.Palette.text3)
                    Text(L10n.text("settings.title"))
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
        .onAppear {
            app.refreshPermissionState()
            availableMics = MicrophoneScanner.devices()
        }
        .onDisappear {
            activeRecorder = nil
        }
        .task(id: checkRequested) {
            guard checkRequested else { return }
            await updater.check()
            checkRequested = false
        }
        .task(id: installRequested) {
            guard installRequested else { return }
            await updateInstaller.install()

            guard updateInstaller.installState == .installedAwaitingRelaunch else {
                installRequested = false
                return
            }
            // Bei Navigation aus den Einstellungen wird der View-Task abgebrochen.
            // Das installierte Update soll die App dann trotzdem neu starten.
            try? await Task.sleep(for: .seconds(1.5))
            relaunchAfterUpdate()
        }
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
        section(L10n.text("settings.section.recording")) {
            hotkeyRow
            rowDivider()
            handsFreeRow
            rowDivider()
            shortcutActionsRow
            rowDivider()
            modeRow
            rowDivider()
            permissionActionRow(title: L10n.text("permission.accessibility"),
                                granted: app.accessibilityGranted)
        }
    }

    private var hotkeyRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("settings.pushToTalk.title"))
                        .font(Theme.Typo.zeilenTitel())
                        .foregroundColor(Theme.Palette.ink)
                    Text(L10n.text("settings.pushToTalk.description"))
                        .font(Theme.Typo.secondary(size: 11.5))
                        .foregroundColor(Theme.Palette.text2)
                }
                Spacer()
                KeyBadge(activeRecorder == .pushToTalk ? "…" : VirtualKey.display(app.currentCombo))
                    .opacity(activeRecorder == .pushToTalk ? 0.4 : 1)
                Button(L10n.text("action.change.uppercase")) {
                    activeRecorder = .pushToTalk
                }
                .font(Theme.Typo.kicker(size: 10.5))
                .tracking(0.8)
                .foregroundColor(Theme.Palette.stempelrot)
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("settings.pushToTalk.changeAccessibility"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if activeRecorder == .pushToTalk {
                HotkeyRecorderField(
                    initialDraft: HotkeyCaptureDraft(combo: app.currentCombo),
                    prompt: L10n.text("hotkeyRecorder.pressNow"),
                    guidance: [L10n.text("hotkeyRecorder.minimumModifier")],
                    symbols: { draft in
                        guard let combo = draft.combo else { return [] }
                        return VirtualKey.display(combo).split(separator: " ").map(String.init)
                    },
                    canCommit: { $0.isValidSelection },
                    policy: { draft, event in
                        if case .cancel = event { return .cancel }
                        draft.process(event)
                        return .keep
                    },
                    onCancel: { activeRecorder = nil },
                    onCommit: { draft in
                        guard draft.isValidSelection, let combo = draft.combo else { return }
                        app.applyHotkey(combo)
                        activeRecorder = nil
                    }
                )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
        }
    }

    private var handsFreeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("settings.handsFree.title"))
                        .font(Theme.Typo.zeilenTitel())
                        .foregroundColor(Theme.Palette.ink)
                    Text(L10n.text("settings.handsFree.description", VirtualKey.keySymbol(Int(settings.handsFreeKeyCode))))
                        .font(Theme.Typo.secondary(size: 11.5))
                        .foregroundColor(Theme.Palette.text2)
                }
                Spacer()
                KeyBadge("\(VirtualKey.keySymbol(Int(settings.handsFreeKeyCode))) ×2")
                    .opacity(activeRecorder == .handsFree ? 0.4 : 1)
                Button(L10n.text("action.change.uppercase")) {
                    activeRecorder = .handsFree
                }
                .font(Theme.Typo.kicker(size: 10.5))
                .tracking(0.8)
                .foregroundColor(Theme.Palette.stempelrot)
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("settings.handsFree.changeAccessibility"))
                toggleControl(isOn: Binding(
                    get: { settings.handsFreeOn },
                    set: { app.setHandsFreeEnabled($0) }
                ), accessibilityLabel: L10n.text("settings.handsFree.title"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if activeRecorder == .handsFree {
                HotkeyRecorderField(
                    initialDraft: Optional(HotkeyEngine.Combo(
                        keyCode: settings.handsFreeKeyCode,
                        flags: 0
                    )),
                    prompt: L10n.text("hotkeyRecorder.pressModifier"),
                    guidance: [
                        L10n.text("hotkeyRecorder.modifiersOnly"),
                        L10n.text("hotkeyRecorder.normalKeysBlocked"),
                    ],
                    symbols: { draft in
                        draft.map { [VirtualKey.keySymbol(Int($0.keyCode))] } ?? []
                    },
                    canCommit: { draft in
                        draft.map { VirtualKey.isHandsFreeModifier($0.keyCode) } ?? false
                    },
                    policy: { draft, event in
                        switch event {
                        case .cancel:
                            return .cancel
                        case .modifier(let combo):
                            if VirtualKey.isHandsFreeModifier(combo.keyCode) { draft = combo }
                        case .modifierReleased:
                            break
                        case .key:
                            draft = nil
                        }
                        return .keep
                    },
                    onCancel: { activeRecorder = nil },
                    onCommit: { draft in
                        guard let combo = draft,
                              VirtualKey.isHandsFreeModifier(combo.keyCode) else { return }
                        app.applyHandsFreeKeyCode(combo.keyCode)
                        activeRecorder = nil
                    }
                )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
        }
    }

    private var shortcutActionsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("settings.lastProtocol.title"))
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(L10n.text("settings.lastProtocol.description"))
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            HStack(spacing: 6) {
                KeyBadge("⌃⌘C")
                Text(L10n.text("action.copy.uppercase"))
                    .font(Theme.Typo.kicker(size: 9.5))
                    .foregroundColor(Theme.Palette.text3)
                KeyBadge("⌃⌘V")
                Text(L10n.text("action.insert.uppercase"))
                    .font(Theme.Typo.kicker(size: 9.5))
                    .foregroundColor(Theme.Palette.text3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var modeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("settings.mode.title"))
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(settings.hotkeyMode == .pushToTalk
                     ? L10n.text("settings.mode.pushToTalkDescription")
                     : L10n.text("settings.mode.toggleDescription"))
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
                Text(L10n.text("permission.granted.uppercase"))
                    .font(Theme.Typo.kicker(size: 10))
                    .tracking(0.8)
                    .foregroundColor(Theme.Palette.successText)
            } else {
                Button(L10n.text("permission.allow.uppercase")) {
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
        section(L10n.text("settings.section.input")) {
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
        return availableMics.first(where: \.isDefault)?.name ?? L10n.text("microphone.systemDefault")
    }

    private var micRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("microphone.title"))
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(L10n.text("microphone.description"))
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
            .accessibilityLabel(L10n.text("microphone.chooseAccessibility"))
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
                Text(L10n.text("settings.transcriptionLanguage.title"))
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(L10n.text("settings.transcriptionLanguage.description"))
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Picker("", selection: Binding(get: { settings.language },
                                          set: {
                                              settings.language = $0
                                              Task {
                                                  await app.prepareModel(
                                                      for: settings.transcriptionLocale
                                                  )
                                              }
                                          })) {
                Text(L10n.text("language.auto.short")).tag("auto")
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
        section(L10n.text("settings.section.behavior")) {
            toggleRow(title: L10n.text("settings.sound.title"),
                      description: L10n.text("settings.sound.description"),
                      isOn: Binding(get: { settings.soundOn }, set: { settings.soundOn = $0 }))
            rowDivider()
            postProcessingRow
            rowDivider()
            toggleRow(title: L10n.text("settings.autostart.title"),
                      description: L10n.text("settings.autostart.description"),
                      isOn: Binding(get: { settings.autostartOn }, set: { settings.autostartOn = $0 }))
            rowDivider()
            toggleRow(title: L10n.text("settings.irony.title"),
                      description: L10n.text("settings.irony.description"),
                      isOn: Binding(get: { settings.ironyOn }, set: { settings.ironyOn = $0 }))
        }
    }

    private var postProcessingRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.postProcessingTitle)
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(Copy.postProcessingDescription(for: settings.postProcessing))
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Picker("", selection: Binding(get: { settings.postProcessing },
                                           set: { settings.postProcessing = $0 })) {
                Text(Copy.postProcessingOffLabel).tag(PolishLevel.off)
                Text(Copy.postProcessingStandardLabel).tag(PolishLevel.standard)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
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
            toggleControl(isOn: isOn, disabled: disabled, accessibilityLabel: title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func toggleControl(isOn: Binding<Bool>, disabled: Bool = false,
                               accessibilityLabel: String) -> some View {
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(L10n.text(isOn.wrappedValue ? "accessibility.on" : "accessibility.off"))
        .accessibilityAddTraits(.isToggle)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: DARSTELLUNG (v3: fünf Akzent-Farbkreise)

    private var darstellungSection: some View {
        section(L10n.text("settings.section.appearance")) {
            VStack(alignment: .leading, spacing: 0) {
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
                    .accessibilityLabel(L10n.text("settings.accent.accessibility", name))
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
                Spacer()
                Text(activeAccentName)
                    .font(Theme.Typo.counter(11))
                    .foregroundColor(Theme.Palette.text3)
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                rowDivider()
                uiLanguageRow
            }
        }
    }

    private var uiLanguageRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("settings.uiLanguage.title"))
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(L10n.text("settings.uiLanguage.restartHint"))
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Picker("", selection: Binding(get: { settings.uiLanguage },
                                           set: { settings.uiLanguage = $0 })) {
                Text(L10n.text("language.auto.long")).tag("auto")
                Text(L10n.text("language.german")).tag("de")
                Text(L10n.text("language.english")).tag("en")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var activeAccentName: String {
        SettingsStore.accentPresets.first(where: { $0.1 == settings.accentHex })?.0
            ?? L10n.text("settings.accent.charcoal")
    }

    // MARK: SPEICHER

    @State private var showDeleteConfirm = false

    private var speicherSection: some View {
        section(L10n.text("settings.section.storage")) {
            retentionRow
            rowDivider()
            deleteAllRow
        }
        .alert(L10n.text("settings.deleteAll.confirmTitle"), isPresented: $showDeleteConfirm) {
            Button(L10n.text("settings.deleteAll.title"), role: .destructive) {
                app.deleteAllHistory()
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("settings.deleteAll.confirmBody"))
        }
        .onChange(of: settings.retention) { _, _ in
            app.applyRetention()
        }
    }

    private var retentionRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("settings.retention.title"))
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(L10n.text("settings.retention.description"))
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Picker("", selection: Binding(get: { settings.retention },
                                          set: { settings.retention = $0 })) {
                ForEach(Retention.allCases) { retention in
                    Text(retention.label).tag(retention)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var deleteAllRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("settings.deleteAll.title"))
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(L10n.text("settings.deleteAll.description"))
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Button(L10n.text("settings.deleteAll.uppercase")) {
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
        let presentation = UpdateStatusPresentation(
            status: updater.status,
            installState: updateInstaller.installState
        )

        return section(L10n.text("settings.section.about")) {
            HStack(spacing: 10) {
                Text(L10n.text("settings.about.version", AppVersion.display, AppVersion.akte))
                    .font(Theme.Typo.counter(12).weight(.bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundColor(Theme.Palette.ink)
                Spacer()
                Button {
                    checkRequested = true
                } label: {
                    Text(L10n.text(updater.isChecking ? "update.checking.uppercase" : "update.check.uppercase"))
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
                .disabled(
                    checkRequested || updater.isChecking
                        || updateInstaller.installState == .installing
                )

                if case let .updateAvailable(version, url, _) = updater.status {
                    updateAction(version: version, url: url)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            // Statuszeile
            HStack(spacing: 7) {
                if presentation.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 10, height: 10)
                } else {
                    Circle()
                        .fill(updateStatusColor(for: presentation.colorRole))
                        .frame(width: 6, height: 6)
                }
                Text(presentation.text)
                    .font(Theme.Typo.counter(10))
                    .monospacedDigit()
                    .textCase(.uppercase)
                    .foregroundColor(updateStatusColor(for: presentation.colorRole))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if case let .updateAvailable(version, url, _) = updater.status,
               case .failed = updateInstaller.installState,
               isCaskInstalled {
                HStack {
                    releaseLinkButton(version: version, url: url)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            if case .updateAvailable = updater.status, !isCaskInstalled {
                Text(L10n.text("update.install.zipHint"))
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            Rectangle().fill(Theme.Palette.linieInnen).frame(height: Theme.Metrics.hairline)

            Text(Copy.privacyFootnote(settings))
                .font(Theme.Typo.secondary(size: 11.5))
                .foregroundColor(Theme.Palette.text2)
                .lineHeight()
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
        }
    }

    @ViewBuilder
    private func updateAction(version: String, url: URL) -> some View {
        switch updateInstaller.installation {
        case .caskInstalled:
            switch updateInstaller.installState {
            case .failed:
                EmptyView()
            case .installedAwaitingRelaunch:
                EmptyView()
            case .idle, .installing:
                Button(L10n.text("update.installHomebrew.uppercase")) {
                    installRequested = true
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
                .disabled(installRequested || updateInstaller.installState == .installing)
            }
        case .notInstalled, .brewWithoutCask:
            releaseLinkButton(version: version, url: url)
        }
    }

    private func releaseLinkButton(version: String, url: URL) -> some View {
        Button(L10n.text("update.install.uppercase", version)) {
            NSWorkspace.shared.open(url)
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
    }

    private var isCaskInstalled: Bool {
        if case .caskInstalled = updateInstaller.installation { return true }
        return false
    }

    private func relaunchAfterUpdate() {
        let command = HomebrewUpdater.relaunchCommand(appPath: Bundle.main.bundleURL.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            installRequested = false
            updateInstaller.reportRelaunchFailure(error.localizedDescription)
        }
    }

    private func updateStatusColor(for role: UpdateStatusPresentation.ColorRole) -> Color {
        switch role {
        case .neutral:
            Theme.Palette.text3
        case .success:
            Theme.Palette.archivgruen
        case .updateAvailable:
            Theme.Palette.stempelrot
        case .warning:
            Theme.Palette.warning
        }
    }
}

private enum HotkeyRecorderPolicyResult {
    case keep
    case cancel
}

/// Gemeinsames Aufnahmefeld; nur Ereignis-Policy und Commit unterscheiden die Kürzelarten.
private struct HotkeyRecorderField<Draft>: View {
    @State private var draft: Draft
    @State private var monitor: Any?
    @State private var monitorTarget: HotkeyCaptureMonitorTarget?

    let prompt: String
    let guidance: [String]
    let symbols: (Draft) -> [String]
    let canCommit: (Draft) -> Bool
    let policy: (inout Draft, HotkeyCaptureEvent) -> HotkeyRecorderPolicyResult
    let onCancel: () -> Void
    let onCommit: (Draft) -> Void

    init(
        initialDraft: Draft,
        prompt: String,
        guidance: [String],
        symbols: @escaping (Draft) -> [String],
        canCommit: @escaping (Draft) -> Bool,
        policy: @escaping (inout Draft, HotkeyCaptureEvent) -> HotkeyRecorderPolicyResult,
        onCancel: @escaping () -> Void,
        onCommit: @escaping (Draft) -> Void
    ) {
        _draft = State(initialValue: initialDraft)
        self.prompt = prompt
        self.guidance = guidance
        self.symbols = symbols
        self.canCommit = canCommit
        self.policy = policy
        self.onCancel = onCancel
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt)
                .kicker(Theme.Palette.stempelrot, tracking: 1.6)

            HStack(spacing: 6) {
                ForEach(symbols(draft), id: \.self) { symbol in
                    KeyBadge(symbol)
                        .font(Theme.Typo.keycap(14))
                }
                BlinkingCursor()
            }

            ForEach(guidance, id: \.self) { line in
                Text(line)
                    .font(Theme.Typo.secondary(size: 11))
                    .foregroundColor(Theme.Palette.text3)
            }

            HStack {
                Spacer()
                Button(L10n.text("action.cancel")) { cancel() }
                    .buttonStyle(GhostButtonStyle())
                Button(L10n.text("action.apply")) { commit() }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(!canCommit(draft))
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
        .onAppear { installMonitor() }
        .onDisappear { removeMonitor() }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        let target = HotkeyCaptureMonitorTarget { event in
            if policy(&draft, event) == .cancel {
                cancel()
            }
        }
        monitorTarget = target
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak target] event in
            guard let action = HotkeyCaptureEvent.parse(event) else { return event }
            target?.send(action)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        monitorTarget = nil
    }

    private func cancel() {
        removeMonitor()
        onCancel()
    }

    private func commit() {
        guard canCommit(draft) else { return }
        removeMonitor()
        onCommit(draft)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let list = devices
            if list.isEmpty {
                Text(L10n.text("microphone.noneFound"))
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

            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.Palette.successColor)
                    .frame(width: 6, height: 6)
                Text(L10n.text("microphone.selected.uppercase"))
                    .font(Theme.Typo.kicker(size: 9.5))
                    .tracking(1)
                    .foregroundColor(Theme.Palette.successText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(width: 270)
        .background(Theme.Palette.papier)
        .onAppear {
            devices = MicrophoneScanner.devices()
        }
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
                    Text(L10n.text("microphone.default.uppercase"))
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
