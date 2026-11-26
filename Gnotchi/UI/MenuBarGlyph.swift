import AppKit
import OSLog

/// Menüleisten-Symbol der App-Familie (26.11.): Kopf mit Panda-Ohren, Notch-Pille und Play-Dreieck, 18 pt.
/// Liegt als Vorlagenbild im Asset-Katalog (`MenuBarGnotchi`, gerendert aus `design/menueleiste/gnotchi.svg`):
/// macOS übernimmt die Farbe (hell, dunkel, Glas, getönt). Die Restzeit des Timers daneben bleibt (GnotchiApp).
@MainActor
enum MenuBarGlyph {

    static let assetName = "MenuBarGnotchi"
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "start")

    static let image: NSImage = {
        if let img = NSImage(named: assetName) {
            img.isTemplate = true
            return img
        }
        // Nie ohne Symbol in der Menüleiste: Fehlt das Bild im Bündel, steht es im Protokoll, und die
        // bisherige gezeichnete Kapsel springt ein.
        log.notice("Menüleisten-Symbol \(assetName, privacy: .public) fehlt im Bündel – gezeichnete Kapsel als Ersatz")
        return fallback
    }()

    /// Bisheriges Symbol „Insel mit Pegel“ (bis 0.46): Kapsel mit drei ausgesparten Balken.
    private static var fallback: NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            let path = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3, width: 19, height: 10),
                                    xRadius: 5, yRadius: 5)
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
    }
}
