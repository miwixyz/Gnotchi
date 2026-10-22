// Messwerkzeug 0.8.0 (22.10.): Erkennt Gnotchi ein Ziehen in einer anderen App ohne Freigabe (G1)?
// Liest nur NSEvent.pressedMouseButtons und NSPasteboard(name: .drag).changeCount + Typen (keine Inhalte).
// Aufruf: swift tools/drag-probe.swift [sekunden]  (Ausgabe nur bei Änderung)
import AppKit
setvbuf(stdout, nil, _IOLBF, 0)
let secs = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let pb = NSPasteboard(name: .drag)
var lastCount = pb.changeCount, lastButtons = NSEvent.pressedMouseButtons
let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
print(f.string(from: Date()), "Start, changeCount", lastCount)
let end = Date().addingTimeInterval(secs)
while Date() < end {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let c = pb.changeCount, b = NSEvent.pressedMouseButtons
    if c != lastCount || b != lastButtons {
        let types = c != lastCount ? (pb.types ?? []).map(\.rawValue).filter { !$0.hasPrefix("dyn.") }.prefix(6).joined(separator: ", ") : ""
        print(f.string(from: Date()), "Taste:", b, "changeCount:", c, types.isEmpty ? "" : "Typen: \(types)")
        lastCount = c; lastButtons = b
    }
}
print(f.string(from: Date()), "Ende")
