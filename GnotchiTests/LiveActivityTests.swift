import CoreAudio
import XCTest

/// 0.4.0 Live-Aktivitäten: Rotation, Pause beim Überfahren, Trackwechsel, Medienfilter (G25), Kopfhörer, Insel-Formen.
@MainActor
final class LiveActivityTests: XCTestCase {

    // MARK: Rotation

    private let three: [LiveActivity] = [.media, .headphones, .update(.kalli)]

    func testItemsInFixedOrder() {
        XCTAssertEqual(ActivityModel.rotationItems(media: true, headphones: true, updates: [.kalli, .seam]),
                       [.media, .headphones, .update(.kalli), .update(.seam)])
        XCTAssertEqual(ActivityModel.rotationItems(media: false, headphones: true, updates: []), [.headphones])
        XCTAssertEqual(ActivityModel.rotationItems(media: false, headphones: false, updates: []), [])
    }

    func testRotationSequenceWrapsAround() {
        var cursor: LiveActivity?
        var seen: [LiveActivity?] = []
        for _ in 0..<4 {
            cursor = ActivityModel.advance(cursor: cursor, items: three, paused: false, enabled: true)
            seen.append(cursor)
        }
        XCTAssertEqual(seen, [.headphones, .update(.kalli), .media, .headphones])
    }

    func testPauseHoldsCurrent() {
        XCTAssertEqual(ActivityModel.advance(cursor: .headphones, items: three, paused: true, enabled: true), .headphones)
    }

    func testSingleActivityDoesNotChange() {
        XCTAssertEqual(ActivityModel.advance(cursor: nil, items: [.media], paused: false, enabled: true), .media)
        XCTAssertNil(ActivityModel.advance(cursor: nil, items: [], paused: false, enabled: true))
    }

    func testRotationOffShowsFirst() {
        XCTAssertEqual(ActivityModel.advance(cursor: .headphones, items: three, paused: false, enabled: false), .media)
        XCTAssertEqual(ActivityModel.resolve(cursor: .headphones, items: three, enabled: false), .media)
    }

    func testVanishedActivityFallsBackToFirst() {
        XCTAssertEqual(ActivityModel.resolve(cursor: .update(.seam), items: three, enabled: true), .media)
        XCTAssertEqual(ActivityModel.advance(cursor: .update(.seam), items: three, paused: false, enabled: true),
                       .headphones)
    }

    func testModelTickPausedByHover() {
        let activity = ActivityModel(media: NowPlayingModel())
        activity.setHeadphones(Headphones(name: "Test", symbol: "headphones"))
        activity.setFamilyUpdates([FamilyUpdates.Entry(app: .kalli, version: "0.11.0", seen: Date())])
        XCTAssertTrue(activity.isVisible, "Kopfhörer und Updates halten die Insel offen")
        XCTAssertEqual(activity.currentActivity, .headphones)
        activity.tick()
        XCTAssertEqual(activity.currentActivity, .update(.kalli))
        activity.setRotationPaused(true)
        activity.tick()
        XCTAssertEqual(activity.currentActivity, .update(.kalli), "Maus über der Insel: Takt steht")
        activity.setRotationPaused(false)
        activity.tick()
        XCTAssertEqual(activity.currentActivity, .headphones)
    }

    func testOwnUpdateJoinsRotation() {
        let activity = ActivityModel(media: NowPlayingModel())
        activity.setOwnUpdate(FamilyUpdates.ownEntry("0.5.0", now: Date()))
        XCTAssertEqual(activity.rotationItems, [.update(.gnotchi)])
        activity.setOwnUpdate(nil)
        XCTAssertFalse(activity.isVisible)
    }

    // MARK: Trackwechsel

