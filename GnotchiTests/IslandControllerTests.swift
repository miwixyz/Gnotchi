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
        XCTAssertTrue(IslandController.coversScreen(windows: [.init(layer: 0, bounds: target, isRegularApp: true)], target: target))
    }

    func testMaximizedWindowBelowMenuBarIsNotFullscreen() {
        let target = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let zoomed = CGRect(x: 0, y: 32, width: 1470, height: 924)
        XCTAssertFalse(IslandController.coversScreen(windows: [.init(layer: 0, bounds: zoomed, isRegularApp: true)], target: target))
    }

    func testNonNormalLayerIsIgnored() {
        // Menüleiste, Dock, Schreibtisch-Bild u. ä. liegen nicht auf Ebene 0.
        let target = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let windows: [IslandController.WindowInfo] = [.init(layer: 24, bounds: target, isRegularApp: true),
                                                      .init(layer: -2_147_483_624, bounds: target, isRegularApp: true)]
        XCTAssertFalse(IslandController.coversScreen(windows: windows, target: target))
    }

    func testFullscreenOnOtherScreenDoesNotCount() {
        let main = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let ext = CGRect(x: 1470, y: -484, width: 2560, height: 1440)
        XCTAssertFalse(IslandController.coversScreen(windows: [.init(layer: 0, bounds: ext, isRegularApp: true)], target: main))
        XCTAssertTrue(IslandController.coversScreen(windows: [.init(layer: 0, bounds: ext, isRegularApp: true)], target: ext))
    }

    func testHalfPointRoundingStillCounts() {
        let target = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let rounded = CGRect(x: 0, y: 0, width: 1470.5, height: 956)
        XCTAssertTrue(IslandController.coversScreen(windows: [.init(layer: 0, bounds: rounded, isRegularApp: true)], target: target))
    }

    func testNonRegularFullScreenWindowIsIgnored() {
        // Gemessen 18.10.: Seams Abdunkel-Fenster liegt auf Ebene 0 und deckt den Bildschirm exakt ab.
        let target = CGRect(x: 0, y: 0, width: 1470, height: 956)
        XCTAssertFalse(IslandController.coversScreen(windows: [.init(layer: 0, bounds: target, isRegularApp: false)],
                                                     target: target))
    }

    func testNoWindowsIsNotFullscreen() {
        XCTAssertFalse(IslandController.coversScreen(windows: [], target: mainFrame))
    }

    // MARK: Fensterliste lesen

    private func entry(pid: Int32, layer: Int = 0) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 1470, height: 956).dictionaryRepresentation]
    }

    func testOwnWindowsNeverCountAsRegular() {
        let w = IslandController.windows(from: [entry(pid: 42)], ownPID: 42) { _ in true }
        XCTAssertEqual(w.count, 1)
        XCTAssertFalse(w[0].isRegularApp)
    }

    func testRegularAppClassifiedOncePerPID() {
        var asked: [Int32] = []
        let list = [entry(pid: 7), entry(pid: 7, layer: 3), entry(pid: 9)]
        let w = IslandController.windows(from: list, ownPID: 42) { pid in asked.append(pid); return pid == 7 }
        XCTAssertEqual(asked, [7, 9])
        XCTAssertEqual(w.map { $0.isRegularApp }, [true, true, false])
        XCTAssertEqual(w.map { $0.layer }, [0, 3, 0])
        XCTAssertEqual(w[0].bounds, CGRect(x: 0, y: 0, width: 1470, height: 956))
    }

    func testEntryWithoutPIDOrBoundsIsSkipped() {
        let broken: [String: Any] = [kCGWindowLayer as String: 0]
        XCTAssertTrue(IslandController.windows(from: [broken], ownPID: 42) { _ in true }.isEmpty)
    }

    // MARK: Bildschirm-Änderungen

    func testLayoutsChanged() {
        let a = IslandGeometry.layout(for: .init(frame: mainFrame, safeTop: 32, auxLeftWidth: 645.5, auxRightWidth: 645.5))
        let b = IslandGeometry.layout(for: .init(frame: extFrame, safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil))
        XCTAssertFalse(IslandController.layoutsChanged(old: [1: a, 2: b], new: [2: b, 1: a]))
        XCTAssertTrue(IslandController.layoutsChanged(old: [1: a], new: [1: a, 2: b]))     // Bildschirm dazu
        XCTAssertTrue(IslandController.layoutsChanged(old: [1: a, 2: b], new: [1: a]))     // Bildschirm weg
        XCTAssertTrue(IslandController.layoutsChanged(old: [1: a], new: [1: b]))           // Auflösung geändert
        XCTAssertTrue(IslandController.layoutsChanged(old: [1: a], new: [3: a]))           // anderer Bildschirm
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
