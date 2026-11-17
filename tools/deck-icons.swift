// ABGELÖST (17.11.2026): NICHT MEHR LAUFEN LASSEN – es würde die Glas-Symbole in `imgs/` mit dem alten Stil überschreiben.
// Die Plugin-Bilder kommen jetzt aus dem Skill „streamdeck-glas“ (Designsprache „Glas“, gilt für alle Stream-Deck-Plugins
// von Michael: dunkle Glasfläche, weiße Lucide-Linien, Leuchten je Kategorie, Medien = Terrakotta #E9A27F). Neu erzeugen:
//   node "$HOME/MWs2ndBrain/04 Ressourcen/Claude Skills/streamdeck-glas/scripts/build.mjs" plugins gnotchi --out /tmp/gnotchi-glas
//   cp /tmp/gnotchi-glas/plugins/gnotchi/imgs/*.png GnotchiDeck/dev.mwlr.gnotchi.deck.sdPlugin/imgs/
// Bildnamen und Grundgrößen stehen dort in `plugins.json`; ein neues Bild im Plugin zuerst dort eintragen.
// Die Datei bleibt nur als Nachweis des alten Stils im Repo.
//
// (Alt) Zeichnet die Symbole des Stream-Deck-Plugins (G59) als PNG – einheitlicher Satz im Stil der App-Familie (Michael 17.11.:
// „schöne passende Icons“, dann „Gelb ist eine so hässliche Farbe, mach das passend zu Gnotchi und Tippi“): dunkle Fläche
// mit leichtem Verlauf, helle Zeichen, Akzent Schiefer-Iris (#98A9E1, FamilyTheme dunkel, wie Seam/Tippi), runde Linien,
// gefüllte Wiedergabe-Zeichen. Tastenbilder lassen unten Platz für den Titel (App-Name).
// Einmal laufen lassen, Ergebnis liegt im Repo:
//   swiftc -O tools/deck-icons.swift -o /tmp/deck-icons && /tmp/deck-icons GnotchiDeck/dev.mwlr.gnotchi.deck.sdPlugin/imgs
// Keine Emojis, keine fremden Symbole (SF Symbols nicht außerhalb von Apple-Oberflächen).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
/// Zeichen: fast weiß, wie Systemsymbole im Dunkelmodus. Akzent: Schiefer-Iris der App-Familie (nur Plugin-Symbol).
let gold = NSColor(red: 0xEE / 255, green: 0xEF / 255, blue: 0xF4 / 255, alpha: 1)
let goldDim = NSColor(red: 0xEE / 255, green: 0xEF / 255, blue: 0xF4 / 255, alpha: 0.32)
let accent = NSColor(red: 0x98 / 255, green: 0xA9 / 255, blue: 0xE1 / 255, alpha: 1)
let white = NSColor(white: 1, alpha: 1)

enum Glyph { case speaker, speakerUp, speakerDown, speakerMute, play, pause, next, previous, route }

/// Feld 0…1 → Pixel; y von oben gedacht, CoreGraphics zählt von unten.
struct Canvas {
    let box: CGRect
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: box.minX + x * box.width, y: box.maxY - y * box.height) }
    func r(_ v: CGFloat) -> CGFloat { v * box.width }
}

