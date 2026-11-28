import AppKit
import SwiftUI

/// Farbe einer App für die Kopfleiste der Zwischenablage-Karten (0.50.0, Vorbild Paste: Karte von Weitem an der
/// Quell-App erkennen). Aus dem App-Symbol auf dem Mac berechnet: häufigster kräftiger Farbton, auf eine lesbare
/// Helligkeit gebracht. Kein Netz, keine feste Markenliste. Graue/schwarze Symbole → `nil` (neutrale Leiste).
enum AppTint {

    struct Tint: Equatable {
        let hue: Double
        let saturation: Double
        let brightness: Double

        var color: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }

        /// Dunkle Schrift auf hellen Tönen (Gelb, Hellgrün), sonst weiß. Relative Luminanz nach WCAG.
        var prefersDarkText: Bool {
            let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
                .usingColorSpace(.sRGB) ?? .gray
            func lin(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let l = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
            return l > 0.4
        }
    }

    @MainActor private static var cache = BoundedCache<String, Tint?>(limit: 32)

    @MainActor
    static func tint(for bundleID: String) -> Tint? {
        if let hit = cache[bundleID] { return hit }
        let tint = AppIcons.icon(for: bundleID).flatMap(tint(of:))
        cache.insert(tint, for: bundleID)
        return tint
    }

    /// Symbol auf 32×32 rechnen und auswerten.
    static func tint(of image: NSImage) -> Tint? {
        let side = 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return tint(rgba: Array(UnsafeBufferPointer(start: data, count: side * side * 4)))
    }

    /// Rein, getestet: RGBA-Bytes (vormultipliziert oder nicht, Alpha ≥ 200 zählt) → Farbton.
    static func tint(rgba: [UInt8]) -> Tint? {
        let bins = 36
        var weight = [Double](repeating: 0, count: bins)
        var sums = [(s: Double, b: Double, x: Double, y: Double)](repeating: (0, 0, 0, 0), count: bins)
        var pixels = 0
        for i in stride(from: 0, to: rgba.count - 3, by: 4) where rgba[i + 3] >= 200 {
            pixels += 1
            let c = NSColor(srgbRed: CGFloat(rgba[i]) / 255, green: CGFloat(rgba[i + 1]) / 255,
                            blue: CGFloat(rgba[i + 2]) / 255, alpha: 1)
            let h = Double(c.hueComponent), s = Double(c.saturationComponent), b = Double(c.brightnessComponent)
            guard s >= 0.3, b >= 0.25 else { continue }
            let w = s * b
            let bin = min(Int(h * Double(bins)), bins - 1)
            weight[bin] += w
            // Farbton als Winkel mitteln (Rot liegt an beiden Enden).
            sums[bin].x += cos(h * 2 * .pi) * w
            sums[bin].y += sin(h * 2 * .pi) * w
            sums[bin].s += s * w
            sums[bin].b += b * w
        }
        guard pixels > 0 else { return nil }
        // Bin mit Nachbarn zusammen, damit ein Verlauf nicht auf zwei Fächer zerfällt.
        var best = 0
        var bestWeight = 0.0
        for i in 0..<bins {
            let w = weight[(i + bins - 1) % bins] + weight[i] + weight[(i + 1) % bins]
            if w > bestWeight { bestWeight = w; best = i }
        }
        // Zu wenig Farbe (graue, schwarze, weiße Symbole) → neutral.
        guard bestWeight / Double(pixels) >= 0.08 else { return nil }
        // Vielfarbig ohne klaren Sieger (Fotos, Chrome) → neutral statt eines zufälligen Tons.
        guard bestWeight / weight.reduce(0, +) >= 0.5 else { return nil }
        var x = 0.0, y = 0.0, s = 0.0, b = 0.0, w = 0.0
        for j in [(best + bins - 1) % bins, best, (best + 1) % bins] {
            x += sums[j].x; y += sums[j].y; s += sums[j].s; b += sums[j].b; w += weight[j]
        }
        var hue = atan2(y, x) / (2 * .pi)
        if hue < 0 { hue += 1 }
        return Tint(hue: hue, saturation: min(max(s / w, 0.5), 0.85), brightness: min(max(b / w, 0.62), 0.85))
    }
}
