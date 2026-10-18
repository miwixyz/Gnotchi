import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cover aus dem Adapter-Strom (G6). Bilddaten kommen von beliebigen Websites;
/// ImageIO ist der Systemparser, wir begrenzen nur, was er zu sehen bekommt.
enum Artwork {
    /// Gleiche Grenze wie beim Parsen der Zeile – eine Quelle der Wahrheit.
    static let maxBase64Bytes = NowPlayingInfo.maxArtworkBase64Bytes
    static let maxPixel = 256
    /// Dekompressionsbombe: ein winziges (z. B. interlaced) PNG kann 30000 × 30000 px deklarieren
    /// und beim Dekodieren hunderte MB und Sekunden kosten. Der Header ist billig zu lesen.
    static let maxDimension = 8192
    static let maxPixels = 16_000_000
    private static let allowed: Set<String> = [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier]

    /// Nicht auf dem Hauptthread aufrufen (Dekodieren kann ~0.3 s dauern).
    static func decode(base64: String) -> CGImage? {
        // Größe zuerst prüfen: nichts Übergroßes dekodieren oder an ImageIO geben.
        guard base64.utf8.count <= maxBase64Bytes,
              let data = Data(base64Encoded: base64),
              let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(src) as String?, allowed.contains(type),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= maxDimension, h <= maxDimension, w * h <= maxPixels else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
