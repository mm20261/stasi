import SwiftUI

// MARK: - Insights (v2)
// 3 große Stat-Karten, „Wohin diktiert wird"-Balken, Streak-Heatmap (16 Wochen × 7 Tage).

struct InsightsView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Insights")
                    .font(Theme.Typo.h1())
                    .tracking(-0.3)
                    .foregroundColor(Theme.Palette.ink)
                Text(subtitle)
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.Palette.sub)
                    .padding(.top, 5)

                bigStatsRow
                    .padding(.top, 22)

                HStack(alignment: .top, spacing: 14) {
                    appUsageCard
                        .frame(maxWidth: .infinity)
                    heatmapCard
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 80)
        }
    }

    private var subtitle: String {
        settings.ironyOn
            ? "Der Überwachungsbericht. Lückenlos, versteht sich."
            : "Deine Diktier-Statistik."
    }

    // MARK: Große Stat-Karten

    private var bigStatsRow: some View {
        HStack(spacing: 14) {
            bigStatCard(value: weekWordsValue,
                        label: "WÖRTER / WOCHE",
                        delta: weekDeltaText)
            bigStatCard(value: wpmValue,
                        label: "WÖRTER / MINUTE",
                        delta: wpmFactorText)
            bigStatCard(value: timeSavedValue,
                        label: "ZEIT GESPART",
                        delta: "diese Woche")
        }
    }

    private func bigStatCard(value: String, label: String, delta: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.Typo.bigStat())
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundColor(Theme.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .kicker(Theme.Palette.sub)
                .padding(.top, 7)
            Text(delta)
                .font(.custom("Geist", size: 11.5))
                .foregroundColor(Theme.accent)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
        .liftOnHover()
    }

    private var weekWordsValue: String {
        StatsCalculator.compactCount(
            StatsCalculator.weekComparison(app.history.records, calendar: calendar).thisWeek
        )
    }

    private var weekDeltaText: String {
        let cmp = StatsCalculator.weekComparison(app.history.records, calendar: calendar)
        guard let delta = cmp.deltaPercent else { return "keine Vorwoche" }
        let sign = delta >= 0 ? "+" : ""
        let kw = calendar.component(.weekOfYear,
                                    from: calendar.date(byAdding: .weekOfYear, value: -1, to: Date())!)
        return "\(sign)\(Int(delta.rounded())) % ggü. KW \(kw)"
    }

    private var wpmValue: String {
        guard let wpm = StatsCalculator.wordsPerMinute(app.history.records) else { return "—" }
        return "\(Int(wpm.rounded()))"
    }

    private var wpmFactorText: String {
        guard let wpm = StatsCalculator.wordsPerMinute(app.history.records), wpm > 0 else {
            return "noch keine Daten"
        }
        let factor = wpm / 40
        let text = String(format: "%.1f", factor).replacingOccurrences(of: ".", with: ",")
        return "\(text)× schneller als Tippen"
    }

    private var timeSavedValue: String {
        StatsCalculator.timeSavedText(StatsCalculator.timeSaved(app.history.records))
    }

    // MARK: Wohin diktiert wird

    private var appUsageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wohin diktiert wird")
                .font(.custom("Geist", size: 14).weight(.semibold))
                .foregroundColor(Theme.Palette.ink)

            let usage = StatsCalculator.appUsage(app.history.records)
            if usage.isEmpty {
                Text("Noch keine Daten.")
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.sub)
                    .padding(.top, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(usage, id: \.app) { share in
                        appUsageRow(share)
                    }
                }
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    private func appUsageRow(_ share: StatsCalculator.AppUsageShare) -> some View {
        HStack(spacing: 10) {
            Text(share.app)
                .font(.custom("Geist", size: 12))
                .foregroundColor(Theme.Palette.sub)
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.hover)
                    Capsule().fill(Theme.accent)
                        .frame(width: geo.size.width * share.percent / 100)
                }
            }
            .frame(height: 8)
            Text("\(Int(share.percent.rounded())) %")
                .font(Theme.Typo.counter(10.5))
                .foregroundColor(Theme.Palette.sub)
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: Streak-Heatmap

    private var heatmapCard: some View {
        let streak = StatsCalculator.currentStreak(app.history.records, calendar: calendar)
        let record = StatsCalculator.longestStreak(app.history.records, calendar: calendar)
        let heat = StatsCalculator.heatmapWords(app.history.records, calendar: calendar)
        let maxDay = heat.flatMap { $0 }.max() ?? 0

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(streak) Tage Serie")
                    .font(.custom("Geist", size: 14).weight(.semibold))
                    .foregroundColor(Theme.Palette.ink)
                Spacer()
                Text("REKORD · \(record) TAGE")
                    .kicker(Theme.Palette.sub)
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 16)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<112, id: \.self) { i in
                    let day = i / 16
                    let week = i % 16
                    let words = heat[day][week]
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Theme.accent)
                        .opacity(cellOpacity(words: words, maxDay: maxDay))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.top, 16)

            Text(streakNote(streak: streak))
                .font(.custom("Geist", size: 11))
                .foregroundColor(Theme.Palette.sub)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    private func cellOpacity(words: Int, maxDay: Int) -> Double {
        guard words > 0 else { return 0.08 }
        let ratio = Double(words) / Double(max(maxDay, 1))
        return 0.18 + 0.82 * ratio
    }

    private func streakNote(streak: Int) -> String {
        settings.ironyOn
            ? "\(streak) Tage ohne eine einzige Lücke. Vorbildliche Aktenführung."
            : "\(streak) Tage in Folge diktiert."
    }
}
