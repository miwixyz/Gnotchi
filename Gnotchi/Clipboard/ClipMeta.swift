import Foundation
import ImageIO

/// Beschriftung der Zwischenablage-Karten (0.50.0): Art oben in der Kopfleiste, Angabe unten („65 Zeichen“,
/// „2400 × 2400“). Rein bis auf das Auslesen der Bildmaße (nur Kopfdaten, das Bild wird nicht dekodiert).
enum ClipMeta {

    static func kindLabel(_ kind: ClipKind, isColor: Bool, concealed: Bool, vault: Bool) -> String {
        if vault { return String(localized: "Tresor") }
        if concealed { return String(localized: "Schlüssel") }
        if isColor { return String(localized: "Farbe") }
        switch kind {
        case .text, .richText: return String(localized: "Text")
        case .link: return String(localized: "Link")
        case .image: return String(localized: "Bild")
        case .file: return String(localized: "Datei")
        }
    }

    /// `nil` = nichts anzuzeigen (Link, Datei, Farbe, verdeckt).
    @MainActor
    static func detail(kind: ClipKind, payload: ClipPayload, isColor: Bool, id: UUID) -> String? {
        guard !isColor else { return nil }
        switch kind {
        case .text, .richText:
            let n = payload.plain.count
            return n == 1 ? String(localized: "1 Zeichen") : String(localized: "\(n) Zeichen")
        case .image:
            return pixelSize(payload, id: id).map { "\($0.width) × \($0.height)" }
        case .link, .file:
            return nil
        }
    }

    @MainActor private static let sizes = NSCache<NSUUID, NSValue>()

    /// Pixelmaße des ersten Bildformats aus den Kopfdaten (CGImageSource), zwischengespeichert.
    @MainActor
    static func pixelSize(_ payload: ClipPayload, id: UUID) -> (width: Int, height: Int)? {
        let key = id as NSUUID
        if let hit = sizes.object(forKey: key) { return (Int(hit.sizeValue.width), Int(hit.sizeValue.height)) }
        for format in payload.formats {
            guard let source = CGImageSourceCreateWithData(format.data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int,
                  let h = props[kCGImagePropertyPixelHeight] as? Int else { continue }
            sizes.setObject(NSValue(size: NSSize(width: w, height: h)), forKey: key)
            return (w, h)
        }
        return nil
    }
}
