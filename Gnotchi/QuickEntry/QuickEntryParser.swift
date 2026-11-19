import Foundation

/// Schnelleingabe in Alltagssprache (specs/2026-11-19-gnotchi-schnelleingabe.md): „Zahnarzt morgen 15 Uhr“ →
/// Termin morgen 15:00 mit Titel „Zahnarzt“. Rein (ohne EventKit, ohne Oberfläche) und getestet; gespeichert wird
/// in Kalli (G61). Nur Deutsch.
///
/// Gemessen 19.11.: `NSDataDetector` allein lag bei 3 von 20 Sätzen still daneben („7:15“ → 19:15), deshalb eigene
/// Regeln. Grundsätze (Michael, Fragen 3–6):
/// - mit Uhrzeit → Termin, sonst Erinnerung; „erinnere mich“, „nicht vergessen“, „bis <Datum>“ → immer Erinnerung
/// - Uhrzeiten **wörtlich** im 24-h-Format („7 Uhr“ = 07:00, „halb drei“ = 02:30); „nachmittags/abends“ verschieben
/// - immer in die Zukunft: Wochentag = heute → heute, wenn die Uhrzeit noch kommt; Uhrzeit ohne Datum vorbei → morgen
/// - Zeitangaben und Füllwörter am Rand fallen aus dem Titel, der Rest bleibt wörtlich
/// - Zweifel (zwei Daten, Uhrzeit zwischen 0 und 6 Uhr) → `needsCheck`, die Vorschau markiert gelb
enum QuickEntryParser {

    enum Kind: String, Equatable, Sendable { case event, reminder }

    struct Entry: Equatable, Sendable {
        var kind: Kind
        var title: String
        /// Termin: Beginn. Erinnerung: Fälligkeit (`nil` = ohne Datum). Ganztägig: Tagesbeginn.
        var start: Date?
        /// Nur Termine mit Uhrzeit.
        var end: Date?
        var allDay: Bool
        var urgent: Bool
        var needsCheck: Bool
    }

    /// Dauer eines Termins ohne Angabe (Michael, Frage 4).
    nonisolated static let defaultDuration: TimeInterval = 3600
    nonisolated static let maxDuration: TimeInterval = 24 * 3600

    // MARK: Einstieg

