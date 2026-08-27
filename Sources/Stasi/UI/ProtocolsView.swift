import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Protokolle (v3: Vollhistorie mit Suche)
// Topbar mit Suchfeld (⌘F, Trefferzähler) + Filter-Chips, gruppiert nach Tag,
// Zeile: zweizeilige Mono-Spalte (HH:MM:SS + Aktenzeichen), Text (3 Zeilen,
// Klick klappt auf), Meta mit App-Badge/Dauer/Wörter/Korrekturen, rechts
// Play · Kopieren · ⋯-Menü.

struct ProtocolsView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings
    @Environment(AppSelection.self) private var selection

    @State private var expandedIds: Set<UUID> = []
    @State private var playingId: UUID?
    @State private var copiedId: UUID?
    @State private var rawTextRecord: TranscriptionRecord?
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedRecordID: UUID?

    @State private var player = AudioPlayerHelper()
    private var calendar: Calendar { .current }

    // MARK: Gefilterte Daten

    private var filteredRecords: [TranscriptionRecord] {
        ProtocolSearch.filter(app.history.records,
                              query: selection.searchQuery,
                              filter: selection.searchFilter,
                              calendar: calendar)
    }

    private var dayGroups: [ProtocolSearch.DayGroup] {
        ProtocolSearch.groupByDay(filteredRecords, calendar: calendar)
    }

    private var isSearching: Bool {
        !selection.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
            || selection.searchFilter != .all
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topbar
                header
                    .padding(.top, 22)
                listSection
                    .padding(.top, 18)
            }
            .padding(.horizontal, Theme.Metrics.contentPaddingH)
            .padding(.bottom, 80)
            .frame(maxWidth: 1080 + 2 * Theme.Metrics.contentPaddingH, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { focusSearchIfRequested() }
        .onChange(of: selection.searchFocusRequest) { _, _ in
            focusSearchIfRequested()
        }
        .onAppear { app.refreshPermissionState() }
        .sheet(item: $rawTextRecord) { record in
            RawTranscriptView(record: record, onCopy: { copyRawText(record) })
        }
    }

    // MARK: Topbar (Suche)

    private var topbar: some View {
        HStack(spacing: 12) {
            searchBar
            if isSearching {
                Text("\(Copy.formatGermanNumber(filteredRecords.count)) TREFFER")
                    .font(Theme.Typo.counter(10))
                    .foregroundColor(Theme.Palette.text3)
                    .monospacedDigit()
            }
            Spacer()
            filterChips
        }
        .padding(.top, 14)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(Theme.Palette.text3)
            TextField("Aktenrecherche — Volltext, alle Protokolle",
                      text: Binding(get: { selection.searchQuery },
                                    set: { selection.searchQuery = $0 }))
                .textFieldStyle(.plain)
                .font(Theme.Typo.counter(12))
                .foregroundColor(Theme.Palette.ink)
                .focused($searchFocused)
                .accessibilityLabel("Protokolle durchsuchen")
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
                .strokeBorder(searchFocused ? Theme.accent : Theme.Palette.line,
                              lineWidth: Theme.Metrics.hairline)
        )
    }

    private func focusSearchIfRequested() {
        guard selection.consumeSearchFocusRequest() else { return }
        searchFocused = true
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach(ProtocolSearchFilter.allCases) { f in
                let active = selection.searchFilter == f
                Button {
                    withAnimation(Theme.Motion.fast) { selection.searchFilter = f }
                } label: {
                    Text(f.label)
                        .font(Theme.Typo.kicker(size: 10.5))
                        .tracking(0.8)
                        .foregroundColor(active ? .white : Theme.Palette.text3)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                                .fill(active ? Theme.accent : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                                .strokeBorder(active ? Color.clear : Theme.Palette.line,
                                              lineWidth: Theme.Metrics.hairline)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PROTOKOLLE · \(Copy.formatGermanNumber(app.history.records.count))")
                    .kicker(Theme.Palette.text3)
                Text("Protokolle")
                    .font(Theme.Typo.h1())
                    .tracking(-0.6)
                    .foregroundColor(Theme.Palette.ink)
                Text(Copy.protocolsSubtitle(settings, count: app.history.records.count))
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.text2)
            }
            Spacer()
            Button {
                exportAll()
            } label: {
                Text("EXPORT ALLER PROTOKOLLE")
                    .font(Theme.Typo.kicker(size: 10.5))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundColor(Theme.Palette.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.Palette.linieSidebar, lineWidth: Theme.Metrics.hairline))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Liste (nach Tag gruppiert)

    @ViewBuilder
    private var listSection: some View {
        if app.history.records.isEmpty {
            emptyState
        } else if filteredRecords.isEmpty {
            VStack(spacing: 6) {
                Text("Keine Treffer")
                    .font(Theme.Typo.body().weight(.medium))
                    .foregroundColor(Theme.Palette.ink)
                Text("Keine passenden Protokolle gefunden.")
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.text2)
                Button(Copy.resetProtocolSearch) {
                    selection.searchQuery = ""
                    selection.searchFilter = .all
                    searchFocused = true
                }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .secondaryCard()
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(dayGroups, id: \.day) { group in
                    dayCard(group)
                }
            }
        }
    }

    private func dayCard(_ group: ProtocolSearch.DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.dateLine(group.day, calendar: calendar))
                .kicker(Theme.Palette.text3, tracking: 1)
            VStack(spacing: 0) {
                ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                    row(for: record)
                    if index < group.records.count - 1 {
                        Divider().overlay(Theme.Palette.linieInnen).padding(.leading, 16)
                    }
                }
            }
            .card(padding: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Keine Protokolle")
                .font(Theme.Typo.body().weight(.medium))
                .foregroundColor(Theme.Palette.ink)
            Text(Copy.emptyProtocols(settings))
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.text2)
        }
        .frame(maxWidth: .infinity)
        .secondaryCard()
        .padding(.vertical, 48)
    }

    // MARK: Zeile

    private func row(for record: TranscriptionRecord) -> some View {
        let isExpanded = expandedIds.contains(record.id)
        let isPlaying = playingId == record.id

        return HStack(alignment: .top, spacing: 14) {
            // Zweizeilige Mono-Spalte: Zeit + Aktenzeichen
            VStack(alignment: .leading, spacing: 2) {
                Text(record.date.formatted(.dateTime.hour().minute().second()))
                    .font(Theme.Typo.counter(10.5))
                    .monospacedDigit()
                    .foregroundColor(Theme.Palette.text3)
                Text(FileNumber.forRecord(id: record.id))
                    .font(Theme.Typo.counter(9.5))
                    .foregroundColor(Theme.Palette.text3.opacity(0.75))
            }
            .frame(width: 84, alignment: .leading)
            .padding(.top, 3)

            // Text + Meta
            VStack(alignment: .leading, spacing: 6) {
                Text(record.correctedText)
                    .font(Theme.Typo.body())
                    .lineHeight()
                    .foregroundColor(Theme.Palette.ink)
                    .lineLimit(isExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                metaRow(for: record)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1) // v4: minmax(0,1fr) – Text darf schrumpfen, Ellipsis
            .contentShape(Rectangle())
            .onTapGesture { toggleExpand(record.id) }
            .focusable()
            .focused($focusedRecordID, equals: record.id)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                    .strokeBorder(focusedRecordID == record.id ? Theme.accent : Color.clear,
                                  lineWidth: 2)
            )
            .onKeyPress(.return) {
                toggleExpand(record.id)
                return .handled
            }
            .onKeyPress(.space) {
                toggleExpand(record.id)
                return .handled
            }

            // Icon-Buttons
            HStack(spacing: 4) {
                if record.audioPath != nil {
                    iconButton(isPlaying ? "stop.fill" : "play.fill", active: isPlaying) {
                        Task { @MainActor in togglePlay(record) }
                    }
                }
                iconButton(copiedId == record.id ? "checkmark" : "doc.on.doc",
                           active: copiedId == record.id) {
                    Task { @MainActor in copyRecord(record) }
                }
                rowMenu(for: record)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .background(Theme.Palette.papier)
    }

    private func metaRow(for record: TranscriptionRecord) -> some View {
        HStack(spacing: 10) {
            if !record.targetApp.isEmpty {
                Text(record.targetApp.uppercased())
                    .font(Theme.Typo.kicker(size: 9.5))
                    .tracking(0.6)
                    .foregroundColor(Theme.Palette.archivgruen)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 150)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.chip))
            }
            if record.durationSecs > 0 {
                Text(DurationFormatter.minutesAndSeconds(record.durationSecs))
                if let wpm = wordsPerMinute(record) {
                    Text("\(wpm) WPM")
                }
            }
            Text("\(record.wordCount) Wörter")
            if !record.corrections.isEmpty {
                Text("\(record.corrections.count) KORREKTUREN")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.Palette.linieSidebar, lineWidth: Theme.Metrics.hairline))
            }
            PolishBadge(record: record)
        }
        .font(Theme.Typo.counter(10))
        .monospacedDigit()
        .foregroundColor(Theme.Palette.text3)
        .lineLimit(1)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func wordsPerMinute(_ record: TranscriptionRecord) -> Int? {
        guard record.durationSecs > 1 else { return nil }
        return Int((Double(record.wordCount) / record.durationSecs * 60).rounded())
    }

    private func rowMenu(for record: TranscriptionRecord) -> some View {
        Menu {
            Button("Rohtext anzeigen") { rawTextRecord = record }
            Button("Rohtext kopieren") { copyRawText(record) }
            Divider()
            Button("Audio extrahieren (.wav)") { extractAudio(record) }
            Button("Export als .txt") { export(record, asMarkdown: false) }
            Button("Export als .md") { export(record, asMarkdown: true) }
            Divider()
            Button("Löschen", role: .destructive) {
                Task { @MainActor in
                    if playingId == record.id { player.stop(); playingId = nil }
                    app.deleteHistoryRecord(record)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.text3)
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
                .scaleOnHover()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 27, height: 27)
        .accessibilityLabel("Weitere Aktionen für Protokoll")
    }

    private func iconButton(_ symbol: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(active ? Theme.Palette.stempelrot : Theme.Palette.text3)
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleOnHover()
        .accessibilityLabel(accessibilityLabel(for: symbol))
    }

    private func accessibilityLabel(for symbol: String) -> String {
        switch symbol {
        case "play.fill": "Audio abspielen"
        case "stop.fill": "Audio stoppen"
        case "doc.on.doc": "Protokoll kopieren"
        case "checkmark": "Protokoll kopiert"
        default: symbol
        }
    }

    // MARK: Aktionen

    private func toggleExpand(_ id: UUID) {
        if expandedIds.contains(id) { expandedIds.remove(id) } else { expandedIds.insert(id) }
    }

    private func copyRecord(_ record: TranscriptionRecord) {
        app.copy(record)
        copiedId = record.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedId == record.id { copiedId = nil }
        }
    }

    private func copyRawText(_ record: TranscriptionRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.rawText, forType: .string)
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

    private func exportAll() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "stasi-protokolle.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = ProtocolExporter.markdownAll(app.history.records, calendar: calendar)
        try? md.write(to: url, atomically: true, encoding: .utf8)
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

    private func extractAudio(_ record: TranscriptionRecord) {
        guard let path = record.audioPath else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "wav") ?? .audio]
        panel.nameFieldStringValue = "stasi-audio.wav"
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.copyItem(atPath: path, toPath: url.path)
        }
    }
}

struct RawTranscriptView: View {
    let record: TranscriptionRecord
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rohtext")
                .font(Theme.Typo.sectionTitle())
                .foregroundColor(Theme.Palette.ink)
            ScrollView {
                Text(record.rawText)
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180)
            HStack {
                Spacer()
                Button("Rohtext kopieren", action: onCopy)
                    .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 520, height: 320)
        .background(Theme.Palette.surface)
    }
}

// MARK: - Audio-Wiedergabe-Helfer

@MainActor
final class AudioPlayerHelper: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    var onEnd: (() -> Void)?

    func play(url: URL, onEnd: @escaping () -> Void) {
        stop()
        self.onEnd = onEnd
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.player = nil
            self?.onEnd?()
        }
    }
}

// MARK: - Zeilenhöhe

extension View {
    /// line-height ≈ 1.55 für Fließtext (Lesbarkeit laut Handoff)
    func lineHeight() -> some View {
        lineSpacing(4.5)
    }
}
