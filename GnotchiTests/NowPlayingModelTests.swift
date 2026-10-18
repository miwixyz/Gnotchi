import XCTest
@testable import Gnotchi

/// Spezifikation: sichtbar bei Wiedergabe; nach 5 s Pause zurück in die Notch.
final class NowPlayingModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testVisibleWhilePlaying() {
        XCTAssertTrue(NowPlayingModel.isVisible(hasInfo: true, playing: true, pausedSince: nil, now: t0))
    }

    func testVisibleShortlyAfterPause() {
        XCTAssertTrue(NowPlayingModel.isVisible(hasInfo: true, playing: false, pausedSince: t0, now: t0.addingTimeInterval(4)))
    }

    func testHiddenFiveSecondsAfterPause() {
        XCTAssertFalse(NowPlayingModel.isVisible(hasInfo: true, playing: false, pausedSince: t0, now: t0.addingTimeInterval(5)))
    }

    func testHiddenWithoutInfo() {
        XCTAssertFalse(NowPlayingModel.isVisible(hasInfo: false, playing: false, pausedSince: nil, now: t0))
    }

    // MARK: nextPausedSince

    func testPausedSinceSetOnPlayToPause() {
        XCTAssertEqual(NowPlayingModel.nextPausedSince(hasInfo: true, isPlaying: false, wasPlaying: true,
                                                       current: nil, now: t0), t0)
    }

    func testPausedSinceKeptOnPauseToPause() {
        let earlier = t0.addingTimeInterval(-3)
        XCTAssertEqual(NowPlayingModel.nextPausedSince(hasInfo: true, isPlaying: false, wasPlaying: false,
                                                       current: earlier, now: t0), earlier)
    }

    func testPausedSinceSetWhenFirstInfoIsPaused() {
        XCTAssertEqual(NowPlayingModel.nextPausedSince(hasInfo: true, isPlaying: false, wasPlaying: false,
                                                       current: nil, now: t0), t0)
    }

    func testPausedSinceClearedWhenPlayingOrGone() {
        XCTAssertNil(NowPlayingModel.nextPausedSince(hasInfo: true, isPlaying: true, wasPlaying: false,
                                                     current: t0, now: t0))
        XCTAssertNil(NowPlayingModel.nextPausedSince(hasInfo: false, isPlaying: false, wasPlaying: true,
                                                     current: t0, now: t0))
    }

    // MARK: artworkKey

    private func info(title: String = "T", artist: String? = "A", bundle: String? = "com.apple.Music",
                      contentID: String? = nil) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, album: nil, appBundleID: bundle, isPlaying: true,
                       duration: 100, elapsedAtStamp: 0, stamp: t0, rate: 1,
                       contentID: contentID, artworkBase64: nil)
    }

    func testArtworkKeyNilForNoInfo() {
        XCTAssertNil(NowPlayingModel.artworkKey(for: nil))
    }

    func testArtworkKeyPrefersContentIDOverTitle() {
        XCTAssertEqual(NowPlayingModel.artworkKey(for: info(title: "X", contentID: "id1")),
                       NowPlayingModel.artworkKey(for: info(title: "Y", contentID: "id1")))
    }

    func testArtworkKeyDiffersByBundle() {
        XCTAssertNotEqual(NowPlayingModel.artworkKey(for: info(bundle: "a")),
                          NowPlayingModel.artworkKey(for: info(bundle: "b")))
    }

    func testArtworkKeyDiffersByArtistWithSameTitle() {
        XCTAssertNotEqual(NowPlayingModel.artworkKey(for: info(artist: "A")),
                          NowPlayingModel.artworkKey(for: info(artist: "B")))
    }

    // MARK: Hinweis bei verweigerter Automation (G7)

    func testDeniedReasonNamesTheApps() {
        let one = NowPlayingModel.deniedReason(names: ["Spotify"])
        XCTAssertTrue(one.hasPrefix("Automation für Spotify nicht erlaubt"), one)
        XCTAssertTrue(one.contains("Datenschutz"))
        XCTAssertTrue(NowPlayingModel.deniedReason(names: ["Spotify", "Musik"]).hasPrefix("Automation für Spotify und Musik nicht erlaubt"))
    }
}
