import XCTest

/// Gleiche Regeln wie Seams `LinkRules.isBundleID`: ASCII-Buchstaben/-Ziffern, Punkt, Bindestrich,
/// 1 bis 255 Zeichen. Die Bundle-ID kommt aus dem Adapter-Strom, also von beliebigen Apps (G4).
final class BundleIDTests: XCTestCase {

    func testTypicalIDsAreValid() {
        for id in ["com.spotify.client", "com.apple.Safari", "com.microsoft.edgemac", "net.imput.helium", "a", "x-y.z9"] {
            XCTAssertTrue(BundleID.isValid(id), id)
        }
    }

    func testEmptyIsInvalid() {
        XCTAssertFalse(BundleID.isValid(""))
    }

    func testLengthLimit() {
        XCTAssertTrue(BundleID.isValid(String(repeating: "a", count: 255)))
        XCTAssertFalse(BundleID.isValid(String(repeating: "a", count: 256)))
    }

    func testForbiddenCharacters() {
        for id in ["com.example app", "com/example", "com.example\n", "com.example;rm", "com_example", "com.exämple",
                   "com.example\u{202E}", "com.ｅxample", "com.example:1"] {
            XCTAssertFalse(BundleID.isValid(id), id)
        }
    }
}
