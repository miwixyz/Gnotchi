// SYNTHETISCH – Testwerkzeug, enthält keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
// Sichttest 0.2.0: sichtbare Fenster eines Prozesses mit Lage und Größe (CGWindowList, ohne Titel –
// braucht kein Bildschirmfoto-Recht). Aufruf: swift tools/island-windows.swift <pid>
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments.dropFirst().first ?? "") ?? 0
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
let rects = mine.compactMap { w -> String? in
    guard let d = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) else { return nil }
    return "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))"
}
print("\(Date().formatted(date: .omitted, time: .standard)) sichtbar: \(rects.count) \(rects.joined(separator: " · "))")
