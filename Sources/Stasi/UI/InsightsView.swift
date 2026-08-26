import SwiftUI

// MARK: - Insights (v3)
// Eine Leitzahl statt drei Karten · App-Balken in einem Rotton abgestuft ·
// Serie-Heatmap mit Stempel-Badge.

struct InsightsView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(StatsCalculator.weekKickerLabel(for: Date(), calendar: calendar))
                    .kicker(Theme.Palette.text3)
                Text("Insights")
                    .font(Theme.Typo.h1())
                    .tracking(-0.6)
                    .foregroundColor(Theme.Palette.ink)
                    .padding(.top, 4)
                Text(Copy.insightsSubtitle(settings))
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.Palette.text2)
                    .padding(.top, 5)

                if app.history.records.isEmpty {
                    emptyState
                        .padding(.top, 22)
                } else {
                    leitzahlCard
                        .padding(.top, 22)

                    HStack(alignment: .top, spacing: Theme.Metrics.gridGap) {
                        appUsageCard
                            .frame(maxWidth: .infinity)
                        streakCard
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, Theme.Metrics.gridGap)
                }
            }
            .padding(.horizontal, Theme.Metrics.contentPaddingH)
            .padding(.bottom, 80)
            .frame(maxWidth: 1080 + 2 * Theme.Metrics.contentPaddingH, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { app.refreshPermissionState() }
    }

    private var emptyState: some View {
        Text(Copy.insightsEmpty)
            .font(Theme.Typo.body())
            .foregroundColor(Theme.Palette.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .secondaryCard(insets: EdgeInsets(top: 24, leading: 24,
                                               bottom: 24, trailing: 24))
    }

    // MARK: Leitzahl-Karte

    private var leitzahlCard: some View {
        let records = app.history.records
        let comparison = StatsCalculator.weekComparison(records, calendar: calendar)
        let typing = StatsCalculator.timeSavedText(
            StatsCalculator.typingTimeThisWeek(records, calendar: calendar))

        return HStack(alignment: .bottom, spacing: 30) {
            VStack(alignment: .leading, spacing: 6) {
                Text(StatsCalculator.compactCount(comparison.thisWeek))
                    .font(Theme.Typo.leitzahl())
                    .monospacedDigit()
                    .tracking(-1.3)
                    .foregroundColor(Theme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("Wörter diese Woche\(deltaSuffix(comparison.deltaPercent)).")
                    .font(Theme.Typo.input())
                    .foregroundColor(Theme.Palette.text2)
                Text("Getippt hättest du dafür etwa \(typing) gebraucht.")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.Palette.text3)
            }
            Spacer()
            sideValue(value: wpmText,
                      label: "WÖRTER / MINUTE")
            sideValue(value: "\(StatsCalculator.currentStreak(records, calendar: calendar))",
                      label: "SERIE · TAGE")
        }
        .card(insets: EdgeInsets(top: 22, leading: 24, bottom: 22, trailing: 24))
    }

    private func deltaSuffix(_ delta: Double?) -> String {
        guard let delta else { return "" }
        let rounded = Int(delta.rounded())
        if rounded == 0 { return " – wie letzte Woche" }
        let sign = rounded > 0 ? "+" : ""
        return sign == "+" ? " — \(sign)\(rounded) % mehr als letzte Woche"
                           : " — \(abs(rounded)) % weniger als letzte Woche"
    }

    private func sideValue(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(value)
                .font(Theme.Typo.nebenZahl())
                .monospacedDigit()
                .foregroundColor(Theme.Palette.ink)
            Text(label)
                .kicker(Theme.Palette.text3, tracking: 1)
        }
    }

    private var wpmText: String {
        guard let wpm = StatsCalculator.wordsPerMinute(app.history.records) else { return "—" }
        return "\(Int(wpm.rounded()))"
    }

    // MARK: Wohin diktiert wird (ein Rotton, abgestuft)

    private var appUsageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wohin diktiert wird")
                .font(Theme.Typo.kartentitel())
                .foregroundColor(Theme.Palette.ink)

            let usage = StatsCalculator.appUsage(app.history.records)
            if usage.isEmpty {
                Text("Noch keine Daten.")
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.text2)
            } else {
                ForEach(Array(usage.enumerated()), id: \.element.app) { index, share in
                    HStack(spacing: 10) {
                        Text(share.app)
                            .font(Theme.Typo.secondary(size: 12))
                            .foregroundColor(Theme.Palette.text2)
                            .frame(width: 74, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Theme.Palette.linieInnen)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.Palette.stempelrot.opacity(Theme.appBarOpacity(rank: index)))
                                    .frame(width: max(4, geo.size.width * share.percent / 100))
                            }
                        }
                        .frame(height: 8)
                        Text("\(Int(share.percent.rounded())) %")
                            .font(Theme.Typo.counter(10.5))
                            .monospacedDigit()
                            .foregroundColor(Theme.Palette.text3)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .secondaryCard(padding: 20)
    }

    // MARK: Serie + Heatmap

    private var streakCard: some View {
        let records = app.history.records
        let streak = StatsCalculator.currentStreak(records, calendar: calendar)
        let record = StatsCalculator.longestStreak(records, calendar: calendar)
        let heat = StatsCalculator.heatmapWords(records, calendar: calendar)
        let maxDay = heat.flatMap { $0 }.max() ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text("\(streak) Tage Serie")
                    .font(Theme.Typo.kartentitel())
                    .foregroundColor(Theme.Palette.ink)
                Spacer()
                stampBadge("REKORD · \(record) TAGE")
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 3.5), count: 16)
            LazyVGrid(columns: columns, spacing: 3.5) {
                ForEach(0..<112, id: \.self) { i in
                    let day = i / 16
                    let week = i % 16
                    let words = heat[day][week]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Palette.stempelrot.opacity(
                            Theme.heatmapOpacity(words: words, maxDay: maxDay)))
                        .aspectRatio(1, contentMode: .fit)
                }
            }

            Text(streakNote(streak: streak))
                .font(Theme.Typo.note())
                .foregroundColor(Theme.Palette.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .secondaryCard(padding: 20)
    }

    /// Schräger Akten-Stempel: roter Rand, −2° gedreht.
    private func stampBadge(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.counter(9.5))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundColor(Theme.Palette.stempelrot)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.Palette.stempelrot, lineWidth: 1.5)
            )
            .rotationEffect(.degrees(-2))
    }

    private func streakNote(streak: Int) -> String {
        settings.ironyOn
            ? "\(streak) Tage ohne eine einzige Lücke. Vorbildliche Aktenführung."
            : "\(streak) Tage in Folge diktiert."
    }
}
