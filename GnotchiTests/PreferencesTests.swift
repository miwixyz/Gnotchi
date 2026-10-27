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

    // MARK: Aufklapp-Verzögerung (Michael, 18.10.: Überfahren soll nicht zu schnell auslösen)

    func testExpandDelayDefault() {
        XCTAssertEqual(Preferences(defaults: defaults).expandDelay, 0.6)
        XCTAssertEqual(Preferences.expandDelayChoices, [0, 0.3, 0.6, 1.0])
    }

    func testExpandDelayIsPersisted() {
        Preferences(defaults: defaults).expandDelay = 0.3
        XCTAssertEqual(defaults.object(forKey: Preferences.Key.expandDelay) as? Double, 0.3)
        XCTAssertEqual(Preferences(defaults: defaults).expandDelay, 0.3)
        Preferences(defaults: defaults).expandDelay = 0
        XCTAssertEqual(Preferences(defaults: defaults).expandDelay, 0)
    }

    func testDelayLabels() {
        XCTAssertEqual(Preferences.expandDelayChoices.map(SettingsView.delayLabel), ["Sofort", "0,3 s", "0,6 s", "1 s"])
    }

    /// Wert außerhalb der Auswahl oder falschen Typs (per `defaults write`) → ab Werk.
    func testInvalidExpandDelayFallsBackToDefault() {
        for bad: Any in [0.45, -1.0, 99.0, Double.nan, "0.3"] {
            defaults.set(bad, forKey: Preferences.Key.expandDelay)
            XCTAssertEqual(Preferences(defaults: defaults).expandDelay, 0.6, "\(bad)")
        }
    }

    /// 0.16.0: Bildschirmfotos behalten – nur Werte aus der Auswahl, ab Werk 30 Min.; ruhige Insel ab Werk an.
    func testScreenshotMinutesAndQuietIslandDefaults() {
        let fresh = Preferences(defaults: defaults)
        XCTAssertEqual(fresh.shelfScreenshotMinutes, 30)
        XCTAssertTrue(fresh.quietIsland)
        for bad: Any in [7, -1, 30.5, true, "15"] {
            defaults.set(bad, forKey: Preferences.Key.shelfScreenshotMinutes)
            XCTAssertEqual(Preferences(defaults: defaults).shelfScreenshotMinutes, 30, "\(bad)")
        }
        defaults.set(0, forKey: Preferences.Key.shelfScreenshotMinutes)
        XCTAssertEqual(Preferences(defaults: defaults).shelfScreenshotMinutes, 0, "„immer“ bleibt erhalten")
    }
}
