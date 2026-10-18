import XCTest
@testable import Gnotchi

/// Der Test-Host ist die App selbst: Im Testlauf darf weder perl (Adapter) noch AppleScript
/// (Rückfall) anlaufen, auch wenn der Schalter an ist.
@MainActor
final class AppModelTests: XCTestCase {

    private let suite = "dev.mwlr.gnotchi.tests.appmodel"

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNotchDoesNotStartInTestRun() throws {
        XCTAssertTrue(AppModel.isRunningTests)
        // Eigene Suite: nie Michaels echte Einstellung im Test-Host überschreiben.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let prefs = Preferences(defaults: defaults)
        prefs.notchMedia = true
        let model = AppModel(prefs: prefs)
        XCTAssertFalse(model.notchRunning)
        model.applyNotchSetting()
        XCTAssertFalse(model.notchRunning)
        XCTAssertNil(model.nowPlaying.unavailableReason)
    }
}
