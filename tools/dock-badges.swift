// Messwerkzeug 0.9.0 (22.10.), Aufruf: swiftc -O tools/dock-badges.swift -o /tmp/gn-dock && /tmp/gn-dock
// Messung 22.10.: Zeigt der Dock Ungelesen-Zahlen per Bedienungshilfen? Nur App-Name + Zahl/Länge.
import AppKit
import ApplicationServices
func a(_ e: AXUIElement, _ k: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
func s(_ e: AXUIElement, _ k: String) -> String { (a(e,k) as? String) ?? "" }
guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { print("kein Dock"); exit(1) }
let root = AXUIElementCreateApplication(dock.processIdentifier)
var n = 0
func walk(_ e: AXUIElement, _ d: Int) {
  if d > 6 { return }
  if s(e, "AXSubrole") == "AXApplicationDockItem" {
    n += 1
    let badge = s(e, "AXStatusLabel")
    if !badge.isEmpty { print("\(s(e, "AXTitle")): Abzeichen \"\(badge)\"") }
  }
  for k in (a(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(k, d + 1) }
}
walk(root, 0)
print("\(n) App-Symbole im Dock gelesen")
