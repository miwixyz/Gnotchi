import AppKit
import XCTest

/// Rechtsklick auf die Insel (Michael, 18.10.): Einstellungen und Hilfe wie im Menüleisten-Menü.
@MainActor
final class IslandContextMenuTests: XCTestCase {

    func testMenuItemsMatchMenuBarMenu() {
        XCTAssertEqual(IslandController.contextMenuItems.map(\.title), ["Einstellungen …", "Hilfe …"])
        XCTAssertEqual(IslandController.contextMenuItems.map(\.windowID),
                       [AppModel.WindowID.settings, AppModel.WindowID.help])
        XCTAssertEqual(AppModel.WindowID.settings, "einstellungen")
        XCTAssertEqual(AppModel.WindowID.help, "hilfe")
    }

    /// Rechtsklick und Ctrl-Klick öffnen das Menü; ein normaler Klick bleibt bei den Tasten/beim Spulen.
    func testContextClickDetection() {
        XCTAssertTrue(IslandController.isContextClick(type: .rightMouseDown, modifiers: []))
        XCTAssertTrue(IslandController.isContextClick(type: .leftMouseDown, modifiers: .control))
        XCTAssertTrue(IslandController.isContextClick(type: .leftMouseDown, modifiers: [.control, .shift]))
        XCTAssertFalse(IslandController.isContextClick(type: .leftMouseDown, modifiers: []))
        XCTAssertFalse(IslandController.isContextClick(type: .leftMouseDown, modifiers: .command))
        XCTAssertFalse(IslandController.isContextClick(type: .mouseMoved, modifiers: .control))
    }

    /// Die Insel hat kein eigenes `openWindow` (Panel außerhalb einer Szene): AppModel reicht die
    /// Fenster-ID an die aus der Szene gemeldete Aktion weiter.
    func testShowWindowRoutesToRegisteredOpener() {
        let model = AppModel(prefs: Preferences(defaults: UserDefaults(suiteName: "dev.mwlr.gnotchi.tests.ctx")!),
                             allowStart: false)
        var opened: [String] = []
        model.registerWindowOpener { opened.append($0) }
        model.showWindow(AppModel.WindowID.help)
        XCTAssertEqual(opened, ["hilfe"])
    }
}
