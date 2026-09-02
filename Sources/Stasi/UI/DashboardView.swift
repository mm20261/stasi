import SwiftUI

// MARK: - Der Bericht (v3)
// Aufgabe: das letzte Diktat finden und kopieren.
// Topbar mit Suche → Datumszeile → Begrüßung → Anleitungsleiste mit
// Status-Chip → Grid (Hero „Zuletzt diktiert" + „Früher heute" | Rail).

struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings
    @Environment(AppSelection.self) private var selection

    @State private var playingId: UUID?
    @State private var heroCopied = false
    @State private var rawTextRecord: TranscriptionRecord?

    @State private var player = AudioPlayerHelper()
    private var calendar: Calendar { .current }

    // MARK: Daten

    var body: some View {
        let records = app.history.records
        let heroRecord = records.first
        let earlierToday = records.filter {
            calendar.isDateInToday($0.date) && $0.id != heroRecord?.id
        }
        let stats = DashboardStats(records: records, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topbar
                screenTitle
                    .padding(.top, 18)
                dateLine
                    .padding(.top, 10)
                headline
                    .padding(.top, 4)
                instructionBar
                    .padding(.top, 16)
                if app.hotkeyBlocker != nil {
                    PermissionWarningCard(onAllow: {
                        Task { @MainActor in app.requestMissingPermissions() }
                    })
                    .padding(.top, 12)
                }
                mainGrid(
                    heroRecord: heroRecord,
                    earlierToday: earlierToday,
                    stats: stats
                )
                    .padding(.top, 20)
            }
            .padding(.horizontal, Theme.Metrics.contentPaddingH)
            .padding(.bottom, 80)
            .frame(maxWidth: 1080 + 2 * Theme.Metrics.contentPaddingH, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { app.refreshPermissionState() }
        .sheet(item: $rawTextRecord) { record in
            RawTranscriptView(record: record, onCopy: { RecordActions.copyRawText(record) })
        }
    }

    // MARK: Topbar (Suche)

    private var topbar: some View {
        HStack(spacing: 12) {
            Button {
                selection.beginSearchFromBericht()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Palette.text3)
                    Text(L10n.text("search.placeholder"))
                        .font(Theme.Typo.counter(12))
                        .foregroundColor(Theme.Palette.text3)
                    Spacer()
                    Text("⌘F")
                        .font(Theme.Typo.counter(10))
                        .foregroundColor(Theme.Palette.text3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                        .fill(Theme.Palette.papier)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                        .strokeBorder(Theme.Palette.linie, lineWidth: Theme.Metrics.hairline)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 14)
    }

    // MARK: Kopf

    private var screenTitle: some View {
        Text(L10n.text("dashboard.title"))
            .font(Theme.Typo.h1())
            .tracking(-0.6)
            .foregroundColor(Theme.Palette.ink)
    }

    private var dateLine: some View {
        Text(Copy.dateLine(Date(), calendar: calendar))
            .font(Theme.Typo.counter(10.5))
            .monospacedDigit()
            .textCase(.uppercase)
            .foregroundColor(Theme.Palette.text3)
    }

    private var headline: some View {
        Text(greeting)
            .font(Theme.Typo.sectionTitle())
            .tracking(-0.6)
            .foregroundColor(Theme.Palette.ink)
            .lineLimit(1)
    }

    private var greeting: String {
        Copy.greetingLine(for: Date(), name: settings.userName, calendar: calendar)
    }

    // MARK: Anleitungsleiste (Keycap + Text + Status-Chip)

    private var instructionBar: some View {
        HStack(spacing: 11) {
            KeyBadge(comboLabel)
            Text(Copy.anleitungText)
                .font(Theme.Typo.body())
                .foregroundColor(Theme.Palette.ink)
            StatusChip(ok: app.hotkeyReady,
                       text: app.hotkeyReady ? Copy.anleitungStatusReady
                                             : Copy.anleitungStatusBlocked,
                       pulse: !app.hotkeyReady)
            Spacer()
        }
        .secondaryCard(insets: EdgeInsets(top: 12, leading: 16,
                                           bottom: 12, trailing: 16))
    }

    private var comboLabel: String {
        VirtualKey.display(app.currentCombo)
    }

    // MARK: Grid

    private func mainGrid(
        heroRecord: TranscriptionRecord?,
        earlierToday: [TranscriptionRecord],
        stats: DashboardStats
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Metrics.gridGap) {
            leftColumn(heroRecord: heroRecord, earlierToday: earlierToday)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1) // v4: minmax(0, 1fr) – Liste schrumpft, Ellipsis
            rail(stats: stats)
                .frame(width: Theme.Metrics.railWidth)
        }
    }

    @ViewBuilder
    private func leftColumn(
        heroRecord: TranscriptionRecord?,
        earlierToday: [TranscriptionRecord]
    ) -> some View {
        if app.history.state == .loading {
            loadingState(L10n.text("protocols.loading"))
        } else if heroRecord == nil {
            FirstStartEmptyState(
                onTry: { app.startDictation() },
                onChangeKey: { selection.section = .einstellungen }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("dashboard.latest.uppercase"))
                    .kicker(Theme.Palette.text3)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
                if let hero = heroRecord {
                    heroCard(hero)
                }
                if !earlierToday.isEmpty {
                    earlierSection(earlierToday)
                }
            }
        }
    }

    private func loadingState(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.secondary())
            .foregroundColor(Theme.Palette.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .secondaryCard()
    }

    // MARK: Hero „Zuletzt diktiert"

    private func heroCard(_ record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(record.correctedText)
                .font(Theme.Typo.hero())
                .lineSpacing(9) // 15,5 px × 1,65
                .foregroundStyle(Theme.Palette.ink)
                .textSelection(.enabled)

            HStack(alignment: .center, spacing: 18) {
                Button {
                    Task { @MainActor in
                        app.copy(record)
                        heroCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            heroCopied = false
                        }
                    }
                } label: {
                    Label(L10n.text(heroCopied ? "action.copied" : "action.copy"),
                          systemImage: heroCopied ? "checkmark" : "doc.on.doc")
                        .font(.custom("Geist", size: 13).weight(.semibold))
                        .foregroundColor(heroCopied ? Theme.Palette.archivgruen : Theme.Palette.papier)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                            .fill(heroCopied ? Theme.Palette.erfolgFlaeche : Theme.Palette.stempelrot))
                }
                .buttonStyle(.plain)

                if record.audioPath != nil {
                    Button {
                        Task { @MainActor in
                            RecordActions.togglePlay(
                                record,
                                player: player,
                                playingId: $playingId
                            )
                        }
                    } label: {
                        Label(L10n.text(playingId == record.id ? "action.stop" : "action.listen"),
                              systemImage: playingId == record.id ? "stop.fill" : "play.fill")
                            .font(.custom("Geist", size: 13).weight(.medium))
                            .foregroundColor(Theme.Palette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                                .strokeBorder(Theme.Palette.linie, lineWidth: Theme.Metrics.hairline))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Text(heroMeta(record))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                    PolishBadge(record: record)
                }
                .font(Theme.Typo.counter(10.5))
                .monospacedDigit()
                .foregroundColor(Theme.Palette.text3)

                Spacer()

                heroMenu(record)
            }
            .padding(.top, 18)
        }
        .card(insets: EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22))
    }

    private func heroMeta(_ record: TranscriptionRecord) -> String {
        var parts = [record.date.formatted(.dateTime.hour().minute())]
        if !record.targetApp.isEmpty { parts.append(record.targetApp) }
        parts.append(L10n.text(record.wordCount == 1 ? "words.one" : "words.many", record.wordCount))
        return parts.joined(separator: " · ")
    }

    private func heroMenu(_ record: TranscriptionRecord) -> some View {
        RecordActionsMenu(
            record: record,
            rawTextRecord: $rawTextRecord,
            playingId: $playingId,
            player: player,
            onDelete: { app.deleteHistoryRecord(record) }
        )
    }

    // MARK: „Früher heute"

    private func earlierSection(_ records: [TranscriptionRecord]) -> some View {
        let lastID = records.last?.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Button {
                    selection.section = .protokolle
                } label: {
                    Text(L10n.text("dashboard.viewAllProtocols"))
                        .font(.custom("Geist", size: 12))
                        .foregroundColor(Theme.Palette.text2)
                        .padding(.bottom, 1)
                        .background(alignment: .bottom) {
                            Rectangle().fill(Theme.Palette.linieSidebar)
                                .frame(height: Theme.Metrics.hairline)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            LazyVStack(spacing: 0) {
                ForEach(records) { record in
                    earlierRow(record)
                        .background(Theme.Palette.papier)
                        .overlay(alignment: .bottom) {
                            if record.id != lastID {
                                Divider().overlay(Theme.Palette.linieInnen)
                                    .padding(.leading, 16)
                            }
                        }
                }
            }
            .secondaryCard(padding: 0)
        }
        .padding(.top, 14)
    }

    private func earlierRow(_ record: TranscriptionRecord) -> some View {
        EarlierRowView(record: record,
                       isPlaying: playingId == record.id,
                       calendar: calendar,
                       onPlay: {
                           Task { @MainActor in
                               RecordActions.togglePlay(
                                   record,
                                   player: player,
                                   playingId: $playingId
                               )
                           }
                       },
                       onCopy: { Task { @MainActor in app.copy(record) } },
                       onOpen: { selection.section = .protokolle })
    }

    // MARK: Rail

    private func rail(stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("protocols.title.uppercase"))
                .kicker(Theme.Palette.text3)
                .padding(.horizontal, 2)
            railStatsCard(stats: stats)
            akteCard(stats: stats)
        }
    }

    private func railStatsCard(stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(stats.totalWordsText)
                .font(Theme.Typo.railNumber())
                .monospacedDigit()
                .tracking(-0.5)
                .foregroundColor(Theme.Palette.ink)
            Text(L10n.text("dashboard.totalWords"))
                .font(Theme.Typo.secondary(size: 12))
                .foregroundColor(Theme.Palette.text2)
                .padding(.top, 2)

            Rectangle().fill(Theme.Palette.linieInnen)
                .frame(height: Theme.Metrics.hairline)
                .padding(.vertical, 12)

            railRow(label: L10n.text("stats.wordsPerMinute"),
                    value: stats.wpmText)
            railRow(label: L10n.text("stats.streak"),
                    value: stats.streakText)
        }
        .secondaryCard(padding: 18)
    }

    private func railRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typo.secondary(size: 12))
                .foregroundColor(Theme.Palette.text2)
            Spacer()
            Text(value)
                .font(Theme.Typo.secondary(size: 12).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(Theme.Palette.ink)
        }
        .padding(.top, 6)
    }

    private func akteCard(stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("dashboard.yourFile"))
                .font(Theme.Typo.kartentitel())
                .foregroundColor(Theme.Palette.ink)
            Text(Copy.akteNote(settings))
                .font(Theme.Typo.secondary(size: 11.5))
                .foregroundColor(Theme.Palette.text2)
                .lineHeight()
                .padding(.top, 3)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.linieInnen)
                    RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.stempelrot)
                        .frame(width: max(4, geo.size.width * stats.milestoneProgress))
                }
            }
            .frame(height: 6)
            .padding(.top, 12)

            Text(L10n.text("dashboard.untilMilestone", stats.wordsUntilMilestoneText, Copy.akteMilestone.uppercased()))
                .font(Theme.Typo.counter(10))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(Theme.Palette.text3)
                .padding(.top, 8)
        }
        .secondaryCard(padding: 18)
    }

}

