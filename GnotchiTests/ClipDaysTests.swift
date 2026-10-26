import XCTest
@testable import Gnotchi

/// 0.14.0: Tagestrenner in der Kartenreihe – Mitternacht und Zeitzone.
final class ClipDaysTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Berlin")!
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        return f.date(from: s)!
    }

    private func entry(_ at: Date) -> ClipEntry {
        let e = ClipEntry(kind: .text, sourceBundleID: nil)
        e.lastUsedAt = at
        return e
    }

    func testGroupsAroundMidnight() {
        let now = date("2026-10-26T00:10:00")
        let list = [entry(date("2026-10-26T00:05:00")), entry(date("2026-10-25T23:55:00")),
                    entry(date("2026-10-25T08:00:00")), entry(date("2026-10-22T12:00:00"))]
        let groups = ClipDays.group(list, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.label).prefix(2), ["Heute", "Gestern"])
        XCTAssertEqual(groups.map { $0.entries.count }, [1, 2, 1])
        XCTAssertFalse(["Heute", "Gestern"].contains(groups[2].label), "älter → Datum")
    }

    func testEmpty() {
        XCTAssertTrue(ClipDays.group([], calendar: calendar).isEmpty)
    }
}
