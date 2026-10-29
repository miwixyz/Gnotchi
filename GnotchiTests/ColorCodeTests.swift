import XCTest

/// 0.14.0 Kartenbild: Farbcode nur, wenn die ganze Kopie einer ist.
final class ColorCodeTests: XCTestCase {

    func testHexForms() {
        XCTAssertEqual(ColorCode.parse("#E50914")?.hex, "#E50914")
        XCTAssertEqual(ColorCode.parse("  #e50914\n")?.hex, "#E50914", "Leerraum und Kleinschreibung")
        XCTAssertEqual(ColorCode.parse("#FFF")?.hex, "#FFFFFF")
        XCTAssertEqual(ColorCode.parse("#000000FF")?.alpha, 1)
        XCTAssertEqual(ColorCode.parse("#0008")?.hex, "#000000")
    }

    func testFunctionalForms() {
        XCTAssertEqual(ColorCode.parse("rgb(229, 9, 20)")?.hex, "#E50914")
        XCTAssertEqual(ColorCode.parse("rgb(229 9 20)")?.hex, "#E50914", "CSS-4-Schreibweise")
        XCTAssertEqual(ColorCode.parse("rgba(0, 0, 0, 0.5)")?.alpha, 0.5)
        XCTAssertEqual(ColorCode.parse("rgb(100%, 0%, 0%)")?.hex, "#FF0000")
        XCTAssertEqual(ColorCode.parse("hsl(0, 100%, 50%)")?.hex, "#FF0000")
        XCTAssertEqual(ColorCode.parse("hsl(120deg 100% 25%)")?.hex, "#008000")
        XCTAssertEqual(ColorCode.parse("hsla(240, 100%, 50%, 0.3)")?.hex, "#0000FF")
    }

    func testNotAColor() {
        let samples = [
            "#E50914 ist unser Rot",       // eingebettet
            "Farbe: #E50914",
            "#GGGGGG", "#12345", "#",
            "rgb(300, 0, 0)",              // außerhalb
            "rgb(1, 2)",
            "hsl(400, 10%, 10%)",
            "rgb(1, 2, 3, 4, 5)",
            "E50914",                      // ohne #
            "#hashtag",
            String(repeating: "#FFF", count: 40),
        ]
        for s in samples { XCTAssertNil(ColorCode.parse(s), s) }
    }

    /// Vorschau (0.15.0): HEX, RGB, HSL.
    func testPreviewColorLines() throws {
        let lines = ClipPreview.colorLines(try XCTUnwrap(ColorCode.parse("#E50914")))
        XCTAssertEqual(lines.map(\.1), ["#E50914", "rgb(229, 9, 20)", "hsl(357, 92%, 47%)"])
        let gray = ClipPreview.colorLines(try XCTUnwrap(ColorCode.parse("#808080")))
        XCTAssertEqual(gray[2].1, "hsl(0, 0%, 50%)")
        XCTAssertEqual(ClipPreview.colorLines(try XCTUnwrap(ColorCode.parse("rgba(0, 0, 0, 0.5)"))).last?.0, "Alpha")
    }

    func testBrightness() {
        XCTAssertTrue(ColorCode.parse("#FFFFFF")?.isLight == true)
        XCTAssertTrue(ColorCode.parse("#FFEB3B")?.isLight == true)
        XCTAssertTrue(ColorCode.parse("#E50914")?.isLight == false)
        XCTAssertTrue(ColorCode.parse("#000000")?.isLight == false)
    }
}
