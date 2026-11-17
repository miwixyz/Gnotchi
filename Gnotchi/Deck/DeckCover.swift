import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Cover für das Stream Deck (G59 Punkt 10e). Nur mit eigenem Schalter „Cover auf dem Deck“ (ab Werk aus).
///
/// - Fremde Bilder (aus dem YouTube-Tab) werden **vor** dem Dekodieren geprüft: JPEG/PNG-Kennung, ≤ 16 KB, Seiten 1…256 px,
///   Decoder ImageIO. Alles andere → nil (kein Cover, keine Fehlermeldung an die Seite).
/// - Gnotchi skaliert jedes Bild selbst auf ≤ 144 px und kodiert es neu als JPEG ≤ `DeckWire.maxCoverBytes`. Ans Plugin geht
///   nie das Originalbild, nie eine Adresse.
enum DeckCover {

    nonisolated static let maxInputBytes = 16_384
    nonisolated static let maxInputPixels = 256
    nonisolated static let dataURLPrefixes = ["data:image/jpeg;base64,", "data:image/png;base64,"]

    /// Antwort des Tabs (`data:`-Adresse aus `canvas.toDataURL`) → geprüftes Bild.
    nonisolated static func image(dataURL s: String) -> CGImage? {
        guard let prefix = dataURLPrefixes.first(where: s.hasPrefix),
              s.utf8.count <= prefix.utf8.count + (maxInputBytes + 2) / 3 * 4,
              let d = Data(base64Encoded: String(s.dropFirst(prefix.count))) else { return nil }
        return image(data: d)
    }

    /// Fremde Bilddaten prüfen und dekodieren. Größe wird aus den Kopfdaten gelesen, bevor ein Pixel dekodiert wird.
    nonisolated static func image(data d: Data) -> CGImage? {
        guard !d.isEmpty, d.count <= maxInputBytes,
              d.starts(with: [0xFF, 0xD8, 0xFF]) || d.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { return nil }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(d as CFData, opts),
              let type = CGImageSourceGetType(src) as String?,
              type == UTType.jpeg.identifier || type == UTType.png.identifier,
              CGImageSourceGetCount(src) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              (1...maxInputPixels).contains(w), (1...maxInputPixels).contains(h) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, opts)
    }

    /// Cover aus der Insel (Adapter, schon begrenzt dekodiert nach G6) → Deck-Bild.
    @MainActor static func render(_ image: NSImage) -> Data? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return render(cg)
    }

    /// Auf ≤ 144 px skalieren (nie vergrößern) und als JPEG ≤ `DeckWire.maxCoverBytes` kodieren. Gelingt das nicht → nil.
    nonisolated static func render(_ image: CGImage) -> Data? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = min(1, Double(DeckWire.coverPixels) / Double(longest))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        for quality in [0.8, 0.6, 0.4] {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            if out.length <= DeckWire.maxCoverBytes { return out as Data }
        }
        return nil
    }
}
