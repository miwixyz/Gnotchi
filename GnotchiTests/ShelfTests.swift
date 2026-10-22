import Darwin
import XCTest
@testable import Gnotchi

// SYNTHETISCH – Testdateien werden in einem frischen Temp-Ordner angelegt (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.8.0 Dateiablage (SECURE-DESIGN G32): Speicher (Verweise, Grenzen, Prüfung), Ziehen-Zustand, ZIP im Prozess,
/// Formen und Ruhe-Insel.
@MainActor
final class ShelfTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-shelf-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func file(_ name: String, _ text: String = "Inhalt") -> URL {
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(text.utf8))
        return url
    }

    // MARK: Speicher

    func testAddDedupesPersistsAndFollowsRename() throws {
        let storeDir = dir.appendingPathComponent("store")
        let a = file("a.txt"), b = file("b.txt")
        let store = ShelfStore(directory: storeDir)
        XCTAssertEqual(store.add([a, b, a, URL(string: "https://example.com")!, dir.appendingPathComponent("fehlt.txt")]), 2,
                       "Doppelte, Webadressen und fehlende Dateien fallen weg")
        let attrs = try FileManager.default.attributesOfItem(atPath: storeDir.appendingPathComponent("ablage.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let moved = dir.appendingPathComponent("a-umbenannt.txt")
        try FileManager.default.moveItem(at: a, to: moved)
        let reloaded = ShelfStore(directory: storeDir)
        XCTAssertEqual(reloaded.items.map(\.name), ["a.txt", "b.txt"])
        XCTAssertEqual(reloaded.resolve(reloaded.items[0])?.lastPathComponent, "a-umbenannt.txt", "Verweis folgt dem Umbenennen")
        reloaded.remove(reloaded.items[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path), "Entfernen löscht nie die Datei")
        try FileManager.default.removeItem(at: b)
        reloaded.prune()
        XCTAssertTrue(reloaded.items.isEmpty, "verschwundene Datei fliegt raus")
    }

    func testLimitOf50() {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let urls = (0..<60).map { file("f\($0).txt") }
        XCTAssertEqual(store.add(urls), ShelfStore.maxItems)
        XCTAssertEqual(store.items.count, ShelfStore.maxItems)
    }

    func testDecodeRejectsGarbage() {
        XCTAssertTrue(ShelfStore.decode(Data("kein json".utf8)).isEmpty)
        // swiftlint:disable:next force_try
        XCTAssertTrue(ShelfStore.decode(try! JSONSerialization.data(withJSONObject: ["v": true, "items": []])).isEmpty)
        let bad: [[String: Any]] = [["id": "keine-uuid", "bookmark": "AAAA", "name": "x"],
                                    ["id": UUID().uuidString, "bookmark": "%%%", "name": "x"]]
        // swiftlint:disable:next force_try
        XCTAssertTrue(ShelfStore.decode(try! JSONSerialization.data(withJSONObject: ["v": 1, "items": bad])).isEmpty)
        XCTAssertTrue(ShelfStore.decode(Data(count: ShelfStore.maxFile + 1)).isEmpty)
        XCTAssertEqual(ShelfStore.cleanName("Böse\u{202E}datei.txt"), "Bösedatei.txt")
    }

    // MARK: Ziehen erkennen (G1: ohne Ereignis-Beobachter)

    func testDragStateOnlyWithPressedButtonNewCountAndFiles() {
        var s = DragWatcher.State(idleCount: 88)
        s.step(pressed: true, count: 88, hasFiles: false)
        XCTAssertFalse(s.dragging, "Klick ohne Ziehen (gemessen 22.10.: Zähler bleibt)")
        s.step(pressed: true, count: 89, hasFiles: false)
        XCTAssertFalse(s.dragging, "Text statt Datei")
        s.step(pressed: false, count: 89, hasFiles: false)
        s.step(pressed: true, count: 90, hasFiles: true)
        XCTAssertTrue(s.dragging)
        s.step(pressed: true, count: 90, hasFiles: true)
        XCTAssertTrue(s.dragging, "bleibt bis zum Loslassen")
        s.step(pressed: false, count: 90, hasFiles: false)
        XCTAssertFalse(s.dragging)
        XCTAssertEqual(s.idleCount, 90)
    }

    // MARK: ZIP (G32, G3: kein Kindprozess in Gnotchi – hier im Test nur zum Nachprüfen)

    func testEntriesRelativeSkipLinksAndRenameDuplicates() throws {
        let folder = dir.appendingPathComponent("Ordner")
        _ = file("Ordner/x.txt")
        _ = file("Ordner/sub/y.txt")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        let other = file("andere/Ordner")   // gleicher Name wie der Ordner
        let (list, links) = try ShelfZip.entries(for: [folder, other])
        XCTAssertEqual(links, 1)
        XCTAssertTrue(list.allSatisfy { !$0.path.hasPrefix("/") && !$0.path.split(separator: "/").contains("..") })
        XCTAssertEqual(Set(list.map(\.path)), ["Ordner", "Ordner/x.txt", "Ordner/sub", "Ordner/sub/y.txt", "Ordner 2"])
        XCTAssertEqual(ShelfZip.safeComponent(".."), "_")
        XCTAssertEqual(ShelfZip.safeComponent("a/b"), "a_b")
    }

    /// Review 22.10.: Ein Link, der nach dem Sammeln untergeschoben wird, wird beim Öffnen abgelehnt (O_NOFOLLOW).
    func testLinkSwappedAfterCollectingIsRefused() throws {
        let a = file("harmlos.txt")
        let secret = file("fremd/geheim.txt", "nicht ins ZIP")
        let (list, _) = try ShelfZip.entries(for: [a])
        try FileManager.default.removeItem(at: a)
        try FileManager.default.createSymbolicLink(at: a, withDestinationURL: secret)
        XCTAssertEqual(list.count, 1)
        XCTAssertThrowsError(try ShelfZip.create([a], password: nil, directory: dir), "Quelle ist jetzt selbst ein Link") { _ in }
        // Direkt: auch der Lesepfad lehnt Links ab.
        XCTAssertEqual(open(a.path, O_RDONLY | O_NOFOLLOW), -1)
    }

    func testUniqueNameNeverOverwrites() {
        _ = file("Ablage.zip")
        _ = file("Ablage 2.zip")
        XCTAssertEqual(ShelfZip.uniqueURL(in: dir).lastPathComponent, "Ablage 3.zip")
    }

    func testZipPlainAndAESWithPassword() throws {
        let a = file("brief.txt", "Erfundener Brief")
        let plain = try ShelfZip.create([a], password: nil, directory: dir)
        XCTAssertEqual(plain.files, 1)
        XCTAssertEqual(try tar(["-xOf", plain.url.path]), "Erfundener Brief")
        let aes = try ShelfZip.create([a], password: "geheim-1234", directory: dir)
        XCTAssertEqual(aes.url.lastPathComponent, "Ablage 2.zip")
        XCTAssertEqual(try tar(["-xOf", aes.url.path, "--passphrase", "geheim-1234"]), "Erfundener Brief")
        XCTAssertNotEqual(try tar(["-xOf", aes.url.path, "--passphrase", "falsch-falsch"]), "Erfundener Brief",
                          "falsches Passwort entpackt nichts")
        XCTAssertThrowsError(try ShelfZip.create([], password: nil, directory: dir)) {
            XCTAssertEqual($0 as? ShelfZip.Failure, .empty)
        }
    }

    func testQuarantineCarriesOver() throws {
        let a = file("geladen.txt")
        let value = Array("0083;00000000;Safari;".utf8)
        XCTAssertEqual(setxattr(a.path, "com.apple.quarantine", value, value.count, 0, XATTR_NOFOLLOW), 0)
        let r = try ShelfZip.create([a], password: nil, directory: dir)
        XCTAssertGreaterThan(getxattr(r.url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW), 0)
    }

    /// Nachprüfen mit dem System-`tar` (nur im Test; Gnotchi selbst startet keine Prozesse dafür).
    private func tar(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: Formen, Ruhe-Insel

    func testDragBeatsBigAndRecordingButNotCall() {
        XCTAssertEqual(IslandController.nextMode(current: .expanded, notice: false, recording: true, drag: true), .shelfDrop)
        XCTAssertEqual(IslandController.nextMode(current: .compact, notice: false, call: true, drag: true), .call)
        XCTAssertEqual(IslandController.nextMode(current: .shelfDrop, notice: false), .compact, "Ziehen vorbei")
    }

    /// Michael 22.10.: „Rack schneller zugänglich“ → Kachelreihe unter jeder großen Sache, außer die Ablage ist selbst groß.
    func testShelfStripUnderBigContentAndTallerFrame() throws {
        let m = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(m.showsShelfStrip)
        m.shelfItems = [ShelfStore.Item(id: UUID(), bookmark: Data([1]), name: "x")]
        m.timerPickerActive = true
        XCTAssertTrue(m.showsShelfStrip, "unter der Timer-Auswahl")
        m.timerPickerActive = false
        m.selectShelf()
        XCTAssertFalse(m.showsShelfStrip, "Ablage groß → keine doppelte Reihe")
        let layout = IslandGeometry.layout(for: .init(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32,
                                                      auxLeftWidth: 666, auxRightWidth: 666))
        let plain = try XCTUnwrap(IslandController.bigFrame(layout: layout, small: false, chipRow: true))
        let strip = try XCTUnwrap(IslandController.bigFrame(layout: layout, small: false, chipRow: true, strip: true))
        XCTAssertEqual(strip.height - plain.height, IslandGeometry.shelfStripHeight)
        XCTAssertEqual(strip.maxY, plain.maxY, "oben bündig")
    }

    func testIdleIslandShowsWeatherOrShelf() {
        let m = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(m.isVisible)
        m.shelfItems = [ShelfStore.Item(id: UUID(), bookmark: Data([1]), name: "x")]
        XCTAssertTrue(m.isVisible, "Ruhe-Insel mit Inhalt")
        XCTAssertEqual(m.bigContent, .shelf, "Überfahren ohne andere Aktivität → Ablage groß")
        m.selectShelf()
        XCTAssertTrue(m.shelfActive)
        m.endMirror()
        XCTAssertFalse(m.shelfActive, "Einklappen")
        m.shelfItems = []
        m.fileDragActive = true
        XCTAssertTrue(m.isVisible)
        XCTAssertTrue(m.showsOverFullscreen, "Ablagefeld auch über Vollbild")
    }
}
