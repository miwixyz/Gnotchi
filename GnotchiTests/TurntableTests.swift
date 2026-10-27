import AppKit
import SwiftUI
import XCTest
@testable import Gnotchi

// SYNTHETISCH – erfundener Titel, gezeichnetes Cover, keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.17.0 Plattenspieler: Drehung, Farben, Lage, Einstellungen, Testbild.
@MainActor
final class TurntableTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testSpinHasNoJumpWhenStartingOrStopping() {
        var spin = TurntableSpin().switched(to: true, at: t0)
        let before = spin.angle(at: t0.addingTimeInterval(2))
        spin = spin.switched(to: false, at: t0.addingTimeInterval(2))
        XCTAssertEqual(spin.angle(at: t0.addingTimeInterval(2)), before.truncatingRemainder(dividingBy: 360), accuracy: 0.001,
                       "Pause beginnt beim aktuellen Winkel")
        XCTAssertEqual(before, 2 * TurntableArt.degreesPerSecond, accuracy: 0.001, "33⅓ U/min")
    }

    func testPauseCoastsOutAndStops() {
        let spin = TurntableSpin().switched(to: true, at: t0).switched(to: false, at: t0)
        let end = spin.angle(at: t0.addingTimeInterval(60))
        XCTAssertEqual(end, TurntableArt.degreesPerSecond * TurntableSpin.tau, accuracy: 0.01, "läuft um ω·τ aus")
        XCTAssertTrue(spin.moving(at: t0.addingTimeInterval(1)))
        XCTAssertFalse(spin.moving(at: t0.addingTimeInterval(5)), "danach steht die Animation")
        XCTAssertFalse(TurntableSpin().moving(at: t0), "ohne Musik keine Animation")
    }

    func testPaletteRowsDarkenDownwardAndGlowIsMostVivid() {
        let gray = TurntableColors.RGB(r: 0.6, g: 0.6, b: 0.6)
        var samples = Array(repeating: gray, count: 9)
        samples[2] = .init(r: 0.9, g: 0.2, b: 0.1)   // kräftigste Probe oben rechts
        let p = TurntableColors.palette(from: samples)
        let top = NSColor(p.mesh[0]).usingColorSpace(.sRGB)!.brightnessComponent
        let bottom = NSColor(p.mesh[6]).usingColorSpace(.sRGB)!.brightnessComponent
        XCTAssertGreaterThan(top, bottom, "oben Raum, unten Boden")
        let glow = NSColor(p.glow).usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(glow.redComponent, glow.blueComponent * 3, "Lichtschein aus der kräftigsten Farbe")
        XCTAssertEqual(TurntableColors.palette(from: []), TurntableColors.fallback)
        let neon = NSColor(p.neon).usingColorSpace(.sRGB)!
        XCTAssertEqual(neon.brightnessComponent, 1, accuracy: 0.01, "Neon in voller Helligkeit")
        let grayCover = TurntableColors.palette(from: Array(repeating: gray, count: 9))
        XCTAssertEqual(grayCover.neon, TurntableColors.fallback.neon, "graues Cover → klassisches Neon-Pink")
    }

    func testShadeKeepsHueAndLimitsBrightness() {
        let c = NSColor(TurntableColors.shade(.init(r: 1, g: 0.5, b: 0.25), 0.5)).usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(c.greenComponent, 0.25, accuracy: 0.01)
        let dark = NSColor(TurntableColors.shade(.init(r: 0.1, g: 0.1, b: 0.1), 0.5)).usingColorSpace(.sRGB)!
        XCTAssertEqual(dark.redComponent, 0.1, accuracy: 0.01, "dunkle Cover werden nicht aufgehellt")
    }

    func testLayoutIsCenteredThirdOfScreen() {
        let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let visible = CGRect(x: 0, y: 0, width: 3440, height: 1410)
        let (frame, deck) = DesktopMusicLink.turntableLayout(screen: screen, visible: visible)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.5)
        XCTAssertEqual(frame.width - 2 * DesktopMusicLink.turntablePad, 3440 / 3, accuracy: 0.5)
        XCTAssertGreaterThan(deck, 700)
        XCTAssertLessThan(frame.height, visible.height, "passt auf den Bildschirm")
    }

    /// Maßstab Hülle : Platte (Mittelweg, Michael 27.10.): nicht mehr Single-klein (vorher 74 %), nicht größer als eine
    /// echte LP (31,4 : 30 cm). Plattenbreite aus der gemessenen Perspektive.
    func testSleeveMatchesRecordScale() {
        let xs = (0..<360).map { d -> CGFloat in
            let a = Double(d) * .pi / 180
            return TurntableGeometry.plane.apply(CGPoint(x: cos(a), y: sin(a))).x
        }
        let record = (xs.max()! - xs.min()!) / TurntableArt.size.width
        XCTAssertEqual(TurntableView.sleeveRatio / record, 0.92, accuracy: 0.03)
        XCTAssertLessThanOrEqual(TurntableView.sleeveRatio / record, 31.4 / 30)
    }

    func testStyleAndScreenDefaults() {
        let suite = "gnotchi-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(Preferences(defaults: d).desktopMusicStyle, .card, "ab Werk Karte")
        XCTAssertTrue(Preferences(defaults: d).desktopMusicNeon, "Neonschrift ab Werk an")
        XCTAssertFalse(Preferences(defaults: d).desktopMusicTonearm, "Tonarm bedienen ab Werk aus")
        d.set("kaputt", forKey: Preferences.Key.desktopMusicStyle)
        d.set(String(repeating: "x", count: 500), forKey: Preferences.Key.desktopMusicScreen)
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.desktopMusicStyle, .card)
        XCTAssertEqual(p.desktopMusicScreen.count, 64, "gekürzt")
    }

    func testArtIsBundledWithMatchingSizes() throws {
        for img in [TurntableArt.base, TurntableArt.armTube, TurntableArt.armBearing, TurntableArt.armRest,
                    TurntableArt.armTubeShadow, TurntableArt.armBearingShadow, TurntableArt.armRestShadow] {
            let rep = try XCTUnwrap(try XCTUnwrap(img).representations.first)
            XCTAssertEqual(rep.pixelsWide, Int(TurntableArt.size.width))
            XCTAssertEqual(rep.pixelsHigh, Int(TurntableArt.size.height))
        }
        for img in [TurntableArt.plate, TurntableArt.sheen] {
            XCTAssertEqual(try XCTUnwrap(try XCTUnwrap(img).representations.first).pixelsWide, Int(TurntableGeometry.circleSize))
        }
        XCTAssertNotNil(TurntableArt.spindle)
    }

    /// Perspektive: Kreismitte landet auf der Achse, der Rand auf dem gemessenen Plattenrand; Inverse stimmt.
    func testGeometryMapsCenterAndRim() {
        let n = Double(TurntableGeometry.circleSize)
        let c = TurntableGeometry.circle.apply(CGPoint(x: n / 2, y: n / 2))
        XCTAssertEqual(c.x, 842.4, accuracy: 0.5)
        XCTAssertEqual(c.y, 341.8, accuracy: 0.5)
        let rightRim = TurntableGeometry.plane.apply(CGPoint(x: 1, y: 0))
        XCTAssertEqual(rightRim.y, 341.8, accuracy: 0.5, "waagrechter Durchmesser bleibt waagrecht")
        let p = CGPoint(x: 0.3, y: -0.6)
        let back = TurntableGeometry.plane.inverse.apply(TurntableGeometry.plane.apply(p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-6)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
    }

    func testArmRotatesAroundBearing() {
        let bearing = TurntableGeometry.plane.apply(TurntableGeometry.pivot)
        let moved = TurntableGeometry.arm(15).apply(bearing)
        XCTAssertEqual(moved.x, bearing.x, accuracy: 0.01, "Lager bleibt stehen")
        XCTAssertEqual(moved.y, bearing.y, accuracy: 0.01)
        XCTAssertEqual(TurntableGeometry.arm(0).apply(CGPoint(x: 100, y: 200)).x, 100, accuracy: 1e-6)
    }

    func testNeedleWandersInwardAndRetracksSmoothly() {
        let a = TurntableArmMotion()
        XCTAssertEqual(a.needleAngle(progress: 0, at: t0), TurntableGeometry.outerAngle, accuracy: 1e-9)
        XCTAssertEqual(a.needleAngle(progress: 1, at: t0), TurntableGeometry.innerAngle, accuracy: 1e-9)
        XCTAssertEqual(a.needleAngle(progress: .nan, at: t0), TurntableGeometry.outerAngle, accuracy: 1e-9)
        let r = a.retracked(from: 18, at: t0)
        XCTAssertEqual(r.needleAngle(progress: 0, at: t0), 18, accuracy: 1e-9, "kein Sprung beim Titelwechsel")
        XCTAssertEqual(r.needleAngle(progress: 0, at: t0.addingTimeInterval(5)), TurntableGeometry.outerAngle, accuracy: 1e-9)
    }

    /// Mitlaufen: klein, periodisch mit einer Umdrehung; Arm starr (nur Drehung), Schatten verschiebt sich.
    func testWobbleIsSmallAndPeriodic() {
        for deg in stride(from: 0.0, to: 360, by: 15) {
            let w = TurntableGeometry.wobble(plateAngle: deg)
            XCTAssertLessThan(abs(w.lateral), 0.08, "kaum seitlich (Michael: „wabbelig“, dann „zu stark“)")
            XCTAssertLessThan(abs(w.shadowShift), 3.5)
            XCTAssertEqual(w.shadowShift, TurntableGeometry.wobble(plateAngle: deg + 360).shadowShift, accuracy: 1e-9)
        }
        let moved = TurntableGeometry.shadowOffset(2).apply(.zero)
        XCTAssertEqual(hypot(moved.x, moved.y), 2, accuracy: 0.01)
    }

    func testArmSwingHasNoJumpEvenWhenReversed() {
        let m = TurntableArmMotion().switched(toPlaying: true, at: t0)
        XCTAssertEqual(m.phase(at: t0), 0, accuracy: 1e-9)
        let mid = m.phase(at: t0.addingTimeInterval(0.6))
        let back = m.switched(toPlaying: false, at: t0.addingTimeInterval(0.6))
        XCTAssertEqual(back.phase(at: t0.addingTimeInterval(0.6)), mid, accuracy: 1e-9, "Umkehr mitten im Schwenk")
        XCTAssertEqual(back.phase(at: t0.addingTimeInterval(5)), 0, accuracy: 1e-9)
        XCTAssertFalse(back.moving(at: t0.addingTimeInterval(5)))
    }

    /// Start/Stopp-Knopf (0.17.2): Fläche liegt auf dem Knopf im Sockelbild, nicht daneben.
    func testStartStopButtonCoversButtonInPhoto() {
        let corners = TurntableArt.startStop
        XCTAssertEqual(corners.count, 4)
        for p in corners {
            XCTAssertTrue((0...TurntableArt.size.width).contains(p.x) && (0...TurntableArt.size.height).contains(p.y))
        }
        let path = TurntableStartStopShape(corners: corners).path(in: .zero)
        XCTAssertTrue(path.contains(CGPoint(x: 170, y: 725)), "Knopfmitte")
        XCTAssertFalse(path.contains(CGPoint(x: 340, y: 760)), "33er-Knopf daneben")
        XCTAssertFalse(path.contains(CGPoint(x: 170, y: 640)), "Sockel darüber")
    }

    /// Messpunkt (27.10.): nur die beweglichen Ebenen, ohne Tönung und Maske – ist das Cover auf der Platte?
    func testRenderLayersOnly() throws {
        let model = NowPlayingModel()
        let artwork = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSColor.systemGreen.setFill(); rect.fill(); return true
        }
        model.setPreviewState(info: NowPlayingInfo(title: "Erfundener Titel", artist: "Muster-Band", album: nil,
                                                   appBundleID: nil, isPlaying: true, duration: 200, elapsedAtStamp: 10,
                                                   stamp: Date(), rate: 0, contentID: nil, artworkBase64: nil),
                              artwork: artwork)
        let view = TurntableView(media: model, deckWidth: 820).layers(at: Date()).background(Color.gray)
        let cg = try XCTUnwrap(ImageRenderer(content: view).cgImage)
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("gnotchi-island-turntable-ebenen.png"))
    }

    func testRenderTurntable() throws {
        let model = NowPlayingModel()
        let artwork = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemOrange, .systemPink])?.draw(in: rect, angle: -60)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 90, dy: 90)).fill()
            return true
        }
        model.setPreviewState(info: NowPlayingInfo(title: "Erfundener Titel", artist: "Muster-Band", album: "Testalbum",
                                                   appBundleID: nil, isPlaying: true, duration: 200, elapsedAtStamp: 10,
                                                   stamp: Date(), rate: 0, contentID: nil, artworkBase64: nil),
                              artwork: artwork)
        let size = CGSize(width: 1400, height: 900)
        let view = ZStack {
            TurntableBackdrop(media: model)
            TurntableView(media: model, deckWidth: 820, neon: true)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        let cg = try XCTUnwrap(renderer.cgImage)
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("gnotchi-island-turntable.png"))
    }
}