private struct DashboardStats {
    private static let milestone = 10_000

    let totalWordsText: String
    let wpmText: String
    let streakText: String
    let milestoneProgress: Double
    let wordsUntilMilestoneText: String

    init(records: [TranscriptionRecord], calendar: Calendar) {
        let totalWords = StatsCalculator.totalWords(records)
        let remainder = totalWords % Self.milestone
        totalWordsText = StatsCalculator.compactCount(totalWords)
        wpmText = StatsCalculator.wordsPerMinute(records)
            .map { "\(Int($0.rounded()))" } ?? "—"
        let streak = StatsCalculator.currentStreak(records, calendar: calendar)
        streakText = L10n.text(streak == 1 ? "days.one" : "days.many", streak)
        milestoneProgress = Double(remainder) / Double(Self.milestone)
        wordsUntilMilestoneText = StatsCalculator.compactCount(Self.milestone - remainder)
    }
}

// MARK: - „Früher heute"-Zeile (eine Zeile, Ellipsis)

private struct EarlierRowView: View {
    let record: TranscriptionRecord
    let isPlaying: Bool
    let calendar: Calendar
    let onPlay: () -> Void
    let onCopy: () -> Void
    let onOpen: () -> Void

    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            Text(record.date.formatted(.dateTime.hour().minute()))
                .font(Theme.Typo.counter(10.5))
                .monospacedDigit()
                .foregroundColor(Theme.Palette.text3)
                .frame(width: 38, alignment: .leading)

