import XCTest
@testable import Gnotchi

/// 0.5.0 Band: Seitenwechsel, Modus, Geometrie.
@MainActor
final class BandTests: XCTestCase {

    func testPagesRotateEveryFourSeconds() {
        let pages = BandPage.pages(media: true, event: true, timer: true)
        XCTAssertEqual(pages, [.media, .event, .timer])
        let t = Date(timeIntervalSince1970: 1_800_000_000)   // durch 4 teilbar
        XCTAssertEqual(BandPage.current(pages, at: t), BandPage.current(pages, at: t.addingTimeInterval(3.9)))
        XCTAssertNotEqual(BandPage.current(pages, at: t), BandPage.current(pages, at: t.addingTimeInterval(4)))
        XCTAssertNil(BandPage.current([], at: t))
    }

    func testBandStaysLikeExpanded() {
        XCTAssertEqual(IslandController.nextMode(current: .band, notice: false), .band)
        XCTAssertEqual(IslandController.nextMode(current: .band, notice: true), .band, "Hinweis verdrängt das Band nicht")
        XCTAssertEqual(IslandController.nextMode(current: .band, notice: false, alarm: true), .compact,
                       "Alarm: klickbare kleine Insel")
    }

    func testBandGeometry() throws {
        let notch = IslandGeometry.layout(for: IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 645.5, auxRightWidth: 645.5))
        let n = try XCTUnwrap(notch.notch)
        XCTAssertEqual(notch.band.width, n.width + 2 * IslandGeometry.bandWing)
        XCTAssertEqual(notch.band.height, n.height, "Menüleisten-Höhe, nicht nach unten")
        XCTAssertEqual(notch.band.midX, n.midX)
        let pill = IslandGeometry.layout(for: IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil))
        XCTAssertEqual(pill.band.width, IslandGeometry.bandPillWidth)
        XCTAssertEqual(pill.band.height, IslandGeometry.pillSize.height)
        XCTAssertEqual(IslandController.panelFrame(mode: .band, layout: pill), pill.band)
        let tall = IslandGeometry.layout(for: IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 3440, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil,
            menuBarHeight: 30))
        XCTAssertEqual(tall.band.height, 30, "so hoch wie die Menüleiste")
        XCTAssertEqual(tall.band.maxY, 1440, "oben bündig")
        XCTAssertEqual(tall.compact.height, IslandGeometry.pillSize.height, "kleine Insel unverändert")
    }
}
