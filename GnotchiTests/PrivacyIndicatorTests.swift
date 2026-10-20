import XCTest
@testable import Gnotchi

/// 0.2.0 Mikrofon/Kamera aktiv: Punkt an der Insel, beim Darüberfahren welche App das Mikrofon nutzt
/// (Michael 20.10.). Namen aus dem lokalen App-Bundle, nie ins Protokoll.
@MainActor
final class PrivacyIndicatorTests: XCTestCase {

    /// Hilfsprozesse (Browser) gehören zur äußersten App im Pfad.
    func testOutermostApp() {
        let helper = "/Applications/Beispiel Browser.app/Contents/Frameworks/B.framework/Versions/1/Helpers/"
            + "Beispiel Browser Helper.app/Contents/MacOS/Beispiel Browser Helper"
        XCTAssertEqual(PrivacyMonitor.outermostApp(path: helper), "/Applications/Beispiel Browser.app")
        XCTAssertEqual(PrivacyMonitor.outermostApp(path: "/Applications/Konferenz.app/Contents/MacOS/konferenz"),
                       "/Applications/Konferenz.app")
        XCTAssertNil(PrivacyMonitor.outermostApp(path: "/usr/bin/sox"))
        XCTAssertNil(PrivacyMonitor.outermostApp(path: nil))
    }

    func testMicNames() {
        let names = PrivacyMonitor.micNames(
            [.init(bundleID: "a.b", path: "/Applications/Konferenz.app/Contents/MacOS/k"),
             .init(bundleID: "a.b.helper", path: "/Applications/Konferenz.app/Contents/Helpers/H.app/Contents/MacOS/h"),
             .init(bundleID: AudioRoute.webKitGPU, path: "/System/Library/Frameworks/WebKit.framework/x"),
             .init(bundleID: nil, path: "/usr/bin/sox")],
            displayName: { $0 == "/Applications/Konferenz.app" ? "Konferenz" : nil })
        XCTAssertEqual(names, ["Konferenz", "Webseite", "Unbekannte App"], "doppelte zusammengefasst, Reihenfolge stabil")
        XCTAssertEqual(PrivacyMonitor.micNames([], displayName: { _ in nil }), [])
    }

    func testPrivacyTexts() {
        let mic = ActivityModel.Privacy(micApps: ["Konferenz", "Webseite"], camera: false)
        XCTAssertEqual(mic.compactLabel, "Mikrofon")
        XCTAssertEqual(mic.micLine, "Konferenz, Webseite")
        XCTAssertEqual(ActivityModel.Privacy(micApps: ["X"], camera: true).compactLabel, "Mikrofon · Kamera")
        XCTAssertEqual(ActivityModel.Privacy(micApps: [], camera: true).compactLabel, "Kamera")
        XCTAssertNil(ActivityModel.Privacy.none.compactLabel)
        XCTAssertFalse(ActivityModel.Privacy.none.isActive)
    }

    func testPrivacyMakesIslandVisible() {
        let activity = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(activity.isVisible)
        activity.setPrivacy(.init(micApps: [], camera: true))
        XCTAssertTrue(activity.isVisible)
        activity.setPrivacy(.none)
        XCTAssertFalse(activity.isVisible)
    }

    /// Groß ohne Musik: nur die Datenschutz-Zeilen in Hinweis-Größe; mit Musik eine Zeile mehr Höhe.
    func testExpandedFrameDependsOnContent() throws {
        let l = IslandGeometry.layout(for: IslandGeometry.ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 645.5, auxRightWidth: 645.5))
        XCTAssertEqual(IslandController.panelFrame(mode: .expanded, layout: l, hasMedia: true, privacy: false), l.expanded)
        let tall = try XCTUnwrap(IslandController.panelFrame(mode: .expanded, layout: l, hasMedia: true, privacy: true))
        XCTAssertEqual(tall.height, l.expanded.height + IslandGeometry.privacyLineHeight)
        XCTAssertEqual(tall.maxY, l.expanded.maxY, "oben bündig, wächst nach unten")
        XCTAssertEqual(IslandController.panelFrame(mode: .expanded, layout: l, hasMedia: false, privacy: true), l.notice)
    }
}
