import AppKit
import XCTest

/// Musik auf dem Schreibtisch: Sichtbarkeit (0.15.0) und Widget-Format (0.26.0) – nur ERFUNDENE Titel (G16).
@MainActor
final class DesktopMusicTests: XCTestCase {

    func testVisibility() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(DesktopMusicLink.shouldShow(hasInfo: false, playing: false, pausedSince: nil, now: t0))
        XCTAssertTrue(DesktopMusicLink.shouldShow(hasInfo: true, playing: true, pausedSince: nil, now: t0))
        XCTAssertTrue(DesktopMusicLink.shouldShow(hasInfo: true, playing: false, pausedSince: t0,
                                                  now: t0.addingTimeInterval(599)), "Pause unter 10 Min.")
        XCTAssertFalse(DesktopMusicLink.shouldShow(hasInfo: true, playing: false, pausedSince: t0,
                                                   now: t0.addingTimeInterval(600)), "nach 10 Min. aus")
    }

    func testPausedSinceStartsOnceAndResetsWhenPlaying() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = DesktopMusicLink.nextPausedSince(hasInfo: true, playing: false, current: nil, now: t0)
        XCTAssertEqual(first, t0)
        XCTAssertEqual(DesktopMusicLink.nextPausedSince(hasInfo: true, playing: false, current: first,
                                                        now: t0.addingTimeInterval(30)), t0, "bleibt beim Start der Pause")
        XCTAssertNil(DesktopMusicLink.nextPausedSince(hasInfo: true, playing: true, current: first, now: t0))
        XCTAssertNil(DesktopMusicLink.nextPausedSince(hasInfo: false, playing: false, current: first, now: t0))
    }

    // MARK: - Widget (0.26.0, G49)

    private func info(title: String = "Erfundener Titel", playing: Bool = true) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: "Muster-Band", album: "Testalbum", appBundleID: nil, isPlaying: playing,
                       duration: 200, elapsedAtStamp: 10, stamp: Date(), rate: 0, contentID: nil, artworkBase64: nil)
    }

    func testNowIsBuiltAndClipped() throws {
        let now = DesktopWidgetFeed.makeNow(info: info(title: String(repeating: "x", count: 1000)), hasCover: true)
        XCTAssertEqual(now.title.count, WidgetWire.maxText)
        XCTAssertEqual(now.subtitle, "Muster-Band · Testalbum")
        XCTAssertTrue(now.playing)
        let data = try JSONEncoder().encode(now)
        XCTAssertEqual(WidgetWire.decodeNow(data), now, "hin und zurück gleich")
    }

    func testNowRejectsOversizeAndUnknownVersion() throws {
        var now = DesktopWidgetFeed.makeNow(info: info(), hasCover: false)
        now.v = 2
        XCTAssertNil(WidgetWire.decodeNow(try JSONEncoder().encode(now)), "fremde Fassung")
        XCTAssertNil(WidgetWire.decodeNow(Data(repeating: 0x20, count: WidgetWire.maxJSON + 1)), "zu groß")
        XCTAssertNil(WidgetWire.decodeNow(Data("kein json".utf8)))
        // Zu lange Felder von außen werden beim Lesen gekürzt.
        let long = #"{"v":1,"title":"\#(String(repeating: "a", count: 2000))","subtitle":"b","playing":false,"hasCover":false}"#
        XCTAssertEqual(WidgetWire.decodeNow(Data(long.utf8))?.title.count, WidgetWire.maxText)
    }

    func testCommandMustBeFreshAndKnown() throws {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let cmd = WidgetWire.Command(id: UUID(), action: .playPause, at: t0.timeIntervalSince1970)
        let data = try JSONEncoder().encode(cmd)
        XCTAssertEqual(WidgetWire.decodeCommand(data, now: t0.addingTimeInterval(1)), cmd)
        XCTAssertNil(WidgetWire.decodeCommand(data, now: t0.addingTimeInterval(3.5)), "zu alt")
        XCTAssertNil(WidgetWire.decodeCommand(data, now: t0.addingTimeInterval(-5)), "aus der Zukunft")
        let bad = #"{"v":1,"id":"\#(UUID().uuidString)","action":"quit","at":\#(t0.timeIntervalSince1970)}"#
        XCTAssertNil(WidgetWire.decodeCommand(Data(bad.utf8), now: t0), "nur die drei Aktionen")
        XCTAssertNil(WidgetWire.decodeCommand(Data(repeating: 0x20, count: WidgetWire.maxCommand + 1), now: t0))
    }

    func testCommandRunsOnlyOnce() {
        var handled: [UUID] = []
        let id = UUID()
        XCTAssertTrue(DesktopWidgetFeed.accept(id, handled: &handled))
        XCTAssertFalse(DesktopWidgetFeed.accept(id, handled: &handled), "derselbe Befehl nie zweimal")
        for _ in 0..<40 { _ = DesktopWidgetFeed.accept(UUID(), handled: &handled) }
        XCTAssertEqual(handled.count, 32, "Gedächtnis begrenzt")
    }

    func testCoverIsSmallPngAndWidgetAcceptsIt() throws {
        let big = NSImage(size: NSSize(width: 1000, height: 600), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange])?.draw(in: rect, angle: 60)
            return true
        }
        let png = try XCTUnwrap(DesktopWidgetFeed.png(big))
        let image = try XCTUnwrap(WidgetWire.coverImage(png))
        XCTAssertEqual(image.width, 256)
        XCTAssertLessThanOrEqual(image.height, 256)
        // Kein PNG → abgelehnt.
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        let jpeg = try XCTUnwrap(rep.representation(using: .jpeg, properties: [:]))
        XCTAssertNil(WidgetWire.coverImage(jpeg))
    }

    func testCoverRejectsHugeDeclaredSize() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 10, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertNil(WidgetWire.coverImage(png), "breiter als 512 px")
    }
}
