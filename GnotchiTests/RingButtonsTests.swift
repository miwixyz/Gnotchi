import XCTest

/// 0.28.0 Tasten-Ring: Sichtbarkeit, Plätze, Randzugabe, Zuklapp-Flächen, Einstellungen.
@MainActor
final class RingButtonsTests: XCTestCase {

    private let island = CGSize(width: 600, height: 110)

    // MARK: Sichtbarkeit

    func testVisibleNeedsEnabledAndAvailable() {
        let v = Ring.visible(enabled: [.timer, .weather], available: [.timer, .awake])
        XCTAssertEqual(v, [.timer, .pin, .settings], "Wetter ist an, hat aber nichts zu zeigen; Wach bleiben ist aus")
    }

    func testPinAndSettingsAreAlwaysThere() {
        XCTAssertEqual(Ring.visible(enabled: [], available: []), [.pin, .settings])
    }

    func testVisibleKeepsFixedOrder() {
        let v = Ring.visible(enabled: Set(RingButton.allCases), available: Set(RingButton.allCases))
        XCTAssertEqual(v, RingButton.allCases)
    }

    func testDefaultsAreOldToolsOnNewActionsOff() {
        XCTAssertEqual(RingButton.defaults, Set(RingButton.allCases).subtracting([.mic, .screenshot, .speedtest]),
                       "Neue Tasten mit Nebenwirkung sind ab Werk aus")
    }

    // MARK: Gespeicherte Werte

    func testValidDropsUnknownAndKeepsKnown() {
        let v = RingButton.valid(["timer", "gibt-es-nicht", 3, "weather", "timer"])
        XCTAssertEqual(v, [.timer, .weather])
    }

    func testValidRejectsNonArray() {
        XCTAssertNil(RingButton.valid("timer"))
        XCTAssertNil(RingButton.valid(nil))
    }

    // MARK: Plätze

    func testLeftColumnGoesTopDown() {
        let r = Ring.rects(buttons: [.timer, .awake, .mirror], island: island)
        XCTAssertEqual(r[.timer], CGRect(x: -50, y: 0, width: 40, height: 40))
        XCTAssertEqual(r[.awake], CGRect(x: -50, y: 50, width: 40, height: 40))
        XCTAssertEqual(r[.mirror], CGRect(x: -50, y: 100, width: 40, height: 40))
    }

    func testRightColumnSitsRightOfIsland() {
        let r = Ring.rects(buttons: [.weather, .shelf], island: island)
        XCTAssertEqual(r[.weather], CGRect(x: 610, y: 0, width: 40, height: 40))
        XCTAssertEqual(r[.shelf], CGRect(x: 610, y: 50, width: 40, height: 40))
    }

    func testBottomRowStartsLeftAndSettingsSitsRight() {
        let r = Ring.rects(buttons: [.pin, .settings], island: island)
        XCTAssertEqual(r[.pin], CGRect(x: 0, y: 120, width: 40, height: 40))
        XCTAssertEqual(r[.settings], CGRect(x: 560, y: 120, width: 40, height: 40), "rechtsbündig mit der Insel")
    }

    func testNoButtonOverlapsIslandOrAnother() {
        let all = Ring.rects(buttons: RingButton.allCases, island: island)
        let islandRect = CGRect(origin: .zero, size: island)
        for (b, r) in all {
            XCTAssertFalse(r.intersects(islandRect), "\(b) liegt auf der Insel")
            for (o, q) in all where o != b { XCTAssertFalse(r.intersects(q), "\(b) und \(o) überlappen") }
        }
    }

    // MARK: Randzugabe fürs Panel

    func testMarginsBottomRowOnly() {
        let m = Ring.margins(buttons: [.pin, .settings], island: island)
        XCTAssertEqual(m, Ring.Margins(side: 0, bottom: 50))
    }

    func testMarginsWithSidesAndBottom() {
        let m = Ring.margins(buttons: [.timer, .weather, .pin], island: island)
        XCTAssertEqual(m, Ring.Margins(side: 50, bottom: 50))
    }

    func testMarginsNothing() {
        XCTAssertEqual(Ring.margins(buttons: [], island: island), .zero)
    }

    func testTallColumnOverflowsIslandBottom() {
        // 3 Tasten = 140 pt, Insel nur 110 pt hoch: ohne untere Reihe braucht das Panel 30 pt Platz darunter.
        let m = Ring.margins(buttons: [.timer, .awake, .mirror], island: island)
        XCTAssertEqual(m, Ring.Margins(side: 50, bottom: 30))
    }

