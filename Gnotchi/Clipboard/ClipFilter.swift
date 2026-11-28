import Foundation

/// Suchfilter der Zwischenablage (0.49.0): Quell-App und Zeitraum, zusätzlich zum Suchtext. Rein, getestet.
/// Vorbild Paste („Links aus Mail, letzte Woche“). Nutzt nur, was ohnehin im Klartext steht (Quell-App,
/// `lastUsedAt`, G38) – kein Entschlüsseln, kein Netz.
struct ClipFilter: Equatable {

    enum Period: String, CaseIterable, Identifiable {
        case all, today, week, month
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: String(localized: "Jederzeit")
            case .today: String(localized: "Heute")
            case .week: String(localized: "Letzte 7 Tage")
            case .month: String(localized: "Letzte 30 Tage")
            }
        }

        /// Kurzform für die Anzeige neben dem Filterknopf.
        var shortLabel: String {
            switch self {
            case .all: ""
            case .today: String(localized: "Heute")
            case .week: String(localized: "7 Tage")
            case .month: String(localized: "30 Tage")
            }
        }

        /// Frühester Zeitpunkt, der noch dazugehört (Tagesbeginn, heute zählt mit). `nil` = keine Grenze.
        func start(now: Date, calendar: Calendar) -> Date? {
            let today = calendar.startOfDay(for: now)
            switch self {
            case .all: return nil
            case .today: return today
            case .week: return calendar.date(byAdding: .day, value: -6, to: today)
            case .month: return calendar.date(byAdding: .day, value: -29, to: today)
            }
        }
    }

    var period: Period = .all
    /// Nur Einträge aus dieser App. `nil` = alle Apps.
    var sourceBundleID: String?

    var isActive: Bool { period != .all || sourceBundleID != nil }

    /// Wie bei den Tagestrennern zählt `lastUsedAt` (zuletzt kopiert oder benutzt).
    func includes(_ entry: ClipEntry, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let sourceBundleID, entry.sourceBundleID != sourceBundleID { return false }
        if let start = period.start(now: now, calendar: calendar), entry.lastUsedAt < start { return false }
        return true
    }

    /// Quell-Apps der Einträge, häufigste zuerst (bei Gleichstand nach Kennung, damit die Liste nicht springt).
    static func sources(of entries: [ClipEntry]) -> [String] {
        var counts: [String: Int] = [:]
        for case let id? in entries.map(\.sourceBundleID) { counts[id, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}
