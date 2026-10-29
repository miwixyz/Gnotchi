import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// G6: nur JPEG/PNG/HEIC, Base64 ≤ 2 MB, verkleinert auf ≤ 256 px.
final class ArtworkTests: XCTestCase {

    private func image(_ type: UTType, size: Int) -> Data {
        image(type, width: size, height: size)
    }

    private func image(_ type: UTType, width: Int, height: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testPNGDecodesAndShrinks() throws {
        let cg = try XCTUnwrap(Artwork.decode(base64: image(.png, size: 600).base64EncodedString()))
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 256)
    }

    func testGIFRejected() {
        XCTAssertNil(Artwork.decode(base64: image(.gif, size: 20).base64EncodedString()))
    }

    func testGarbageRejected() {
        XCTAssertNil(Artwork.decode(base64: Data("kein bild".utf8).base64EncodedString()))
        XCTAssertNil(Artwork.decode(base64: "%%%"))
    }

    func testJPEGDecodesAndShrinks() throws {
        let cg = try XCTUnwrap(Artwork.decode(base64: image(.jpeg, size: 600).base64EncodedString()))
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 256)
    }

    func testHEICDecodesAndShrinks() throws {
        let cg = try XCTUnwrap(Artwork.decode(base64: image(.heic, size: 600).base64EncodedString()))
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 256)
    }

    func testNonSquareKeepsAspectRatio() throws {
        let cg = try XCTUnwrap(Artwork.decode(base64: image(.png, width: 600, height: 300).base64EncodedString()))
        XCTAssertEqual(cg.width, 256, accuracy: 1)
        XCTAssertEqual(cg.height, 128, accuracy: 1)
    }

    /// Gültiges PNG, das nur durch angehängte Nullbytes über das Limit wächst:
    /// ImageIO würde es akzeptieren – scheitert also nur, wenn die Größenprüfung greift.
    func testOversizeRejectedBeforeDecoding() {
        var data = image(.png, size: 20)
        data.append(Data(count: Artwork.maxBase64Bytes))
        let base64 = data.base64EncodedString()
        XCTAssertGreaterThan(base64.utf8.count, Artwork.maxBase64Bytes)
        XCTAssertNil(Artwork.decode(base64: base64))
        // Gegenprobe: dasselbe Bild ohne Anhang wird akzeptiert.
        XCTAssertNotNil(Artwork.decode(base64: image(.png, size: 20).base64EncodedString()))
    }

    /// Dekompressionsbombe: Header deklariert mehr Pixel, als wir zu dekodieren bereit sind.
    func testTooWideRejected() {
        XCTAssertNil(Artwork.decode(base64: image(.png, width: 9000, height: 10).base64EncodedString()))
    }

    func testTooManyPixelsRejected() {
        XCTAssertNil(Artwork.decode(base64: image(.png, width: 4100, height: 4100).base64EncodedString()))
    }
}
