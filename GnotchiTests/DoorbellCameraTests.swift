import AppKit
import SwiftUI
import XCTest

/// Türklingel-Livebild (27.11.): Adressprüfung, Bildprüfung, Abruf nur solange sichtbar, längere Anzeigezeit.
@MainActor
final class DoorbellCameraTests: XCTestCase {

    private static func png(width: Int = 4, height: Int = 3) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func homeNote(_ id: String) -> NotifyWire.Note {
        NotifyWire.Note(id: id, kind: .note, app: "Home", bundle: "com.apple.Home", title: "Klingel", subtitle: "",
                        body: "", actions: [])
    }

    // MARK: Adresse

    func testValidURLAcceptsOnlyHTTPWithHostAndWithoutCredentials() {
        XCTAssertEqual(DoorbellCamera.validURL(" http://192.168.1.10:4799/doorbell/frame.jpg ")?.absoluteString,
                       "http://192.168.1.10:4799/doorbell/frame.jpg")
        XCTAssertNotNil(DoorbellCamera.validURL("https://kamera.local/bild.jpg"))
        for bad in ["", "   ", "ftp://host/x.jpg", "file:///etc/passwd", "http:///x.jpg", "kamera.local/bild.jpg",
                    "http://user:pass@host/x.jpg", "http://user@host/x.jpg",
                    "http://host/" + String(repeating: "a", count: DoorbellCamera.maxURLLength)] {
            XCTAssertNil(DoorbellCamera.validURL(bad), bad)
        }
    }

    func testProblemExplainsCredentialsAndBadAddressesButNotEmptyOrValid() {
        XCTAssertNil(DoorbellCamera.problem(""))
        XCTAssertNil(DoorbellCamera.problem("http://host/x.jpg"))
        XCTAssertEqual(DoorbellCamera.problem("http://u:p@host/x.jpg"), "Bitte ohne Benutzername und Passwort in der Adresse.")
        XCTAssertNotNil(DoorbellCamera.problem("rtsp://host:8554/ch2"))
    }

    // MARK: Bild

    func testImageChecksStatusSizeAndFormat() {
        XCTAssertEqual(DoorbellCamera.image(data: Self.png(), status: 503).failure, .status(503))
        XCTAssertEqual(DoorbellCamera.image(data: Data("<html>".utf8), status: 200).failure, .notImage)
        XCTAssertEqual(DoorbellCamera.image(data: Data([0xFF, 0xD8, 0xFF, 0x00]), status: 200).failure, .notImage,
                       "JPEG-Anfang allein reicht nicht")
        XCTAssertEqual(DoorbellCamera.image(data: Data(count: DoorbellCamera.maxBytes + 1), status: 200).failure, .tooLarge)
        let bomb = Self.png(width: DoorbellCamera.maxPixels + 1, height: 1)
        XCTAssertLessThan(bomb.count, DoorbellCamera.maxBytes, "klein in Bytes, zu groß in Pixeln")
        XCTAssertEqual(DoorbellCamera.image(data: bomb, status: 200).failure, .tooLarge)
        let image = try? DoorbellCamera.image(data: Self.png(), status: 200).get()
        XCTAssertEqual(image?.size, CGSize(width: 4, height: 3))
    }

    // MARK: Abruf

    func testFeedFetchesOnlyWhileAttachedAndForgetsTheImage() async throws {
        let feed = DoorbellFeed()
        let png = Self.png()
        feed.load = { _ in (png, 200) }
        feed.attach()
        XCTAssertFalse(feed.isRunning, "ohne Adresse kein Abruf")
        feed.detach()

        feed.url = URL(string: "http://host/x.jpg")
        feed.attach()
        feed.attach()   // zweiter Bildschirm
        try await waitUntil { feed.frame != nil }
        XCTAssertNil(feed.error)
        feed.detach()
        XCTAssertTrue(feed.isRunning, "ein Bildschirm zeigt noch")
        feed.detach()
        XCTAssertFalse(feed.isRunning)
        XCTAssertNil(feed.frame, "Bild nur im Speicher, solange zu sehen")
    }

    func testFeedShowsErrorsInsteadOfStaleImage() async throws {
        let feed = DoorbellFeed()
        feed.url = URL(string: "http://host/x.jpg")
        feed.load = { _ in throw URLError(.cannotConnectToHost) }
        feed.attach()
        try await waitUntil { feed.error != nil }
        XCTAssertEqual(feed.error, "Kamerabild nicht erreichbar")
        XCTAssertNil(feed.frame)
        feed.stop()

        feed.load = { _ in (Data(), 503) }
        feed.attach()
        try await waitUntil { feed.error != nil }
        XCTAssertEqual(feed.error, "Kamerabild: Fehler 503")
        feed.stop()
        XCTAssertNil(feed.error)
    }

