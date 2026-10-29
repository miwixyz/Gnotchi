import AppKit
import XCTest

/// 0.15.1: Datei-Einträge mit mitkopiertem Bild zeigen das Bild. Gemessen 26.10. an CleanShot/Clop:
/// public.file-url + public.png (405 KB) + Klartext in einem Eintrag → als `.file` gespeichert, Karte und Vorschau
/// zeigten nur Datei-Symbol und Pfad.
@MainActor
final class ClipThumbnailsTests: XCTestCase {

    private func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func payload(withImage: Bool) -> ClipPayload {
        let path = "file:///Users/test/Library/Caches/Clop/images/CleanShot.png"
        var formats = [ClipPayload.Format(type: ClipboardCapture.UTI.fileURL, data: Data(path.utf8))]
        if withImage { formats.append(.init(type: ClipboardCapture.UTI.png, data: png())) }
        return ClipPayload(formats: formats, plain: path)
    }

    func testFileWithCopiedImageHasThumbnail() {
        let entry = ClipEntry(kind: .file, sourceBundleID: nil)
        XCTAssertNotNil(ClipThumbnails.image(for: entry, payload: payload(withImage: true)))
    }

    func testFileWithoutImageHasNoThumbnail() {
        let entry = ClipEntry(kind: .file, sourceBundleID: nil)
        XCTAssertNil(ClipThumbnails.image(for: entry, payload: payload(withImage: false)))
    }

    /// Text mit Bild (z. B. Tabelle aus Excel/Keynote) bleibt eine Textkarte.
    func testTextWithImageStaysText() {
        let entry = ClipEntry(kind: .text, sourceBundleID: nil)
        let p = ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data("a\tb".utf8)),
                                      .init(type: ClipboardCapture.UTI.png, data: png())], plain: "a\tb")
        XCTAssertNil(ClipThumbnails.image(for: entry, payload: p))
    }
}
