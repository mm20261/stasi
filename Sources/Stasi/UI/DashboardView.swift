import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Der Bericht (Dashboard, v2)
// Startseite: Begrüßung, Heute-Liste (Play/Kopieren/⋯-Menü), rechte Rail
// (Wörter gesamt, WPM, Serie, „Deine Akte"-Fortschritt).

struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings
    @Environment(AppSelection.self) private var selection

    @State private var expandedIds: Set<UUID> = []
    @State private var playingId: UUID?
    @State private var copiedId: UUID?
    @State private var menuId: UUID?

    private let player = AudioPlayerHelper()
    private var calendar: Calendar { .current }

    private var greeting: String {
        let hour = calendar.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "Guten Morgen"
        case 11..<14: return "Guten Tag"
        case 14..<18: return "Guten Nachmittag"
        default: return "Guten Abend"
        }
    }

    private var todayRecords: [TranscriptionRecord] {
        app.history.records.filter { calendar.isDateInToday($0.date) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let blocker = app.hotkeyBlocker {
                    blockerRow(blocker)
                }
                HStack(alignment: .top, spacing: 18) {
                    todayColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    rail
                        .frame(width: 252)
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 80)
        }
    }

    // MARK: Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAGESBERICHT · \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .kicker(Theme.accent)
            Text("\(greeting)\(settings.userName.isEmpty ? "" : ", \(settings.userName)").")
                .font(Theme.Typo.h1())
                .tracking(-0.3)
                .foregroundColor(Theme.Palette.ink)
        }
    }

    private func blockerRow(_ blocker: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.Palette.recRed).frame(width: 7, height: 7)
            Text("Hotkey inaktiv – \(blocker) fehlt.")
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)
            Button("Erteilen") {
                Task { @MainActor in app.requestMissingPermissions() }
            }
            .font(Theme.Typo.secondary())
            .buttonStyle(GhostButtonStyle())
        }
        .padding(.top, 14)
    }

    // MARK: Heute-Liste

    private var todayColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("HEUTE")
                    .kicker(Theme.Palette.sub)
                Spacer()
                HStack(spacing: 8) {
                    Text("\(todayRecords.count) Protokolle")
                        .font(Theme.Typo.secondary())
                        .foregroundColor(Theme.Palette.sub)
                    Button("Alle ansehen") { selection.section = .protokolle }
                        .font(Theme.Typo.secondary())
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if todayRecords.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(todayRecords.enumerated()), id: \.element.id) { index, record in
                        row(for: record)
                        if index < todayRecords.count - 1 {
                            Divider().overlay(Theme.Palette.line)
                                .padding(.leading, 18)
                        }
                    }
                }
            }
            .card(padding: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Keine Protokolle heute")
                .font(Theme.Typo.body().weight(.medium))
                .foregroundColor(Theme.Palette.ink)
            Text(Copy.emptyProtocols(settings))
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func row(for record: TranscriptionRecord) -> some View {
        let isExpanded = expandedIds.contains(record.id)
        let isPlaying = playingId == record.id

        return HStack(alignment: .top, spacing: 16) {
            Text(record.date.formatted(.dateTime.hour().minute()))
                .font(Theme.Typo.counter(10.5))
                .foregroundColor(Theme.Palette.sub)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 7) {
                Text(record.correctedText)
                    .font(Theme.Typo.body())
                    .lineHeight()
                    .foregroundColor(Theme.Palette.ink)
                    .lineLimit(isExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpand(record.id) }

                Text(metaLine(record))
                    .font(Theme.Typo.counter(10))
                    .foregroundColor(Theme.Palette.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                if record.audioPath != nil {
                    actionButton(isPlaying ? "stop.fill" : "play.fill",
                                 active: isPlaying, filled: true) {
                        Task { @MainActor in togglePlay(record) }
                    }
                }
                actionButton(copiedId == record.id ? "checkmark" : "doc.on.doc",
                             active: copiedId == record.id, filled: false) {
                    Task { @MainActor in
                        app.copy(record)
                        copiedId = record.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            if copiedId == record.id { copiedId = nil }
                        }
                    }
                }
                menuButton(for: record)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func metaLine(_ record: TranscriptionRecord) -> String {
        var parts: [String] = []
        if !record.targetApp.isEmpty { parts.append("→ \(record.targetApp)") }
        if record.durationSecs > 0 {
            parts.append(String(format: "%.0f:%02d", record.durationSecs / 60,
                                Int(record.durationSecs) % 60))
        }
        parts.append("\(record.wordCount) Wörter")
        return parts.joined(separator: " · ")
    }

    // MARK: Rail

    private var rail: some View {
        VStack(spacing: 14) {
            statsCard
            akteCard
        }
    }

    private var statsCard: some View {
        VStack(spacing: 0) {
            railStat(value: StatsCalculator.compactCount(StatsCalculator.totalWords(app.history.records)),
                     label: "Wörter gesamt")
            railStat(value: wpmText, label: "Wörter / Minute")
            railStat(value: "\(StatsCalculator.currentStreak(app.history.records)) Tage",
                     label: "Serie")
        }
        .card(padding: 20)
    }

    private func railStat(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(value)
                .font(Theme.Typo.stat())
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundColor(Theme.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }

    private var wpmText: String {
        guard let wpm = StatsCalculator.wordsPerMinute(app.history.records) else { return "—" }
        return "\(Int(wpm.rounded()))"
    }

    private var akteCard: some View {
        let milestone = 10_000
        let total = StatsCalculator.totalWords(app.history.records)
        let remainder = total % milestone
        let progress = Double(remainder) / Double(milestone)
        let next = milestone - remainder

        return VStack(alignment: .leading, spacing: 0) {
            Text("Deine Akte")
                .font(.custom("Geist", size: 14).weight(.semibold))
                .foregroundColor(Theme.Palette.ink)
            Text(akteNote)
                .font(.custom("Geist", size: 11.5))
                .foregroundColor(Theme.Palette.sub)
                .lineHeight()
                .padding(.top, 3)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.hover)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 6)
            .padding(.top, 12)

            Text("NÄCHSTER EINTRAG IN \(StatsCalculator.compactCount(next)) WÖRTERN")
                .font(Theme.Typo.kicker(size: 10))
                .tracking(0.6)
                .foregroundColor(Theme.Palette.sub)
                .padding(.top, 7)
        }
        .card(padding: 18)
    }

    private var akteNote: String {
        settings.ironyOn
            ? "Alles dokumentiert, nichts vergessen. Du führst sie ausnahmsweise selbst."
            : "Dein Diktier-Fortschritt diese Woche."
    }

    // MARK: Zeilen-Aktionen

    private func actionButton(_ symbol: String, active: Bool, filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.accent : Theme.Palette.sub)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(active ? Theme.tint(Theme.accent) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleOnHover()
    }

    private func menuButton(for record: TranscriptionRecord) -> some View {
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
            Text("⋯")
                .font(.system(size: 15))
                .foregroundColor(Theme.Palette.sub)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .scaleOnHover()
    }

    private func toggleExpand(_ id: UUID) {
        if expandedIds.contains(id) { expandedIds.remove(id) } else { expandedIds.insert(id) }
    }

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
