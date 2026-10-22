// Messwerkzeug 0.6.0 (22.10.): Lässt sich Apples Banner-Fenster per AXPosition wegschieben und zurückholen?
// Aufruf: osascript -e 'display notification "Test" with title "Probe"'; swift tools/nc-park.swift
import AppKit
import ApplicationServices
func a(_ e: AXUIElement, _ k: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
func pos(_ e: AXUIElement) -> CGPoint? { guard let v = a(e, "AXPosition") else { return nil }; var p = CGPoint.zero; AXValueGetValue(v as! AXValue, .cgPoint, &p); return p }
func cgBounds() -> [String] {
  let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
  return info.filter { ($0[kCGWindowOwnerName as String] as? String) == "Mitteilungszentrale" }.map { "\($0[kCGWindowBounds as String] ?? "")" }
}
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first!
let root = AXUIElementCreateApplication(app.processIdentifier)
let t0 = Date()
var win: AXUIElement?
while Date().timeIntervalSince(t0) < 5 {
  for w in (a(root,"AXWindows") as? [AXUIElement]) ?? [] where (a(w,"AXSubrole") as? String) == "AXSystemDialog" { win = w }
  if win != nil { break }; usleep(100_000)
}
guard let w = win else { print("kein Banner-Fenster"); exit(1) }
let orig = pos(w)!
print("vorher AX:", orig, "CG:", cgBounds())
var hidden = CGPoint(x: -10000, y: -10000)
let r = AXUIElementSetAttributeValue(w, "AXPosition" as CFString, AXValueCreate(.cgPoint, &hidden)!)
usleep(300_000)
print("setzen:", r.rawValue, "nachher AX:", pos(w) as Any, "CG:", cgBounds())
sleep(2)
var o = orig
let r2 = AXUIElementSetAttributeValue(w, "AXPosition" as CFString, AXValueCreate(.cgPoint, &o)!)
usleep(300_000)
print("zurück:", r2.rawValue, "AX:", pos(w) as Any, "CG:", cgBounds())
