// Messwerkzeug 0.6.0 (22.10.): Lage von Apples Mitteilungsfenster (AX) + Größe der Gnotchi-Panels, eine Zeile.
// Aufruf: swiftc -O tools/notify-state.swift -o /tmp/gn-state && /tmp/gn-state <gnotchi-pid>
import AppKit
import ApplicationServices
// Zustand: Position des Apple-Mitteilungsfensters (AX) + Größe der Gnotchi-Panels (CGWindowList, nur Lage).
func a(_ e: AXUIElement, _ k: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first!
let root = AXUIElementCreateApplication(nc.processIdentifier)
var ncPos = "kein Fenster"
for w in (a(root, "AXWindows") as? [AXUIElement]) ?? [] where (a(w, "AXSubrole") as? String) == "AXSystemDialog" {
  var p = CGPoint.zero; if let v = a(w, "AXPosition") { AXValueGetValue(v as! AXValue, .cgPoint, &p) }; ncPos = "\(p)"
}
let gpid = Int32(CommandLine.arguments[1])!
let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let sizes = info.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == gpid }.compactMap { d -> String? in
  guard let b = d[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }; return "\(Int(b["Width"]!))x\(Int(b["Height"]!))" }
let f = DateFormatter(); f.dateFormat = "HH:mm:ss.S"
print(f.string(from: Date()), "Apple-Fenster:", ncPos, "| Gnotchi-Panels:", sizes.joined(separator: ", "))
