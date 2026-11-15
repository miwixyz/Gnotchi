import XCTest

/// Hotfix 0.27.1: Die Abfrage „darf Gnotchi Spotify/Musik steuern?“ (`AEDeterminePermissionToAutomateTarget`) blockierte am 15.11. zweimal
/// den Hauptthread dauerhaft. Der Aufrufer darf nie darauf warten.
@MainActor
final class AutomationStatusTests: XCTestCase {

    func testNeverBlocksTheCaller() {
        // Die Systemabfrage blockierte im Test länger als 2 s und am 15.11. zweimal dauerhaft: `isAllowed`/`refresh` kehren sofort zurück.
        let start = Date()
        for _ in 0..<50 { _ = AutomationStatus.shared.isAllowed(AppleScriptSource.spotify) }
        AutomationStatus.shared.refresh()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testUnknownAppIsNeverAllowed() {
        XCTAssertFalse(AutomationStatus.shared.isAllowed("evil.app"))
    }

    func testMayReadUsesTheCacheNotTheSystemCall() {
        let source = AppleScriptSource()
        let start = Date()
        _ = source.mayRead(AppleScriptSource.spotify)
        _ = source.mayRead(AppleScriptSource.music)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, "mayRead wartet nicht auf macOS")
    }
}
