import AppKit
import SwiftUI
import XCTest
@testable import Gnotchi

/// 0.15.0 Musik auf dem Schreibtisch: Sichtbarkeit, Lage, Bild (nur ERFUNDENE Titel, G16).
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

    private let area = CGRect(x: 0, y: 80, width: 1470, height: 840)   // sichtbarer Bereich ohne Dock/Menüleiste
    private var size: CGSize { DesktopMusicLink.windowSize(.medium) }

    func testCornersAndFlushInset() {
        let pad = DesktopMusicLink.pad
        let bl = DesktopMusicLink.frame(corner: .bottomLeft, inset: CGSize(width: 24, height: 24), size: size, in: area)
        XCTAssertEqual(bl.minX + pad, 24, "Inhalt 24 vom linken Rand")
        XCTAssertEqual(bl.minY + pad, 80 + 24)
        // Michael: „ganz in die rechte untere Ecke“ – Inhalt bündig, Schattenrand ragt hinaus.
        let flush = DesktopMusicLink.frame(corner: .bottomRight, inset: .zero, size: size, in: area)
        XCTAssertEqual(flush.maxX - pad, area.maxX)
        XCTAssertEqual(flush.minY + pad, area.minY, "bündig unten im erlaubten Bereich")
    }

    /// Ziehen → Ecke + Abstand merken → neu platzieren = dieselbe Stelle (auch nach Bildschirmwechsel stabil).
    func testAnchorRoundTrip() {
        for origin in [CGPoint(x: 1200, y: 60), CGPoint(x: 40, y: 600), CGPoint(x: 700, y: 300), CGPoint(x: 1180, y: 620)] {
            let window = CGRect(origin: origin, size: size)
            let (corner, inset) = DesktopMusicLink.anchor(for: window, in: area)
            let back = DesktopMusicLink.frame(corner: corner, inset: inset, size: size, in: area)
            XCTAssertEqual(back.origin.x, origin.x, accuracy: 0.01, "\(origin)")
            XCTAssertEqual(back.origin.y, origin.y, accuracy: 0.01, "\(origin)")
        }
    }

    /// Über den Rand hinaus gezogen → zurück in den sichtbaren Bereich (Inhalt bündig).
    func testDraggedBeyondEdgeIsClamped() {
        let window = CGRect(origin: CGPoint(x: 1400, y: 20), size: size)   // rechts unten, halb über dem Dock
        let (corner, inset) = DesktopMusicLink.anchor(for: window, in: area)
        XCTAssertEqual(corner, .bottomRight)
        XCTAssertEqual(inset, .zero)
    }

    func testRenderDesktopMusic() throws {
        let model = NowPlayingModel()
        let artwork = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange])?.draw(in: rect, angle: 60)
            return true
        }
        model.setPreviewState(info: NowPlayingInfo(title: "Erfundener Titel", artist: "Muster-Band", album: "Testalbum",
                                                   appBundleID: nil, isPlaying: true, duration: 200, elapsedAtStamp: 10,
                                                   stamp: Date(), rate: 0, contentID: nil, artworkBase64: nil),
                              artwork: artwork)
        let size = DesktopMusicLink.windowSize(.medium)
        let view = ZStack {
            LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom)   // „Schreibtisch“
            DesktopMusicView(media: model, cover: Preferences.DesktopSize.medium.cover, hovering: true)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage)
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("gnotchi-island-desktop-music.png"))
    }
}