            Text(record.correctedText)
                .font(Theme.Typo.body())
                .foregroundColor(Theme.Palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1) // v4: min-width 0 – Text darf schrumpfen

            if !record.targetApp.isEmpty {
                Text(record.targetApp)
                    .font(Theme.Typo.counter(10))
                    .foregroundColor(Theme.Palette.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 112, alignment: .trailing)
            }

            PolishBadge(record: record, compact: true)

            HStack(spacing: 2) {
                if record.audioPath != nil {
                    miniIcon(isPlaying ? "stop.fill" : "play.fill",
                             label: L10n.text(isPlaying ? "audio.stop" : "audio.play")) { onPlay() }
                }
                miniIcon(copied ? "checkmark" : "doc.on.doc",
                         tint: copied ? Theme.Palette.archivgruen : Theme.Palette.text3,
                         label: L10n.text(copied ? "protocol.copied" : "protocol.copy")) {
                    onCopy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                }
            }
        }
        .frame(height: 27)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .focusable()
        .focused($rowFocused)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                .strokeBorder(rowFocused ? Theme.accent : Color.clear, lineWidth: 2)
        )
        .onKeyPress(.return) {
            onOpen()
            return .handled
        }
        .onKeyPress(.space) {
            onOpen()
            return .handled
        }
    }

    private func miniIcon(_ symbol: String, tint: Color = Theme.Palette.text3,
                          label: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @FocusState private var rowFocused: Bool
}

