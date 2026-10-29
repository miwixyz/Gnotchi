import XCTest

// SYNTHETISCH – Testdateien in einem frischen Temp-Ordner (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.10.0 Bildschirmfotos in die Ablage (SECURE-DESIGN G36): Filter und Schalter.
@MainActor
final class ScreenshotWatcherTests: XCTestCase {

    private var dir: URL!
    private var home: URL { dir.appendingPathComponent("home") }
    private var copies: URL { home.appendingPathComponent("Library/Application Support/Gnotchi/Ablage-Kopien") }
    private let earlier = Date().addingTimeInterval(-60)

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-shot-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func file(_ relative: String, in base: URL? = nil) -> URL {
        let url = (base ?? home).appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("kein echtes Bild".utf8))
        return url
    }

    private func candidate(_ url: URL, since: Date? = nil) -> Bool {
        ScreenshotWatcher.isCandidate(url, since: since ?? earlier, home: home, copies: copies)
    }

    func testFreshImageInHomeIsTaken() {
        XCTAssertTrue(candidate(file("Desktop/Bildschirmfoto.png")))
        XCTAssertTrue(candidate(file("Library/Mobile Documents/com~apple~CloudDocs/Screenshots/CleanShot.jpg")))
    }

    func testVideoIsNotTaken() {
        XCTAssertFalse(candidate(file("Desktop/Bildschirmaufnahme.mov")), "nur Fotos (Michael 23.10.)")
    }

    func testOlderThanSwitchOnIsNotTaken() {
        XCTAssertFalse(candidate(file("Desktop/alt.png"), since: Date().addingTimeInterval(3600)),
                       "kein Nachladen alter Fotos")
    }

    func testSymlinkIsNotTaken() throws {
        let target = file("Desktop/echt.png")
        let link = home.appendingPathComponent("Desktop/link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertFalse(candidate(link))
    }

    func testTrashOutsideHomeAndOwnCopiesAreNotTaken() {
        XCTAssertFalse(candidate(file(".Trash/geloescht.png")))
        XCTAssertFalse(candidate(file("woanders/foto.png", in: dir)), "außerhalb des Benutzerordners")
        XCTAssertFalse(candidate(file("\(UUID().uuidString)/kopie.png", in: copies)), "Gnotchis eigene Kopien")
    }

    func testAppInternalLibraryCopiesAreNotTakenButICloudDriveIs() {
        XCTAssertFalse(candidate(file("Library/Application Support/CleanShot/media/media_x/CleanShot.png")),
                       "CleanShots Verlaufskopie (gemessen 23.10.)")
        XCTAssertTrue(candidate(file("Library/Mobile Documents/com~apple~CloudDocs/Screenshots/CleanShot.png")))
    }

    func testCopyKeepsFingerprintSecondPhotoDoesNot() throws {
        let created = Date(timeIntervalSince1970: 1_792_000_000.25)
        let original = file("Library/Mobile Documents/com~apple~CloudDocs/Screenshots/a.png")
        let copy = file("Desktop/a.png")
        let other = file("Desktop/b.png")
        FileManager.default.createFile(atPath: other.path, contents: Data("anderes, längeres Foto".utf8))
        for url in [original, copy, other] {
            try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        }
        XCTAssertNotNil(ScreenshotWatcher.fingerprint(original))
        XCTAssertEqual(ScreenshotWatcher.fingerprint(original), ScreenshotWatcher.fingerprint(copy),
                       "Finder-Kopie beim Rausziehen kommt nicht zurück (gemessen 23.10.)")
        XCTAssertNotEqual(ScreenshotWatcher.fingerprint(original), ScreenshotWatcher.fingerprint(other))
    }

    func testDirectoryIsNotTaken() throws {
        let folder = home.appendingPathComponent("Desktop/ordner.png")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertFalse(candidate(folder))
    }

    func testSwitchIsOffByDefault() {
        let suite = "dev.mwlr.gnotchi.tests.screenshots"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(Preferences(defaults: defaults).shelfScreenshots, "ab Werk aus (Michael 23.10.)")
        Preferences(defaults: defaults).shelfScreenshots = true
        XCTAssertTrue(Preferences(defaults: defaults).shelfScreenshots)
    }
}
