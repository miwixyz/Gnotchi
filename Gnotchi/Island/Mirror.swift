import AVFoundation
import AppKit
import OSLog
import SwiftUI

/// Spiegel (0.5.0, specs/2026-10-21-gnotchi-0.5.0-spiegel.md, SECURE-DESIGN G27): Kamerabild in der großen Insel.
///
/// Das Bild geht **nur** von der `AVCaptureSession` direkt in eine `AVCaptureVideoPreviewLayer` – kein
/// Video- oder Foto-Ausgang, kein Puffer im eigenen Code, nichts auf der Platte. Die Kamera läuft nur, solange
/// der Spiegel sichtbar ist (`MirrorView.onAppear`/`onDisappear`). Protokoll ohne Inhalt.
final class MirrorCamera: @unchecked Sendable {

    enum Status: Equatable, Sendable { case starting, running, denied, noCamera }

    static let shared = MirrorCamera()
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "spiegel")

    /// Nur auf `queue` verändert; die Vorschau-Ebene hält eine Referenz zum Anzeigen.
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.mwlr.gnotchi.mirror")
    private var configured = false
    /// Zählt Starts: Ein spätes `startRunning` nach einem schnellen `stop` darf die Kamera nicht anlassen.
    private var generation = 0

    /// Fragt beim ersten Mal nach der Freigabe (ausgelöst durch den Klick), startet dann die Kamera.
    func start(_ status: @escaping @MainActor @Sendable (Status) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run(status)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [self] ok in
                if ok { run(status) } else { Task { @MainActor in status(.denied) } }
            }
        default:
            Self.log.notice("Spiegel: Kamera nicht erlaubt")
            Task { @MainActor in status(.denied) }
        }
    }

    func stop() {
        queue.async { [self] in
            generation += 1
            guard session.isRunning else { return }
            session.stopRunning()
            Self.log.notice("Spiegel aus")
        }
    }

    private func run(_ status: @escaping @MainActor @Sendable (Status) -> Void) {
        queue.async { [self] in
            generation += 1
            let mine = generation
            guard configure() else {
                Self.log.notice("Spiegel: keine Kamera")
                Task { @MainActor in status(.noCamera) }
                return
            }
            guard mine == generation, !session.isRunning else { return }
            session.startRunning()
            Self.log.notice("Spiegel an")
            Task { @MainActor in status(.running) }
        }
    }

    /// Einmalig: Standard-Kamera als einziger Eingang, **kein** Ausgang außer der Vorschau-Ebene.
    private func configure() -> Bool {
        if configured { return true }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.commitConfiguration()
        configured = true
        return true
    }
}

/// Große Insel, Spiegel: Kamerabild gespiegelt, abgerundet; ohne Freigabe bzw. Kamera eine Karte.
struct MirrorView: View {
    let onSettings: () -> Void
    @State private var status = MirrorCamera.Status.starting

    var body: some View {
        ZStack {
            CameraPreview(session: MirrorCamera.shared.session, running: status == .running)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            switch status {
            case .denied:
                ActivityCard(title: "Kamera nicht erlaubt", subtitle: "Freigabe in den Systemeinstellungen",
                             action: "Einstellungen", onTap: onSettings, leading: {
                    Image(systemName: "video.slash.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                })
            case .noCamera:
                ActivityCard(title: "Keine Kamera gefunden", subtitle: "Spiegel nicht verfügbar") {
                    Image(systemName: "video.slash.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                }
            case .starting, .running:
                EmptyView()
            }
        }
        .onAppear { MirrorCamera.shared.start { status = $0 } }
        .onDisappear { MirrorCamera.shared.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Spiegel"))
    }

    /// Datenschutz → Kamera in den Systemeinstellungen.
    static func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Vorschau-Ebene, waagrecht gespiegelt wie ein Spiegel.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let running: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Die Verbindung gibt es erst, wenn die Sitzung einen Eingang hat (nach dem Start).
        guard running, let connection = (view.layer as? AVCaptureVideoPreviewLayer)?.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
