import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Protokolle (Transcriptions-Historie)

struct ProtocolsView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings

    @State private var expandedIds: Set<UUID> = []
    @State private var playingId: UUID?
    @State private var copiedId: UUID?
    @State private var menuId: UUID?

    private var player = AudioPlayerHelper()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                listCard
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Protokolle")
                .font(Theme.Typo.h1())
                .tracking(-0.3)
                .foregroundColor(Theme.Palette.ink)
            Text(Copy.protocolsSubtitle(settings, count: app.history.records.count))
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)
        }
    }

    // MARK: Liste

    private var listCard: some View {
        VStack(spacing: 0) {
            if app.history.records.isEmpty {
                emptyState
                    .padding(.vertical, 48)
            } else {
                ForEach(Array(app.history.records.enumerated()), id: \.element.id) { index, record in
                    row(for: record)
                    if index < app.history.records.count - 1 {
                        Divider().overlay(Theme.Palette.line)
                    }
                }
            }
        }
        .card(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Keine Protokolle")
                .font(Theme.Typo.body().weight(.medium))
                .foregroundColor(Theme.Palette.ink)
            Text(Copy.emptyProtocols(settings))
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Zeile

    private func row(for record: TranscriptionRecord) -> some View {
        let isExpanded = expandedIds.contains(record.id)
        let isPlaying = playingId == record.id

        return HStack(alignment: .top, spacing: 14) {
            // Zeit-Spalte
            Text(record.date.formatted(.dateTime.hour().minute().second()))
                .font(Theme.Typo.counter(11))
                .foregroundColor(Theme.Palette.sub)
                .frame(width: 72, alignment: .leading)
                .padding(.top, 3)

            // Text + Meta
            VStack(alignment: .leading, spacing: 5) {
                Text(record.correctedText)
                    .font(Theme.Typo.body())
                    .lineHeight()
                    .foregroundColor(Theme.Palette.ink)
                    .lineLimit(isExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpand(record.id) }

                HStack(spacing: 10) {
                    if !record.targetApp.isEmpty {
                        Text("→ \(record.targetApp)")
                    }
                    if record.durationSecs > 0 {
                        Text(String(format: "%.0f:%02d", record.durationSecs / 60,
                                    Int(record.durationSecs) % 60))
                    }
                    Text("\(record.wordCount) Wörter")
                    ForEach(record.corrections) { c in
                        Label(c.target, systemImage: "arrow.triangle.swap")
                            .foregroundColor(Theme.accent.brightenedForDarkMode())
                    }
                }
                .font(Theme.Typo.counter(10.5))
                .foregroundColor(Theme.Palette.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Icon-Buttons
            HStack(spacing: 6) {
                if record.audioPath != nil {
                    iconButton(isPlaying ? "stop.fill" : "play.fill", active: isPlaying) {
                        Task { @MainActor in togglePlay(record) }
                    }
                }
                iconButton(copiedId == record.id ? "checkmark" : "doc.on.doc",
                           active: copiedId == record.id) {
                    Task { @MainActor in
                        app.copy(record)
                        copiedId = record.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            if copiedId == record.id { copiedId = nil }
                        }
                    }
                }
                rowMenu(for: record)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func rowMenu(for record: TranscriptionRecord) -> some View {
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
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Theme.Palette.surface)
        )
        .contentShape(Rectangle())
    }

    private func iconButton(_ symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(active ? Theme.accent.brightenedForDarkMode() : Theme.Palette.sub)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Theme.tint(Theme.accent) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Aktionen

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