    // MARK: Äußeres Rechteck und Zuklapp-Fläche

    func testIslandRectInsideOuter() {
        let outer = CGRect(x: 100, y: 200, width: 700, height: 160)   // 600 + 2 · 50 breit, 110 + 50 hoch
        let r = DetachedIsland.islandRect(outer: outer, margins: Ring.Margins(side: 50, bottom: 50))
        XCTAssertEqual(r, CGRect(x: 150, y: 250, width: 600, height: 110), "oben bündig, unten Platz für den Ring")
    }

    func testOuterSizeAddsMargins() {
        let l = RingLayout(island: island, buttons: [.timer, .pin], margins: Ring.Margins(side: 50, bottom: 50))
        XCTAssertEqual(l.outerSize, CGSize(width: 700, height: 160))
    }

    func testZonesAreInScreenCoordinatesWithGap() {
        // Insel auf dem Bildschirm: x 150…750, y 250…360 (AppKit, y nach oben).
        let screenIsland = CGRect(x: 150, y: 250, width: 600, height: 110)
        let z = Ring.zones(buttons: [.timer], island: screenIsland)
        XCTAssertEqual(z.count, 1)
        // Taste links oben: x −50…−10 an der Insel, y 0…40 von oben → 320…360 auf dem Bildschirm, je 10 pt Lücke.
        XCTAssertEqual(z[0], CGRect(x: 90, y: 310, width: 60, height: 60))
        XCTAssertTrue(DetachedIsland.contains(CGPoint(x: 150, y: 340), z), "die Lücke zur Insel zählt zur Fläche")
    }

    func testZonesJoinIslandAndGap() {
        let compact = CGRect(x: 1630, y: 1416, width: 180, height: 24)
        let island = CGRect(x: 1570, y: 1300, width: 600, height: 108)
        let ring = Ring.zones(buttons: [.weather], island: island)
        let all = DetachedIsland.zones(compact: compact, island: island, ring: ring)
        XCTAssertEqual(all.count, 3 + 1, "klein, Insel, Lücke dazwischen, eine Taste")
    }

    // MARK: Einstellungen

    func testPreferencesRingOnByDefault() {
        let defaults = UserDefaults(suiteName: "dev.mwlr.gnotchi.tests.ring")!
        defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.ring")
        defer { defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.ring") }
        let p = Preferences(defaults: defaults)
        XCTAssertTrue(p.ring)
        XCTAssertEqual(p.ringButtons, RingButton.defaults)
    }

    func testPreferencesPersistRingButtons() {
        let defaults = UserDefaults(suiteName: "dev.mwlr.gnotchi.tests.ring2")!
        defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.ring2")
        defer { defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.ring2") }
        let p = Preferences(defaults: defaults)
        p.setRingButton(.weather, on: false)
        XCTAssertFalse(p.isRingButtonOn(.weather))
        XCTAssertFalse(Preferences(defaults: defaults).ringButtons.contains(.weather), "bleibt nach dem Neustart aus")
    }

    func testPinAndSettingsCannotBeSwitchedOff() {
        let defaults = UserDefaults(suiteName: "dev.mwlr.gnotchi.tests.ring3")!
        defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.ring3")
        defer { defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.ring3") }
        let p = Preferences(defaults: defaults)
        p.setRingButton(.pin, on: false)
        p.setRingButton(.settings, on: false)
        XCTAssertTrue(p.isRingButtonOn(.pin))
        XCTAssertTrue(p.isRingButtonOn(.settings))
    }

    func testForeignValuesInDefaultsAreIgnored() {
        let defaults = UserDefaults(suiteName: "dev.mwlr.gnotchi.tests.ring4")!
        defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.ring4")
        defer { defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.ring4") }
        defaults.set(["rm -rf", "timer", "../../x"], forKey: Preferences.Key.ringButtons)
        XCTAssertEqual(Preferences(defaults: defaults).ringButtons, [.timer])
    }

    // MARK: Leiste und Ring

    func testChipRowLosesFixedButtonsWithRing() {
        // Ohne Ring steht die Leiste immer (Timer-Symbol, 0.5.0); mit Ring nur noch bei mehreren Dingen.
        XCTAssertTrue(ActivityModel.showsChipRow(items: 1, big: .media, privacy: false, quota: false, fixedButtons: true))
        XCTAssertFalse(ActivityModel.showsChipRow(items: 1, big: .media, privacy: false, quota: false, fixedButtons: false))
    }
}
