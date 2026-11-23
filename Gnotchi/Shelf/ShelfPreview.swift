import AppKit
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Größere Vorschau in der Insel (0.42.0, G64): Bild oder erste PDF-Seite, verkleinert, nur im Speicher.
/// Kein eigenes Fenster (das Insel-Fenster ist nie in Bildschirmfreigabe, G58), kein Tasten-Beobachter (G1).
enum ShelfPreview {
    /// So lange ruht der Zeiger, bevor die Vorschau erscheint.
    nonisolated static let dwell: Duration = .milliseconds(600)
    /// Längste Seite der Vorschau in Pixeln.
    nonisolated static let maxPixelSize = 1_600
    /// Bilder mit mehr Pixeln werden nicht geöffnet (gleiche Größenordnung wie die Bildtext-Suche).
    nonisolated static let pixelLimit = 400_000_000
    /// Dateien über dieser Größe werden nicht gelesen.
    nonisolated static let byteLimit = 200 * 1_024 * 1_024

    /// Nur Bilder und PDFs; Ordner und symbolische Links nie.
    nonisolated static func canPreview(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentTypeKey]),
              values.isDirectory != true, values.isSymbolicLink != true, let type = values.contentType else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    /// Lädt die Vorschau abseits des Hauptthreads. nil bei Fehler, zu großer Datei oder zu vielen Pixeln.
    nonisolated static func load(_ url: URL) -> CGImage? {
        guard canPreview(url),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0, size <= byteLimit else { return nil }
        if (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .pdf) == true {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let box = page.bounds(for: .mediaBox)
            let scale = CGFloat(maxPixelSize) / max(box.width, box.height, 1)
            let target = CGSize(width: max(1, box.width * scale), height: max(1, box.height * scale))
            return page.thumbnail(of: target, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w * h <= pixelLimit else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}

/// Merkt sich das Insel-Fenster und zeigt die Vorschau in einem eigenen Fenster darunter (Muster der großen Ansicht in
/// der Zwischenablage, G40): nie aktiv, nimmt keine Maus und keine Tasten an, `sharingType = .none` (nie in
/// Bildschirmfreigabe oder -aufnahme, G58), nur im Speicher.
@MainActor
final class ShelfPreviewAnchor {
    fileprivate weak var island: NSWindow?
    private var panel: NSPanel?
    private var task: Task<Void, Never>?
    private var current: URL?
    private nonisolated static let maxSize = CGSize(width: 760, height: 560)

    func show(_ url: URL?) {
        task?.cancel()
        current = url
        guard let url, let island else { hide(); return }
        task = Task {
            let loaded = await Task.detached(priority: .userInitiated) { ShelfPreview.load(url) }.value
            guard !Task.isCancelled, current == url, let loaded else { return }
            place(loaded, below: island)
        }
    }

    private func hide() { panel?.orderOut(nil); panel?.contentView = nil }

    private func place(_ cg: CGImage, below island: NSWindow) {
        let visible = (island.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let top = island.frame.minY - 8
        let limit = CGSize(width: min(Self.maxSize.width, visible.width - 40), height: min(Self.maxSize.height, top - visible.minY - 12))
        guard limit.width > 80, limit.height > 80 else { return }
        let scale = min(limit.width / CGFloat(cg.width), limit.height / CGFloat(cg.height), 1)
        let size = CGSize(width: (CGFloat(cg.width) * scale).rounded(), height: (CGFloat(cg.height) * scale).rounded())
        let x = min(max(island.frame.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        let p = panel ?? makePanel()
        panel = p
        let view = NSImageView(image: NSImage(cgImage: cg, size: size))
        view.imageScaling = .scaleAxesIndependently
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        p.contentView = view
        p.setFrame(frame, display: true)
        p.level = NSWindow.Level(rawValue: island.level.rawValue + 1)
        p.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isReleasedWhenClosed = false
        p.title = ""
        return p
    }

    /// Liefert das Insel-Fenster der Ablage.
    struct Reader: NSViewRepresentable {
        let anchor: ShelfPreviewAnchor
        func makeNSView(context: Context) -> NSView { ShelfPreviewReaderView(anchor: anchor) }
        func updateNSView(_ view: NSView, context: Context) {}

    }
}

final class ShelfPreviewReaderView: NSView {
    let anchor: ShelfPreviewAnchor
    init(anchor: ShelfPreviewAnchor) { self.anchor = anchor; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() { MainActor.assumeIsolated { anchor.island = window } }
}
