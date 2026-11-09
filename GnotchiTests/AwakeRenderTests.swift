import AppKit
import SwiftUI
import XCTest

/// „Wach bleiben“ (0.21.0, Mausbewegung wählbar 09.11.): passt die Ansicht in `IslandGeometry.awakeHeight`?
/// PNG über `NSHostingView` statt `ImageRenderer` – nur so erscheinen die Schalter (AppKit) im Bild:
/// `TEST_RUNNER_GNOTCHI_RENDER_DIR=… make test`.
@MainActor
final class AwakeRenderTests: XCTestCase {

    func testAwakeViewFitsIslandHeight() throws {
        try check(schedule: true, name: "gnotchi-island-awake.png")
        try check(schedule: false, name: "gnotchi-island-awake-ohne-zeitplan.png")
    }

    private func check(schedule: Bool, name: String) throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "gnotchi-awake-render-\(UUID())"))
        let awake = StayAwake(defaults: defaults)
        awake.schedule = schedule
        awake.nudge = true
        // Längste Zeile: Warnung neben „Von Hand“.
        let content = AwakeView(awake: awake, helperTrusted: false).padding(.top, 6)
        let fit = NSHostingView(rootView: content.frame(width: DetachedIsland.width))
        let needed = fit.fittingSize.height
        XCTAssertLessThanOrEqual(needed + 8, IslandGeometry.awakeHeight, "Ansicht \(needed) pt + Rand")

        let view = ZStack(alignment: .top) { Color(white: 0.42); content }   // wie Glas über hellem Fenster (Testbild 09.11.)
            .frame(width: DetachedIsland.width, height: IslandGeometry.awakeHeight)
            .environment(\.colorScheme, .dark)
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(x: 0, y: 0, width: DetachedIsland.width, height: IslandGeometry.awakeHeight)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(name), options: .atomic)
        print("[awake-render] \(name): \(needed) pt von \(IslandGeometry.awakeHeight)")
    }
}
