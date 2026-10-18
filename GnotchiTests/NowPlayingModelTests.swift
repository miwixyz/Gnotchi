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
}
