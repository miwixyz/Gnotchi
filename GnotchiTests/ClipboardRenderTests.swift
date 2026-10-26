import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import Gnotchi

/// 0.14.0 Kartenbild: Sichtprüfung des Herunterklappens ohne App-Start, nur mit ERFUNDENEN Einträgen in einem
/// Speicher im Arbeitsspeicher (nie Michaels Verlauf). PNG wie bei den Insel-Bildern:
/// `TEST_RUNNER_GNOTCHI_RENDER_DIR=… xcodebuild … -only-testing:GnotchiTests/ClipboardRenderTests`.
@MainActor
final class ClipboardRenderTests: XCTestCase {

    private func text(_ s: String) -> ClipPayload {
        ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data(s.utf8))], plain: s)
    }

    private func imagePayload() throws -> ClipPayload {
        let size = NSSize(width: 240, height: 160)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: rect, angle: 35)
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        return ClipPayload(formats: [.init(type: ClipboardCapture.UTI.png, data: png)], plain: "")
    }

    private func makeLink() throws -> ClipboardLink {
        let prefs = Preferences(defaults: try XCTUnwrap(UserDefaults(suiteName: "gnotchi-render-\(UUID())")))
        let link = ClipboardLink(activity: ActivityModel(media: NowPlayingModel()), prefs: prefs)
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let now = Date()
        let yesterday = now.addingTimeInterval(-26 * 3600)
        store.secretsSince = now.addingTimeInterval(-60)
        try store.add(text("Erfundene Notiz: Plakat für den Filmabend am Freitag bestellen, 20 Stück A1."),
                      kind: .text, source: nil, now: yesterday)
        try store.add(text("https://example.com/kino/programm?woche=44"), kind: .link, source: nil,
                      now: yesterday.addingTimeInterval(60))
        let pinned = try store.add(text("#E50914"), kind: .text, source: nil, now: now.addingTimeInterval(-600))
        try store.togglePinned(pinned)
        try store.add(text("rgb(255, 235, 59)"), kind: .text, source: nil, now: now.addingTimeInterval(-500))
        try store.add(try imagePayload(), kind: .image, source: nil, now: now.addingTimeInterval(-400))
        try store.add(text(SecretTests.github), kind: .text, source: nil, now: now.addingTimeInterval(-60))
        try store.add(text("Kurz"), kind: .text, source: nil, now: now)
        _ = try store.createCollection(name: "Arbeit", color: .blue, symbol: "folder")
        _ = try store.createCollection(name: "Tresor", color: .red, symbol: "lock.fill", isVault: true)
        link.attachForRendering(store)
        return link
    }

    func testRenderDropFromNotch() throws {
        let link = try makeLink()
        let state = ClipboardPanelState(link: link, edge: .notch) {}
        state.topInset = 32
        state.selection = 1
        let size = CGSize(width: ClipboardPanelController.dropSize.width,
                          height: ClipboardPanelController.dropSize.height + 32)
        let view = ZStack(alignment: .top) {
            Color(white: 0.55)
            ClipboardPanelView(state: state).frame(width: size.width, height: size.height)
            // Notch als rote Haarlinie (wie bei den Insel-Bildern), MacBook-Maße.
            Rectangle().stroke(Color.red, lineWidth: 0.5).frame(width: 179, height: 32)
        }
        .frame(width: size.width + 80, height: size.height + 40)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage, "ImageRenderer lieferte kein Bild")
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("gnotchi-island-clipboard-drop.png"), options: .atomic)
    }

    /// Die Karten je Art ohne Rollbereich (ImageRenderer zeichnet AppKit-Rollbereiche nicht).
    func testRenderTiles() throws {
        let link = try makeLink()
        let entries = try XCTUnwrap(link.store?.entries())
        let view = HStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                ClipTile(link: link, entry: e, number: i + 1, selected: i == 1)
            }
        }
        .padding(14)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage)
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("gnotchi-island-clipboard-tiles.png"))
    }

    func testDropFrameSitsUnderNotch() {
        let notch = IslandGeometry.ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32,
                                                 auxLeftWidth: 645.5, auxRightWidth: 645.5)
        let (frame, inset) = ClipboardPanelController.dropFrame(notch)
        XCTAssertEqual(inset, 32)
        XCTAssertEqual(frame.maxY, 956, "oben bündig")
        XCTAssertEqual(frame.midX, 735, accuracy: 0.5, "mittig unter der Notch")
        XCTAssertEqual(frame.height, ClipboardPanelController.dropSize.height + 32)

        let pill = IslandGeometry.ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 800, height: 600), safeTop: 0,
                                                auxLeftWidth: nil, auxRightWidth: nil, menuBarHeight: 24)
        let (small, pillInset) = ClipboardPanelController.dropFrame(pill)
        XCTAssertEqual(pillInset, 24)
        XCTAssertLessThanOrEqual(small.width, 800 - 16, "schmaler Bildschirm: gekürzt")
        XCTAssertGreaterThanOrEqual(small.minX, 8)
    }
}
