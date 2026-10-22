// Messwerkzeug 0.6.0 (22.10.): Aufbau der Mitteilungszentrale – nur Rollen, Kennungen, Knopfnamen; Texte nur als Länge.
// Aufruf: swiftc -O tools/nc-structure.swift -o /tmp/nc-structure && /tmp/nc-structure > $(mktemp)  (braucht Bedienungshilfen)
// Messwerkzeug Anruf-Test: protokolliert nur Struktur (Rolle, Kennung, Knopfnamen), Texte nur als Länge.
import AppKit
import ApplicationServices
setvbuf(stdout, nil, _IOLBF, 0)
func a(_ e: AXUIElement, _ k: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
func s(_ e: AXUIElement, _ k: String) -> String { (a(e,k) as? String) ?? ((a(e,k) as? NSAttributedString)?.string ?? "") }
func len(_ x: String) -> String { x.isEmpty ? "" : "<\(x.count) Z.>" }
func actionNames(_ e: AXUIElement) -> [String] {
  var n: CFArray?; AXUIElementCopyActionNames(e, &n)
  return ((n as? [String]) ?? []).map { r in
    if let range = r.range(of: "Name:") { return String(r[range.upperBound...].prefix { $0 != "\n" }) }
    return r }
}
// Beschriftung nur bei Knöpfen und Anrufart-Symbol zeigen (UI-Texte wie „Annehmen“) – Namen/Inhalte nie
// (22.10.: die erste Fassung schrieb den Anrufernamen mit, weil er kürzer als 25 Zeichen war).
func labelOK(_ e: AXUIElement) -> Bool { s(e, "AXRole") == "AXButton" || s(e, "AXIdentifier") == "AvatarView" }
func ts() -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f.string(from: Date()) }
func dump(_ e: AXUIElement, _ d: Int, _ out: inout [String]) {
  if d > 16 || out.count > 200 { return }
  let desc = s(e,"AXDescription")
  let firstPart = desc.split(separator: ",").first.map(String.init) ?? ""
  out.append(String(repeating: "  ", count: d) + "\(s(e,"AXRole"))/\(s(e,"AXSubrole")) id=\(s(e,"AXIdentifier").count > 30 ? "<uuid>" : s(e,"AXIdentifier")) val=\(len(s(e,"AXValue"))) desc[0]=\(labelOK(e) ? firstPart : len(firstPart)) desc=\(len(desc)) title=\(len(s(e,"AXTitle"))) act=\(actionNames(e).joined(separator: ","))")
  var kids = (a(e,"AXChildren") as? [AXUIElement]) ?? []
  if kids.isEmpty { kids = (a(e,"AXOrderedChildren") as? [AXUIElement]) ?? [] }
  for k in kids { dump(k, d+1, &out) }
}
var seen = Set<String>()
var seenOwners = Set<String>()
func cgOwners() -> [String] {
  let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
  return info.map { "\($0[kCGWindowOwnerName as String] as? String ?? "?")@L\($0[kCGWindowLayer as String] as? Int ?? 0)" }
}
for o in cgOwners() { seenOwners.insert(o) }
print("\(ts()) Start – warte auf Mitteilungen/Anruf-Fenster (Strg-C beendet)")
while true {
  if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    for w in (a(root,"AXWindows") as? [AXUIElement]) ?? [] {
      var out: [String] = []; dump(w, 0, &out)
      let sig = out.joined(separator: "\n")
      if !seen.contains(sig) && out.count > 3 { seen.insert(sig); print("\(ts()) === NC-Fenster neu/geändert\n" + sig) }
    }
  }
  for o in cgOwners() where !seenOwners.contains(o) { seenOwners.insert(o); print("\(ts()) neues Fenster auf dem Bildschirm: \(o)") }
  usleep(300_000)
}
