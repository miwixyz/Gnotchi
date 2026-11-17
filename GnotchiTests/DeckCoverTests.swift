import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Stream Deck, Cover (G59 Punkt 10e): Prüfung fremder Bilder vor dem Dekodieren, eigene Skalierung, Nachricht ans Plugin,
/// feste Tab-Skripte.
@MainActor
final class DeckCoverTests: XCTestCase {

    private func image(_ w: Int, _ h: Int, type: UTType = .jpeg, noise: Bool = false) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        if noise, let p = ctx.data?.assumingMemoryBound(to: UInt8.self) {
            for i in 0..<(ctx.bytesPerRow * h) { p[i] = UInt8.random(in: 0...255) }
        } else {
            ctx.setFillColor(NSColor.orange.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    // MARK: Prüfung vor dem Dekodieren

    func testAcceptsSmallJPEGAndPNG() {
        XCTAssertNotNil(DeckCover.image(data: image(144, 81)))
        XCTAssertNotNil(DeckCover.image(data: image(64, 64, type: .png)))
    }

    func testRejectsOversizeAndForeignFormats() {
        XCTAssertNil(DeckCover.image(data: image(257, 100)), "Seite > 256 px")
        XCTAssertNil(DeckCover.image(data: image(200, 200, noise: true)), "> 16 KB")
        XCTAssertNil(DeckCover.image(data: image(64, 64, type: .gif)), "GIF")
        XCTAssertNil(DeckCover.image(data: Data()))
        XCTAssertNil(DeckCover.image(data: Data([0xFF, 0xD8, 0xFF, 0x00, 0x01])), "nur Kennung, kein Bild")
    }

    func testDataURLOnlyWithKnownPrefixAndLength() {
        let jpeg = image(144, 81)
        XCTAssertNotNil(DeckCover.image(dataURL: "data:image/jpeg;base64," + jpeg.base64EncodedString()))
        XCTAssertNil(DeckCover.image(dataURL: "data:image/svg+xml;base64," + jpeg.base64EncodedString()))
        XCTAssertNil(DeckCover.image(dataURL: "https://i.ytimg.com/vi/x/hqdefault.jpg"))
        XCTAssertNil(DeckCover.image(dataURL: "data:image/jpeg;base64," + String(repeating: "A", count: 30_000)))
        XCTAssertNil(DeckCover.image(dataURL: "data:image/jpeg;base64,kein base64!"))
    }

    // MARK: Eigene Skalierung

    func testRenderScalesDownToCoverPixelsAndFitsTheLimit() throws {
        let big = try XCTUnwrap(NSImage(data: image(600, 600, noise: true)))
        let out = try XCTUnwrap(DeckCover.render(big))
        XCTAssertLessThanOrEqual(out.count, DeckWire.maxCoverBytes)
        XCTAssertTrue(out.starts(with: [0xFF, 0xD8, 0xFF]))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, DeckWire.coverPixels)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, DeckWire.coverPixels)
    }

    /// Gemessen 18.11.: detailreiches quadratisches Cover (Spotify) passte bei 144 px nicht in die Grenze → gar kein Cover.
    /// Jetzt wird es kleiner statt verworfen.
    func testRenderStepsDownWhenDetailedCoverDoesNotFit() throws {
        let detailed = try XCTUnwrap(NSImage(data: image(144, 144, noise: true))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertNil(DeckCover.render(detailed, side: DeckWire.coverPixels), "Ausgangslage: passt bei 144 px nicht")
        let out = try XCTUnwrap(DeckCover.render(detailed))
        XCTAssertLessThanOrEqual(out.count, DeckWire.maxCoverBytes)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertLessThan(try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int), DeckWire.coverPixels)
    }

