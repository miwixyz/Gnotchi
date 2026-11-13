import XCTest

// SYNTHETISCH – Testdateien werden in einem frischen Temp-Ordner angelegt (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.24 Ablage-Stapel (Michael 13.11.): in einem Zug abgelegte Dateien bilden eine Kachel und ziehen zusammen raus.
@MainActor
final class ShelfStackTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-stack-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func file(_ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("Inhalt".utf8))
        return url
    }

    func testDropOfSeveralFilesBecomesOneStackThatPersists() {
        let storeDir = dir.appendingPathComponent("store")
        let a = file("a.txt"), b = file("b.txt"), c = file("c.txt"), single = file("d.txt")
        let store = ShelfStore(directory: storeDir)
        XCTAssertEqual(store.add([single], stacked: true), 1)
        XCTAssertEqual(store.add([a, b, c], stacked: true), 3)
        let stacks = ShelfStore.stacks(store.items)
        XCTAssertEqual(stacks.map { $0.items.map(\.name) }, [["d.txt"], ["a.txt", "b.txt", "c.txt"]],
                       "eine Datei bleibt einzeln, drei in einem Zug werden eine Kachel")
        XCTAssertNil(store.items[0].stack)
        XCTAssertEqual(ShelfStore.stacks(ShelfStore(directory: storeDir).items), stacks, "Stapel übersteht den Neustart")
    }

    func testOnlyNewlyAddedFilesJoinTheStack() {
        let a = file("a.txt"), b = file("b.txt"), c = file("c.txt")
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        store.add([a])
        XCTAssertEqual(store.add([a, b, c], stacked: true), 2)
        XCTAssertEqual(ShelfStore.stacks(store.items).map(\.items.count), [1, 2], "schon abgelegte Datei bleibt einzeln")
    }

    func testScreenshotsAndUnstackedAddsStaySingle() {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        store.add([file("a.png"), file("b.png")], screenshotAt: Date())
        XCTAssertEqual(ShelfStore.stacks(store.items).count, 2)
    }

    func testUnstackKeepsEntriesAsSingles() {
        let storeDir = dir.appendingPathComponent("store")
        let store = ShelfStore(directory: storeDir)
        store.add([file("a.txt"), file("b.txt")], stacked: true)
        let stack = try? XCTUnwrap(store.items.first?.stack)
        store.unstack(stack ?? UUID())
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(ShelfStore.stacks(ShelfStore(directory: storeDir).items).count, 2)
    }

    func testDecodeIgnoresBrokenStackButKeepsEntry() {
        let mark = Data([1, 2, 3]).base64EncodedString()
        let json = #"{"v":1,"items":[{"id":"\#(UUID().uuidString)","bookmark":"\#(mark)","name":"a","stack":"kaputt"},"#
            + #"{"id":"\#(UUID().uuidString)","bookmark":"\#(mark)","name":"b","stack":42}]}"#
        let items = ShelfStore.decode(Data(json.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.stack == nil })
    }
}