    private func info(_ title: String, app: String? = "com.spotify.client", playing: Bool = true) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: "X", album: nil, appBundleID: app, isPlaying: playing, duration: 200,
                       elapsedAtStamp: 0, stamp: Date(), rate: 1, contentID: nil, artworkBase64: nil)
    }

    func testTrackChangeOnlyOnOtherTitle() {
        XCTAssertTrue(NowPlayingModel.isTrackChange(old: info("A"), new: info("B")))
        XCTAssertTrue(NowPlayingModel.isTrackChange(old: info("A"), new: info("A", app: "com.apple.Music")), "andere App")
        XCTAssertFalse(NowPlayingModel.isTrackChange(old: info("A"), new: info("A", playing: false)), "Pause")
        XCTAssertFalse(NowPlayingModel.isTrackChange(old: info("A", playing: false), new: info("A")), "Weiter")
        XCTAssertFalse(NowPlayingModel.isTrackChange(old: nil, new: info("A")), "erster Titel")
        XCTAssertFalse(NowPlayingModel.isTrackChange(old: info("A"), new: nil))
        XCTAssertFalse(NowPlayingModel.isTrackChange(old: info("A"), new: info("B", playing: false)),
                       "Wechsel in der Pause: nichts aufblitzen lassen")
    }

    func testFlashBringsMediaToFrontThenEnds() async throws {
        let model = NowPlayingModel()
        model.setPreviewState(info: info("B"), artwork: nil)
        let activity = ActivityModel(media: model, flashDuration: .milliseconds(50))
        activity.setHeadphones(Headphones(name: "Test", symbol: "headphones"))
        activity.rotationCursor = .headphones
        activity.flashTrack()
        XCTAssertEqual(activity.currentActivity, .media)
        XCTAssertTrue(activity.showsTrackFlash)
        activity.tick()
        XCTAssertEqual(activity.currentActivity, .media, "während der breiten Form kein Wechsel")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(activity.showsTrackFlash)
    }

    func testWideModeOnlyFromCompact() {
        XCTAssertEqual(IslandController.nextMode(current: .compact, notice: false, trackFlash: true), .wide)
        XCTAssertEqual(IslandController.nextMode(current: .hidden, notice: false, trackFlash: true), .wide)
        XCTAssertEqual(IslandController.nextMode(current: .wide, notice: false, trackFlash: false), .compact)
        XCTAssertEqual(IslandController.nextMode(current: .expanded, notice: false, trackFlash: true), .expanded)
        XCTAssertEqual(IslandController.nextMode(current: .wide, notice: true, trackFlash: true), .notice, "Hinweis verdrängt")
        XCTAssertEqual(IslandController.nextMode(current: .wide, notice: false, recording: true, trackFlash: true), .compact,
                       "Aufnahme verdrängt")
        XCTAssertTrue(IslandController.shouldExpand(stillInside: true, mouseDown: false, mode: .wide))
    }

    // MARK: Geometrie

    private let notchScreen = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 645.5, auxRightWidth: 645.5)
    private let pillScreen = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil)

    func testWideIsWiderSameHeightSameCenter() throws {
        for screen in [notchScreen, pillScreen] {
            let l = IslandGeometry.layout(for: screen)
            XCTAssertGreaterThan(l.wide.width, l.compact.width)
            XCTAssertEqual(l.wide.height, l.compact.height)
            XCTAssertEqual(l.wide.midX, l.compact.midX, accuracy: 0.5)
            XCTAssertEqual(l.wide.maxY, l.compact.maxY)
            XCTAssertEqual(IslandController.panelFrame(mode: .wide, layout: l), l.wide)
        }
    }

    func testExpandedGrowsWithUpdateLinesAndRows() throws {
        let l = IslandGeometry.layout(for: notchScreen)
        let one = try XCTUnwrap(IslandController.panelFrame(mode: .expanded, layout: l, updates: 1))
        XCTAssertEqual(one.height, l.expanded.height + IslandGeometry.privacyLineHeight)
        XCTAssertEqual(one.maxY, l.expanded.maxY, "wächst nach unten")
        XCTAssertEqual(IslandController.panelFrame(mode: .expanded, layout: l, hasMedia: false, rows: 2), l.notice)
        let four = try XCTUnwrap(IslandController.panelFrame(mode: .expanded, layout: l, hasMedia: false, rows: 4))
        XCTAssertEqual(four.height, l.notice.height + 2 * IslandGeometry.privacyLineHeight)
    }

    // MARK: Kopfhörer

    func testHeadphonesOnlyForBluetoothAndWhenOn() {
        let bt = OutputDevices.Device(id: 1, name: "Beispiel-Kopfhörer", transport: kAudioDeviceTransportTypeBluetooth)
        let speaker = OutputDevices.Device(id: 2, name: "MacBook-Lautsprecher", transport: kAudioDeviceTransportTypeBuiltIn)
        XCTAssertEqual(HeadphoneWatcher.headphones(bt, enabled: true)?.name, "Beispiel-Kopfhörer")
        XCTAssertNil(HeadphoneWatcher.headphones(bt, enabled: false))
        XCTAssertNil(HeadphoneWatcher.headphones(speaker, enabled: true))
        XCTAssertNil(HeadphoneWatcher.headphones(nil, enabled: true))
    }

    // MARK: Medienfilter (G25)

    func testFilterDropsExcludedAppOnly() {
        let excluded: (String) -> Bool = { $0 == "com.apple.Safari" }
        XCTAssertNil(NowPlayingModel.filtered(info("A", app: "com.apple.Safari"), isExcluded: excluded))
        XCTAssertEqual(NowPlayingModel.filtered(info("A"), isExcluded: excluded)?.title, "A")
        XCTAssertEqual(NowPlayingModel.filtered(info("A", app: nil), isExcluded: { _ in true })?.title, "A",
                       "ohne Bundle-ID nie gefiltert")
    }

    func testSeenAppsBoundedAndValidated() {
        var list: [String] = []
        list = NowPlayingModel.noting("com.spotify.client", in: list)
        list = NowPlayingModel.noting("com.spotify.client", in: list)
        list = NowPlayingModel.noting("evil app/../x", in: list)
        XCTAssertEqual(list, ["com.spotify.client"])
        for i in 0..<100 { list = NowPlayingModel.noting("app.n\(i)", in: list) }
        XCTAssertEqual(list.count, NowPlayingModel.maxSeenApps)
        XCTAssertEqual(list.last, "app.n99")
    }

    func testFilterListKnownInstalledSeenExcluded() {
        let names = ["com.spotify.client": "Spotify", "com.apple.Music": "Musik", "com.apple.Safari": "Safari"]
        let list = NowPlayingModel.filterApps(known: ["com.spotify.client", "com.apple.Music", "org.videolan.vlc"],
                                              seen: ["com.apple.Safari", "com.spotify.client"],
                                              excluded: ["app.weg.deinstalliert"], name: { names[$0] })
        XCTAssertEqual(list.map(\.id), ["app.weg.deinstalliert", "com.apple.Music", "com.apple.Safari", "com.spotify.client"],
                       "VLC nicht installiert → fehlt; ausgeschlossene bleibt sichtbar (sonst nie wieder einschaltbar)")
        XCTAssertEqual(list.first?.name, "app.weg.deinstalliert", "ohne Namen die Bundle-ID")
    }

    func testExcludedListValidated() {
        XCTAssertEqual(Preferences.validExcluded(["com.apple.Safari", "com.apple.Safari", "bad id", "a/b", 42,
                                                 String(repeating: "a", count: 256), "org.mozilla.firefox"]),
                       ["com.apple.Safari", "org.mozilla.firefox"])
        XCTAssertEqual(Preferences.validExcluded("com.apple.Safari"), [], "kein Array")
        XCTAssertEqual(Preferences.validExcluded((0..<100).map { "app.n\($0)" }).count, Preferences.maxExcluded)
    }

    func testExcludedPersistedAndToggled() {
        let suite = "dev.mwlr.gnotchi.tests.filter"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.liveRotation && prefs.headphoneActivity && prefs.familyUpdates, "ab Werk an")
        prefs.setMediaExcluded("com.apple.Safari", true)
        prefs.setMediaExcluded("kaputt mit Leerzeichen", true)
        XCTAssertEqual(Preferences(defaults: defaults).mediaExcluded, ["com.apple.Safari"])
        XCTAssertTrue(prefs.isMediaExcluded("com.apple.Safari"))
        prefs.setMediaExcluded("com.apple.Safari", false)
        XCTAssertEqual(Preferences(defaults: defaults).mediaExcluded, [])
    }
}
