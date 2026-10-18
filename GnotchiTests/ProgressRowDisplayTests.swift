import XCTest
@testable import Gnotchi

/// Was die Fortschrittszeile zeigt – reine Rechnung aus Position und Dauer (Review 18.10.).
final class ProgressRowDisplayTests: XCTestCase {

    // MARK: display

    /// Livestream ohne Dauer: Zeit läuft weiter (vorher blieb sie bei 0:01 stehen), Slider gesperrt.
    func testNoDurationLabelRunsOnSliderDisabled() {
        let d = ProgressRow.display(elapsed: 125, duration: nil)
        XCTAssertEqual(d.elapsedLabel, "2:05")
        XCTAssertEqual(d.durationLabel, ProgressRow.placeholder)
        XCTAssertFalse(d.seekable)
        XCTAssertLessThanOrEqual(d.sliderValue, d.sliderUpper)
        XCTAssertEqual(d.accessibilityValue, "2:05")
    }

    func testWithDuration() {
        let d = ProgressRow.display(elapsed: 83, duration: 225)
        XCTAssertEqual(d.elapsedLabel, "1:23")
        XCTAssertEqual(d.durationLabel, "3:45")
        XCTAssertTrue(d.seekable)
        XCTAssertEqual(d.sliderValue, 83)
        XCTAssertEqual(d.sliderUpper, 225)
        XCTAssertEqual(d.accessibilityValue, "1:23 von 3:45")
    }

    /// Slider-Wert bleibt im Bereich, auch wenn die Position (kurz) über der Dauer liegt.
    func testSliderValueClampedLabelNot() {
        let d = ProgressRow.display(elapsed: 230, duration: 225)
        XCTAssertEqual(d.sliderValue, 225)
        XCTAssertEqual(d.elapsedLabel, "3:50")
    }

    func testNonFiniteElapsed() {
        let d = ProgressRow.display(elapsed: .nan, duration: 225)
        XCTAssertEqual(d.elapsedLabel, ProgressRow.placeholder)
        XCTAssertEqual(d.sliderValue, 0)
    }

    // MARK: PendingSeek – nach dem Loslassen nicht zurückspringen

    private let t0 = Date(timeIntervalSince1970: 1000)

    private func info(stamp: Date, title: String = "A") -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: "X", album: nil, appBundleID: "com.apple.Music", isPlaying: true,
                       duration: 225, elapsedAtStamp: 10, stamp: stamp, rate: 1, contentID: nil, artworkBase64: nil)
    }

    func testPendingSeekHoldsUntilNewStamp() {
        let i = info(stamp: t0)
        let p = ProgressRow.PendingSeek(value: 120, info: i, released: t0)
        XCTAssertEqual(p.value(for: i, now: t0.addingTimeInterval(0.5)), 120)
        XCTAssertNil(p.value(for: info(stamp: t0.addingTimeInterval(1)), now: t0.addingTimeInterval(0.5)))
    }

    func testPendingSeekDroppedOnTrackChange() {
        let p = ProgressRow.PendingSeek(value: 120, info: info(stamp: t0), released: t0)
        XCTAssertNil(p.value(for: info(stamp: t0, title: "B"), now: t0))
    }

    /// Kommt nie eine neue Meldung (Befehl verloren), darf die Zeit nicht ewig stehen.
    func testPendingSeekExpires() {
        let i = info(stamp: t0)
        let p = ProgressRow.PendingSeek(value: 120, info: i, released: t0)
        XCTAssertNil(p.value(for: i, now: t0.addingTimeInterval(ProgressRow.PendingSeek.maxWait + 0.1)))
    }
}