    // MARK: Insel

    func testOnlyHomeNotesWithAddressShowCameraAndStayLonger() async throws {
        let m = ActivityModel(media: NowPlayingModel(), noteDuration: .seconds(60), callArmDelay: .milliseconds(1))
        var sent: [NotifyWire.Command] = []
        m.notifyCommand = { sent.append($0) }
        m.appInstalled = { _ in false }
        m.doorbellNoteDuration = .milliseconds(50)
        XCTAssertFalse(m.showsDoorbellCamera(homeNote("h")), "ohne Adresse kein Bild")
        m.doorbellFeed.url = URL(string: "http://host/x.jpg")
        XCTAssertTrue(m.showsDoorbellCamera(homeNote("h")))
        XCTAssertFalse(m.showsDoorbellCamera(NotifyWire.Note(id: "a", kind: .note, app: "X", bundle: "com.example.app",
                                                             title: "", subtitle: "", body: "", actions: [])))
        m.receiveNote(homeNote("h"))
        m.noteDisplayed()
        try await waitUntil { sent.contains(.release("h")) }
        XCTAssertNil(m.currentNote, "eigene Anzeigezeit für den Klingel-Hinweis")
    }

    func testCameraMakesMessageIslandTaller() {
        let layout = IslandGeometry.layout(for: IslandGeometry.ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                              safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil))
        let n = homeNote("h")
        let plain = IslandController.messageFrame(layout: layout, note: n)
        let cam = IslandController.messageFrame(layout: layout, note: n, camera: true)
        XCTAssertEqual(cam.height - plain.height, IslandGeometry.doorbellImageHeight + 8)
        XCTAssertEqual(cam.maxY, plain.maxY, "oben bündig, wächst nach unten")
    }

    func testClearNotifyStopsFeed() {
        let m = ActivityModel(media: NowPlayingModel())
        m.doorbellFeed.url = URL(string: "http://host/x.jpg")
        m.doorbellFeed.load = { _ in try await Task.sleep(for: .seconds(10)); return (Data(), 200) }
        m.doorbellFeed.attach()
        XCTAssertTrue(m.doorbellFeed.isRunning)
        m.clearNotify()
        XCTAssertFalse(m.doorbellFeed.isRunning)
    }

    // MARK: Sichtprüfung

    /// Rendert den Klingel-Hinweis mit Bild. Ohne Umgebung mit erfundenem Bild; mit
    /// `TEST_RUNNER_GNOTCHI_DOORBELL_URL=http://…/frame.jpg` holt der echte Abrufweg (`DoorbellFeed.liveLoad`) ein Bild vom
    /// eigenen Dienst. PNG nur mit `TEST_RUNNER_GNOTCHI_RENDER_DIR`. Die Adresse steht nie im Code.
    func testRenderDoorbellNote() async throws {
        let feed = DoorbellFeed()
        let env = ProcessInfo.processInfo.environment
        if let live = env["GNOTCHI_DOORBELL_URL"].flatMap(DoorbellCamera.validURL) {
            feed.url = live
        } else {
            feed.url = URL(string: "http://kamera.invalid/bild.jpg")
            let png = Self.png()
            feed.load = { _ in (png, 200) }
        }
        feed.attach()
        try await waitUntil({ feed.frame != nil || feed.error != nil }, timeout: .seconds(10))
        XCTAssertNil(feed.error)
        let frame = try XCTUnwrap(feed.frame)
        let layout = IslandGeometry.layout(for: IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 645.5, auxRightWidth: 645.5))
        let note = homeNote("h")
        let size = IslandController.messageFrame(layout: layout, note: note, camera: true).size
        let view = NoteIsland(note: note, queued: 0, topInset: 32, camera: feed, onOpen: {}, onAction: { _ in })
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(cg.height, Int(size.height * 2))
        if let dir = env["GNOTCHI_RENDER_DIR"], !dir.isEmpty {
            let out = URL(fileURLWithPath: dir).appendingPathComponent("gnotchi-island-doorbell.png")
            try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])).write(to: out)
            print("Türklingel-Bild: \(Int(frame.size.width))×\(Int(frame.size.height)) → \(out.path)")
        }
        feed.stop()
    }

    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(3)) async throws {
        let end = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < end else { return XCTFail("Bedingung nicht erreicht") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let e) = self { e } else { nil } }
}
