import SwiftUI
import XCTest

// SYNTHETISCH – erfundene Einträge, keine echten Kalenderdaten (Datenschutz-Gate, SECURE-DESIGN G16)

/// Bilder der Eingabezeile (G61) für die Sichtprüfung: mit `GNOTCHI_RENDER_DIR` als PNG, sonst nur „rendert“.
@MainActor
final class QuickEntryRenderTests: XCTestCase {

    private func render(_ state: QuickEntryState, name: String) throws {
        let size = QuickEntryPanelController.size
        let view = QuickEntryView(state: state, topInset: 32)
            .frame(width: size.width, height: size.height + 32)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage, "ImageRenderer lieferte kein Bild")
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("gnotchi-quickentry-\(name).png"), options: .atomic)
    }

    private func state(_ text: String, result: Result<UUID, QuickEntryFailure> = .success(UUID())) -> QuickEntryState {
        let s = QuickEntryState(submit: { _ in result }, undo: { _ in nil }, close: {})
        s.text = text
        return s
    }

    func testRenderStates() async throws {
        try render(state("Zahnarzt morgen 15 Uhr"), name: "vorschau")
        try render(state("Mittwoch halb drei Friseur"), name: "pruefen")
        try render(state("Rechnung zahlen bis 30.11. !"), name: "erinnerung")
        let saved = state("Zahnarzt morgen 15 Uhr")
        await saved.save()
        saved.cancelPendingClose()
        try render(saved, name: "gespeichert")
        let failed = state("Zahnarzt morgen 15 Uhr", result: .failure(.kalliNotRunning))
        await failed.save()
        try render(failed, name: "fehler")
    }
}
