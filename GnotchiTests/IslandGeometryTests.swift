import CoreGraphics
import XCTest
@testable import Gnotchi

/// Spezifikation „Aufbau 4“: Lage aus den Notch-Maßen; ohne Notch Pille 180 × 24 oben mittig.
final class IslandGeometryTests: XCTestCase {

    // MacBook Air 13": 1470 × 956, Notch ~ 185 breit, 32 hoch (Annahme aus dem Plan).
    private let mac = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 642.5, auxRightWidth: 642.5)
    // Gemessen am MacBook Air M5 (macOS 27.0.1, 18.10.): Notch 179 breit, Seitenflächen je 645.5.
    private let measured = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 645.5, auxRightWidth: 645.5)
    private let ext = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil)

    func testNotchRect() throws {
        let n = try XCTUnwrap(IslandGeometry.layout(for: mac).notch)
        XCTAssertEqual(n.width, 185, accuracy: 0.5)
        XCTAssertEqual(n.height, 32)
        XCTAssertEqual(n.maxY, 956)
        XCTAssertEqual(n.midX, 735, accuracy: 0.5)
    }

    func testMeasuredNotchRect() throws {
        let n = try XCTUnwrap(IslandGeometry.layout(for: measured).notch)
        XCTAssertEqual(n.width, 179, accuracy: 0.01)
        XCTAssertEqual(n.height, 32)
        XCTAssertEqual(n.maxY, 956)
        XCTAssertEqual(n.midX, 735, accuracy: 0.01)
    }

    func testCompactWrapsNotchWithWings() throws {
        let l = IslandGeometry.layout(for: mac)
        let n = try XCTUnwrap(l.notch)
        XCTAssertEqual(l.compact.width, n.width + 2 * IslandGeometry.wing, accuracy: 0.5)
        XCTAssertEqual(l.compact.maxY, 956)
        XCTAssertEqual(l.compact.midX, n.midX, accuracy: 0.5)
    }

    func testPillWithoutNotch() {
        let l = IslandGeometry.layout(for: ext)
        XCTAssertNil(l.notch)
        XCTAssertEqual(l.compact.size, CGSize(width: 180, height: 24))
        XCTAssertEqual(l.compact.midX, 1470 + 1280, accuracy: 0.5)
        XCTAssertEqual(l.compact.maxY, 1440)
    }

    func testExpandedCenteredAndInside() {
        for m in [mac, measured, ext] {
            let l = IslandGeometry.layout(for: m)
            XCTAssertEqual(l.expanded.width, IslandGeometry.expandedSize.width)
            XCTAssertEqual(l.expanded.midX, l.compact.midX, accuracy: 0.5)
            XCTAssertEqual(l.expanded.maxY, m.frame.maxY)
            XCTAssertTrue(m.frame.contains(l.expanded))
        }
    }

    /// Notch nicht mittig (ungleiche Seitenflächen): Kompakt folgt der Notch, nicht der Bildschirmmitte.
    func testOffCenterNotchCompactFollowsNotch() throws {
        let m = IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 600, auxRightWidth: 691)
        let l = IslandGeometry.layout(for: m)
        let n = try XCTUnwrap(l.notch)
        XCTAssertEqual(n.minX, 600)
        XCTAssertEqual(n.width, 179, accuracy: 0.01)
        XCTAssertNotEqual(n.midX, m.frame.midX)
        XCTAssertEqual(l.compact.midX, n.midX, accuracy: 0.01)
        XCTAssertEqual(l.expanded.midX, n.midX, accuracy: 0.01)
    }

    /// Notch nahe am Rand: Gross wird nach innen geschoben, bleibt im Bildschirm.
    func testExpandedClampedAtEdge() {
        let m = IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 100, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 50, auxRightWidth: 1241)
        let l = IslandGeometry.layout(for: m)
        XCTAssertEqual(l.expanded.minX, 100)
        XCTAssertEqual(l.expanded.width, IslandGeometry.expandedSize.width)
        XCTAssertTrue(m.frame.contains(l.expanded))
    }

    /// Bildschirm schmaler als die grosse Ansicht (z. B. virtuell 360 pt): Breite schrumpft auf die Bildschirmbreite.
    func testExpandedShrinksOnNarrowScreen() {
        let m = IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 40, y: 0, width: 360, height: 640), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil)
        let l = IslandGeometry.layout(for: m)
        XCTAssertEqual(l.expanded.width, 360)
        XCTAssertEqual(l.expanded.minX, 40)
        XCTAssertEqual(l.expanded.height, IslandGeometry.expandedSize.height)
        XCTAssertTrue(m.frame.contains(l.expanded))
    }
}
