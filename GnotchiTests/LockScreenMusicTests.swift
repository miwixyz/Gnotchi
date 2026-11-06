import AppKit
import XCTest

/// 0.20.0 Musik auf dem Sperrbildschirm (G46): Sichtbarkeit, Sperrzustand, Lage, ein Fenster im Space.
@MainActor
final class LockScreenMusicTests: XCTestCase {

    func testOnlyWhenLockedAndMusicThere() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(LockScreenMusicLink.shouldShow(locked: true, hasInfo: true, playing: true, pausedSince: nil, now: t0))
        XCTAssertFalse(LockScreenMusicLink.shouldShow(locked: false, hasInfo: true, playing: true, pausedSince: nil, now: t0),
                       "entsperrt nie – Ebene 400 läge sonst über allem")
        XCTAssertFalse(LockScreenMusicLink.shouldShow(locked: true, hasInfo: false, playing: false, pausedSince: nil, now: t0))
        XCTAssertTrue(LockScreenMusicLink.shouldShow(locked: true, hasInfo: true, playing: false, pausedSince: t0,
                                                     now: t0.addingTimeInterval(599)))
        XCTAssertFalse(LockScreenMusicLink.shouldShow(locked: true, hasInfo: true, playing: false, pausedSince: t0,
                                                      now: t0.addingTimeInterval(600)), "nach 10 Min. Pause weg")
    }

    func testSessionLockedReadsOnlyTheBoolFlag() {
        XCTAssertTrue(LockScreenMusicLink.sessionLocked(["CGSSessionScreenIsLocked": true]))
        XCTAssertFalse(LockScreenMusicLink.sessionLocked(["CGSSessionScreenIsLocked": false]))
        XCTAssertFalse(LockScreenMusicLink.sessionLocked([:]), "Feld fehlt = nicht gesperrt (macOS setzt es nur beim Sperren)")
        XCTAssertFalse(LockScreenMusicLink.sessionLocked(nil))
        XCTAssertFalse(LockScreenMusicLink.sessionLocked(["CGSSessionScreenIsLocked": "ja"]), "falscher Typ zählt nicht")
    }

    func testFrameStaysBetweenClockAndLogin() {
        for screen in [CGRect(x: 0, y: 0, width: 1470, height: 956),      // MacBook Air 13"
                       CGRect(x: 0, y: 0, width: 2560, height: 1440),
                       CGRect(x: 0, y: 0, width: 1280, height: 720)] {
            let f = LockScreenMusicLink.frame(screen: screen)
            XCTAssertEqual(f.midX, screen.midX, accuracy: 0.5, "waagrecht mittig")
            XCTAssertLessThanOrEqual(f.maxY, screen.maxY - screen.height * 0.25 + 0.5, "Uhr bleibt frei")
            XCTAssertGreaterThanOrEqual(f.minY, min(screen.minY + screen.height * 0.30,
                                                    f.maxY - LockScreenMusicLink.cardSize.height) - 0.5,
                                        "Anmeldung bleibt frei")
            XCTAssertGreaterThanOrEqual(f.height, LockScreenMusicLink.cardSize.height, "kleine Karte passt immer")
        }
    }

    func testBigCoverShrinksOnSmallScreens() {
        XCTAssertEqual(LockScreenMusicLink.bigCover(windowHeight: 1000), LockScreenMusicLink.bigCoverMax)
        let small = LockScreenMusicLink.frame(screen: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let cover = LockScreenMusicLink.bigCover(windowHeight: small.height)
        XCTAssertLessThan(cover, LockScreenMusicLink.bigCoverMax)
        XCTAssertLessThanOrEqual(cover + LockScreenMusicLink.bigFooter, small.height, "Cover + Knöpfe passen ins Fenster")
    }

    func testOffByDefault() {
        let defaults = UserDefaults(suiteName: "LockScreenMusicTests-\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults)
        XCTAssertFalse(prefs.lockScreenMusic, "neue Fläche für Fremde – ab Werk aus")
        XCTAssertFalse(prefs.lockScreenHideTitle)
    }

    /// G46: Nie mehr als ein Fenster im Sperr-Space. Leeres, durchsichtiges Fenster, damit nichts sichtbar wird.
    func testSpaceHostsExactlyOneWindow() throws {
        try XCTSkipUnless(LockScreenSpace.isAvailable, "SkyLight-Funktionen fehlen")
        let space = try XCTUnwrap(LockScreenSpace())
        defer { space.tearDown() }
        func panel() -> NSPanel {
            let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 4, height: 4), styleMask: [.borderless],
                            backing: .buffered, defer: false)
            p.backgroundColor = .clear
            p.isOpaque = false
            p.orderFrontRegardless()
            return p
        }
        let a = panel(), b = panel()
        defer { a.orderOut(nil); b.orderOut(nil) }
        space.host(a)
        space.host(a)
        XCTAssertEqual(space.windows, [a.windowNumber])
        space.host(b)
        XCTAssertEqual(space.windows, [b.windowNumber], "das alte Fenster ist draußen")
        space.release()
        XCTAssertTrue(space.windows.isEmpty)
    }
}
