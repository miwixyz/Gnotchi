import AppKit
import SwiftUI
import XCTest

/// 0.50.0: App-Farbe aus dem Symbol und Kartenangaben.
@MainActor
final class AppTintTests: XCTestCase {

    /// `count` gleiche Pixel als RGBA-Bytes.
    private func px(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8, _ count: Int) -> [UInt8] {
        (0..<count).flatMap { _ in [r, g, b, a] }
    }

    func testRedIconGivesRedHue() throws {
        let t = try XCTUnwrap(AppTint.tint(rgba: px(230, 30, 40, 255, 64)))
        XCTAssertTrue(t.hue < 0.03 || t.hue > 0.97, "Rot, auch über die 0-Grenze gemittelt: \(t.hue)")
        XCTAssertFalse(t.prefersDarkText)
    }

    /// Rot an beiden Enden des Farbkreises darf nicht zu Türkis (Mittelwert 0,5) werden.
    func testRedAcrossHueWrapStaysRed() throws {
        let mix = px(230, 20, 60, 255, 32) + px(230, 60, 20, 255, 32)
        let t = try XCTUnwrap(AppTint.tint(rgba: mix))
        XCTAssertTrue(t.hue < 0.06 || t.hue > 0.94, "\(t.hue)")
    }

    func testGrayAndTransparentGiveNoTint() {
        XCTAssertNil(AppTint.tint(rgba: px(128, 128, 128, 255, 64)))
        XCTAssertNil(AppTint.tint(rgba: px(230, 30, 40, 0, 64)))
        XCTAssertNil(AppTint.tint(rgba: []))
    }

    /// Ein kleiner farbiger Fleck auf grauem Symbol reicht nicht (unter 8 % kräftige Farbe).
    func testTinyAccentOnGrayIsNeutral() {
        let list = px(120, 120, 120, 255, 98) + px(20, 90, 230, 255, 2)
        XCTAssertNil(AppTint.tint(rgba: list))
    }

    /// Vier gleich starke Farben (wie Fotos oder Chrome) → kein Sieger, neutrale Leiste.
    func testMulticolorIconIsNeutral() {
        let list = px(230, 40, 40, 255, 25) + px(40, 180, 60, 255, 25)
            + px(40, 90, 230, 255, 25) + px(245, 200, 30, 255, 25)
        XCTAssertNil(AppTint.tint(rgba: list))
    }

    func testDominantColorWins() throws {
        let list = px(20, 90, 230, 255, 60) + px(240, 200, 20, 255, 20)
        let t = try XCTUnwrap(AppTint.tint(rgba: list))
        XCTAssertEqual(t.hue, 0.6, accuracy: 0.05, "Blau überwiegt")
    }

    func testYellowPrefersDarkTextAndBrightnessIsClamped() throws {
        let t = try XCTUnwrap(AppTint.tint(rgba: px(250, 210, 30, 255, 64)))
        XCTAssertTrue(t.prefersDarkText)
        XCTAssertLessThanOrEqual(t.brightness, 0.85)
        let dark = try XCTUnwrap(AppTint.tint(rgba: px(40, 10, 120, 255, 64)))
        XCTAssertGreaterThanOrEqual(dark.brightness, 0.62, "dunkles Lila aufgehellt")
    }

    // MARK: Angaben

    private func text(_ s: String) -> ClipPayload {
        ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data(s.utf8))], plain: s)
    }

    func testDetailCountsCharactersNotBytes() {
        XCTAssertEqual(ClipMeta.detail(kind: .text, payload: text("Grüße"), isColor: false, id: UUID()), "5 Zeichen")
        XCTAssertEqual(ClipMeta.detail(kind: .text, payload: text("a"), isColor: false, id: UUID()), "1 Zeichen")
        XCTAssertNil(ClipMeta.detail(kind: .text, payload: text("#E50914"), isColor: true, id: UUID()))
        XCTAssertNil(ClipMeta.detail(kind: .link, payload: text("https://example.com"), isColor: false, id: UUID()))
    }

    func testDetailReadsImageSizeFromHeader() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 160,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let payload = ClipPayload(formats: [.init(type: ClipboardCapture.UTI.png, data: png)], plain: "")
        XCTAssertEqual(ClipMeta.detail(kind: .image, payload: payload, isColor: false, id: UUID()), "240 × 160")
        let broken = ClipPayload(formats: [.init(type: ClipboardCapture.UTI.png, data: Data("kaputt".utf8))], plain: "")
        XCTAssertNil(ClipMeta.detail(kind: .image, payload: broken, isColor: false, id: UUID()))
    }

    func testKindLabels() {
        XCTAssertEqual(ClipMeta.kindLabel(.text, isColor: true, concealed: false, vault: false), "Farbe")
        XCTAssertEqual(ClipMeta.kindLabel(.text, isColor: false, concealed: true, vault: false), "Schlüssel")
        XCTAssertEqual(ClipMeta.kindLabel(.link, isColor: false, concealed: false, vault: true), "Tresor")
        XCTAssertEqual(ClipMeta.kindLabel(.image, isColor: false, concealed: false, vault: false), "Bild")
    }
}

/// Musterbogen der Kopfleisten für installierte Apps (nur mit GNOTCHI_RENDER_DIR, nur App-Symbole, keine Inhalte).
@MainActor
final class AppTintRenderTests: XCTestCase {
    func testRenderTintSheet() throws {
        let ids = ["com.apple.mail", "com.apple.Notes", "com.apple.MobileSMS", "com.apple.Photos", "com.apple.Music",
                   "com.apple.Safari", "com.apple.finder", "com.apple.TextEdit", "com.apple.Terminal",
                   "com.apple.reminders", "com.apple.iCal", "com.apple.Preview", "net.imput.helium", "md.obsidian",
                   "com.spotify.client", "com.microsoft.teams2", "com.microsoft.Outlook", "com.google.Chrome",
                   "com.apple.dt.Xcode", "com.microsoft.edgemac"]
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        let view = VStack(alignment: .leading, spacing: 6) {
            ForEach(ids, id: \.self) { id in
                let tint = AppTint.tint(for: id)
                HStack(spacing: 4) {
                    Text(verbatim: AppIcons.name(for: id) ?? id).font(.system(size: 10, weight: .semibold))
                    Text(verbatim: "vor 5 Min.").font(.system(size: 9)).opacity(0.75)
                    Spacer(minLength: 0)
                    AppSymbol(bundleID: id, size: 14)
                }
                .foregroundStyle(tint?.prefersDarkText == true ? Color.black : Color.white)
                .padding(.horizontal, 8)
                .frame(width: 160, height: 20)
                .background(tint?.color ?? Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage)
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("gnotchi-island-app-tints.png"))
    }
}
