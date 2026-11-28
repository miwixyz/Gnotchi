import AppKit
import XCTest

// SYNTHETISCH – Testdateien werden in einem frischen Temp-Ordner angelegt (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.42 (G64): Mehrfachauswahl per Umschalt/Befehl-Klick und „Rückgängig“ nach Entfernen und Leeren.
@MainActor
final class ShelfSelectionUndoTests: XCTestCase {
    private struct Fixture {
        let link: ShelfLink
        let store: ShelfStore
        let activity: ActivityModel
    }

    private func makeLink(count: Int = 4) -> Fixture {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-selundo-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = (0..<count).map { i -> URL in
            let u = dir.appendingPathComponent("datei\(i).txt")
            FileManager.default.createFile(atPath: u.path, contents: Data("x".utf8))
            return u
        }
        let prefs = Preferences(defaults: throwawayDefaults("gnotchi-selundo"))
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let activity = ActivityModel(media: NowPlayingModel())
        let link = ShelfLink(activity: activity, prefs: prefs, store: store)
        activity.shelf = link
        for u in urls { link.drop([u]) }   // einzeln, damit jede Datei eine eigene Kachel ist
        activity.clearNotice()
        return Fixture(link: link, store: store, activity: activity)
    }

    func testPlainClickDoesNotSelectAndModifierClickToggles() {
        let f = makeLink()
        let a = [f.store.items[0]], b = [f.store.items[1]]
        f.link.click(a, modifiers: [])
        XCTAssertTrue(f.link.selected.isEmpty)
        f.link.click(a, modifiers: .shift)
        f.link.click(b, modifiers: .command)
        XCTAssertEqual(f.link.selected.count, 2)
        f.link.click(a, modifiers: .shift)   // zweiter Klick nimmt heraus
        XCTAssertEqual(f.link.selected, [b[0].id])
        f.link.click(a, modifiers: [])       // normaler Klick hebt alles auf
        XCTAssertTrue(f.link.selected.isEmpty)
    }

    func testActionsUseSelectionOtherwiseEverything() {
        let f = makeLink()
        XCTAssertEqual(f.link.urls().count, 4)
        f.link.click([f.store.items[2]], modifiers: .shift)
        XCTAssertEqual(f.link.urls().map(\.lastPathComponent), ["datei2.txt"])
        XCTAssertEqual(f.link.actionItems.count, 1)
    }

    func testRemoveSelectionThenUndoBringsThemBack() {
        let f = makeLink()
        f.link.click([f.store.items[0]], modifiers: .shift)
        f.link.click([f.store.items[1]], modifiers: .shift)
        f.link.removeSelection()
        XCTAssertEqual(f.store.items.count, 2)
        XCTAssertTrue(f.link.selected.isEmpty)
        XCTAssertEqual(f.activity.notice?.action, .undoShelf)
        f.activity.performNoticeAction()
        XCTAssertEqual(f.store.items.count, 4)
        XCTAssertEqual(f.activity.shelfItems.count, 4)
    }

    func testClearThenUndoRestoresAllButOnlyOnce() {
        let f = makeLink()
        f.link.clear()
        XCTAssertTrue(f.store.items.isEmpty)
        f.link.undoRemove()
        XCTAssertEqual(f.store.items.count, 4)
        f.link.undoRemove()   // zweiter Aufruf legt nichts doppelt an
        XCTAssertEqual(f.store.items.count, 4)
    }

    func testUndoRespectsTheLimitAndOnlyLastActionCounts() {
        let f = makeLink()
        f.link.remove([f.store.items[0]])
        f.link.remove([f.store.items[0]])   // zweiter Vorgang ersetzt den ersten
        XCTAssertEqual(f.store.items.count, 2)
        f.link.undoRemove()
        XCTAssertEqual(f.store.items.count, 3)
    }

    /// Entfernte eigene Kopien (Dateiversprechen) bleiben nur für die Rückgängig-Frist auf der Platte.
    func testOwnCopyIsDeletedAfterUndoWindowButKeptByUndo() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-copy-\(UUID().uuidString.prefix(6))")
        let store = ShelfStore(directory: dir)
        let folder = try XCTUnwrap(store.newCopyFolder())
        let file = folder.appendingPathComponent("anhang.txt")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        store.release(folder)
        XCTAssertEqual(store.add([file]), 1)
        let item = store.items[0]
        let gone = store.removeKeepingCopies([item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "für Rückgängig noch da")
        store.restore(gone)                       // Rückgängig → bleibt
        store.discardKept(gone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let gone2 = store.removeKeepingCopies([item.id])
        store.discardKept(gone2)                  // Frist um → weg
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testSelectionIsPrunedWhenItemsDisappear() {
        let f = makeLink()
        f.link.click([f.store.items[0]], modifiers: .shift)
        f.link.remove([f.store.items[0]])
        XCTAssertTrue(f.link.selected.isEmpty)
    }
}
