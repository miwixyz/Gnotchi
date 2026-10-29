import XCTest

/// Name der Quell-App für die Kopfzeile der großen Insel (Michael, 18.10.: „welche App spielt“).
/// Der Name kommt aus dem lokalen App-Bundle (FileManager.displayName), nie aus dem Strom.
final class AppIconsTests: XCTestCase {

    func testStripsAppExtension() {
        // displayName zeigt „.app“, wenn im Finder „Alle Dateinamensuffixe einblenden“ an ist.
        XCTAssertEqual(AppIcons.cleanName("Spotify.app"), "Spotify")
        XCTAssertEqual(AppIcons.cleanName("Safari.APP"), "Safari")
    }

    func testKeepsLocalizedName() {
        XCTAssertEqual(AppIcons.cleanName("Musik"), "Musik")
        XCTAssertEqual(AppIcons.cleanName("Microsoft Edge"), "Microsoft Edge")
    }

    func testEmptyOrMissingGivesNil() {
        XCTAssertNil(AppIcons.cleanName(nil))
        XCTAssertNil(AppIcons.cleanName(""))
        XCTAssertNil(AppIcons.cleanName(".app"))
        XCTAssertNil(AppIcons.cleanName(" \u{202E} "))
    }

    /// Bundle-Namen sind frei wählbar: Steuer-/Richtungszeichen weg, Länge begrenzt.
    func testSanitizedAndCapped() {
        XCTAssertEqual(AppIcons.cleanName("Spo\u{202E}tify"), "Spotify")
        let long = String(repeating: "x", count: 200)
        XCTAssertEqual(AppIcons.cleanName(long)?.count, AppIcons.maxNameLength)
    }
}