    func testRenderNeverUpscales() throws {
        let small = try XCTUnwrap(DeckCover.image(data: image(80, 45)))
        let out = try XCTUnwrap(DeckCover.render(small))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 80)
    }

    // MARK: Nachricht ans Plugin

    func testCoverMessageRoundTripAndFrameSize() throws {
        let jpeg = try XCTUnwrap(DeckCover.render(try XCTUnwrap(NSImage(data: image(600, 600, noise: true)))))
        let msg = DeckWire.encodeCover(app: "net.imput.helium", jpeg: jpeg)
        XCTAssertNotNil(LiveText.frame(msg, max: DeckWire.maxCoverFrame), "größtes Cover passt in den Rahmen")
        XCTAssertNil(LiveText.frame(msg, max: DeckWire.maxFrame), "aber nicht in den alten – deshalb nur nach hello/cover")
        let data = try JSONSerialization.data(withJSONObject: msg)
        let back = try XCTUnwrap(DeckWire.parseCover(data))
        XCTAssertEqual(back.app, "net.imput.helium")
        XCTAssertEqual(back.jpeg, jpeg)
        let clear = try JSONSerialization.data(withJSONObject: DeckWire.encodeCover(app: "current", jpeg: nil))
        XCTAssertEqual(DeckWire.parseCover(clear)?.app, "current")
        XCTAssertNil(DeckWire.parseCover(clear)?.jpeg)
    }

    func testCoverMessageRejectsNonJPEGOversizeAndBadApp() throws {
        let png = image(64, 64, type: .png)
        let bad: [[String: Any]] = [
            ["v": 1, "cover": "current", "img": png.base64EncodedString()],
            ["v": 1, "cover": "current", "img": Data(repeating: 0xFF, count: 6000).base64EncodedString()],
            ["v": 1, "cover": "../x", "img": NSNull()],
            ["v": 2, "cover": "current", "img": NSNull()],
            ["v": 1, "cover": "current"],
        ]
        for b in bad { XCTAssertNil(DeckWire.parseCover(try JSONSerialization.data(withJSONObject: b)), "\(b)") }
        // Eine normale Rückmeldung ist keine Cover-Nachricht.
        let status = DeckWire.Status(app: "current", name: "Spotify", title: nil, artist: nil, percent: nil, muted: false,
                                     playing: true, canPlay: true, state: .ok)
        XCTAssertNil(DeckWire.parseCover(try JSONSerialization.data(withJSONObject: DeckWire.encode(status))))
    }

    func testHelloCarriesCoverOnlyWhenSet() throws {
        let old = try JSONSerialization.data(withJSONObject: ["v": 1, "hello": "0.36.0"])
        XCTAssertEqual(DeckWire.parse(old), .hello(version: "0.36.0", cover: false))
        let new = try JSONSerialization.data(withJSONObject: DeckWire.encode(.hello(version: "0.36.0", cover: true)))
        XCTAssertEqual(DeckWire.parse(new), .hello(version: "0.36.0", cover: true))
        XCTAssertNil(DeckWire.encode(.hello(version: "0.36.0"))["cover"])
    }

    // MARK: Feste Tab-Skripte

    func testCoverScriptsAreConstantsWithHostCheck() {
        for js in [BrowserTab.coverStartJavaScript, BrowserTab.coverCollectJavaScript] {
            XCTAssertTrue(js.hasPrefix("(function(){var h=location.hostname;if(h!=='www.youtube.com'&&h!=='music.youtube.com')"))
            XCTAssertNotNil(BrowserTab.tabScript(window: 1, index: 2, javascript: js), "keine Anführungszeichen/Backslashes")
        }
        XCTAssertTrue(BrowserTab.coverStartJavaScript.contains("credentials:'omit'"))
        XCTAssertTrue(BrowserTab.coverCollectJavaScript.contains("delete window.__gnotchiCover"))
        XCTAssertNil(BrowserTab.tabScript(window: 1, index: 2, javascript: "alert(\"x\")"))
    }

    func testCollectOutcome() {
        XCTAssertEqual(BrowserTab.collectOutcome("wait"), .waiting)
        XCTAssertEqual(BrowserTab.collectOutcome(""), .done(nil))
        XCTAssertEqual(BrowserTab.collectOutcome(nil), .done(nil))
        XCTAssertEqual(BrowserTab.collectOutcome("data:image/jpeg;base64,AAAA"), .done(nil))
        let ok = BrowserTab.collectOutcome("data:image/jpeg;base64," + image(144, 81).base64EncodedString())
        guard case .done(let d?) = ok else { return XCTFail("gültiges Bild verworfen") }
        XCTAssertLessThanOrEqual(d.count, DeckWire.maxCoverBytes)
    }
}
