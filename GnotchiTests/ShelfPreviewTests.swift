import AppKit
import XCTest

// SYNTHETISCH – Testdateien werden in einem frischen Temp-Ordner angelegt (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.42.0 (G64): Vorschau in der Ablage – nur Bilder und PDFs, verkleinert, mit Größen- und Pixelgrenze.
final class ShelfPreviewTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-preview-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func png(_ name: String, width: Int, height: Int) -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let url = dir.appendingPathComponent(name)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        return url
    }

    func testSmallImageLoadsAndLargeOneIsShrunk() throws {
        let big = png("gross.png", width: 3_200, height: 2_000)
        XCTAssertTrue(ShelfPreview.canPreview(big))
        let image = try XCTUnwrap(ShelfPreview.load(big))
        XCTAssertEqual(max(image.width, image.height), ShelfPreview.maxPixelSize)
    }

    func testNonImagesFoldersAndLinksAreNotPreviewed() throws {
        let text = dir.appendingPathComponent("a.txt")
        try "x".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertFalse(ShelfPreview.canPreview(text))
        XCTAssertNil(ShelfPreview.load(text))
        XCTAssertFalse(ShelfPreview.canPreview(dir))
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: png("echt.png", width: 10, height: 10))
        XCTAssertFalse(ShelfPreview.canPreview(link))
    }

    func testBrokenAndEmptyImagesGiveNothing() throws {
        let broken = dir.appendingPathComponent("kaputt.png")
        try Data("kein bild".utf8).write(to: broken)
        XCTAssertNil(ShelfPreview.load(broken))
        let empty = dir.appendingPathComponent("leer.png")
        try Data().write(to: empty)
        XCTAssertNil(ShelfPreview.load(empty))
    }

    func testPdfFirstPageIsRendered() throws {
        let url = dir.appendingPathComponent("a.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
        let image = try XCTUnwrap(ShelfPreview.load(url))
        XCTAssertEqual(max(image.width, image.height), ShelfPreview.maxPixelSize)
    }
}
