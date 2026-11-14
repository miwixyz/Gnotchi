import Foundation

/// „Heute“ / „Gestern“ / Datum als Trenner in der Kartenreihe (0.14.0). Rein, getestet.
enum ClipDays {

    struct Group: Identifiable {
        let id: Date          // Tagesbeginn
        let label: String
        let entries: [ClipEntry]
    }

    /// Einträge sind schon nach `lastUsedAt` absteigend sortiert; die Reihenfolge bleibt erhalten.
    /// `pinnedFirst`: führende angeheftete Einträge (Verlauf, Michael 14.11.) bilden eine eigene Gruppe „Angeheftet“.
    static func group(_ entries: [ClipEntry], pinnedFirst: Bool = false, now: Date = Date(),
                      calendar: Calendar = .current) -> [Group] {
        var groups: [Group] = []
        var rest = entries[...]
        if pinnedFirst {
            let pinned = Array(entries.prefix(while: \.isPinned))
            if !pinned.isEmpty {
                groups.append(Group(id: .distantFuture, label: String(localized: "Angeheftet"), entries: pinned))
                rest = entries.dropFirst(pinned.count)
            }
        }
        var currentDay: Date?
        var bucket: [ClipEntry] = []
        func flush() {
            guard let day = currentDay, !bucket.isEmpty else { return }
            groups.append(Group(id: day, label: label(for: day, now: now, calendar: calendar), entries: bucket))
        }
        for entry in rest {
            let day = calendar.startOfDay(for: entry.lastUsedAt)
            if day != currentDay {
                flush()
                currentDay = day
                bucket = []
            }
            bucket.append(entry)
        }
        flush()
        return groups
    }

    static func label(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Heute") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) { return String(localized: "Gestern") }
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: calendar.locale ?? .current,
                                     calendar: calendar, timeZone: calendar.timeZone)
        return day.formatted(style.weekday(.abbreviated))
    }
}
