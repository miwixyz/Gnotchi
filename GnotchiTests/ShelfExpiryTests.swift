import XCTest
@testable import Gnotchi

// SYNTHETISCH – Testdateien werden in einem frischen Temp-Ordner angelegt (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.16.0: Bildschirmfotos laufen aus der Ablage ab (Datei bleibt), ruhige Insel ohne Notch.
@MainActor
final class ShelfExpiryTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-ablauf-\(UUID().uuidString.prefix(8))")
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

    /// 0.16.0: nur automatisch abgelegte Bildschirmfotos laufen ab, nur der Verweis geht, Zeitpunkt übersteht den Neustart.
    func testScreenshotsExpireOnlyFromShelfFileStays() {
        let storeDir = dir.appendingPathComponent("store")
        let own = file("selbst.png"), shot = file("Bildschirmfoto.png"), fresh = file("neu.png")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let store = ShelfStore(directory: storeDir)
        store.add([own])
        store.add([shot], screenshotAt: t0)
        store.add([fresh], screenshotAt: t0.addingTimeInterval(20 * 60))
        let reloaded = ShelfStore(directory: storeDir)
        XCTAssertEqual(reloaded.items.map(\.screenshotAt), [nil, t0, t0.addingTimeInterval(20 * 60)], "Zeitpunkt gespeichert")
        XCTAssertEqual(reloaded.removeExpiredScreenshots(minutes: 0, now: t0.addingTimeInterval(9_999)), 0, "0 = behalten")
        XCTAssertEqual(reloaded.removeExpiredScreenshots(minutes: 30, now: t0.addingTimeInterval(29 * 60)), 0, "noch nicht fällig")
        XCTAssertEqual(reloaded.removeExpiredScreenshots(minutes: 30, now: t0.addingTimeInterval(30 * 60)), 1)
        XCTAssertEqual(reloaded.items.map(\.name), ["selbst.png", "neu.png"], "selbst Abgelegtes läuft nie ab")
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.path), "Datei bleibt liegen")
        XCTAssertEqual(ShelfStore(directory: storeDir).items.count, 2, "Entfernen gespeichert")
    }

    func testShotDateRejectsGarbage() {
        for bad: Any in [true, "1800000000", Double.nan, Double.infinity, 12.0, -5.0] {
            XCTAssertNil(ShelfStore.shotDate(bad), "\(bad)")
        }
        XCTAssertEqual(ShelfStore.shotDate(1_800_000_000.0), Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// Ruhig nur, wenn eingeschaltet, Ruhe-Inhalt da und keine Live-Bedingung (jede einzeln geprüft).
    func testQuietOnlyWithoutLiveActivity() {
        func quiet(enabled: Bool = true, idle: Bool = true, live: [Bool] = [false, false, false, false, false]) -> Bool {
            ActivityModel.isQuiet(enabled: enabled, idleContent: idle, live: live)
        }
        XCTAssertTrue(quiet())
        XCTAssertFalse(quiet(enabled: false), "Schalter aus")
        XCTAssertFalse(quiet(idle: false), "nichts zu zeigen")
        for i in 0..<5 {
            var live = [false, false, false, false, false]
            live[i] = true
            XCTAssertFalse(quiet(live: live), "Live-Bedingung \(i)")
        }
    }
}