// MARK: - Warnkarte „Berechtigung fehlt"

struct PermissionWarningCard: View {
    var onAllow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.Palette.recRed)
                .frame(width: 8, height: 8)
                .pulseForever(intensity: 0.75)
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.permissionWarningTitle)
                    .font(Theme.Typo.body().weight(.semibold))
                    .foregroundColor(Theme.Palette.ink)
                Text(Copy.permissionWarningBody)
                    .font(Theme.Typo.secondary(size: 11.5))
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Button {
                onAllow()
            } label: {
                Text(Copy.permissionWarningButton)
                    .font(.custom("Geist", size: 13).weight(.semibold))
                    .foregroundColor(Theme.Palette.papier)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                        .fill(Theme.Palette.stempelrot))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Palette.warnFlaeche)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.Palette.warnRand, lineWidth: Theme.Metrics.hairline))
        )
    }
}

// MARK: - Leerzustand erster Start

struct FirstStartEmptyState: View {
    /// Startet eine echte Probaufnahme (Pill mit ✓ zum Beenden).
    var onTry: () -> Void
    var onChangeKey: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 10) {
            Text(Copy.firstStartTitle)
                .font(Theme.Typo.emptyTitle())
                .foregroundColor(Theme.Palette.ink)
            Text(instructionWithKeycap)
                .font(Theme.Typo.body())
                .lineHeight()
                .foregroundColor(Theme.Palette.text2)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button { onTry() } label: {
                    Text(Copy.firstStartTryButton)
                        .font(.custom("Geist", size: 13).weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                            .fill(Theme.accent))
                }
                .buttonStyle(.plain)

                Button {
                    onChangeKey()
                } label: {
                    Text(Copy.firstStartChangeKeyButton)
                        .font(.custom("Geist", size: 13).weight(.medium))
                        .foregroundColor(Theme.Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                            .fill(Theme.Palette.chip))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .secondaryCard(insets: EdgeInsets(top: 28, leading: 24, bottom: 28, trailing: 24))
    }

    private var instructionWithKeycap: String {
        Copy.firstStartBody(combo: app.currentCombo)
    }
}