func stroke(_ path: NSBezierPath, _ c: Canvas, width: CGFloat) {
    path.lineWidth = c.r(width)
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func speakerBody(_ c: Canvas, x0: CGFloat = 0.10, x1: CGFloat = 0.26, x2: CGFloat = 0.48) -> NSBezierPath {
    let b = NSBezierPath()
    b.move(to: c.p(x0, 0.38)); b.line(to: c.p(x1, 0.38)); b.line(to: c.p(x2, 0.18))
    b.line(to: c.p(x2, 0.82)); b.line(to: c.p(x1, 0.62)); b.line(to: c.p(x0, 0.62)); b.close()
    return b
}

func drawGlyph(_ g: Glyph, _ c: Canvas, color: NSColor) {
    color.setStroke()
    color.setFill()
    let w: CGFloat = 0.075
    switch g {
    case .speaker, .speakerUp, .speakerDown, .speakerMute:
        let body = speakerBody(c)
        body.fill()
        stroke(body, c, width: 0.03)
        if g == .speaker {
            for (rad, deg) in [(0.17, 46.0), (0.31, 42.0)] {
                let a = NSBezierPath()
                a.appendArc(withCenter: c.p(0.50, 0.50), radius: c.r(rad), startAngle: -deg, endAngle: deg)
                stroke(a, c, width: w)
            }
        } else if g == .speakerMute {
            let x = NSBezierPath()
            x.move(to: c.p(0.63, 0.37)); x.line(to: c.p(0.89, 0.63))
            x.move(to: c.p(0.89, 0.37)); x.line(to: c.p(0.63, 0.63))
            stroke(x, c, width: w)
        } else {
            let m = NSBezierPath()
            m.move(to: c.p(0.62, 0.50)); m.line(to: c.p(0.90, 0.50))
            if g == .speakerUp { m.move(to: c.p(0.76, 0.36)); m.line(to: c.p(0.76, 0.64)) }
            stroke(m, c, width: w)
        }
    case .play:
        let t = NSBezierPath()
        t.move(to: c.p(0.30, 0.18)); t.line(to: c.p(0.82, 0.50)); t.line(to: c.p(0.30, 0.82)); t.close()
        t.fill(); stroke(t, c, width: 0.06)
    case .pause:
        for x in [0.28, 0.58] as [CGFloat] {
            let top = c.p(x, 0.20), bottom = c.p(x, 0.80)
            NSBezierPath(roundedRect: NSRect(x: top.x, y: bottom.y, width: c.r(0.14), height: top.y - bottom.y),
                         xRadius: c.r(0.04), yRadius: c.r(0.04)).fill()
        }
    case .next, .previous:
        let flip = g == .previous
        func X(_ v: CGFloat) -> CGFloat { flip ? 1 - v : v }
        for start in [0.12, 0.42] as [CGFloat] {
            let t = NSBezierPath()
            t.move(to: c.p(X(start), 0.26)); t.line(to: c.p(X(start + 0.30), 0.50)); t.line(to: c.p(X(start), 0.74)); t.close()
            t.fill(); stroke(t, c, width: 0.05)
        }
        let bar = NSBezierPath()
        bar.move(to: c.p(X(0.82), 0.26)); bar.line(to: c.p(X(0.82), 0.74))
        stroke(bar, c, width: 0.08)
    case .route:
        let body = speakerBody(c, x0: 0.06, x1: 0.18, x2: 0.36)
        body.fill(); stroke(body, c, width: 0.03)
        let a = NSBezierPath()
        a.move(to: c.p(0.50, 0.50)); a.line(to: c.p(0.92, 0.50))
        a.move(to: c.p(0.77, 0.35)); a.line(to: c.p(0.92, 0.50)); a.line(to: c.p(0.77, 0.65))
        stroke(a, c, width: w)
    }
}

/// `tile`: dunkle Fläche mit Verlauf. `scale`: Anteil der Breite für die Glyphe, `top`: Abstand oben (Anteil).
func render(_ g: Glyph, size: Int, color: NSColor, tile: Bool, scale: CGFloat, top: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    if tile {
        // Kühles Dunkelgrau (Schiefer-Unterton) statt warmem Braun.
        NSGradient(starting: NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1),
                   ending: NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    }
    let gs = s * scale
    drawGlyph(g, Canvas(box: CGRect(x: (s - gs) / 2, y: s - s * top - gs, width: gs, height: gs)), color: color)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ name: String, _ g: Glyph, base: Int, color: NSColor, tile: Bool, scale: CGFloat, top: CGFloat) {
    for (suffix, factor) in [("", 1), ("@2x", 2)] {
        try! render(g, size: base * factor, color: color, tile: tile, scale: scale, top: top)
            .write(to: out.appendingPathComponent("\(name)\(suffix).png"))
    }
}

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Plugin-Symbol (Marktplatz/Einstellungen): Gold auf Fläche.
write("plugin", .speaker, base: 256, color: accent, tile: true, scale: 0.62, top: 0.19)
// Aktionsliste in Stream Deck: einfarbig weiß, ohne Fläche (Elgato-Stil).
write("category", .speaker, base: 28, color: white, tile: false, scale: 0.9, top: 0.05)
write("volume", .speaker, base: 20, color: white, tile: false, scale: 0.95, top: 0.025)
write("play", .play, base: 20, color: white, tile: false, scale: 0.95, top: 0.025)
write("output", .route, base: 20, color: white, tile: false, scale: 0.95, top: 0.025)
// Regler (rund dargestellt): Glyphe mittig.
write("volume-dial", .speaker, base: 72, color: gold, tile: true, scale: 0.56, top: 0.22)
write("output-dial", .route, base: 72, color: gold, tile: true, scale: 0.56, top: 0.22)
// Tastenbilder: Glyphe unten, oben Platz für den Titel (Michael 17.11.: „Text bitte oberhalb“). Je Zustand ein Bild.
write("key-volume", .speaker, base: 72, color: gold, tile: true, scale: 0.50, top: 0.40)
write("key-volume-up", .speakerUp, base: 72, color: gold, tile: true, scale: 0.50, top: 0.40)
write("key-volume-down", .speakerDown, base: 72, color: gold, tile: true, scale: 0.50, top: 0.40)
write("key-mute", .speakerMute, base: 72, color: gold, tile: true, scale: 0.50, top: 0.40)
write("key-muted", .speakerMute, base: 72, color: goldDim, tile: true, scale: 0.50, top: 0.40)
write("key-play", .play, base: 72, color: gold, tile: true, scale: 0.46, top: 0.42)
write("key-pause", .pause, base: 72, color: gold, tile: true, scale: 0.46, top: 0.42)
write("key-next", .next, base: 72, color: gold, tile: true, scale: 0.50, top: 0.40)
write("key-previous", .previous, base: 72, color: gold, tile: true, scale: 0.50, top: 0.40)
write("key-output", .route, base: 72, color: gold, tile: true, scale: 0.50, top: 0.40)
print("Symbole geschrieben nach \(out.path)")
