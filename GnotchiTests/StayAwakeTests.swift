import XCTest

/// 0.21.0 Wach bleiben (G47): Zeitfenster, Hand an/aus, Einstellungen, Protokoll `nudge`, Regel im Hilfsprogramm,
/// Lineal der Timer-Auswahl.
@MainActor
final class StayAwakeTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        return f.date(from: s)!
    }

    func testWindowWeekdaysAndTimes() {
        let days = StayAwake.defaultDays   // Mo–Fr
        // 2026-11-06 ist ein Freitag, 2026-11-07 ein Samstag.
        XCTAssertTrue(StayAwake.inWindow(date("2026-11-06T09:00:00"), days: days, from: 540, to: 1080, calendar: calendar))
        XCTAssertTrue(StayAwake.inWindow(date("2026-11-06T17:59:00"), days: days, from: 540, to: 1080, calendar: calendar))
        XCTAssertFalse(StayAwake.inWindow(date("2026-11-06T18:00:00"), days: days, from: 540, to: 1080, calendar: calendar),
                       "Ende gehört nicht dazu")
        XCTAssertFalse(StayAwake.inWindow(date("2026-11-06T08:59:00"), days: days, from: 540, to: 1080, calendar: calendar))
        XCTAssertFalse(StayAwake.inWindow(date("2026-11-07T10:00:00"), days: days, from: 540, to: 1080, calendar: calendar),
                       "Samstag nicht im Plan")
        XCTAssertFalse(StayAwake.inWindow(date("2026-11-06T10:00:00"), days: days, from: 1080, to: 540, calendar: calendar),
                       "kein Fenster über Mitternacht")
    }

    func testManualBeatsScheduleAndOffSuppresses() {
        let now = date("2026-11-06T10:00:00")
        XCTAssertTrue(StayAwake.isActive(now: now, manualUntil: now.addingTimeInterval(60), schedule: false, inWindow: false,
                                         suppressedUntil: nil))
        XCTAssertFalse(StayAwake.isActive(now: now, manualUntil: now, schedule: false, inWindow: false, suppressedUntil: nil),
                       "Dauer abgelaufen")
        XCTAssertTrue(StayAwake.isActive(now: now, manualUntil: nil, schedule: true, inWindow: true, suppressedUntil: nil))
        XCTAssertFalse(StayAwake.isActive(now: now, manualUntil: nil, schedule: true, inWindow: true,
                                          suppressedUntil: now.addingTimeInterval(3600)), "von Hand aus im Fenster")
        XCTAssertFalse(StayAwake.isActive(now: now, manualUntil: nil, schedule: false, inWindow: true, suppressedUntil: nil),
                       "Zeitplan aus")
    }

    func testTurnOnOffFlow() {
        let defaults = UserDefaults(suiteName: "StayAwakeTests-\(UUID().uuidString)")!
        let awake = StayAwake(defaults: defaults)
        XCTAssertFalse(awake.schedule, "ab Werk aus")
        XCTAssertFalse(awake.nudge, "ab Werk aus")
        XCTAssertEqual(awake.days, StayAwake.defaultDays)
        XCTAssertEqual(StayAwake.timeText(awake.from), "9:00")
        XCTAssertEqual(StayAwake.timeText(awake.to), "18:00")
        awake.turnOn(hours: 2)
        XCTAssertTrue(awake.isActive)
        awake.turnOff()
        XCTAssertFalse(awake.isActive)
        awake.turnOn(hours: nil)
        XCTAssertEqual(awake.activeUntil, .distantFuture)
        awake.turnOff()
    }

    func testInvalidStoredValuesFallBack() {
        XCTAssertEqual(StayAwake.validWindow(from: 600, to: 540).0, StayAwake.defaultFrom, "von nach bis")
        XCTAssertEqual(StayAwake.validWindow(from: 545, to: 1080).0, StayAwake.defaultFrom, "keine 15-Min.-Stufe")
        XCTAssertEqual(StayAwake.validWindow(from: "9", to: 1080).0, StayAwake.defaultFrom, "falscher Typ")
        XCTAssertEqual(StayAwake.validWindow(from: 480, to: 1020).1, 1020)
        XCTAssertEqual(StayAwake.validDays([0, 2, 8, 3]), [2, 3])
        XCTAssertEqual(StayAwake.validDays("Mo"), StayAwake.defaultDays)
    }

    // MARK: Protokoll Gnotchi → Hilfsprogramm

    func testNudgeIsContentFree() {
        XCTAssertEqual(NotifyWire.parseCommand(payload(NotifyWire.encode(.nudge))), .nudge)
        XCTAssertEqual(NotifyWire.encode(.nudge).count, 2, "nur v + nudge")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "nudge": false])))
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "nudge": 1])), "Zahl statt Wahrheitswert")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "nudge": true, "dx": 500])), "Zusatz: Richtung")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "nudge": true, "click": true])), "Zusatz: Klick")
    }

    func testFilterCarriesNotesFlag() {
        let nudgeOnly = NotifyWire.Command.filter(apps: [], calls: false, badges: false, notes: false)
        XCTAssertEqual(NotifyWire.parseCommand(payload(NotifyWire.encode(nudgeOnly))), nudgeOnly)
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "apps": [], "calls": true, "badges": false])), "ohne notes")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "apps": [], "calls": true, "badges": false, "notes": "ja"])))
    }

    // MARK: Regel im Hilfsprogramm

    func testPointerMovesOnlyWhenIdleUnlockedTrustedAndNotTooOften() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(NudgePointer.shouldNudge(trusted: true, locked: false, idle: 240, last: nil, now: now))
        XCTAssertFalse(NudgePointer.shouldNudge(trusted: true, locked: false, idle: 239, last: nil, now: now), "Michael arbeitet")
        XCTAssertFalse(NudgePointer.shouldNudge(trusted: false, locked: false, idle: 600, last: nil, now: now))
        XCTAssertFalse(NudgePointer.shouldNudge(trusted: true, locked: true, idle: 600, last: nil, now: now), "gesperrt")
        XCTAssertFalse(NudgePointer.shouldNudge(trusted: true, locked: false, idle: nil, last: nil, now: now), "Leerlauf unbekannt")
        XCTAssertFalse(NudgePointer.shouldNudge(trusted: true, locked: false, idle: 600, last: now.addingTimeInterval(-59), now: now))
        XCTAssertTrue(NudgePointer.shouldNudge(trusted: true, locked: false, idle: 600, last: now.addingTimeInterval(-60), now: now))
    }

    // MARK: Timer-Auswahl und Höhe

    func testRulerDragMapsToMinutes() {
        XCTAssertEqual(TimerPicker.minutes(start: 25, dragX: 0), 25)
        XCTAssertEqual(TimerPicker.minutes(start: 25, dragX: -TimerPicker.pointsPerMinute * 5), 30, "nach links = mehr")
        XCTAssertEqual(TimerPicker.minutes(start: 25, dragX: TimerPicker.pointsPerMinute * 100), 1, "untere Grenze")
        XCTAssertEqual(TimerPicker.minutes(start: 170, dragX: -TimerPicker.pointsPerMinute * 100), 180, "obere Grenze")
        XCTAssertEqual(TimerPicker.presets.map(TimerPicker.presetLabel), ["1m", "5m", "10m", "25m", "45m", "1h"])
    }

    func testTallPagesGetTheirHeight() {
        XCTAssertEqual(IslandController.tallHeight(.timerPicker), IslandGeometry.timerPickerHeight)
        XCTAssertEqual(IslandController.tallHeight(.awake), IslandGeometry.awakeHeight)
        XCTAssertNil(IslandController.tallHeight(.media))
    }

    private func payload(_ obj: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: obj)) ?? Data() }
}
