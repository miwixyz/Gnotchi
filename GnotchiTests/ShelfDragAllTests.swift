import XCTest
@testable import Gnotchi

/// „Alle ziehen“ (0.18): nimmt genau die mitgezogenen Einträge aus der Ablage, und nur mit Schalter.
@MainActor
final class ShelfDragAllTests: XCTestCase {
    private struct Fixture {
        let link: ShelfLink
        let store: ShelfStore
        let activity: ActivityModel
    }

    /// Wie in der App nach `ShelfLink.start()`: Insel kennt die Ablage, Hinweis vom Ablegen ist weg.
    private func makeLink(files: [String], removeOnDrag: Bool) -> Fixture {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-dragall-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = files.map { name -> URL in
            let u = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: u.path, contents: Data("x".utf8))
            return u
        }
        let prefs = Preferences(defaults: UserDefaults(suiteName: "gnotchi-dragall-\(UUID().uuidString)") ?? .standard)
        prefs.shelfRemoveOnDrag = removeOnDrag
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let activity = ActivityModel(media: NowPlayingModel())
        let link = ShelfLink(activity: activity, prefs: prefs, store: store)
        activity.shelf = link
        link.drop(urls)
        activity.clearNotice()
        return Fixture(link: link, store: store, activity: activity)
    }

    func testDraggedOutAllRemovesExactlyTheDraggedItems() {
        let f = makeLink(files: ["a.txt", "b.txt", "c.txt"], removeOnDrag: true)
        let link = f.link, store = f.store, activity = f.activity
        XCTAssertEqual(store.items.count, 3)
        let dragged = Array(store.items.prefix(2))
        link.draggedOut(dragged)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertFalse(store.items.contains { item in dragged.contains { $0.id == item.id } })
        XCTAssertEqual(activity.shelfItems.count, 1)
    }

    func testDraggedOutAllKeepsEverythingWhenSwitchIsOff() {
        let f = makeLink(files: ["a.txt", "b.txt"], removeOnDrag: false)
        let link = f.link, store = f.store
        link.draggedOut(store.items)
        XCTAssertEqual(store.items.count, 2)
    }

    func testDraggingEverythingEmptiesAndDeactivatesShelf() {
        let f = makeLink(files: ["a.txt", "b.txt"], removeOnDrag: true)
        let link = f.link, store = f.store, activity = f.activity
        link.draggedOut(store.items)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(activity.shelfActive)
    }

    /// Ziel meldet „kopiert“, legt aber nichts an → Hinweis mit „Zurückholen“ bringt genau die Einträge zurück.
    func testRestoreBringsBackExactlyTheDraggedItems() {
        let f = makeLink(files: ["a.txt", "b.txt", "c.txt"], removeOnDrag: true)
        let link = f.link, store = f.store, activity = f.activity
        let before = store.items
        let dragged = Array(before.prefix(2))
        link.draggedOut(dragged)
        XCTAssertEqual(activity.notice?.action, .restoreShelf)
        XCTAssertEqual(activity.notice?.subtitle, "2 Dateien")
        activity.performNoticeAction()
        XCTAssertNil(activity.notice)
        XCTAssertEqual(Set(store.items.map(\.id)), Set(before.map(\.id)))
        XCTAssertEqual(activity.shelfItems.count, 3)
        // Zweiter Klick (oder alter Hinweis) legt nichts doppelt ab.
        link.restoreLastDrag()
        XCTAssertEqual(store.items.count, 3)
    }

    func testRestoreAfterEmptyingTheShelf() {
        let f = makeLink(files: ["a.txt", "b.txt"], removeOnDrag: true)
        let link = f.link, store = f.store, activity = f.activity
        link.draggedOut(store.items)
        XCTAssertTrue(store.items.isEmpty)
        activity.performNoticeAction()
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(activity.shelfItems.count, 2)
    }

    func testNoNoticeWhenSwitchIsOffAndSingleWording() {
        let f = makeLink(files: ["a.txt", "b.txt"], removeOnDrag: false)
        let link = f.link, store = f.store, activity = f.activity
        link.draggedOut(store.items)
        XCTAssertNil(activity.notice)
        let f2 = makeLink(files: ["a.txt"], removeOnDrag: true)
        let link2 = f2.link, store2 = f2.store, activity2 = f2.activity
        link2.draggedOut(store2.items[0])
        XCTAssertEqual(activity2.notice?.subtitle, "1 Datei")
    }

    func testDragSourceTakesAllURLsAndSingleStaysSingle() {
        let a = URL(fileURLWithPath: "/tmp/a"), b = URL(fileURLWithPath: "/tmp/b")
        XCTAssertEqual(DragSource(urls: [a, b], onEnded: { _ in }, menu: { _ in nil }).urls, [a, b])
        XCTAssertEqual(DragSource(url: a, onEnded: { _ in }, menu: { _ in nil }).urls, [a])
        XCTAssertEqual(DragSource(url: nil, onEnded: { _ in }, menu: { _ in nil }).urls, [])
    }
}
