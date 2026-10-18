import AppKit

/// Menüleisten-Symbol „Insel mit Pegel“: eine Kapsel mit drei ausgesparten Balken.
/// Gezeichnet statt als Bild mitgeliefert – scharf in jeder Auflösung, und als
/// Vorlagenbild übernimmt macOS die Farbe (hell, dunkel, Glas, getönt).
@MainActor
enum MenuBarGlyph {

    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            let path = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3, width: 19, height: 10),
                                    xRadius: 5, yRadius: 5)
            // Balken mittig, außen kurz, in der Mitte lang (wie der Pegel im App-Symbol).
            for (center, height) in [(8.0, 3.6), (11.0, 6.4), (14.0, 3.6)] {
                path.append(NSBezierPath(roundedRect: NSRect(x: center - 0.8, y: 8 - height / 2,
                                                             width: 1.6, height: height),
                                         xRadius: 0.8, yRadius: 0.8))
            }
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
