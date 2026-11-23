import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest

// SYNTHETISCH – erfundene Bilder in einem frischen Temp-Ordner (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.43.0 (G63): Umwandeln – Original bleibt, nie überschreiben, Ortsdaten raus, Grenzen, Abbruch, PDF.
final class ShelfConvertTests: XCTestCase {
    private var dir: URL!
    private var out: URL!

    override func setUp() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-convert-\(UUID().uuidString.prefix(8))")
        dir = base.appendingPathComponent("in")
        out = base.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

    private func make(_ name: String, _ type: UTType, width: Int, height: Int, gps: Bool = false) -> URL {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 2))
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if gps {
            props[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 48.1, kCGImagePropertyGPSLatitudeRef: "N",
                                                    kCGImagePropertyGPSLongitude: 11.5, kCGImagePropertyGPSLongitudeRef: "E"]
        }
        CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
        CGImageDestinationFinalize(dest)
        return url
    }

    private func props(_ url: URL) -> [CFString: Any] {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
    }

    private func ctx(strip: Bool = true, limits: ShelfConvert.Limits = .init(),
                     cancelled: @escaping @Sendable () -> Bool = { false }) -> ShelfConvert.Context {
        ShelfConvert.Context(directory: out, stripLocation: strip, limits: limits, isCancelled: cancelled)
    }

    private var leftovers: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []).filter { $0.hasSuffix(".tmp") }
    }

    func testShrinkKeepsOriginalMakesNewSmallerFileAndStripsLocation() throws {
        let src = make("foto.jpg", .jpeg, width: 4000, height: 3000, gps: true)
        let before = try Data(contentsOf: src)
        XCTAssertNotNil(props(src)[kCGImagePropertyGPSDictionary])
        let r = ShelfConvert.run(.shrink(longSide: 1280), sources: [src], in: ctx())
        XCTAssertEqual(r.failed, [])
        let made = try XCTUnwrap(r.created.first)
        XCTAssertEqual(made.lastPathComponent, "foto (klein).jpg")
        XCTAssertEqual(props(made)[kCGImagePropertyPixelWidth] as? Int, 1280)
        XCTAssertNil(props(made)[kCGImagePropertyGPSDictionary], "Ortsdaten müssen weg sein")
        XCTAssertEqual(try Data(contentsOf: src), before, "Original unverändert")
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testSecondRunNeverOverwritesButNumbers() {
        let src = make("a.png", .png, width: 800, height: 600)
        let first = ShelfConvert.run(.format(.jpeg), sources: [src], in: ctx()).created
        let second = ShelfConvert.run(.format(.jpeg), sources: [src], in: ctx()).created
        XCTAssertEqual(first.map(\.lastPathComponent), ["a.jpg"])
        XCTAssertEqual(second.map(\.lastPathComponent), ["a 2.jpg"])
    }

    func testFormatChangeStripsLocationByDefaultAndKeepsItWhenAsked() throws {
        let src = make("o.jpg", .jpeg, width: 600, height: 400, gps: true)
        let stripped = try XCTUnwrap(ShelfConvert.run(.format(.png), sources: [src], in: ctx()).created.first)
        XCTAssertNil(props(stripped)[kCGImagePropertyGPSDictionary])
        let kept = try XCTUnwrap(ShelfConvert.run(.format(.heic), sources: [src], in: ctx(strip: false)).created.first)
        XCTAssertNotNil(props(kept)[kCGImagePropertyGPSDictionary], "Schalter aus → Ortsdaten bleiben")
    }

    func testSameFormatIsReportedNotConverted() {
        let src = make("x.png", .png, width: 100, height: 100)
        let r = ShelfConvert.run(.format(.png), sources: [src], in: ctx())
        XCTAssertTrue(r.created.isEmpty)
        XCTAssertEqual(r.failed.map(\.reason), ["Schon in diesem Format"])
    }

    func testBrokenEmptyLinkFolderAndHugeAreReportedAndRestStillRuns() throws {
        let good = make("gut.png", .png, width: 200, height: 100)
        let broken = dir.appendingPathComponent("kaputt.png"); try Data("kein bild".utf8).write(to: broken)
        let empty = dir.appendingPathComponent("leer.png"); try Data().write(to: empty)
        let link = dir.appendingPathComponent("link.png"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: good)
        let folder = dir.appendingPathComponent("ordner"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = dir.appendingPathComponent("a.txt"); try "x".write(to: text, atomically: true, encoding: .utf8)
        let r = ShelfConvert.run(.format(.jpeg), sources: [broken, empty, link, folder, text, good], in: ctx())
        XCTAssertEqual(r.created.map(\.lastPathComponent), ["gut.jpg"])
        XCTAssertEqual(r.failed.map(\.reason), ["Nicht lesbar", "Datei ist leer", "Verknüpfung übersprungen", "Ordner übersprungen", "Kein Bild"])
    }

    func testPixelAndSizeLimitsRejectInsteadOfOpening() {
        let big = make("gross.png", .png, width: 2000, height: 1000)
        var limits = ShelfConvert.Limits()
        limits.maxPixels = 1_000_000
        XCTAssertEqual(ShelfConvert.run(.shrink(longSide: 800), sources: [big], in: ctx(limits: limits)).failed.map(\.reason), ["Zu viele Pixel"])
        limits = ShelfConvert.Limits()
        limits.maxFileBytes = 10
        XCTAssertEqual(ShelfConvert.run(.shrink(longSide: 800), sources: [big], in: ctx(limits: limits)).failed.map(\.reason), ["Zu groß"])
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testCancelLeavesNothingBehind() {
        let a = make("a.png", .png, width: 300, height: 200)
        let b = make("b.png", .png, width: 300, height: 200)
        let r = ShelfConvert.run(.format(.jpeg), sources: [a, b], in: ctx(cancelled: { true }))
        XCTAssertTrue(r.cancelled)
        XCTAssertTrue(r.created.isEmpty)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: out.path))?.count, 0)
    }

    func testPdfMergesImagesAndPdfsInOrder() throws {
        let img = make("1.png", .png, width: 400, height: 300)
        let pdfURL = dir.appendingPathComponent("2.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let c = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
        for _ in 0..<2 { c.beginPDFPage(nil); c.endPDFPage() }
        c.closePDF()
        let img2 = make("3.jpg", .jpeg, width: 400, height: 300)
        let r = ShelfConvert.run(.pdf, sources: [img, pdfURL, img2], in: ctx())
        XCTAssertEqual(r.failed, [])
        let doc = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(r.created.first)))
        XCTAssertEqual(doc.pageCount, 4)
        XCTAssertEqual(r.created.first?.lastPathComponent, "Ablage.pdf")
        XCTAssertGreaterThan(doc.page(at: 0)!.bounds(for: .mediaBox).width, 300, "erste Seite ist das Bild (400 px breit)")
        XCTAssertEqual(doc.page(at: 1)!.bounds(for: .mediaBox).width, 200, "Seiten 2 und 3 stammen aus der PDF")
    }

    func testPdfWithOnlyBrokenFilesMakesNoFile() throws {
        let broken = dir.appendingPathComponent("k.png"); try Data("x".utf8).write(to: broken)
        let r = ShelfConvert.run(.pdf, sources: [broken], in: ctx())
        XCTAssertTrue(r.created.isEmpty)
        XCTAssertEqual(r.failed.count, 1)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: out.path))?.count, 0)
    }

    func testQuarantineIsCarriedOver() throws {
        let src = make("q.png", .png, width: 100, height: 100)
        let value = "0083;5f5e1000;Test;"
        XCTAssertEqual(setxattr(src.path, "com.apple.quarantine", value, value.utf8.count, 0, 0), 0)
        let made = try XCTUnwrap(ShelfConvert.run(.format(.jpeg), sources: [src], in: ctx()).created.first)
        XCTAssertGreaterThan(getxattr(made.path, "com.apple.quarantine", nil, 0, 0, 0), 0)
    }
}
