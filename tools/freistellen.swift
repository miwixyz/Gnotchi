// SYNTHETISCH – Werkzeug, keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
// 0.17.0: stellt das KI-Bild des Plattenspielers frei (Apple Vision, lokal, kein Netz) → PNG mit Transparenz.
// Aufruf: swiftc -O tools/freistellen.swift -o /tmp/gn-frei && /tmp/gn-frei <ein.png> <aus.png>
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3, let src = CIImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    print("Aufruf: freistellen <ein.png> <aus.png>"); exit(1)
}
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: src)
do {
    try handler.perform([request])
    guard let obs = request.results?.first else { print("kein Vordergrund gefunden"); exit(2) }
    print("Vordergrund-Objekte: \(obs.allInstances.count)")
    let masked = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
    let ci = CIImage(cvPixelBuffer: masked)
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(ci, from: ci.extent) else { print("Bild nicht erzeugt"); exit(3) }
    let rep = NSBitmapImageRep(cgImage: cg)
    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2]))
    print("geschrieben: \(args[2]) \(cg.width)x\(cg.height)")
} catch {
    print("Fehler: \(error.localizedDescription)"); exit(4)
}
