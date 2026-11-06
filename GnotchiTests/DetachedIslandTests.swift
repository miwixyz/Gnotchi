import XCTest
@testable import Gnotchi

/// 0.22.0 abgekoppelte große Insel: Lage, Einrasten, Fläche gegen Zuklappen.
final class DetachedIslandTests: XCTestCase {
    /// Pille 180 × 24 oben mittig auf 3440 × 1440, sichtbarer Bereich unter einer 30-pt-Menüleiste.
    private let pill = CGRect(x: 1630, y: 1416, width: 180, height: 24)
    private let visible = CGRect(x: 0, y: 0, width: 3440, height: 1410)
    private let size = CGSize(width: 600, height: 110)

    func testBaseHangs8ptBelowPillCentered() {
        let f = DetachedIsland.frame(compact: pill, size: size, offset: .zero, visible: visible)
        XCTAssertEqual(f.midX, pill.midX)
        XCTAssertEqual(f.maxY, pill.minY - 8)
        XCTAssertEqual(f.size, size)
    }

    func testOffsetMovesTopCenterAndGrowsDown() {
        let o = CGSize(width: 500, height: -400)
        let small = DetachedIsland.frame(compact: pill, size: size, offset: o, visible: visible)
        let tall = DetachedIsland.frame(compact: pill, size: CGSize(width: 600, height: 300), offset: o, visible: visible)
        XCTAssertEqual(small.maxY, tall.maxY, "Oberkante bleibt, die Insel wächst nach unten")
        XCTAssertEqual(small.midX, pill.midX + 500)
    }

    func testClampedIntoVisibleAreaWithoutChangingOffset() {
        let o = CGSize(width: 3000, height: -1380)   // rechts unten über den Rand hinaus
        let f = DetachedIsland.frame(compact: pill, size: CGSize(width: 600, height: 300), offset: o, visible: visible)
        XCTAssertEqual(f.maxX, visible.maxX)
        XCTAssertEqual(f.minY, visible.minY)
        let up = DetachedIsland.frame(compact: pill, size: size, offset: CGSize(width: 0, height: 200), visible: visible)
        XCTAssertEqual(up.maxY, visible.maxY, "nicht in die Menüleiste")
    }

    func testOffsetFromDropAndSnap() {
        let base = DetachedIsland.frame(compact: pill, size: size, offset: .zero, visible: visible)
        XCTAssertEqual(DetachedIsland.offset(island: base.offsetBy(dx: 10, dy: -20), compact: pill), .zero, "≤ 24 pt rastet ein")
        XCTAssertEqual(DetachedIsland.offset(island: base.offsetBy(dx: 300, dy: -200), compact: pill),
                       CGSize(width: 300, height: -200))
    }

    func testZonesBridgeGapOnlyInBase() {
        let base = DetachedIsland.frame(compact: pill, size: size, offset: .zero, visible: visible)
        let zones = DetachedIsland.zones(compact: pill, island: base)
        XCTAssertTrue(DetachedIsland.contains(CGPoint(x: pill.midX, y: pill.minY - 4), zones), "Lücke zählt mit")
        XCTAssertFalse(DetachedIsland.contains(CGPoint(x: base.minX + 5, y: pill.minY - 4), zones), "neben der Pille nicht")
        let moved = base.offsetBy(dx: 800, dy: -500)
        let far = DetachedIsland.zones(compact: pill, island: moved)
        XCTAssertEqual(far.count, 2, "verschoben: keine Brücke")
        XCTAssertTrue(DetachedIsland.contains(CGPoint(x: moved.midX, y: moved.midY), far))
        XCTAssertFalse(DetachedIsland.contains(CGPoint(x: pill.midX, y: pill.minY - 4), far))
        XCTAssertEqual(DetachedIsland.zones(compact: pill, island: nil), [pill])
    }

    func testOffsetStoreRoundTripAndReset() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "DetachedIslandTests"))
        defer { d.removePersistentDomain(forName: "DetachedIslandTests") }
        XCTAssertEqual(DetachedIsland.offset(in: d), .zero)
        DetachedIsland.setOffset(CGSize(width: 120, height: -340), in: d)
        XCTAssertEqual(DetachedIsland.offset(in: d), CGSize(width: 120, height: -340))
        DetachedIsland.setOffset(.zero, in: d)
        XCTAssertNil(d.object(forKey: DetachedIsland.offsetXKey))
        d.set(Double.infinity, forKey: DetachedIsland.offsetXKey)
        XCTAssertEqual(DetachedIsland.offset(in: d), .zero, "kaputter Wert → Grundlage")
    }

    func testGrowAnchorPointsAtPill() {
        let panel = DetachedIsland.frame(compact: pill, size: size, offset: .zero, visible: visible).insetBy(dx: -20, dy: -20)
        let a = DetachedIsland.growAnchor(compact: pill, panel: panel)
        XCTAssertEqual(a.x, 0.5, accuracy: 0.001)
        XCTAssertLessThanOrEqual(a.y, 0.001, "Pille sitzt am oberen Rand des Panels oder darüber")
    }

    @MainActor
    func testDetachedSizeIsUniformWidthAndWithoutNotchStrip() {
        let activity = ActivityModel(media: NowPlayingModel())
        let s = IslandController.detachedSize(activity)
        XCTAssertEqual(s.width, 600)
        XCTAssertGreaterThan(s.height, 0)
        activity.showTimerPicker()
        XCTAssertGreaterThanOrEqual(IslandController.detachedSize(activity).height, IslandGeometry.timerPickerHeight)
    }
}
