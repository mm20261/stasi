import Foundation

// MARK: - StatsCalculator
// Reine Statistik-Logik für Insights-Screen + Dashboard-Rail (v2-Design).
// Bewusst ohne UI-Abhängigkeiten und mit injizierbarem Kalender/Heute-Datum,
// damit alles deterministisch testbar ist.

enum StatsCalculator {

    /// Wörter gesamt über alle Protokolle.
    static func totalWords(_ records: [TranscriptionRecord]) -> Int {
        records.reduce(0) { $0 + $1.wordCount }
    }

    /// Wörter pro Minute über alle Protokolle mit Dauer; nil, wenn keine
    /// Dauer erfasst ist.
    static func wordsPerMinute(_ records: [TranscriptionRecord]) -> Double? {
        var words = 0
        var seconds: TimeInterval = 0
        for r in records where r.durationSecs > 0 {
            words += r.wordCount
            seconds += r.durationSecs
        }
        guard seconds > 0 else { return nil }
        return Double(words) / (seconds / 60)
    }

    /// Laufende Serie: aufeinanderfolgende Tage mit ≥ 1 Protokoll, endend
    /// heute – oder yesterday, falls heute noch nichts diktiert wurde.
    static func currentStreak(_ records: [TranscriptionRecord],
                              calendar: Calendar = .current,
                              today: Date = Date()) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        guard days.contains(cursor) else { return 0 }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    /// Längste Serie überhaupt.
    static func longestStreak(_ records: [TranscriptionRecord],
                              calendar: Calendar = .current) -> Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for i in 1..<days.count {
            let gap = calendar.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 99
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    struct AppUsageShare: Equatable {
        let app: String
        let words: Int
        /// Anteil 0…100
        let percent: Double
    }

    /// Wortanteile je Ziel-App, sortiert absteigend; Rest jenseits von `topN`
    /// landet gebündelt in „Andere“. Einträge ohne Ziel-App werden ignoriert.
    static func appUsage(_ records: [TranscriptionRecord],
                         topN: Int = 4) -> [AppUsageShare] {
        var byApp: [String: Int] = [:]
        for r in records where !r.targetApp.isEmpty {
            byApp[r.targetApp, default: 0] += r.wordCount
        }
        guard !byApp.isEmpty else { return [] }
        let total = byApp.values.reduce(0, +)
        guard total > 0 else { return [] }
        let sorted = byApp.sorted { $0.value > $1.value }
        var result: [AppUsageShare] = []
        var restWords = 0
        for (index, entry) in sorted.enumerated() {
            if index < topN {
                result.append(AppUsageShare(app: entry.key, words: entry.value,
                                            percent: Double(entry.value) / Double(total) * 100))
            } else {
                restWords += entry.value
            }
        }
        if restWords > 0 {
            result.append(AppUsageShare(app: "Andere", words: restWords,
                                        percent: Double(restWords) / Double(total) * 100))
        }
        return result
    }

    /// Geschätzte gesparte Zeit: Tippen mit 40 WPM als Referenz. Negative
    /// Differenzen (langsamere Aufnahme) zählen 0.
    static func timeSaved(_ records: [TranscriptionRecord],
                          typingWPM: Double = 40) -> TimeInterval {
        var saved: TimeInterval = 0
        for r in records {
            let typingTime = Double(r.wordCount) / typingWPM * 60
            saved += max(0, typingTime - r.durationSecs)
        }
        return saved
    }

    /// „2:14 Std“ / „42 Min“ / „0 Min“
    static func timeSavedText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval.rounded(.down)) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h):\(String(format: "%02d", m)) Std" : "\(m) Min"
    }

    /// Wochenvergleich: diese Woche vs. Vorwoche (Wörter). Delta in Prozent
    /// relativ zur Vorwoche, nil wenn die Vorwoche leer war.
    static func weekComparison(_ records: [TranscriptionRecord],
                               calendar: Calendar = .current,
                               today: Date = Date()) -> (thisWeek: Int,
                                                         lastWeek: Int,
                                                         deltaPercent: Double?) {
        func words(inWeekOf date: Date) -> Int {
            records.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .weekOfYear) }
                .reduce(0) { $0 + $1.wordCount }
        }
        let thisWeek = words(inWeekOf: today)
        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: today)!
        let lastWeek = words(inWeekOf: lastWeekDate)
        let delta: Double? = lastWeek > 0 ? Double(thisWeek - lastWeek) / Double(lastWeek) * 100 : nil
        return (thisWeek, lastWeek, delta)
    }

    /// Heatmap-Daten: 7 Zeilen (Montag…Sonntag) × `weeks` Spalten, älteste
    /// Woche links. Wert = Wörter des Tages.
    static func heatmapWords(_ records: [TranscriptionRecord],
                             weeks: Int = 16,
                             calendar: Calendar = .current,
                             today: Date = Date()) -> [[Int]] {
        let perDay: [Date: Int] = records.reduce(into: [:]) { acc, r in
            let day = calendar.startOfDay(for: r.date)
            acc[day, default: 0] += r.wordCount
        }
        // Montag der aktuellen Woche: weekday 1=So…7=Sa, Montag=2 → offset 0.
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (todayWeekday + 5) % 7
        let thisMonday = calendar.date(byAdding: .day, value: -daysSinceMonday,
                                       to: calendar.startOfDay(for: today))!
        let firstMonday = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisMonday)!

        var grid: [[Int]] = []
        for dayIndex in 0..<7 {
            var row: [Int] = []
            for week in 0..<weeks {
                let day = calendar.date(byAdding: .day,
                                        value: week * 7 + dayIndex, to: firstMonday)!
                row.append(perDay[calendar.startOfDay(for: day)] ?? 0)
            }
            grid.append(row)
        }
        return grid
    }

    /// Kompakte Zahlen im deutschen Format: 980 → „980“, 328500 → „328,5K“,
    /// 1240000 → „1,2M“.
    static func compactCount(_ n: Int) -> String {
        func formatted(_ value: Double, suffix: String) -> String {
            let rounded = (value * 10).rounded() / 10
            if rounded >= 1000 { return "\(Int(rounded.rounded()))\(suffix)" }
            if rounded.rounded() == rounded { return "\(Int(rounded))\(suffix)" }
            return String(format: "%.1f%@", rounded, suffix)
                .replacingOccurrences(of: ".", with: ",")
        }
        switch abs(n) {
        case ..<1000:
            return "\(n)"
        case ..<1_000_000:
            return formatted(Double(n) / 1000, suffix: "K")
        default:
            return formatted(Double(n) / 1_000_000, suffix: "M")
        }
    }

    // MARK: v4 „Registratur"

    /// KW-Kicker über der Insights-Leitzahl:
    /// „KALENDERWOCHE 35 · 24.–30. AUGUST“ (Monatswechsel: „… SEPTEMBER – 2. OKTOBER“).
    static func weekKickerLabel(for date: Date,
                                calendar: Calendar = .current) -> String {
        let week = calendar.component(.weekOfYear, from: date)
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 6, to: start)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar

        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        let startMonth = formatter.string(from: start).uppercased()
        let endMonth = formatter.string(from: end).uppercased()

        let range: String
        if startMonth == endMonth {
            range = "\(startDay).–\(endDay). \(endMonth)"
        } else {
            range = "\(startDay). \(startMonth) – \(endDay). \(endMonth)"
        }
        return "KALENDERWOCHE \(week) · \(range)"
    }

    /// Reine Tipzeit-Estimate für die Wörter dieser Woche (40 WPM-Referenz):
    /// „Getippt hättest du dafür etwa 2:14 Stunden gebraucht.“
    static func typingTimeThisWeek(_ records: [TranscriptionRecord],
                                   typingWPM: Double = 40,
                                   calendar: Calendar = .current,
                                   today: Date = Date()) -> TimeInterval {
        let words = weekComparison(records, calendar: calendar, today: today).thisWeek
        return Double(words) / typingWPM * 60
    }
}
