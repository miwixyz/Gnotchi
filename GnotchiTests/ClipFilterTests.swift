import CryptoKit
import XCTest

/// 0.49.0: Suchfilter nach Quell-App und Zeitraum.
@MainActor
final class ClipFilterTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Berlin")!
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        return f.date(from: s)!
    }

    private func entry(_ at: Date, source: String? = nil) -> ClipEntry {
        let e = ClipEntry(kind: .text, sourceBundleID: source)
        e.lastUsedAt = at
        return e
    }

    func testDefaultIncludesEverything() {
        let f = ClipFilter()
        XCTAssertFalse(f.isActive)
        XCTAssertTrue(f.includes(entry(.distantPast), now: Date(), calendar: calendar))
    }

    func testSourceApp() {
        let f = ClipFilter(sourceBundleID: "com.apple.mail")
        XCTAssertTrue(f.isActive)
        XCTAssertTrue(f.includes(entry(Date(), source: "com.apple.mail"), calendar: calendar))
        XCTAssertFalse(f.includes(entry(Date(), source: "com.apple.Safari"), calendar: calendar))
        XCTAssertFalse(f.includes(entry(Date(), source: nil), calendar: calendar), "ohne Quell-App nie bei App-Filter")
    }

    func testTodayStartsAtMidnight() {
        let now = date("2026-11-28T00:10:00")
        let f = ClipFilter(period: .today)
        XCTAssertTrue(f.includes(entry(date("2026-11-28T00:00:00")), now: now, calendar: calendar))
        XCTAssertFalse(f.includes(entry(date("2026-11-27T23:59:00")), now: now, calendar: calendar))
    }

    func testWeekCountsTodayPlusSixDays() {
        let now = date("2026-11-28T15:00:00")
        let f = ClipFilter(period: .week)
        XCTAssertTrue(f.includes(entry(date("2026-11-22T00:00:00")), now: now, calendar: calendar))
        XCTAssertFalse(f.includes(entry(date("2026-11-21T23:59:00")), now: now, calendar: calendar))
    }

    func testMonthCountsTodayPlus29Days() {
        let now = date("2026-11-28T15:00:00")
        let f = ClipFilter(period: .month)
        XCTAssertTrue(f.includes(entry(date("2026-10-30T00:00:00")), now: now, calendar: calendar))
        XCTAssertFalse(f.includes(entry(date("2026-10-29T23:59:00")), now: now, calendar: calendar))
    }

    /// Sommerzeit-Ende 25.10.: Tagesgrenze bleibt Mitternacht, nicht 7 × 24 h.
    func testWeekAcrossDaylightSavingChange() {
        let now = date("2026-10-28T12:00:00")
        let f = ClipFilter(period: .week)
        XCTAssertTrue(f.includes(entry(date("2026-10-22T00:00:00")), now: now, calendar: calendar))
        XCTAssertFalse(f.includes(entry(date("2026-10-21T23:59:00")), now: now, calendar: calendar))
    }

    func testSourcesMostFrequentFirst() {
        let now = Date()
        let list = [entry(now, source: "b"), entry(now, source: "a"), entry(now, source: "c"),
                    entry(now, source: "c"), entry(now, source: nil)]
        XCTAssertEqual(ClipFilter.sources(of: list), ["c", "a", "b"])
    }

    /// Speicher: Filter und Suchtext gelten zusammen.
    func testStoreCombinesFilterAndQuery() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        func text(_ s: String) -> ClipPayload {
            ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data(s.utf8))], plain: s)
        }
        let mail = try store.add(text("https://cinesocial.de"), kind: .link, source: "com.apple.mail")
        try store.add(text("https://cinesocial.de/kino"), kind: .link, source: "com.apple.Safari")
        try store.add(text("Notiz"), kind: .text, source: "com.apple.mail")
        let filter = ClipFilter(sourceBundleID: "com.apple.mail")
        XCTAssertEqual(store.entries(matching: "cinesocial", filter: filter).map(\.id), [mail.id])
        XCTAssertEqual(store.entries(filter: filter).count, 2)
        XCTAssertEqual(store.entries(filter: ClipFilter(period: .today)).count, 3)
        let tomorrow = Date().addingTimeInterval(2 * 86_400)
        XCTAssertTrue(store.entries(filter: ClipFilter(period: .today), now: tomorrow).isEmpty)
    }
}
