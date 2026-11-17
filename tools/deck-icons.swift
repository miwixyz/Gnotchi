// Zeichnet die Symbole des Stream-Deck-Plugins (G59) als Strich-Piktogramme in PNG. Einmal laufen lassen, Ergebnis liegt im Repo:
//   swiftc -O tools/deck-icons.swift -o /tmp/deck-icons && /tmp/deck-icons GnotchiDeck/dev.mwlr.gnotchi.deck.sdPlugin/imgs
// Keine Emojis, keine fremden Symbole (SF Symbols nicht außerhalb von Apple-Oberflächen).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let gold = NSColor(red: 0xE3 / 255, green: 0xB6 / 255, blue: 0x6A / 255, alpha: 1)
let light = NSColor(white: 0.92, alpha: 1)
let tile = NSColor(white: 0.13, alpha: 1)

enum Glyph { case speaker, play }

func draw(_ glyph: Glyph, size: Int, color: NSColor, background: NSColor?) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    if let background {
        background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: s * 0.18, yRadius: s * 0.18).fill()
    }
    color.setStroke()
    let line = max(1.5, s * 0.07)
    switch glyph {
    case .speaker:
        let p = NSBezierPath()
        p.move(to: NSPoint(x: s * 0.18, y: s * 0.40))
        p.line(to: NSPoint(x: s * 0.32, y: s * 0.40))
        p.line(to: NSPoint(x: s * 0.50, y: s * 0.24))
        p.line(to: NSPoint(x: s * 0.50, y: s * 0.76))
        p.line(to: NSPoint(x: s * 0.32, y: s * 0.60))
        p.line(to: NSPoint(x: s * 0.18, y: s * 0.60))
        p.close()
        p.lineWidth = line
        p.lineJoinStyle = .round
        p.stroke()
        for (r, a) in [(s * 0.14, 50.0), (s * 0.26, 45.0)] {
            let w = NSBezierPath()
            w.appendArc(withCenter: NSPoint(x: s * 0.52, y: s * 0.5), radius: r, startAngle: -a, endAngle: a)
            w.lineWidth = line
            w.lineCapStyle = .round
            w.stroke()
        }
    case .play:
        let p = NSBezierPath()
        p.move(to: NSPoint(x: s * 0.34, y: s * 0.24))
        p.line(to: NSPoint(x: s * 0.76, y: s * 0.50))
        p.line(to: NSPoint(x: s * 0.34, y: s * 0.76))
        p.close()
        p.lineWidth = line
        p.lineJoinStyle = .round
        p.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ name: String, _ glyph: Glyph, base: Int, color: NSColor, background: NSColor? = nil) {
    for (suffix, scale) in [("", 1), ("@2x", 2)] {
        try! draw(glyph, size: base * scale, color: color, background: background)
            .write(to: out.appendingPathComponent("\(name)\(suffix).png"))
    }
}

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
write("plugin", .speaker, base: 256, color: gold, background: tile)
write("category", .speaker, base: 28, color: light)
write("volume", .speaker, base: 20, color: light)
// Reglerbild und Zustandsbild müssen 72 × 72 sein (Manifest-Schema „Encoder.Icon“); mit 20 × 20 fehlte die Aktion in der Liste.
write("volume-dial", .speaker, base: 72, color: gold, background: tile)
write("play", .play, base: 20, color: light)
// Tastenbild bleibt leer (dunkel): Name und Zeichen kommen als Titel.
write("play-key", .play, base: 72, color: NSColor(white: 1, alpha: 0.08), background: tile)
print("Symbole geschrieben nach \(out.path)")
