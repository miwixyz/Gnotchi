import XCTest
@testable import Gnotchi

// SYNTHETISCH – erfundene Termine, keine echten Kalenderdaten (Datenschutz-Gate, SECURE-DESIGN G16)

/// 0.5.0 Nächster Termin aus Kalli (SECURE-DESIGN G26): Schema, Anzeigefenster, Rotation.
@MainActor
final class KalliEventsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(_ obj: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    private func event(_ minutes: Double, title: String = "Zahnarzt") -> KalliEvents.Event {
        KalliEvents.Event(title: title, start: now.addingTimeInterval(minutes * 60), color: nil)
    }

    // MARK: Schema

    func testValidEventParses() {
        let start = now.timeIntervalSince1970 + 600
        let m = KalliEvents.parse(payload(["v": 1, "event": ["title": "Zahnarzt", "start": start, "color": "#ff8000"]]),
                                  now: now)
        XCTAssertEqual(m, .event(KalliEvents.Event(title: "Zahnarzt", start: Date(timeIntervalSince1970: start),
                                                   color: KalliEvents.RGB(r: 1, g: 128.0 / 255, b: 0))))
    }

    func testNullOrMissingEventMeansNone() {
        XCTAssertEqual(KalliEvents.parse(payload(["v": 1, "event": NSNull()]), now: now), KalliEvents.Message.none)
        XCTAssertEqual(KalliEvents.parse(payload(["v": 1]), now: now), KalliEvents.Message.none)
    }

    func testWrongTypesAreInvalid() {
        let start = now.timeIntervalSince1970 + 600
        XCTAssertNil(KalliEvents.parse(payload(["v": true, "event": NSNull()]), now: now), "v als Bool")
        XCTAssertNil(KalliEvents.parse(payload(["v": 2, "event": NSNull()]), now: now), "falsche Version")
        XCTAssertNil(KalliEvents.parse(payload(["v": 1, "event": "Zahnarzt"]), now: now), "event kein Objekt")
        XCTAssertNil(KalliEvents.parse(payload(["v": 1, "event": ["title": 5, "start": start]]), now: now), "Titel keine Zeichenkette")
        XCTAssertNil(KalliEvents.parse(payload(["v": 1, "event": ["title": "A", "start": "morgen"]]), now: now), "start kein Zahl")
        XCTAssertNil(KalliEvents.parse(payload(["v": 1, "event": ["title": "A", "start": true]]), now: now), "start als Bool")
        XCTAssertNil(KalliEvents.parse(payload(["v": 1, "event": ["title": "A", "start": start, "color": "rot"]]), now: now))
        XCTAssertNil(KalliEvents.parse(payload(["v": 1, "event": ["title": "A", "start": start, "color": "#12345"]]), now: now))
        XCTAssertNil(KalliEvents.parse(Data("kein json".utf8), now: now))
    }

    func testStartOutsideWindowIsDropped() {
        let past = now.timeIntervalSince1970 - 2 * 86_400
        let far = now.timeIntervalSince1970 + 500 * 86_400
        XCTAssertEqual(KalliEvents.parse(payload(["v": 1, "event": ["title": "A", "start": past]]), now: now), KalliEvents.Message.none)
        XCTAssertEqual(KalliEvents.parse(payload(["v": 1, "event": ["title": "A", "start": far]]), now: now), KalliEvents.Message.none)
    }

    func testTitleSanitizedTruncatedAndNeverEmpty() {
        XCTAssertEqual(KalliEvents.cleanTitle("Zahn\u{202E}arzt\n  um\tzehn"), "Zahnarzt um zehn")
        XCTAssertEqual(KalliEvents.cleanTitle("  \u{200B} "), "Termin")
        let long = KalliEvents.cleanTitle(String(repeating: "x", count: 300))
        XCTAssertEqual(long.count, KalliEvents.maxTitle)
        XCTAssertTrue(long.hasSuffix("…"))
    }

    // MARK: Anzeigefenster

    func testShowsFromFifteenMinutesUntilStart() {
        XCTAssertFalse(KalliEvents.isShowing(event(16), now: now))
        XCTAssertTrue(KalliEvents.isShowing(event(15), now: now))
        XCTAssertTrue(KalliEvents.isShowing(event(0.1), now: now))
        XCTAssertFalse(KalliEvents.isShowing(event(0), now: now), "bei Beginn weg")
        XCTAssertFalse(KalliEvents.isShowing(event(-5), now: now))
    }

    func testNextChange() {
        XCTAssertEqual(KalliEvents.nextChange(event(60), now: now), now.addingTimeInterval(45 * 60))
        XCTAssertEqual(KalliEvents.nextChange(event(10), now: now), now.addingTimeInterval(10 * 60))
        XCTAssertNil(KalliEvents.nextChange(event(0), now: now))
    }

    func testMinutesLeftRoundsUp() {
        XCTAssertEqual(KalliEvents.minutesLeft(event(12), now: now), 12)
        XCTAssertEqual(KalliEvents.minutesLeft(event(11.2), now: now), 12)
        XCTAssertEqual(KalliEvents.minutesLeft(event(0.1), now: now), 1)
    }

    // MARK: Rotation

    func testEventLeadsRotation() {
        XCTAssertEqual(ActivityModel.rotationItems(event: true, media: true, headphones: false, updates: [.kalli]),
                       [.event, .media, .update(.kalli)])
    }

    func testEventMakesIslandVisibleAndCountsAsLine() {
        let model = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(model.isVisible)
        model.setUpcomingEvent(event(10))
        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.activityLines, 1)
        XCTAssertEqual(model.currentActivity, .event)
        model.setUpcomingEvent(nil)
        XCTAssertFalse(model.isVisible)
    }
}
