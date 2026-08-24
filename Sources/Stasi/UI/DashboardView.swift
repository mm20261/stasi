import SwiftUI

// MARK: - Der Bericht (Dashboard)

struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings
    @Environment(AppSelection.self) private var selection

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

    private var todayWords: Int {
        app.history.records
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.wordCount }
    }

    private var weekWords: Int {
        app.history.records
            .filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.wordCount }
    }

    private var avgDuration: TimeInterval {
        let recs = app.history.records.filter { $0.durationSecs > 0 }
        guard !recs.isEmpty else { return 0 }
        return recs.reduce(0) { $0 + $1.durationSecs } / Double(recs.count)
    }

    /// Wörter pro Tag, Mo–So der aktuellen Woche
    private var wordsPerDay: [(day: String, count: Int, isToday: Bool)] {
        let symbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        return symbols.enumerated().map { index, symbol in
            let day = calendar.date(byAdding: .day, value: index, to: weekStart)!
            let count = app.history.records
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.wordCount }
            return (symbol, count, calendar.isDateInToday(day))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                hotkeyCard
                statsSection
                bottomGrid
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
    }

    // MARK: Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGESBERICHT · \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .kicker(Theme.accent.brightenedForDarkMode())
            HStack {
                Text("\(greeting)\(settings.userName.isEmpty ? "" : ", \(settings.userName)")" + ".")
                    .font(Theme.Typo.h1())
                    .tracking(-0.3)
                    .foregroundColor(Theme.Palette.ink)
                Spacer()
            }
        }
    }

    // MARK: Hotkey-Karte

    private var hotkeyCard: some View {
        HStack(spacing: Theme.Metrics.gridGap) {
            KeyBadge(comboText)
            Text(modeHint)
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)

            if let blocker = app.hotkeyBlocker {
                HStack(spacing: 6) {
                    Circle().fill(Theme.Palette.recRed).frame(width: 7, height: 7)
                    Text("Hotkey inaktiv – \(blocker) fehlt")
                        .font(Theme.Typo.secondary())
                        .foregroundColor(Theme.Palette.sub)
                    Button("Erteilen") {
                        Task { @MainActor in app.requestMissingPermissions() }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }

            Spacer()

            if app.phase != .idle {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.Palette.recRed)
                        .frame(width: 8, height: 8)
                        .pulseForever(intensity: 0.5)
                    Text(app.phase.rawValue)
                        .kicker(Theme.accent.brightenedForDarkMode())
                }
            }
        }
        .card(padding: 14)
    }

    private var comboText: String {
        VirtualKey.name(for: Int(app.currentCombo.keyCode))
            .replacingOccurrences(of: " halten", with: "")
    }

    private var modeHint: String {
        settings.hotkeyMode == .pushToTalk
            ? "Halten zum Sprechen, loslassen zum Einfügen."
            : "Einmal drücken startet, nochmal beendet."
    }

    // MARK: Statistiken

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ÜBERWACHUNGSBERICHT KW\(weekNumber) — LÜCKENLOS ERFASST")
                .kicker(Theme.Palette.sub.opacity(0.8))

            HStack(spacing: Theme.Metrics.gridGap) {
                StatTile(value: "\(todayWords)", label: "Wörter heute", delta: nil)
                StatTile(value: "\(weekWords)", label: "Diese Woche", delta: nil)
                StatTile(value: "\(app.history.records.count)", label: "Protokolle", delta: nil)
                StatTile(value: avgDuration > 0 ? String(format: "%.0f s", avgDuration) : "—",
                         label: "Ø Dauer", delta: nil)
            }
        }
    }

    private var weekNumber: Int {
        calendar.component(.weekOfYear, from: Date())
    }

    // MARK: Chart + letzte Protokolle

    private var bottomGrid: some View {
        HStack(alignment: .top, spacing: Theme.Metrics.gridGap) {
            chartCard
                .frame(maxWidth: .infinity)
            recentProtocolsCard
                .frame(maxWidth: .infinity)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wörter pro Tag")
                .font(Theme.Typo.body().weight(.medium))
                .foregroundColor(Theme.Palette.ink)

            let data = wordsPerDay
            let maxCount = max(data.map(\.count).max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    chartBar(item: item, maxCount: maxCount)
                }
            }
            .frame(minHeight: 120, alignment: .bottom)
        }
        .card(padding: 18)
    }

    private func chartBar(item: (day: String, count: Int, isToday: Bool), maxCount: Int) -> some View {
        let barColor: Color = {
            if item.count == 0 { return Theme.Palette.hover }
            if item.isToday { return Theme.accent.brightenedForDarkMode() }
            return Theme.accent.brightenedForDarkMode().opacity(0.22)
        }()
        let height: CGFloat = item.count == 0 ? 5 : max(CGFloat(item.count) / CGFloat(maxCount) * 90, 5)

        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(barColor)
                .frame(height: height)
                .frame(maxHeight: 95, alignment: .bottom)
            Text(item.day)
                .font(Theme.Typo.kicker(size: 9.5))
                .foregroundColor(item.isToday ? Theme.accent.brightenedForDarkMode() : Theme.Palette.sub)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentProtocolsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Letzte Protokolle")
                    .font(Theme.Typo.body().weight(.medium))
                    .foregroundColor(Theme.Palette.ink)
                Spacer()
                Button("Alle ansehen") { selection.section = .protokolle }
                    .font(Theme.Typo.secondary())
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.accent.brightenedForDarkMode())
            }

            if app.history.records.isEmpty {
                Text(Copy.emptyProtocols(settings))
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.sub)
                    .padding(.vertical, 12)
            } else {
                ForEach(app.history.records.prefix(3)) { record in
                    HStack(spacing: 10) {
                        Text(record.date.formatted(.dateTime.hour().minute()))
                            .font(Theme.Typo.counter(11))
                            .foregroundColor(Theme.Palette.sub)
                        Text(record.correctedText)
                            .font(Theme.Typo.body())
                            .foregroundColor(Theme.Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        if !record.targetApp.isEmpty {
                            Text("→ \(record.targetApp)")
                                .font(Theme.Typo.counter(11))
                                .foregroundColor(Theme.accent.brightenedForDarkMode())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .card(padding: 18)
    }
}

// MARK: - Stat-Kachel

struct StatTile: View {
    let value: String
    let label: String
    let delta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.Typo.stat())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(Theme.Palette.ink)
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .kicker(Theme.Palette.sub)
                if let delta {
                    Text(delta)
                        .kicker(Theme.accent.brightenedForDarkMode())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}
