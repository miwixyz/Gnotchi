import CoreGraphics
import Foundation
// Sichttest Schnelleingabe (19.11.): Kürzel global drücken, Text/Tasten NUR an Gnotchi (postToPid, landet nie in einer
// anderen App), Gnotchi-Fenster über CGWindowList (Bedienungshilfen sehen die Panels nicht, kein Bildschirmfoto nötig).
//   quickentry-drive hotkey              ⌃⌥N an das System (Carbon-Kürzel)
//   quickentry-drive type <pid> <text>   Text tippen
//   quickentry-drive key <pid> <code> [cmd]   Taste (36 ↵, 48 Tab, 53 Esc, 6 Z)
//   quickentry-drive windows <pid>       Fenster: Ebene, Größe, Lage
setvbuf(stdout, nil, _IOLBF, 0)
let a = CommandLine.arguments
func post(_ code: CGKeyCode, flags: CGEventFlags = [], pid: pid_t? = nil, text: String? = nil) {
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
        e.flags = flags
        if let text { let u = Array(text.utf16); e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u) }
        if let pid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
        usleep(12_000)
    }
}
switch a[1] {
case "hotkey":
    post(45, flags: [.maskControl, .maskAlternate])
case "type":
    let pid = pid_t(a[2])!
    for ch in a[3] { post(0, pid: pid, text: String(ch)) }
case "key":
    post(CGKeyCode(a[3])!, flags: a.count > 4 ? [.maskCommand] : [], pid: pid_t(a[2])!)
case "windows":
    let pid = Int(a[2])!
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        print("Ebene \(w[kCGWindowLayer as String] ?? "?") \(Int(b["Width"] ?? 0))×\(Int(b["Height"] ?? 0)) bei x=\(Int(b["X"] ?? 0)) y=\(Int(b["Y"] ?? 0))")
    }
default: print("?")
}
