import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

    private let player = AudioPlayerHelper()
    private var calendar: Calendar { .current }

    // MARK: Daten

    private var todayRecords: [TranscriptionRecord] {
        app.history.records.filter { calendar.isDateInToday($0.date) }
    }

    /// Hero = neuestes Protokoll überhaupt (nicht nur heute).
    private var heroRecord: TranscriptionRecord? {
        app.history.records.first
    }

    /// „Früher heute": heutige Einträge ohne den Hero.
    private var earlierToday: [TranscriptionRecord] {
        todayRecords.filter { $0.id != heroRecord?.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topbar
                dateLine
                    .padding(.top, 18)
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
                mainGrid
                    .padding(.top, 20)
            }
            .padding(.horizontal, Theme.Metrics.contentPaddingH)
            .padding(.bottom, 80)
            .frame(maxWidth: 1080 + 2 * Theme.Metrics.contentPaddingH, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { app.refreshPermissionState() }
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
                    Text("Aktenrecherche — Volltext, alle Protokolle")
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

    private var dateLine: some View {
        Text(Copy.dateLine(Date(), calendar: calendar))
            .font(Theme.Typo.counter(10.5))
            .monospacedDigit()
            .textCase(.uppercase)
            .foregroundColor(Theme.Palette.text3)
    }

    private var headline: some View {
        Text(greeting)
            .font(Theme.Typo.h1())
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

    private var mainGrid: some View {
        HStack(alignment: .top, spacing: Theme.Metrics.gridGap) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1) // v4: minmax(0, 1fr) – Liste schrumpft, Ellipsis
            rail
                .frame(width: Theme.Metrics.railWidth)
        }
    }

    @ViewBuilder
    private var leftColumn: some View {
        if app.history.records.isEmpty {
            FirstStartEmptyState(
                onTry: { app.startDictation() },
                onChangeKey: { selection.section = .einstellungen }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("ZULETZT DIKTIERT")
                    .kicker(Theme.Palette.text3)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
                if let hero = heroRecord {
                    heroCard(hero)
                }
                if !earlierToday.isEmpty {
                    earlierSection
                }
            }
        }
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
                    Label(heroCopied ? "Kopiert" : "Kopieren",
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
                        Task { @MainActor in togglePlay(record) }
                    } label: {
                        Label(playingId == record.id ? "Stopp" : "Anhören",
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

                Text(heroMeta(record))
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
        parts.append("\(record.wordCount) Wörter")
        return parts.joined(separator: " · ")
    }

    private func heroMenu(_ record: TranscriptionRecord) -> some View {
        Menu {
            Button("Audio extrahieren (.wav)") { extractAudio(record) }
            Button("Export als .txt") { export(record, asMarkdown: false) }
            Button("Export als .md") { export(record, asMarkdown: true) }
            Divider()
            Button("Löschen", role: .destructive) {
                Task { @MainActor in
                    if playingId == record.id { player.stop(); playingId = nil }
                    app.history.delete(record)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundColor(Theme.Palette.text3)
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
                .scaleOnHover()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    // MARK: „Früher heute"

    private var earlierSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Button {
                    selection.section = .protokolle
                } label: {
                    Text("Alle Protokolle ansehen")
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

            VStack(spacing: 0) {
                ForEach(Array(earlierToday.enumerated()), id: \.element.id) { index, record in
                    earlierRow(record)
                        .background(Theme.Palette.papier)
                    if index < earlierToday.count - 1 {
                        Divider().overlay(Theme.Palette.linieInnen).padding(.leading, 16)
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
                       onPlay: { Task { @MainActor in togglePlay(record) } },
                       onCopy: { Task { @MainActor in app.copy(record) } },
                       onOpen: { selection.section = .protokolle })
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BESTAND")
                .kicker(Theme.Palette.text3)
                .padding(.horizontal, 2)
            railStatsCard
            akteCard
        }
    }

    private var railStatsCard: some View {
        let records = app.history.records
        return VStack(alignment: .leading, spacing: 0) {
            Text(StatsCalculator.compactCount(StatsCalculator.totalWords(records)))
                .font(Theme.Typo.railNumber())
                .monospacedDigit()
                .tracking(-0.5)
                .foregroundColor(Theme.Palette.ink)
            Text("Wörter insgesamt diktiert")
                .font(Theme.Typo.secondary(size: 12))
                .foregroundColor(Theme.Palette.text2)
                .padding(.top, 2)

            Rectangle().fill(Theme.Palette.linieInnen)
                .frame(height: Theme.Metrics.hairline)
                .padding(.vertical, 12)

            railRow(label: "Wörter / Minute",
                    value: wpmText)
            railRow(label: "Serie",
                    value: streakText)
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

    private var wpmText: String {
        guard let wpm = StatsCalculator.wordsPerMinute(app.history.records) else { return "—" }
        return "\(Int(wpm.rounded()))"
    }

    private var streakText: String {
        "\(StatsCalculator.currentStreak(app.history.records, calendar: calendar)) Tage"
    }

    private var akteCard: some View {
        let milestone = 10_000
        let total = StatsCalculator.totalWords(app.history.records)
        let remainder = total % milestone
        let progress = Double(remainder) / Double(milestone)
        let next = milestone - remainder
        _ = next

        return VStack(alignment: .leading, spacing: 0) {
            Text("Deine Akte")
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
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 6)
            .padding(.top, 12)

            Text("NOCH \(StatsCalculator.compactCount(milestone - remainder)) WÖRTER")
                .font(Theme.Typo.counter(10))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(Theme.Palette.text3)
                .padding(.top, 8)
        }
        .secondaryCard(padding: 18)
    }

    // MARK: Aktionen

    private func togglePlay(_ record: TranscriptionRecord) {
        if playingId == record.id {
            player.stop()
            playingId = nil
        } else if let path = record.audioPath {
            player.play(url: URL(fileURLWithPath: path)) {
                Task { @MainActor in self.playingId = nil }
            }
            playingId = record.id
        }
    }

    private func extractAudio(_ record: TranscriptionRecord) {
        guard let path = record.audioPath else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "wav") ?? .audio]
        panel.nameFieldStringValue = "stasi-audio.wav"
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.copyItem(atPath: path, toPath: url.path)
        }
    }

    private func export(_ record: TranscriptionRecord, asMarkdown: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let base = record.date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        panel.nameFieldStringValue = "protokoll-\(base).\(asMarkdown ? "md" : "txt")"
        if panel.runModal() == .OK, let url = panel.url {
            let content = asMarkdown
                ? "# Protokoll · \(record.date.formatted(.dateTime.day().month().year().hour().minute()))\n\n\(record.correctedText)\n"
                : record.correctedText
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
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
                .layoutPriority(1) // v4: min-width 0 – Text darf schrumpfen

            if !record.targetApp.isEmpty {
                Text(record.targetApp)
                    .font(Theme.Typo.counter(10))
                    .foregroundColor(Theme.Palette.text3)
            }

            HStack(spacing: 2) {
                if record.audioPath != nil {
                    miniIcon(isPlaying ? "stop.fill" : "play.fill") { onPlay() }
                }
                miniIcon(copied ? "checkmark" : "doc.on.doc",
                         tint: copied ? Theme.Palette.archivgruen : Theme.Palette.text3) {
                    onCopy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }

    private func miniIcon(_ symbol: String, tint: Color = Theme.Palette.text3,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Warnkarte „Berechtigung fehlt"

struct PermissionWarningCard: View {
    var onAllow: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseOn = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.Palette.recRed)
                .frame(width: 8, height: 8)
                .opacity(pulseOn ? 0.25 : 1)
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
        .onAppear { startPulse() }
        .onChange(of: reduceMotion) { _, newValue in startPulse() }
    }

    private func startPulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulseOn = true
        }
    }
}

// MARK: - Leerzustand erster Start

struct FirstStartEmptyState: View {
    /// Startet eine echte Probaufnahme (Pill mit ✓ zum Beenden).
    var onTry: () -> Void
    var onChangeKey: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(Copy.firstStartTitle)
                .font(.custom("Geist", size: 17).weight(.bold))
                .foregroundColor(Theme.Palette.ink)
            Text(instructionWithKeycap)
                .font(Theme.Typo.body())
                .lineHeight()
                .foregroundColor(Theme.Palette.text2)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {} label: {
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
        Copy.firstStartBody
    }
}
