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

    // MARK: Kopien aus Dateiversprechen (0.9.1)

    /// Simuliert, was eine App beim Einlösen tut: Datei in den von uns vergebenen UUID-Ordner schreiben.
    private func promisedCopy(_ store: ShelfStore, _ name: String = "IMG_0001.jpeg") throws -> (URL, URL) {
        let folder = try XCTUnwrap(store.newCopyFolder())
        let url = folder.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("Foto".utf8))
        return (folder, url)
    }

    func testCopyFolderOnlyDirectUUIDChild() {
        let copies = dir.appendingPathComponent("Ablage-Kopien")
        let id = UUID().uuidString
        XCTAssertEqual(ShelfStore.copyFolder(of: copies.appendingPathComponent("\(id)/a.jpg"), in: copies)?.lastPathComponent, id)
        XCTAssertNil(ShelfStore.copyFolder(of: copies.appendingPathComponent("kein-uuid/a.jpg"), in: copies))
        XCTAssertNil(ShelfStore.copyFolder(of: copies.appendingPathComponent("\(id)/tiefer/a.jpg"), in: copies))
        XCTAssertNil(ShelfStore.copyFolder(of: copies.appendingPathComponent("a.jpg"), in: copies))
        XCTAssertNil(ShelfStore.copyFolder(of: copies.appendingPathComponent("\(id)/../../a.jpg"), in: copies), "kein Ausbruch")
        XCTAssertNil(ShelfStore.copyFolder(of: dir.appendingPathComponent("\(id)/a.jpg"), in: copies))
    }

    func testCopyFolderIsPrivateAndCopyValidated() throws {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let (folder, url) = try promisedCopy(store)
        let attrs = try FileManager.default.attributesOfItem(atPath: folder.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertTrue(store.isValidCopy(url, in: folder))
        let other = file("woanders.jpg")
        XCTAssertFalse(store.isValidCopy(other, in: folder), "Datei außerhalb des eigenen Ordners")
        let link = folder.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        XCTAssertFalse(store.isValidCopy(link, in: folder), "Link wird abgelehnt")
        let (secondFolder, _) = try promisedCopy(store)
        XCTAssertFalse(store.isValidCopy(url, in: secondFolder), "falscher UUID-Ordner")
    }

    func testRemoveDeletesOwnCopyNeverReferencedFile() throws {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let (folder, copy) = try promisedCopy(store)
        let original = file("original.txt")
        store.release(folder)
        XCTAssertEqual(store.add([copy, original]), 2)
        store.remove(store.items[0].id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "eigene Kopie samt Ordner weg")
        store.remove(store.items[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "Verweis: Datei bleibt")
    }

    func testCopyMovedOutStaysWhenRemoved() throws {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let (folder, copy) = try promisedCopy(store)
        store.release(folder)
        XCTAssertEqual(store.add([copy]), 1)
        let outside = dir.appendingPathComponent("Schreibtisch.jpeg")
        try FileManager.default.moveItem(at: copy, to: outside)   // Finder hat beim Rausziehen verschoben
        store.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "draußen liegt sie dem Nutzer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "leerer Ordner aufgeräumt")
    }

    /// Review 23.10.: Browser-Upload/Mail lesen die rausgezogene Kopie womöglich erst später.
    func testDraggedOutCopySurvivesUntilNextStart() throws {
        let storeDir = dir.appendingPathComponent("store")
        let store = ShelfStore(directory: storeDir)
        let (folder, copy) = try promisedCopy(store)
        store.release(folder)
        XCTAssertEqual(store.add([copy]), 1)
        store.removeAfterDrag(store.items[0].id)
        XCTAssertTrue(store.items.isEmpty)
        store.cleanCopies()
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path), "in dieser Sitzung bleibt sie")
        _ = ShelfStore(directory: storeDir)                    // nächster Start
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "beim Start aufgeräumt")
    }

    /// Review 23.10.: kaputte `ablage.json` darf nicht alle Kopien löschen.
    func testBrokenStoreFileDeletesNothing() throws {
        let storeDir = dir.appendingPathComponent("store")
        let store = ShelfStore(directory: storeDir)
        let (folder, copy) = try promisedCopy(store)
        store.release(folder)
        XCTAssertEqual(store.add([copy]), 1)
        try Data("kaputt".utf8).write(to: storeDir.appendingPathComponent("ablage.json"))
        _ = ShelfStore(directory: storeDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }

    /// Review 23.10.: ist der Kopien-Ordner ein Link, wird im Ziel nichts gelöscht.
    func testLinkedCopiesFolderIsNotCleaned() throws {
        let storeDir = dir.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("fremd")
        let victim = target.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: storeDir.appendingPathComponent("Ablage-Kopien"), withDestinationURL: target)
        ShelfStore(directory: storeDir).cleanCopies()
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
    }

    func testCleanCopiesKeepsPendingAndUsedRemovesOrphans() throws {
        let storeDir = dir.appendingPathComponent("store")
        let store = ShelfStore(directory: storeDir)
        let (busy, _) = try promisedCopy(store)
        let (used, usedCopy) = try promisedCopy(store)
        let (orphan, _) = try promisedCopy(store)
        store.release(used)
        store.release(orphan)
        XCTAssertEqual(store.add([usedCopy]), 1)
        let foreign = storeDir.appendingPathComponent("Ablage-Kopien/nicht-von-uns")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        store.cleanCopies()
        XCTAssertTrue(FileManager.default.fileExists(atPath: busy.path), "App schreibt noch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: used.path), "Eintrag zeigt darauf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path), "verwaist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path), "nur UUID-Ordner werden angefasst")
    }

    func testDropTitleTellsTheTruth() {
        XCTAssertEqual(ShelfLink.dropTitle(added: 2, offered: 2, already: 0, failed: 0, full: false), "2 abgelegt")
        XCTAssertEqual(ShelfLink.dropTitle(added: 0, offered: 1, already: 1, failed: 0, full: false), "Schon in der Ablage")
        XCTAssertEqual(ShelfLink.dropTitle(added: 0, offered: 0, already: 0, failed: 1, full: false), "Nicht abgelegt",
                       "23.10.: verworfenes Foto meldete „Schon in der Ablage“")
        XCTAssertEqual(ShelfLink.dropTitle(added: 0, offered: 1, already: 0, failed: 0, full: false), "Nicht abgelegt")
        XCTAssertEqual(ShelfLink.dropTitle(added: 0, offered: 1, already: 0, failed: 0, full: true), "Ablage voll")
    }

    func testPromiseBatchEndsOnceAndCountsMissing() {
        var results: [([URL], Int)] = []
        let batch = PromiseBatch(failed: 1) { results.append(($0, $1)) }
        var released = false
        batch.onFinish = { released = true }
        batch.expect(3)
        batch.check()
        XCTAssertTrue(results.isEmpty)
        batch.arrived(URL(fileURLWithPath: "/tmp/a"))
        batch.arrived(nil)
        batch.finish()                                   // Zeitlimit, eine fehlt noch
        batch.arrived(URL(fileURLWithPath: "/tmp/spaet"))
        batch.finish()
        XCTAssertEqual(results.count, 1, "genau einmal")
        XCTAssertEqual(results.first?.0.map(\.lastPathComponent), ["a"])
        XCTAssertEqual(results.first?.1, 3, "übersprungen + Fehler + fehlend")
        XCTAssertTrue(released)
    }

    /// Gemessen 23.10. (`tools/drag-types.swift`), Typen ohne `dyn.*`: Outlook und Gmail in Helium bieten nur ein
    /// Versprechen an; ein Link ohne Datei öffnet die Ablage nicht.
    func testDragOffersFilesForReferencesAndPromises() {
        typealias Kind = NSPasteboard.PasteboardType
        let finder: [Kind] = [.fileURL, Kind("com.apple.finder.node")]
        let outlook: [Kind] = [Kind("com.apple.pasteboard.promised-file-content-type"), Kind("com.apple.pasteboard.promised-file-url")]
        let gmail: [Kind] = [Kind("org.chromium.chromium-initiated-drag"), Kind("public.url"), Kind("public.url-name"),
                          Kind("com.apple.pasteboard.promised-file-url"), Kind("com.apple.pasteboard.promised-file-content-type"),
                          Kind("public.html"), Kind("public.utf8-plain-text")]
        let link: [Kind] = [Kind("public.url"), Kind("public.url-name"), Kind("public.utf8-plain-text")]
        XCTAssertTrue(DragWatcher.offersFiles(finder))
        XCTAssertTrue(DragWatcher.offersFiles(outlook))
        XCTAssertTrue(DragWatcher.offersFiles(gmail))
        XCTAssertFalse(DragWatcher.offersFiles(link))
        XCTAssertFalse(DragWatcher.offersFiles([]))
        // 0.9.2: Fotos (mit Metadaten) → NSFilePromiseReceiver; Outlook/Gmail (ohne) → alter Weg über NSDraggingInfo.
        let photos: [Kind] = [ShelfLink.promiseMetaData, Kind("com.apple.pasteboard.promised-file-name"),
                           Kind("com.apple.pasteboard.promised-file-content-type"), Kind("public.jpeg"), .fileURL]
        XCTAssertFalse(ShelfLink.isLegacyPromise(photos))
        XCTAssertTrue(ShelfLink.isLegacyPromise(outlook))
        XCTAssertTrue(ShelfLink.isLegacyPromise(gmail))
        XCTAssertFalse(ShelfLink.isLegacyPromise(finder))
        XCTAssertFalse(ShelfLink.isPromise(finder))
    }

    func testArrivedCopiesSkipHiddenAndLinks() throws {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let (folder, copy) = try promisedCopy(store, "Anhang.pdf")
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".zwischen.tmp").path, contents: Data())
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.pdf"), withDestinationURL: file("x.pdf"))
        XCTAssertEqual(ShelfLink.arrivedCopies(in: folder, store: store)?.map(\.lastPathComponent), [copy.lastPathComponent])
    }

    /// Review 23.10.: eine App könnte tausende Dateien schreiben → abbrechen statt Hauptthread lahmlegen.
    func testArrivedCopiesRefusesFlood() throws {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let folder = try XCTUnwrap(store.newCopyFolder())
        for i in 0...(2 * ShelfStore.maxItems) {
            FileManager.default.createFile(atPath: folder.appendingPathComponent("f\(i).pdf").path, contents: Data())
        }
        XCTAssertNil(ShelfLink.arrivedCopies(in: folder, store: store))
    }

    /// Review 23.10.: eine eigene Kopie, die nach der Prüfung gegen einen Link getauscht wurde, wird nicht abgelegt.
    func testCopySwappedForLinkIsNotAdded() throws {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let (folder, copy) = try promisedCopy(store)
        XCTAssertTrue(store.isValidCopy(copy, in: folder))
        try FileManager.default.removeItem(at: copy)
        try FileManager.default.createSymbolicLink(at: copy, withDestinationURL: file("geheim.txt"))
        XCTAssertEqual(store.add([copy]), 0)
    }

    /// Absturz Sichttest 23.10.: macOS ruft den Rückruf auf einer Hintergrund-Warteschlange auf.
    func testPromiseReaderRunsOffMainThread() throws {
        let store = ShelfStore(directory: dir.appendingPathComponent("store"))
        let (folder, copy) = try promisedCopy(store)
        let done = expectation(description: "Kopie angekommen")
        var got: [URL] = []
        let batch = PromiseBatch { urls, _ in got = urls; done.fulfill() }
        batch.expect(1)
        let reader = ShelfLink.promiseReader(batch: batch, store: store, folder: folder)
        let queue = OperationQueue()
        queue.addOperation { reader(copy, nil) }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(got.map(\.lastPathComponent), [copy.lastPathComponent])
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
