import SwiftUI

// MARK: - Onboarding (v4: Fenster 560 × 440, vier Schritte)

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings

    @State private var model = OnboardingModel()
    /// Live-Kombination aus Schritt 3.
    @State private var hotkeyDraft = HotkeyCaptureDraft()
    @State private var captureMonitor: Any?
    @State private var captureTarget: HotkeyCaptureMonitorTarget?
    @State private var microphoneGranted = Permissions.microphoneGranted
    @State private var showPermissionWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            progressBar
                .padding(.top, 10)
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(28)
        .frame(width: 560, height: 440)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard, style: .continuous)
                .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline)
        )
        .shadow(color: Theme.shadow(Theme.accent), radius: 8, x: 0, y: 2)
        .onDisappear { removeMonitor() }
    }

    // MARK: Kopf + Fortschritt

    private var header: some View {
        HStack {
            wordmarkBars
            Spacer()
            Text(OnboardingModel.progressLabel(step: model.step))
                .font(Theme.Typo.counter(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundColor(Theme.Palette.text3)
        }
    }

    private var wordmarkBars: some View {
        HStack(spacing: 2.5) {
            Capsule().fill(Theme.accent).frame(width: 3, height: 9)
            Capsule().fill(Theme.accent).frame(width: 3, height: 16)
            Capsule().fill(Theme.accent).frame(width: 3, height: 6)
        }
    }

    /// Vierteiliger Fortschrittsbalken (3 px, erledigt stempelrot).
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(1...OnboardingModel.totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= model.step ? Theme.Palette.stempelrot : Theme.Palette.linie)
                    .frame(height: 3)
            }
        }
    }

    // MARK: Schritte

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case 1: welcomeStep
        case 2: permissionsStep
        case 3: hotkeyStep
        default: trialStep
        }
    }

    // Schritt 1 – Willkommen
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Guten Tag. Wir legen eine Akte für dich an.")
                .font(Theme.Typo.onboardingTitle())
                .tracking(-0.5)
                .foregroundColor(Theme.Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 34)
            Text("Stasi diktiert on-device auf diesem Mac. Nichts verlässt das Gerät — kein Konto, keine Cloud, kein Mithören. Halte eine Taste gedrückt, sprich, lass los: Der Text steht in dem Feld, in dem dein Cursor blinkt.")
                .font(Theme.Typo.body())
                .lineHeight()
                .foregroundColor(Theme.Palette.text2)
                .padding(.top, 14)
            HStack(spacing: 12) {
                Button {
                    model.next()
                    Task { microphoneGranted = await Permissions.requestMicrophone() }
                } label: {
                    Text("Akte anlegen")
                        .font(.custom("Geist", size: 13).weight(.semibold))
                        .foregroundColor(Theme.Palette.papier)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                            .fill(Theme.Palette.stempelrot))
                }
                .buttonStyle(.plain)
                Text("DAUERT 40 SEKUNDEN")
                    .font(Theme.Typo.counter(9.5))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundColor(Theme.Palette.text3)
            }
            .padding(.top, 22)
            Spacer()
        }
    }

    // Schritt 2 – Befugnisse
    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Zwei Freigaben, dann hören wir zu.")
                .font(Theme.Typo.sectionTitle())
                .tracking(-0.4)
                .foregroundColor(Theme.Palette.ink)
                .padding(.top, 26)

            VStack(spacing: 10) {
                permissionRow(
                    title: "Bedienungshilfen",
                    note: "Damit Stasi in andere Apps tippen darf.",
                    granted: app.accessibilityGranted,
                    action: { Task { @MainActor in app.requestMissingPermissions() } })
                permissionRow(
                    title: "Mikrofon",
                    note: "Für die Aufnahme – bleibt auf diesem Mac.",
                    granted: microphoneGranted,
                    action: {
                        Task { microphoneGranted = await Permissions.requestMicrophone() }
                    })
            }
            .padding(.top, 18)

            HStack(spacing: 7) {
                Circle()
                    .fill(app.modelReady(for: settings.transcriptionLocale)
                          ? Theme.Palette.archivgruen : Theme.Palette.text3)
                    .frame(width: 7, height: 7)
                Text(app.modelReady(for: settings.transcriptionLocale)
                     ? "Sprachmodell bereit ✓"
                     : "Sprachmodell wird vorbereitet…")
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            .padding(.top, 12)

            if showPermissionWarning {
                Text("Ohne Mikrofon und Bedienungshilfen kann Stasi noch nicht diktieren und einfügen.")
                    .font(Theme.Typo.note())
                    .foregroundColor(Theme.Palette.destructive)
                    .padding(.top, 12)
            }

            navButtons(backTitle: "Zurück", backAction: { model.back() },
                       secondaryTitle: "Später", secondaryAction: { model.next() },
                       primaryTitle: "Weiter", primaryAction: { continueFromPermissions() },
                       primaryDisabled: false)
            Spacer()
        }
    }

    private func permissionRow(title: String, note: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(granted ? Theme.Palette.archivgruen : Theme.Palette.recRed)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Typo.zeilenTitel())
                    .foregroundColor(Theme.Palette.ink)
                Text(note)
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            if granted {
                Text("ERTEILT ✓")
                    .font(Theme.Typo.kicker(size: 10))
                    .tracking(0.8)
                    .foregroundColor(Theme.Palette.successText)
            } else {
                Button("FREIGEBEN", action: action)
                    .font(Theme.Typo.kicker(size: 10.5))
                    .tracking(0.8)
                    .foregroundColor(Theme.Palette.papier)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                        .fill(Theme.Palette.stempelrot))
                    .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Theme.Palette.zeileHover))
    }

    // Schritt 3 – Tastenkombination
    static func hotkeyPreviewText(for draft: HotkeyCaptureDraft) -> String {
        guard let combo = draft.combo else { return "" }
        return VirtualKey.display(combo)
    }

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welche Taste hält das Mikrofon offen?")
                .font(Theme.Typo.sectionTitle())
                .tracking(-0.4)
                .foregroundColor(Theme.Palette.ink)
                .padding(.top, 26)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        KeyBadge(Self.hotkeyPreviewText(for: hotkeyDraft))
                        BlinkingCursor()
                    }
                    Text("Taste frei belegbar – Modifier plus Taste oder ein Modifier allein.")
                        .font(Theme.Typo.secondary(size: 11))
                        .foregroundColor(Theme.Palette.text3)
                }
                Spacer()
                Text("ODER: FN ×2")
                    .font(Theme.Typo.counter(10))
                    .tracking(1)
                    .foregroundColor(Theme.Palette.text3)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Palette.recorderFlaeche)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.Palette.stempelrot,
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            )
            .padding(.top, 16)
            .onAppear { startCapture() }
            .onDisappear { removeMonitor() }

            navButtons(backTitle: "Zurück", backAction: { removeMonitor(); model.back() },
                       primaryTitle: "Übernehmen", primaryAction: { commitHotkey(); model.next() },
                       primaryDisabled: !hotkeyDraft.isValidSelection)
            Spacer()
        }
    }

    // Schritt 4 – Probediktat
    private var trialStep: some View {
        let lastRecord = app.history.records.first
        return VStack(alignment: .leading, spacing: 0) {
            Text("Halte \(VirtualKey.display(app.currentCombo)) und sag irgendwas.")
                .font(Theme.Typo.sectionTitle())
                .tracking(-0.4)
                .foregroundColor(Theme.Palette.ink)
                .padding(.top, 26)

            // Ergebniskarte
            HStack(alignment: .top, spacing: 6) {
                Text(displayText(lastRecord))
                    .font(Theme.Typo.hero())
                    .lineSpacing(7)
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BlinkingCursor()
            }
            .card(padding: 16)
            .frame(minHeight: 96, alignment: .top)
            .padding(.top, 16)

            // Fußzeile
            HStack(spacing: 8) {
                if lastRecord != nil {
                    Circle().fill(Theme.Palette.archivgruen).frame(width: 6, height: 6)
                    Text(trialFootnote(lastRecord!))
                        .font(Theme.Typo.counter(9.5))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundColor(Theme.Palette.text3)
                } else {
                    Text("Noch nichts erfasst – sprich einfach einen Satz.")
                        .font(Theme.Typo.secondary(size: 11.5))
                        .foregroundColor(Theme.Palette.text3)
                }
                Spacer()

                stampBadge("EINSATZBEREIT")

            }
            .padding(.top, 14)

            navButtons(backTitle: "Zurück", backAction: { model.back() },
                       primaryTitle: "Akte eröffnen", primaryAction: { finishOnboarding() },
                       primaryDisabled: false)
            Spacer()
        }
    }

    private func displayText(_ record: TranscriptionRecord?) -> String {
        if let record { return record.correctedText }
        return app.phase == .recording || !app.partialText.isEmpty
            ? app.partialText
            : "…"
    }

    private func trialFootnote(_ record: TranscriptionRecord) -> String {
        let duration = DurationFormatter.minutesAndSeconds(record.durationSecs)
        return "ERFASST · \(duration) · \(record.wordCount) WÖRTER · IN ZWISCHENABLAGE"
    }

    private func stampBadge(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.counter(9.5))
            .tracking(0.8)
            .foregroundColor(Theme.Palette.stempelrot)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Theme.Palette.stempelrot, lineWidth: 1.5))
            .rotationEffect(.degrees(-3))
    }

    // MARK: Navigation unten

    @ViewBuilder
    private func navButtons(backTitle: String?, backAction: @escaping () -> Void,
                            secondaryTitle: String? = nil,
                            secondaryAction: @escaping () -> Void = {},
                            primaryTitle: String?, primaryAction: @escaping () -> Void,
                            primaryDisabled: Bool) -> some View {
        HStack {
            if let backTitle {
                Button(backTitle, action: backAction)
                    .buttonStyle(GhostButtonStyle())
            }
            if let secondaryTitle {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.plain)
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            if let primaryTitle {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(AccentButtonStyle())
                    .disabled(primaryDisabled)
            }
        }
        .padding(.top, 20)
    }

    private func continueFromPermissions() {
        guard app.accessibilityGranted && microphoneGranted else {
            showPermissionWarning = true
            return
        }
        showPermissionWarning = false
        model.next()
    }

    // MARK: Hotkey-Capture (Schritt 3)

    private func startCapture() {
        guard captureMonitor == nil else { return }
        if hotkeyDraft.combo == nil {
            hotkeyDraft = HotkeyCaptureDraft(combo: app.currentCombo)
        }
        let target = HotkeyCaptureMonitorTarget { action in
            hotkeyDraft.process(action)
        }
        captureTarget = target
        captureMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak target] event in
            guard let action = HotkeyCaptureEvent.parse(event) else { return event }
            target?.send(action)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor = captureMonitor { NSEvent.removeMonitor(monitor) }
        captureMonitor = nil
        captureTarget = nil
    }

    private func commitHotkey() {
        guard hotkeyDraft.isValidSelection, let combo = hotkeyDraft.combo else { return }
        app.applyHotkey(combo)
        hotkeyDraft = HotkeyCaptureDraft()
    }

    private func finishOnboarding() {
        removeMonitor()
        settings.onboardingDone = true
        model.finish()
    }

}
