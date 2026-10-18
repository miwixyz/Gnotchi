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

    // Gemessen 18.10. am MacBook Air M5 (macOS 27.0.1), CGWindow-Koordinaten (Ursprung oben links).
    private let notchScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let notchInset: CGFloat = 32          // Notch-Höhe = safeTop
    private let plainScreen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    private func covers(_ bounds: CGRect, on target: CGRect, topInset: CGFloat,
                        layer: Int = 0, regular: Bool = true) -> Bool {
        IslandController.coversScreen(windows: [.init(layer: layer, bounds: bounds, isRegularApp: regular)],
                                      target: target, topInset: topInset)
    }

    func testMeasuredFullscreenBelowNotchCounts() {
        // Vollbild-Fenster beginnt unter Notch/Menüleiste, nicht am Bildschirmrand.
        XCTAssertTrue(covers(CGRect(x: 0, y: 33, width: 1470, height: 923), on: notchScreen, topInset: notchInset))
    }

    func testMaximizedWithDockIsNotFullscreen() {
        XCTAssertFalse(covers(CGRect(x: 0, y: 33, width: 1470, height: 875), on: notchScreen, topInset: notchInset))
    }

    func testFullFrameRegularWindowCounts() {
        XCTAssertTrue(covers(notchScreen, on: notchScreen, topInset: notchInset))
        XCTAssertTrue(covers(plainScreen, on: plainScreen, topInset: 0))
    }

    func testMaximizedWithGapIsNotFullscreen() {
        // Seams Maximieren lässt rundum einen Rand.
        XCTAssertFalse(covers(CGRect(x: 5, y: 38, width: 1460, height: 880), on: notchScreen, topInset: notchInset))
    }

    func testScreenWithoutNotchNeedsFullFrame() {
        XCTAssertFalse(covers(CGRect(x: 0, y: 25, width: 2560, height: 1415), on: plainScreen, topInset: 0))
    }

    func testTopBeyondInsetIsNotFullscreen() {
        XCTAssertFalse(covers(CGRect(x: 0, y: 40, width: 1470, height: 916), on: notchScreen, topInset: notchInset))
    }

    func testKnownLimitMaximizedWithHiddenDockOnNotchScreen() {
        // Bekannte Grenze: maximiert bei ausgeblendetem Dock ist an der Lage nicht von Vollbild zu
        // unterscheiden → Insel blendet aus. Bewusst hingenommen.
        XCTAssertTrue(covers(CGRect(x: 0, y: 33, width: 1470, height: 923), on: notchScreen, topInset: notchInset))
    }

    func testNonNormalLayerIsIgnored() {
        // Menüleiste, Dock, Schreibtisch-Bild u. ä. liegen nicht auf Ebene 0.
        XCTAssertFalse(covers(notchScreen, on: notchScreen, topInset: notchInset, layer: 24))
        XCTAssertFalse(covers(notchScreen, on: notchScreen, topInset: notchInset, layer: -2_147_483_624))
    }

    func testFullscreenOnOtherScreenDoesNotCount() {
        let ext = CGRect(x: 1470, y: -484, width: 2560, height: 1440)
        XCTAssertFalse(covers(ext, on: notchScreen, topInset: notchInset))
        XCTAssertTrue(covers(ext, on: ext, topInset: 0))
    }

    func testHalfPointRoundingStillCounts() {
        XCTAssertTrue(covers(CGRect(x: 0, y: 0, width: 1470.5, height: 956), on: notchScreen, topInset: notchInset))
    }

    func testNonRegularFullScreenWindowIsIgnored() {
        // Gemessen 18.10.: Seams Abdunkel-Fenster liegt auf Ebene 0 und deckt den Bildschirm exakt ab.
        XCTAssertFalse(covers(notchScreen, on: notchScreen, topInset: notchInset, regular: false))
    }

    func testNoWindowsIsNotFullscreen() {
        XCTAssertFalse(IslandController.coversScreen(windows: [], target: mainFrame, topInset: 0))
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
