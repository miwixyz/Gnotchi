// Messwerkzeug 0.9.0 (22.10.), Aufruf: swiftc -O tools/voicemail-stop-probe.swift -o /tmp/gn-vstop && /tmp/gn-vstop
// Einmal-Messung 22.10.: drückt im Anruf-Banner genau einmal „Live-Voicemail stoppen“ (3 s nach Erscheinen),
// protokolliert danach 15 s lang nur Knopfnamen. Keine Namen/Nummern. Beendet sich selbst.
import AppKit
import ApplicationServices
setvbuf(stdout, nil, _IOLBF, 0)
func a(_ e: AXUIElement, _ k: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
func s(_ e: AXUIElement, _ k: String) -> String { (a(e,k) as? String) ?? "" }
func ts() -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f.string(from: Date()) }
func buttons(_ e: AXUIElement, _ out: inout [(String, AXUIElement)], _ d: Int = 0) {
  if d > 14 { return }
  if s(e, "AXRole") == "AXButton" { out.append((s(e, "AXDescription"), e)) }
  for k in (a(e, "AXChildren") as? [AXUIElement]) ?? [] { buttons(k, &out, d + 1) }
}
func callButtons() -> [(String, AXUIElement)] {
  guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else { return [] }
  let root = AXUIElementCreateApplication(app.processIdentifier)
  var out: [(String, AXUIElement)] = []
  func find(_ e: AXUIElement, _ d: Int) {
    if d > 8 { return }
    if s(e, "AXIdentifier") == "FACETIME_NOTIFICATION" { buttons(e, &out); return }
    for k in (a(e, "AXChildren") as? [AXUIElement]) ?? [] { find(k, d + 1) }
  }
  for w in (a(root, "AXWindows") as? [AXUIElement]) ?? [] { find(w, 0) }
  return out
}
print("\(ts()) Start – warte auf „Live-Voicemail stoppen“ (max. 10 Min)")
var last = ""
var seenAt: Date?
var pressedAt: Date?
let start = Date()
while Date().timeIntervalSince(start) < 600 {
  let bs = callButtons()
  let names = bs.map(\.0).joined(separator: " · ")
  if names != last { print("\(ts()) Knöpfe: [\(names)]"); last = names }
  if pressedAt == nil, let stop = bs.first(where: { $0.0 == "Live-Voicemail stoppen" }) {
    if seenAt == nil { seenAt = Date() }
    if Date().timeIntervalSince(seenAt!) >= 3 {
      let r = AXUIElementPerformAction(stop.1, kAXPressAction as CFString)
      print("\(ts()) GEDRÜCKT: Live-Voicemail stoppen (AXError \(r.rawValue))"); pressedAt = Date()
    }
  }
  if let p = pressedAt, Date().timeIntervalSince(p) > 15 { print("\(ts()) Ende"); exit(0) }
  usleep(200_000)
}
print("\(ts()) Zeit abgelaufen, nichts gedrückt")
