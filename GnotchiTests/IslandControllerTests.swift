import CoreGraphics
import XCTest
@testable import Gnotchi

/// Reine Rechnungen des IslandControllers: Koordinaten, Vollbild-Erkennung, Panelgröße.
final class IslandControllerTests: XCTestCase {

    // Hauptbildschirm 1470 × 956 (MacBook Air), rechts daneben 2560 × 1440, unten bündig.
    private let primaryHeight: CGFloat = 956
    private let mainFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let extFrame = CGRect(x: 1470, y: 0, width: 2560, height: 1440)

    // MARK: AppKit → CGWindow-Koordinaten

    func testPrimaryScreenMapsOntoItself() {
        XCTAssertEqual(IslandController.cgWindowRect(fromAppKit: mainFrame, primaryHeight: primaryHeight), mainFrame)
    }

    func testTallerSecondScreenGetsNegativeY() {
        // Ragt 484 pt über den Hauptbildschirm hinaus → in CG-Koordinaten (Ursprung oben) y = −484.
        let r = IslandController.cgWindowRect(fromAppKit: extFrame, primaryHeight: primaryHeight)
        XCTAssertEqual(r, CGRect(x: 1470, y: -484, width: 2560, height: 1440))
    }

    func testScreenBelowPrimaryGetsPositiveY() {
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let r = IslandController.cgWindowRect(fromAppKit: below, primaryHeight: primaryHeight)
        XCTAssertEqual(r, CGRect(x: 0, y: 956, width: 1920, height: 1080))
    }

    // MARK: Vollbild-Erkennung

    func testNormalWindowCoveringScreenIsFullscreen() {
        let target = CGRect(x: 0, y: 0, width: 1470, height: 956)
        XCTAssertTrue(IslandController.coversScreen(windows: [(layer: 0, bounds: target)], target: target))
    }

    func testMaximizedWindowBelowMenuBarIsNotFullscreen() {
        let target = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let zoomed = CGRect(x: 0, y: 32, width: 1470, height: 924)
        XCTAssertFalse(IslandController.coversScreen(windows: [(layer: 0, bounds: zoomed)], target: target))
    }

    func testNonNormalLayerIsIgnored() {
        // Menüleiste, Dock, Schreibtisch-Bild u. ä. liegen nicht auf Ebene 0.
        let target = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let windows: [(layer: Int, bounds: CGRect)] = [(layer: 24, bounds: target), (layer: -2_147_483_624, bounds: target)]
        XCTAssertFalse(IslandController.coversScreen(windows: windows, target: target))
    }

    func testFullscreenOnOtherScreenDoesNotCount() {
        let main = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let ext = CGRect(x: 1470, y: -484, width: 2560, height: 1440)
        XCTAssertFalse(IslandController.coversScreen(windows: [(layer: 0, bounds: ext)], target: main))
        XCTAssertTrue(IslandController.coversScreen(windows: [(layer: 0, bounds: ext)], target: ext))
    }

    func testHalfPointRoundingStillCounts() {
        let target = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let rounded = CGRect(x: 0, y: 0, width: 1470.5, height: 956)
        XCTAssertTrue(IslandController.coversScreen(windows: [(layer: 0, bounds: rounded)], target: target))
    }

    func testNoWindowsIsNotFullscreen() {
        XCTAssertFalse(IslandController.coversScreen(windows: [], target: mainFrame))
    }

    // MARK: Panelgröße je Zustand

    private let layout = IslandGeometry.Layout(
        notch: CGRect(x: 645.5, y: 924, width: 179, height: 32),
        compact: CGRect(x: 605.5, y: 924, width: 259, height: 32),
        expanded: CGRect(x: 545, y: 814, width: 380, height: 142))

    func testPanelFrameFollowsMode() {
        XCTAssertEqual(IslandController.panelFrame(mode: .compact, layout: layout), layout.compact)
        XCTAssertEqual(IslandController.panelFrame(mode: .expanded, layout: layout), layout.expanded)
        XCTAssertNil(IslandController.panelFrame(mode: .hidden, layout: layout))
    }
}
