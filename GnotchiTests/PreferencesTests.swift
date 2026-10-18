import XCTest
@testable import Gnotchi

@MainActor
final class PreferencesTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "dev.mwlr.gnotchi.tests.prefs"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNotchMediaIsOnByDefault() {
        XCTAssertTrue(Preferences(defaults: defaults).notchMedia)
    }

    func testNotchMediaIsPersisted() {
        Preferences(defaults: defaults).notchMedia = false
        XCTAssertEqual(defaults.object(forKey: Preferences.Key.notchMedia) as? Bool, false)
        XCTAssertFalse(Preferences(defaults: defaults).notchMedia)
    }

    /// Ein Wert falschen Typs (von außen per `defaults write` gesetzt) fällt auf „ab Werk“ zurück.
    func testWrongTypeFallsBackToDefault() {
        defaults.set("nein", forKey: Preferences.Key.notchMedia)
        XCTAssertTrue(Preferences(defaults: defaults).notchMedia)
    }
}
