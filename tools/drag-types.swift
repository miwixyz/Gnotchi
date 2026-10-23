// Messwerkzeug 0.9.1 (23.10.): Was legt eine App beim Ziehen auf die Zieh-Zwischenablage? Typen je Element,
// dazu public.file-url / promised-file-url mit „existiert/lesbar“ (Fotos: Verweis zeigt nur auf eine Vorschau).
// Aufruf: swiftc -O tools/drag-types.swift -o /tmp/gn-dragtypes && /tmp/gn-dragtypes [sekunden]  (Ausgabe nur bei Änderung)
// Gibt Pfade aus (Dateinamen) – Ausgabe nur nach /tmp, nie ins Repo.
import AppKit
setvbuf(stdout, nil, _IOLBF, 0)
let pb = NSPasteboard(name: .drag)
var last = pb.changeCount
let end = Date().addingTimeInterval(Double(CommandLine.arguments.dropFirst().first ?? "180") ?? 180)
print("Start", last)
while Date() < end {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let c = pb.changeCount
    guard c != last else { continue }
    last = c
    for (i, item) in (pb.pasteboardItems ?? []).enumerated() {
        print(c, "Element", i, item.types.map(\.rawValue).filter { !$0.hasPrefix("dyn.") }.joined(separator: " | "))
        for t in ["public.file-url", "com.apple.pasteboard.promised-file-url"] {
            guard let s = item.string(forType: NSPasteboard.PasteboardType(t)), let u = URL(string: s), u.isFileURL else { continue }
            print("  ", t, "=>", u.path, "existiert=\(FileManager.default.fileExists(atPath: u.path))",
                  "lesbar=\(FileManager.default.isReadableFile(atPath: u.path))")
        }
    }
}
print("Ende")
