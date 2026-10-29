import XCTest

/// Der Schutz in AppModel (kein Sparkle, kein Medien-Adapter, kein Aufräumen in ~/.claude/settings.json)
/// muss im Testziel greifen – über das Kompilier-Kennzeichen GNOTCHI_TESTS, nicht über eine
/// Umgebungsvariable, die Apple jederzeit ändern kann (2026-10-29).
final class TestGuardTests: XCTestCase {
    func testGuardIsActiveViaCompilationCondition() {
        #if GNOTCHI_TESTS
        XCTAssertTrue(AppModel.isRunningTests)
        #else
        XCTFail("Testziel ohne GNOTCHI_TESTS kompiliert – Schutz hängt wieder an der Umgebungsvariable")
        #endif
    }
}
