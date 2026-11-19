import XCTest

// SYNTHETISCH – erfundene Einträge, keine echten Kalenderdaten (Datenschutz-Gate, SECURE-DESIGN G16)

/// Schnelleingabe in Alltagssprache (specs/2026-11-19-gnotchi-schnelleingabe.md): Testfälle der Spezifikation,
/// Bezug Donnerstag 19.11.2026, 14:30 in Berlin.
final class QuickEntryParserTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private var now: Date { date(2026, 11, 19, 14, 30) }

    private func parse(_ s: String) -> QuickEntryParser.Entry {
        QuickEntryParser.parse(s, now: now, calendar: calendar)
    }

    private struct Case {
        let text: String
        let kind: QuickEntryParser.Kind
        let start: Date?
        let end: Date?
        let allDay: Bool
        let title: String
        var urgent = false
        var check = false
    }

    private func event(_ text: String, _ start: Date, end: Date? = nil, _ title: String, check: Bool = false) -> Case {
        Case(text: text, kind: .event, start: start, end: end ?? start.addingTimeInterval(3600), allDay: false,
             title: title, check: check)
    }

    private func reminder(_ text: String, _ start: Date?, allDay: Bool, _ title: String, urgent: Bool = false) -> Case {
        Case(text: text, kind: .reminder, start: start, end: nil, allDay: allDay, title: title, urgent: urgent)
    }

    private var cases: [Case] {
        [
            event("Zahnarzt Do 15 Uhr", date(2026, 11, 19, 15), "Zahnarzt"),
            event("Zahnarzt morgen um 15 Uhr", date(2026, 11, 20, 15), "Zahnarzt"),
            event("Call mit Andrea übermorgen 9:30", date(2026, 11, 21, 9, 30), "Call mit Andrea"),
            event("Meeting am 3.12. um 14 Uhr", date(2026, 12, 3, 14), "Meeting"),
            event("Meeting am 3. Dezember 14:00", date(2026, 12, 3, 14), "Meeting"),
            event("Kino BiiGZ Freitag 20 Uhr", date(2026, 11, 20, 20), "Kino BiiGZ"),
            event("nächsten Montag Steuerberater 11 Uhr", date(2026, 11, 23, 11), "Steuerberater"),
            event("heute 18 Uhr Sport", date(2026, 11, 19, 18), "Sport"),
            event("9 Uhr Sport", date(2026, 11, 20, 9), "Sport"),
            reminder("Müll rausbringen morgen früh", date(2026, 11, 20), allDay: true, "Müll rausbringen"),
            reminder("Rechnung zahlen bis 30.11.", date(2026, 11, 30), allDay: true, "Rechnung zahlen"),
            event("in 2 Stunden Cati anrufen", date(2026, 11, 19, 16, 30), "Cati anrufen"),
            reminder("erinnere mich in 2 Stunden Cati anzurufen", date(2026, 11, 19, 16, 30), allDay: false,
                     "Cati anzurufen"),
            reminder("in 3 Tagen Paket abholen", date(2026, 11, 22), allDay: true, "Paket abholen"),
            event("Mittwoch halb drei nachmittags Friseur", date(2026, 11, 25, 14, 30), "Friseur"),
            event("Mittwoch halb drei Friseur", date(2026, 11, 25, 2, 30), "Friseur", check: true),
            reminder("Geburtstag Mama 12.01.2027", date(2027, 1, 12), allDay: true, "Geburtstag Mama"),
            event("Weihnachtsfeier 18.12. 19:00", date(2026, 12, 18, 19), "Weihnachtsfeier"),
            event("Termin Dienstag 8 Uhr", date(2026, 11, 24, 8), "Termin"),
            event("Flug am Sonntag um 7:15", date(2026, 11, 22, 7, 15), "Flug"),
            event("Flug am Sonntag um 7 Uhr abends", date(2026, 11, 22, 19), "Flug"),
            event("Teams-Call 16:30", date(2026, 11, 19, 16, 30), "Teams-Call"),
            event("Teams-Call 16:30 bis 17:15", date(2026, 11, 19, 16, 30), end: date(2026, 11, 19, 17, 15),
                  "Teams-Call"),
            reminder("nächste Woche Mittwoch Vertrag prüfen", date(2026, 11, 25), allDay: true, "Vertrag prüfen"),
            reminder("am Wochenende Fahrrad reparieren", date(2026, 11, 21), allDay: true, "Fahrrad reparieren"),
            reminder("Steuer abgeben !", nil, allDay: false, "Steuer abgeben", urgent: true),
        ]
    }

    func testSpecificationCases() {
        XCTAssertEqual(cases.count, 26, "Tabelle der Spezifikation vollständig (ohne „morgen 15 Uhr“, eigener Test)")
        for c in cases {
            let e = parse(c.text)
            XCTAssertEqual(e.kind, c.kind, "Art: \(c.text)")
            XCTAssertEqual(e.start, c.start, "Beginn: \(c.text)")
            XCTAssertEqual(e.end, c.end, "Ende: \(c.text)")
            XCTAssertEqual(e.allDay, c.allDay, "ganztägig: \(c.text)")
            XCTAssertEqual(e.title, c.title, "Titel: \(c.text)")
            XCTAssertEqual(e.urgent, c.urgent, "dringend: \(c.text)")
            XCTAssertEqual(e.needsCheck, c.check, "Prüfen: \(c.text)")
        }
    }

    func testOnlyTimeLeavesEmptyTitle() {
        XCTAssertEqual(parse("morgen 15 Uhr").title, "", "Vorschau: Bitte einen Titel eingeben")
    }

    // MARK: Grenzfälle

    func testWeekdayTodayWithPassedTimeMeansNextWeek() {
        XCTAssertEqual(parse("Zahnarzt Do 9 Uhr").start, date(2026, 11, 26, 9))
    }

    func testWordsInsideSentencesAreNotDates() {
        let e = parse("Fahrrad so reparieren wie besprochen")
        XCTAssertNil(e.start, "„so“ ist kein Sonntag")
        XCTAssertEqual(e.title, "Fahrrad so reparieren wie besprochen")
        XCTAssertNil(parse("eine Uhr kaufen").start, "„eine Uhr“ ist keine Uhrzeit")
        XCTAssertNil(parse("Montags Yoga").start, "„montags“ ist kein Datum")
    }

    func testPastDateWithoutYearMovesToNextYear() {
        XCTAssertEqual(parse("Steuer 3.2.").start, date(2027, 2, 3))
        XCTAssertNil(parse("Termin 31.11.").start, "31.11. gibt es nicht")
        XCTAssertTrue(parse("Termin 31.11.").needsCheck)
    }

    func testDurationsAndRelativeTimes() {
        let call = parse("Call morgen 10 Uhr 30 Min")
        XCTAssertEqual(call.end, date(2026, 11, 20, 10, 30))
        XCTAssertEqual(call.title, "Call")
        XCTAssertEqual(parse("Workshop Fr 9 Uhr für 2 Std").end, date(2026, 11, 20, 11))
        XCTAssertEqual(parse("in einer halben Stunde Tee").start, date(2026, 11, 19, 15))
        XCTAssertEqual(parse("in zwei Wochen Reifen").start, date(2026, 12, 3))
    }

    func testDeadlineWithTimeIsReminder() {
        let e = parse("Bericht bis 17 Uhr")
        XCTAssertEqual(e.kind, .reminder)
        XCTAssertEqual(e.start, date(2026, 11, 19, 17))
        XCTAssertEqual(e.title, "Bericht")
    }

    func testDoubtfulInputsAreMarked() {
        XCTAssertTrue(parse("Meeting 3.12. und 5.12. 10 Uhr").needsCheck, "zwei Daten")
        XCTAssertTrue(parse("Meeting morgen 16 Uhr bis 15 Uhr").needsCheck, "Ende vor Beginn")
        XCTAssertTrue(parse("Sport heute 9 Uhr").needsCheck, "liegt in der Vergangenheit")
        XCTAssertFalse(parse("Sport morgen 9 Uhr").needsCheck)
    }

    func testNothingRecognizedStaysReminderWithoutDate() {
        let e = parse("Paket abholen")
        XCTAssertEqual(e.kind, .reminder)
        XCTAssertNil(e.start)
        XCTAssertEqual(e.title, "Paket abholen")
    }

    func testToggleSwitchesKind() {
        let e = parse("Zahnarzt morgen 15 Uhr")
        let r = QuickEntryParser.toggled(e, now: now, calendar: calendar)
        XCTAssertEqual(r.kind, .reminder)
        XCTAssertNil(r.end)
        XCTAssertEqual(r.start, e.start)
        let back = QuickEntryParser.toggled(r, now: now, calendar: calendar)
        XCTAssertEqual(back.kind, .event)
        XCTAssertEqual(back.end, date(2026, 11, 20, 16))
        let undated = QuickEntryParser.toggled(parse("Paket abholen"), now: now, calendar: calendar)
        XCTAssertEqual(undated.kind, .event)
        XCTAssertEqual(undated.start, date(2026, 11, 19))
        XCTAssertTrue(undated.allDay)
    }
}
