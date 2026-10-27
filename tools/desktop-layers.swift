// SYNTHETISCH – Testwerkzeug, enthält keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
// Spike 0.17.0 (Spec specs/2026-10-27-gnotchi-0.17.0-plattenspieler.md, Entscheidung 9): Bleibt eine Farbfläche auf
// Schreibtischhöhe UNTER den Finder-Symbolen und über dem Hintergrundbild, und liegt ein Platzhalter darüber?
// Zeigt beides `sekunden` lang auf dem Hauptbildschirm und liest dabei die Fensterliste (Ebene, Besitzer, Größe).
// Aufruf: swiftc -O tools/desktop-layers.swift -o /tmp/gn-layers && /tmp/gn-layers [sekunden=25]
import AppKit

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 25 : 25
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.screens[0]
let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

func makeWindow(_ rect: NSRect, level: Int) -> NSWindow {
    let w = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
    w.level = NSWindow.Level(rawValue: level)
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    return w
}

// Farbfläche: ganzer Hauptbildschirm, eine Ebene über dem Hintergrundbild.
let back = makeWindow(screen.frame, level: desktopLevel + 1)
let grad = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
grad.wantsLayer = true
let g = CAGradientLayer()
g.frame = grad.bounds
g.colors = [NSColor(calibratedRed: 0.55, green: 0.18, blue: 0.20, alpha: 0.92).cgColor,
            NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.40, alpha: 0.92).cgColor]
grad.layer?.addSublayer(g)
back.contentView = grad
back.orderFront(nil)

// Platzhalter: Drittel in der Mitte, über den Symbolen (wie die Karte aus 0.15.0).
let side = min(screen.frame.width, screen.frame.height) / 3
let mid = NSRect(x: screen.frame.midX - side / 2, y: screen.frame.midY - side / 2, width: side, height: side)
let front = makeWindow(mid, level: iconLevel + 1)
let box = NSTextField(labelWithString: "Gnotchi-Test\nPlattenspieler-Platzhalter")
box.alignment = .center
box.font = .systemFont(ofSize: 22, weight: .semibold)
box.textColor = .white
box.wantsLayer = true
box.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
box.layer?.cornerRadius = 24
box.frame = NSRect(origin: .zero, size: mid.size)
front.contentView = box
front.orderFront(nil)

print("Ebenen: Hintergrund(desktop)=\(desktopLevel) Symbole(desktopIcon)=\(iconLevel) Farbe=\(desktopLevel + 1) Platzhalter=\(iconLevel + 1)")

func dump(_ label: String) {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    print("— \(label): Fenster unterhalb der normalen Ebene, von oben nach unten")
    for w in list {
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        guard layer < 0 || layer == iconLevel + 1 else { continue }
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
        print("  Ebene \(layer)  \(owner)  \(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0)) @\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0))  alpha \(alpha)")
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 2) { dump("nach 2 s") }
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { dump("Ende"); app.terminate(nil) }
app.run()
