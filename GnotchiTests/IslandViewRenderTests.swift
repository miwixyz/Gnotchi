import AppKit
import SwiftUI
import XCTest
@testable import Gnotchi

/// Sichtprüfung ohne App-Start: rendert die Insel (klein/groß, Notch/Pille). Prüft nur, dass gerendert
/// wird; das Aussehen beurteilt ein Mensch (Plan Aufgabe 10/14). PNGs nur auf Wunsch, z. B.:
/// `TEST_RUNNER_GNOTCHI_RENDER_DIR=/tmp/gnotchi-render make test` (xcodebuild reicht Variablen mit
/// Präfix `TEST_RUNNER_` ohne Präfix an den Testlauf durch).
@MainActor
final class IslandViewRenderTests: XCTestCase {

    // Gemessen am MacBook Air M5 (macOS 27.0.1, 18.10.), wie IslandGeometryTests.
    private let notchScreen = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 645.5, auxRightWidth: 645.5)
    private let pillScreen = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil)

    func testRenderNotchCompact() throws { try render(notchScreen, .compact, name: "notch-compact") }
    func testRenderNotchExpanded() throws { try render(notchScreen, .expanded, name: "notch-expanded") }
    func testRenderPillCompact() throws { try render(pillScreen, .compact, name: "pill-compact") }
    func testRenderPillExpanded() throws { try render(pillScreen, .expanded, name: "pill-expanded") }
    /// Mit App-Symbol. Gemessen 18.10.: Ein NSWorkspace-Symbol dunkelt im ImageRenderer das GANZE Bild
    /// ab (Grau 0,55 → 0,45) – Renderer-Eigenheit; deshalb die anderen Bilder ohne Symbol (farbecht).
    func testRenderNotchExpandedWithAppIcon() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-appicon", appBundleID: "com.apple.Music")
    }
    /// Spotify Connect: „Auf anderem Gerät“ oben rechts, klein ein Lautsprecher statt Pegel.
    func testRenderNotchExpandedRemote() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-remote", appBundleID: "com.spotify.client", route: .remote)
    }
    func testRenderNotchCompactRemote() throws {
        try render(notchScreen, .compact, name: "notch-compact-remote", route: .remote)
    }
    /// Langer AirPlay-Name: wird gekürzt, drückt den Titel nicht weg.
    func testRenderPillExpandedAirPlay() throws {
        try render(pillScreen, .expanded, name: "pill-expanded-airplay",
                   route: .device(name: "Wohnzimmer HomePod mini Stereo-Paar", kind: .airPlay))
    }
    /// App-Abzeichen unten rechts am kleinen Cover.
    func testRenderNotchCompactWithAppBadge() throws {
        try render(notchScreen, .compact, name: "notch-compact-appbadge", appBundleID: "com.apple.Music")
    }

    /// 0.2.0 Kopfhörer-Hinweis: Streifen unter der Notch bzw. Pille, Name gekürzt.
    func testRenderNotchNotice() throws {
        try render(notchScreen, .notice, name: "notch-notice",
                   notice: ActivityModel.Notice(symbol: "headphones", title: "Beispiel-Kopfhörer Pro", subtitle: "Verbunden"))
    }
    func testRenderPillNoticeLongName() throws {
        try render(pillScreen, .notice, name: "pill-notice",
                   notice: ActivityModel.Notice(symbol: "speaker.wave.2", title: "Ein sehr langer Lautsprechername im Wohnzimmer",
                                                subtitle: "Kopfhörer getrennt"))
    }

    /// 0.2.0 Mikrofon/Kamera: Punkte klein (mit/ohne Musik), Zeile groß.
    private let callPrivacy = ActivityModel.Privacy(micApps: ["Konferenz-App", "Webseite"], camera: true)
    func testRenderNotchCompactPrivacyOnly() throws {
        try render(notchScreen, .compact, name: "notch-compact-privacy", privacy: callPrivacy, withMedia: false)
    }
    func testRenderPillCompactPrivacyOnly() throws {
        try render(pillScreen, .compact, name: "pill-compact-privacy", privacy: callPrivacy, withMedia: false)
    }
    func testRenderNotchCompactPrivacyWithMusic() throws {
        try render(notchScreen, .compact, name: "notch-compact-privacy-music", privacy: callPrivacy)
    }
    func testRenderNotchExpandedPrivacyOnly() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-privacy", privacy: callPrivacy, withMedia: false)
    }
    func testRenderPillExpandedPrivacyWithMusic() throws {
        try render(pillScreen, .expanded, name: "pill-expanded-privacy-music", privacy: callPrivacy)
    }

    private func render(_ screen: IslandGeometry.ScreenMetrics, _ mode: IslandState.Mode, name: String,
                        appBundleID: String? = nil, route: PlaybackRoute = .local,
                        notice: ActivityModel.Notice? = nil, privacy: ActivityModel.Privacy = .none,
                        withMedia: Bool = true) throws {
        let layout = IslandGeometry.layout(for: screen)
        let state = IslandState(layout: layout)
        state.mode = mode
        let model = NowPlayingModel()
        // Klein mit Pause: der Pegel steht, das Bild ist bei jedem Lauf gleich. Groß zeigt keinen Pegel;
        // dort hält rate 0 die Zeit fest.
        model.setPreviewState(info: withMedia ? Self.info(appBundleID: appBundleID, playing: mode == .expanded) : nil,
                              artwork: Self.artwork(), route: route)
        let activity = ActivityModel(media: model)
        if let notice { activity.post(notice) }
        activity.setPrivacy(privacy)

        // Panel ist so groß wie der aktuelle Zustand (wie im IslandController).
        let panel = IslandController.panelFrame(mode: mode, layout: layout, hasMedia: withMedia,
                                                privacy: privacy.isActive) ?? layout.compact
        let canvas = CGSize(width: 520, height: 170)
        let view = ZStack(alignment: .top) {
            // Mittelgrau statt Hintergrundbild: Form und Kanten sind so gut zu sehen.
            Color(white: 0.55)
            IslandView(state: state, onHover: { _ in })
                .environment(model)
                .environment(activity)
                .frame(width: panel.width, height: panel.height)
            // Hardware-Notch als rote Haarlinie, um die Ausrichtung zu prüfen.
            if let n = layout.notch {
                Rectangle().stroke(Color.red, lineWidth: 0.5).frame(width: n.width, height: n.height)
            }
        }
        .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage, "ImageRenderer lieferte kein Bild")
        XCTAssertEqual(cg.width, Int(canvas.width * 2))
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("gnotchi-island-\(name).png"), options: .atomic)
    }

    private static func info(appBundleID: String?, playing: Bool) -> NowPlayingInfo {
        NowPlayingInfo(
            title: "Ein ziemlich langer Songtitel, der sicher abgeschnitten wird",
            artist: "Interpretin mit Namen", album: nil, appBundleID: appBundleID,
            isPlaying: playing, duration: 225, elapsedAtStamp: 83,
            stamp: Date(timeIntervalSince1970: 1_800_000_000), rate: 0,
            contentID: nil, artworkBase64: nil)
    }

    /// Farbverlauf als Platzhalter-Cover (kein echtes Bild im Repo nötig).
    private static func artwork() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSGradient(starting: .systemOrange, ending: .systemPink)?.draw(in: rect, angle: 45)
            return true
        }
    }
}