    nonisolated static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Entry {
        var scan = Scan(text: text)
        let today = calendar.startOfDay(for: now)

        // Reihenfolge zählt: Spezielles vor Allgemeinem, jeder Treffer wird im Arbeitstext ausgeblendet.
        scan.urgent = scan.take(#"\s*!+\s*$"#) != nil
        if scan.take(#"\berinnere\s+mich(?:\s+daran)?\b,?"#) != nil { scan.forceReminder = true }
        if scan.take(#"\bnicht\s+vergessen\b:?"#) != nil { scan.forceReminder = true }

        // „bis 17 Uhr“ (Ende), „bis 30.11.“ (Frist → Erinnerung).
        if let m = scan.take(#"\bbis\s+(\d{1,2})(?::(\d{2}))?(?![\d.])(?:\s*uhr\b)?"#),
           let t = clock(m.int(1), m.int(2) ?? 0) { scan.endTime = t }
        if scan.take(#"\bbis\b(?=\s+(?:\d{1,2}\.\d{1,2}\.|\d{1,2}\.\s*[a-zä]|heute|morgen|übermorgen|ende|"#
                     + #"(?:nächste[nmr]?\s+|kommende[nmr]?\s+)?"# + weekdayAlternation + #"))"#) != nil {
            scan.forceReminder = true
        }

        relative(&scan, now: now, today: today, calendar: calendar)
        duration(&scan)
        dates(&scan, now: now, today: today, calendar: calendar)
        times(&scan)
        dayParts(&scan)

        return assemble(scan, now: now, today: today, calendar: calendar)
    }

    /// Tab in der Vorschau: Termin ↔ Erinnerung.
    nonisolated static func toggled(_ e: Entry, now: Date = Date(), calendar: Calendar = .current) -> Entry {
        var out = e
        switch e.kind {
        case .event:
            out.kind = .reminder
            out.end = nil
        case .reminder:
            out.kind = .event
            if out.start == nil {
                out.start = calendar.startOfDay(for: now)
                out.allDay = true
            }
            if !out.allDay, let s = out.start { out.end = s.addingTimeInterval(defaultDuration) }
        }
        return out
    }

    // MARK: Relative Angaben

    private nonisolated static func relative(_ scan: inout Scan, now: Date, today: Date, calendar: Calendar) {
        if scan.take(#"\bin\s+einer\s+halben\s+stunde\b"#) != nil {
            scan.absolute = now.addingTimeInterval(1800)
            return
        }
        guard let m = scan.take(#"\bin\s+(\d{1,3}|"# + numberAlternation
                                + #")\s+(minuten?|min\.?|stunden?|std\.?|tag(?:en)?|wochen?)\b"#),
              let n = number(m.string(1)) else { return }
        let unit = (m.string(2) ?? "").lowercased()
        if unit.hasPrefix("min") {
            scan.absolute = now.addingTimeInterval(Double(n) * 60)
        } else if unit.hasPrefix("st") {
            scan.absolute = now.addingTimeInterval(Double(n) * 3600)
        } else if unit.hasPrefix("tag") {
            scan.setDay(calendar.date(byAdding: .day, value: n, to: today))
        } else {
            scan.setDay(calendar.date(byAdding: .day, value: 7 * n, to: today))
        }
    }

    /// „2 Std“, „30 Min“, „1,5 Stunden“ (ohne „in“ davor – das ist oben schon weg).
    private nonisolated static func duration(_ scan: inout Scan) {
        guard let m = scan.take(#"\b(?:für\s+)?(\d{1,2}(?:,\d)?|"# + numberAlternation
                                + #")\s*(stunden?|std\.?|h|minuten|min\.?)(?![\wäöü])"#) else { return }
        let raw = (m.string(1) ?? "").replacingOccurrences(of: ",", with: ".")
        guard let n = Double(raw) ?? number(raw).map(Double.init) else { return }
        let unit = (m.string(2) ?? "").lowercased()
        scan.duration = unit.hasPrefix("m") ? n * 60 : n * 3600
    }

    // MARK: Datum

    private nonisolated static func dates(_ scan: inout Scan, now: Date, today: Date, calendar: Calendar) {
        let prefix = #"(?:(?:am|ab|zum|bis)\s+)?"#
        // 12.01.2027 · 3.12. · 3.12.27
        while let m = scan.take(prefix + #"\b(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})?(?!\d)"#) {
            scan.setDay(explicitDate(day: m.int(1), month: m.int(2), year: m.int(3), today: today, calendar: calendar))
        }
        // 3. Dezember 2026 · 3. Dez
        while let m = scan.take(prefix + #"\b(\d{1,2})\.\s*("# + monthAlternation + #")\.?(?:\s+(\d{4}))?(?![\wäöü])"#) {
            scan.setDay(explicitDate(day: m.int(1), month: month(m.string(2)), year: m.int(3), today: today,
                                     calendar: calendar))
        }
        if let m = scan.take(prefix + #"\b(übermorgen|morgen|heute)\b"#) {
            let offset = ["heute": 0, "morgen": 1, "übermorgen": 2][(m.string(1) ?? "").lowercased()] ?? 0
            scan.setDay(calendar.date(byAdding: .day, value: offset, to: today))
        }
        // „nächste Woche Mittwoch“ → Mittwoch der nächsten Kalenderwoche; „nächste Woche“ allein → deren Montag.
        if let m = scan.take(#"\b(?:nächste|kommende)\s+woche(?:\s+(?:am\s+)?("# + weekdayAlternation + #"))?\b"#) {
            let monday = startOfNextWeek(today, calendar: calendar)
            let target = weekday(m.string(1)) ?? 2
            scan.setDay(calendar.date(byAdding: .day, value: (target - 2 + 7) % 7, to: monday))
        }
        // „nächsten Montag“ → der kommende Montag, nie heute.
        if let m = scan.take(#"\b(?:(?:am\s+)?nächste[nmr]?|kommende[nmr]?)\s+("# + weekdayAlternation + #")\b"#),
           let w = weekday(m.string(1)) {
            let ahead = (w - calendar.component(.weekday, from: today) + 7) % 7
            scan.setDay(calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: today))
        }
        // „Freitag“, „am Sonntag“ · Kurzformen nur groß und mit Punkt oder Zahl dahinter („Do 15 Uhr“), sonst
        // würde „so“ im Satz zum Sonntag.
        let plain = scan.take(#"(?:\bam\s+)?\b("# + weekdayAlternation + #")\b"#)
            ?? scan.take(#"(?:\bam\s+)?\b(Mo|Di|Mi|Do|Fr|Sa|So)(?:\.|(?=\s+\d))"#, caseInsensitive: false)
        if let m = plain, let w = weekday(m.string(1)) {
            let ahead = (w - calendar.component(.weekday, from: today) + 7) % 7
            scan.setDay(calendar.date(byAdding: .day, value: ahead, to: today))
            scan.weekdayIsToday = ahead == 0
        }
        if scan.take(#"(?:\bam\s+|\bübers\s+)?\bwochenende\b"#) != nil {
            let w = calendar.component(.weekday, from: today)   // 1 = So, 7 = Sa
            let ahead = w == 1 ? 0 : 7 - w
            scan.setDay(calendar.date(byAdding: .day, value: ahead, to: today))
        }
    }

    /// Ohne Jahr: dieses Jahr, liegt der Tag schon zurück → nächstes. Zweistellig → 20xx. Ungültig → nil.
    private nonisolated static func explicitDate(day: Int?, month: Int?, year: Int?, today: Date,
                                                 calendar: Calendar) -> Date? {
        guard let day, let month, (1...31).contains(day), (1...12).contains(month) else { return nil }
        let current = calendar.component(.year, from: today)
        var y = year.map { $0 < 100 ? 2000 + $0 : $0 } ?? current
        func make(_ y: Int) -> Date? {
            let c = DateComponents(year: y, month: month, day: day)
            guard let d = calendar.date(from: c), calendar.component(.day, from: d) == day else { return nil }   // 31.11.
            return d
        }
        guard var date = make(y) else { return nil }
        if year == nil, date < today {
            y += 1
            guard let next = make(y) else { return nil }
            date = next
        }
        return date
    }

    private nonisolated static func startOfNextWeek(_ today: Date, calendar: Calendar) -> Date {
        let w = calendar.component(.weekday, from: today)   // Mo = 2
        let toMonday = (2 - w + 7) % 7
        return calendar.date(byAdding: .day, value: toMonday == 0 ? 7 : toMonday, to: today) ?? today
    }

    // MARK: Uhrzeit

    private nonisolated static func times(_ scan: inout Scan) {
        let um = #"(?:\bum\s+|\bab\s+|\bgegen\s+)?"#
        if let m = scan.take(um + #"\b(\d{1,2}):(\d{2})(?:\s*uhr\b)?"#) {
            scan.setTime(clock(m.int(1), m.int(2)))
        } else if let m = scan.take(um + #"\bhalb\s+(\d{1,2}|"# + clockAlternation + #")\b"#),
                  let h = number(m.string(1)) {
            scan.setTime(clock((h + 23) % 24, 30))
        } else if let m = scan.take(um + #"\bviertel\s+(nach|vor)\s+(\d{1,2}|"# + clockAlternation + #")\b"#),
                  let h = number(m.string(2)) {
            scan.setTime(m.string(1)?.lowercased() == "nach" ? clock(h, 15) : clock((h + 23) % 24, 45))
        } else if let m = scan.take(um + #"\b(\d{1,2}|"# + clockAlternation + #")\s*uhr\b"#),
                  let h = number(m.string(1)) {
            scan.setTime(clock(h, 0))
        } else if let m = scan.take(#"\b(?:um|gegen)\s+(\d{1,2})(?![\d.:])"#) {
            scan.setTime(clock(m.int(1), 0))
        }
    }

    private nonisolated static func dayParts(_ scan: inout Scan) {
        let pattern = #"(?:\bam\s+|\bin\s+der\s+)?\b(morgens|früh|vormittags|vormittag|mittags|nachmittags|nachmittag|"#
            + #"abends|abend|nachts|nacht)\b"#
        guard let m = scan.take(pattern), let word = m.string(1)?.lowercased() else { return }
        switch word {
        case "nachmittags", "nachmittag", "abends", "abend": scan.dayPart = .afternoon
        case "mittags": scan.dayPart = .noon
        case "nachts", "nacht": scan.dayPart = .night
        default: scan.dayPart = .morning
        }
    }

    nonisolated static func clock(_ h: Int?, _ m: Int?) -> QuickEntryClock? {
        guard let h, let m, (0...23).contains(h), (0...59).contains(m) else { return nil }
        return QuickEntryClock(hour: h, minute: m)
    }

    // MARK: Zusammenbauen

    private nonisolated static func assemble(_ scan: Scan, now: Date, today: Date, calendar: Calendar) -> Entry {
        let time = scan.time.map { applying(scan.dayPart, to: $0) }
        if scan.absolute == nil || scan.day != nil, time == nil, let deadline = scan.endTime {
            // „bis 17 Uhr“ ohne Beginn: Frist mit Uhrzeit → Erinnerung.
            let start = at(scan.day ?? today, deadline, calendar: calendar)
            var entry = finish(scan, kind: .reminder, start: start, end: nil, allDay: false)
            entry.needsCheck = entry.needsCheck || isDoubtful(start, hour: deadline.hour, scan: scan, now: now)
            return entry
        }
        var start: Date?
        if let absolute = scan.absolute, scan.day == nil {
            start = absolute
        } else if let t = time {
            start = future(at(scan.day ?? today, t, calendar: calendar), scan: scan, now: now, calendar: calendar)
        }
        let hasTime = start != nil
        if !hasTime { start = scan.day }
        let kind: Kind = scan.forceReminder || !hasTime ? .reminder : .event
        let end = kind == .event ? start.map { eventEnd($0, scan: scan, calendar: calendar) } : nil
        var entry = finish(scan, kind: kind, start: start, end: end?.date, allDay: start != nil && !hasTime)
        if end?.wanted == false { entry.needsCheck = true }   // „16 Uhr bis 15 Uhr“
        if hasTime, isDoubtful(start, hour: scan.absolute == nil ? time?.hour : nil, scan: scan, now: now) {
            entry.needsCheck = true
        }
        return entry
    }

    /// „nachmittags/abends“ +12, „mittags“ für 1–5 Uhr +12, sonst wörtlich.
    private nonisolated static func applying(_ part: QuickEntryDayPart?, to t: QuickEntryClock) -> QuickEntryClock {
        switch part {
        case .afternoon? where t.hour < 12, .noon? where t.hour < 6: QuickEntryClock(hour: t.hour + 12, minute: t.minute)
        default: t
        }
    }

    /// Immer in die Zukunft: Uhrzeit heute vorbei → morgen (ohne Datum) bzw. nächste Woche (Wochentag = heute).
    private nonisolated static func future(_ s: Date?, scan: Scan, now: Date, calendar: Calendar) -> Date? {
        guard let s, s <= now else { return s }
        if scan.day == nil { return calendar.date(byAdding: .day, value: 1, to: s) }
        if scan.weekdayIsToday { return calendar.date(byAdding: .day, value: 7, to: s) }
        return s
    }

    /// Ende eines Termins: „bis 17:15“, sonst Dauer, sonst 1 h. `wanted == false`: angegebenes Ende passte nicht.
    private nonisolated static func eventEnd(_ s: Date, scan: Scan, calendar: Calendar) -> (date: Date, wanted: Bool?) {
        let wanted = scan.endTime.flatMap { at(calendar.startOfDay(for: s), $0, calendar: calendar) }
        if let e = wanted, e > s, e.timeIntervalSince(s) <= maxDuration { return (e, true) }
        let length = min(max(scan.duration ?? defaultDuration, 60), maxDuration)
        return (s.addingTimeInterval(length), wanted == nil ? nil : false)
    }

    /// Zweifel: Uhrzeit zwischen 0 und 6 Uhr ohne Tageszeit-Wort, oder Zeitpunkt schon vorbei.
    private nonisolated static func isDoubtful(_ start: Date?, hour: Int?, scan: Scan, now: Date) -> Bool {
        if let h = hour, h < 6, scan.dayPart == nil { return true }
        if let s = start, s <= now { return true }
        return false
    }

    private nonisolated static func finish(_ scan: Scan, kind: Kind, start: Date?, end: Date?, allDay: Bool) -> Entry {
        Entry(kind: kind, title: scan.title(), start: start, end: end, allDay: allDay, urgent: scan.urgent,
              needsCheck: scan.extraDates > 0)
    }

    private nonisolated static func at(_ day: Date, _ t: QuickEntryClock, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day)
    }

    // MARK: Wörter

    nonisolated static let weekdays: [String: Int] = [
        "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5, "freitag": 6, "samstag": 7,
        "sonnabend": 7, "so": 1, "mo": 2, "di": 3, "mi": 4, "do": 5, "fr": 6, "sa": 7,
    ]
    private nonisolated static let weekdayAlternation =
        "montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag"

    nonisolated static func weekday(_ s: String?) -> Int? { s.flatMap { weekdays[$0.lowercased()] } }

    nonisolated static let numbers: [String: Int] = [
        "ein": 1, "eine": 1, "einer": 1, "eins": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6,
        "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12,
    ]
    private nonisolated static let numberAlternation =
        "zwölf|elf|zehn|neun|acht|sieben|sechs|fünf|vier|drei|zwei|eins|einer|eine|ein"
    /// Für Uhrzeiten ohne „ein/eine“ („eine Uhr kaufen“ ist keine Uhrzeit).
    private nonisolated static let clockAlternation = "zwölf|elf|zehn|neun|acht|sieben|sechs|fünf|vier|drei|zwei|eins"

    nonisolated static func number(_ s: String?) -> Int? {
        guard let s else { return nil }
        return Int(s) ?? numbers[s.lowercased()]
    }

    private nonisolated static let months: [(String, Int)] = [
        ("januar", 1), ("jan", 1), ("februar", 2), ("feb", 2), ("märz", 3), ("maerz", 3), ("mär", 3),
        ("april", 4), ("apr", 4), ("mai", 5), ("juni", 6), ("jun", 6), ("juli", 7), ("jul", 7), ("august", 8),
        ("aug", 8), ("september", 9), ("sept", 9), ("sep", 9), ("oktober", 10), ("okt", 10), ("november", 11),
        ("nov", 11), ("dezember", 12), ("dez", 12),
    ]
    private nonisolated static let monthAlternation = months.map(\.0).joined(separator: "|")

    nonisolated static func month(_ s: String?) -> Int? {
        guard let s = s?.lowercased() else { return nil }
        return months.first { $0.0 == s }?.1
    }
}

// MARK: - Arbeitstext

extension QuickEntryParser {

    /// Arbeitstext mit ausgeblendeten Treffern (durch Leerzeichen gleicher Länge ersetzt, damit Bereiche im
    /// Original gültig bleiben) und dem, was bisher erkannt wurde.
    struct Scan {

        let original: NSString
        private var work: NSMutableString
        private var removed: [NSRange] = []

        var urgent = false
        var forceReminder = false
        var day: Date?
        var extraDates = 0
        var weekdayIsToday = false
        var time: QuickEntryClock?
        var absolute: Date?
        var endTime: QuickEntryClock?
        var duration: TimeInterval?
        var dayPart: QuickEntryDayPart?

        init(text: String) {
            original = text as NSString
            work = NSMutableString(string: text)
        }

        /// Erster Treffer im noch nicht ausgeblendeten Text; blendet ihn aus.
        mutating func take(_ pattern: String, caseInsensitive: Bool = true) -> QuickEntryMatch? {
            let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
            guard let re = try? NSRegularExpression(pattern: pattern, options: options),
                  let result = re.firstMatch(in: work as String, range: NSRange(location: 0, length: work.length)),
                  result.range.length > 0 else { return nil }
            let snapshot = NSString(string: work as String)
            work.replaceCharacters(in: result.range, with: String(repeating: " ", count: result.range.length))
            removed.append(result.range)
            return QuickEntryMatch(result: result, source: snapshot)
        }

        /// Erstes Datum gewinnt, jedes weitere macht die Eingabe zweifelhaft. Ungültig (31.11.) → zweifelhaft.
        mutating func setDay(_ d: Date?) {
            guard let d else { extraDates += 1; return }
            if day == nil { day = d } else if d != day { extraDates += 1 }
        }

        mutating func setTime(_ t: QuickEntryClock?) {
            guard let t else { extraDates += 1; return }
            if time == nil { time = t }
        }

        /// Original ohne Treffer, Leerraum zusammengezogen, Füllwörter und Satzzeichen am Rand weg.
        func title() -> String {
            let text = NSMutableString(string: original)
            for r in removed.sorted(by: { $0.location > $1.location }) {
                text.replaceCharacters(in: r, with: " ")
            }
            var words = (text as String).split(whereSeparator: \.isWhitespace).map(String.init)
            let filler: Set<String> = ["am", "um", "bis", "ab", "an", "im", "in", "für", "zum", "zur", "von", "und",
                                       "gegen", "-", "–", "—", ",", ":", ";", "uhr"]
            func trimPunctuation(_ w: String) -> String { w.trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) }
            while let first = words.first, filler.contains(first.lowercased()) || trimPunctuation(first).isEmpty {
                words.removeFirst()
            }
            while let last = words.last, filler.contains(last.lowercased()) || trimPunctuation(last).isEmpty {
                words.removeLast()
            }
            if let last = words.last { words[words.count - 1] = trimPunctuation(last) }
            if let first = words.first { words[0] = trimPunctuation(first) }
            return words.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}

struct QuickEntryClock: Equatable, Sendable { let hour, minute: Int }

enum QuickEntryDayPart { case morning, noon, afternoon, night }

/// Treffer mit Zugriff auf seine Gruppen (aus dem Arbeitstext vor dem Ausblenden).
struct QuickEntryMatch {
    let result: NSTextCheckingResult
    let source: NSString
    func string(_ i: Int) -> String? {
        let r = result.range(at: i)
        return r.location == NSNotFound ? nil : source.substring(with: r)
    }
    func int(_ i: Int) -> Int? { string(i).flatMap { Int($0) } }
}
