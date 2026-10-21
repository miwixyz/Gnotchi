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

    // MARK: Große Insel – „Eine Sache groß“

    func testBigContentFollowsCurrentActivity() {
        XCTAssertEqual(ActivityModel.bigContent(current: .event, privacy: true, hasMediaInfo: true), .event)
        XCTAssertEqual(ActivityModel.bigContent(current: .update(.kalli), privacy: false, hasMediaInfo: true), .update(.kalli))
        XCTAssertEqual(ActivityModel.bigContent(current: nil, privacy: true, hasMediaInfo: true), .privacy)
        XCTAssertEqual(ActivityModel.bigContent(current: nil, privacy: false, hasMediaInfo: true), .media, "pausierte Musik")
        XCTAssertEqual(ActivityModel.bigContent(current: nil, privacy: false, hasMediaInfo: false), .none)
    }

    func testChipRowOnlyWithMoreThanOneThing() {
        XCTAssertFalse(ActivityModel.showsChipRow(items: 1, big: .media, privacy: false, quota: false), "nur Musik")
        XCTAssertTrue(ActivityModel.showsChipRow(items: 2, big: .media, privacy: false, quota: false))
        XCTAssertTrue(ActivityModel.showsChipRow(items: 1, big: .media, privacy: true, quota: false), "Musik + Mikrofon")
        XCTAssertFalse(ActivityModel.showsChipRow(items: 0, big: .privacy, privacy: true, quota: false), "nur Mikrofon")
        XCTAssertTrue(ActivityModel.showsChipRow(items: 1, big: .media, privacy: false, quota: true))
    }

    func testPausedMusicStaysInChipRow() {
        let media = NowPlayingModel()
        media.setPreviewState(info: NowPlayingInfo(title: "Lied", artist: nil, album: nil, appBundleID: nil, isPlaying: false,
                                                   duration: 200, elapsedAtStamp: 10, stamp: Date(), rate: 0,
                                                   contentID: nil, artworkBase64: nil),
                              artwork: nil, route: .local)
        let model = ActivityModel(media: media)
        model.setUpcomingEvent(event(10))
        XCTAssertEqual(model.chipItems, [.event, .media])
        model.select(.media)
        XCTAssertEqual(model.bigContent, .media)
    }

    func testSelectSwitchesBigContent() {
        let model = ActivityModel(media: NowPlayingModel())
        model.setUpcomingEvent(event(10))
        model.setHeadphones(Headphones(name: "Beispiel", symbol: "headphones"))
        XCTAssertEqual(model.bigContent, .event)
        model.select(.headphones)
        XCTAssertEqual(model.bigContent, .headphones)
        model.select(.update(.seam))
        XCTAssertEqual(model.bigContent, .headphones, "nicht vorhandene Aktivität wird ignoriert")
    }

    func testBigFrameSizes() throws {
        let l = IslandGeometry.layout(for: IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil))
        XCTAssertEqual(IslandController.bigFrame(layout: l, small: false, chipRow: false), l.expanded)
        XCTAssertEqual(IslandController.bigFrame(layout: l, small: true, chipRow: false), l.notice, "nur Mikrofon")
        let big = try XCTUnwrap(IslandController.bigFrame(layout: l, small: false, chipRow: true))
        XCTAssertEqual(big.height, l.expanded.height + IslandGeometry.privacyLineHeight)
    }

    // MARK: Spiegel (G27)

    func testMirrorOnlyWhenEnabledAndEndsOnSelectOrCollapse() {
        let model = ActivityModel(media: NowPlayingModel())
        model.setUpcomingEvent(event(10))
        model.selectMirror()
        XCTAssertFalse(model.mirrorActive, "Schalter aus → nie an")
        model.setMirrorEnabled(true)
        XCTAssertTrue(model.showsChipRow, "Spiegel-Symbol braucht die Leiste")
        model.selectMirror()
        XCTAssertEqual(model.bigContent, .mirror)
        model.select(.event)
        XCTAssertFalse(model.mirrorActive, "anderes Symbol → Kamera aus")
        model.selectMirror()
        model.endMirror()
        XCTAssertFalse(model.mirrorActive, "Einklappen → Kamera aus")
        model.selectMirror()
        model.setMirrorEnabled(false)
        XCTAssertFalse(model.mirrorActive, "Schalter aus → Kamera aus")
    }

    func testMirrorFrameIsTaller() throws {
        let l = IslandGeometry.layout(for: IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil))
        let m = try XCTUnwrap(IslandController.bigFrame(layout: l, small: false, chipRow: true, mirror: true))
        XCTAssertEqual(m.height, IslandGeometry.mirrorHeight + IslandGeometry.privacyLineHeight)
        XCTAssertEqual(m.maxY, l.expanded.maxY, "wächst nach unten, oben bündig")
    }
}
