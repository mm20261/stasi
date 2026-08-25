import Foundation

// MARK: - ProtocolSearch (v4 „Registratur")
// Volltextsuche über alle Protokolle (correctedText, rawText, Ziel-App),
// Datumsfilter (Alle / 7 Tage / 30 Tage), Trefferzähler, Tagesgruppierung.
// Bewusst reine Logik ohne UI – deterministisch testbar.

enum ProtocolSearchFilter: String, CaseIterable, Identifiable {
    case all
    case last7Days
    case last30Days

    var id: String { rawValue }

    /// Chip-Label (mono, UPPERCASE im UI)
    var label: String {
        switch self {
        case .all: "ALLE"
        case .last7Days: "7 TAGE"
        case .last30Days: "30 TAGE"
        }
    }

    /// Tage zurück; nil = unbegrenzt.
    var days: Int? {
        switch self {
        case .all: nil
        case .last7Days: 7
        case .last30Days: 30
        }
    }
}

enum ProtocolSearch {

    /// Volltext-Treffer: Groß-/Kleinschreibung egal, durchsucht korrigierten
    /// Text, Rohtext und die Ziel-App.
    static func matches(_ record: TranscriptionRecord, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.lowercased()
        return record.correctedText.lowercased().contains(needle)
            || record.rawText.lowercased().contains(needle)
            || record.targetApp.lowercased().contains(needle)
    }

    /// Kombinierter Filter (Query ∩ Zeitraum), Reihenfolge bleibt erhalten.
    static func filter(_ records: [TranscriptionRecord],
                       query: String,
                       filter: ProtocolSearchFilter,
                       calendar: Calendar = .current,
                       now: Date = Date()) -> [TranscriptionRecord] {
        var result = records.filter { matches($0, query: query) }
        if let days = filter.days {
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            result = result.filter { $0.date >= cutoff }
        }
        _ = calendar
        return result
    }

    /// Trefferzähler für die Suchzeile („7 TREFFER").
    static func hitCount(in records: [TranscriptionRecord]) -> Int {
        records.count
    }

    // MARK: Tagesgruppierung (Protokolle-Ansicht)

    struct DayGroup {
        let day: Date          // Start des Tages
        let records: [TranscriptionRecord] // älteste zuerst innerhalb des Tags
    }

    /// Gruppiert nach Kalendertag, Tage absteigend, Einträge innerhalb eines
    /// Tages aufsteigend (chronologisch wie eine Registratur).
    static func groupByDay(_ records: [TranscriptionRecord],
                           calendar: Calendar = .current) -> [DayGroup] {
        let ascending = records.sorted { $0.date < $1.date }
        var order: [Date] = []
        var byDay: [Date: [TranscriptionRecord]] = [:]
        for record in ascending {
            let day = calendar.startOfDay(for: record.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(record)
        }
        return order.reversed().map { DayGroup(day: $0, records: byDay[$0]!) }
    }
}

// MARK: - Aktenzeichen

/// Stabiles Pseudo-Aktenzeichen aus der Record-ID (4 Hex-Zeichen) –
/// überlebt Sortierung/Löschungen und sieht registraturecht aus.
enum FileNumber {
    static func forRecord(id: UUID) -> String {
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "")
            .prefix(4).uppercased()
        return "AZ \(hex)"
    }
}

// MARK: - Sammelexport

enum ProtocolExporter {
    /// Alle Protokolle als Markdown, nach Tag gruppiert, innerhalb des Tages
    /// chronologisch. Format pro Eintrag wie beim Einzel-Export.
    static func markdownAll(_ records: [TranscriptionRecord],
                            calendar: Calendar = .current,
                            exportedAt: Date = Date()) -> String {
        var lines: [String] = []
        lines.append("# Protokolle")
        lines.append("")
        lines.append("Exportiert am \(exportedAt.formatted(.dateTime.day().month().year().hour().minute())) · \(records.count) Protokolle")
        lines.append("")
        for group in ProtocolSearch.groupByDay(records, calendar: calendar) {
            lines.append("## \(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
            lines.append("")
            for record in group.records {
                let time = record.date.formatted(.dateTime.hour().minute().second())
                var meta: [String] = []
                if !record.targetApp.isEmpty { meta.append("→ \(record.targetApp)") }
                if record.durationSecs > 0 {
                    meta.append(String(format: "%.0f:%02d",
                                       record.durationSecs / 60,
                                       Int(record.durationSecs) % 60))
                }
                meta.append("\(record.wordCount) Wörter")
                meta.append(FileNumber.forRecord(id: record.id))
                lines.append("### \(time) · \(meta.joined(separator: " · "))")
                lines.append("")
                lines.append(record.correctedText)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
