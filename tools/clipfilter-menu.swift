// Liest das Filtermenü der Zwischenablage-Vorführung in der Bild-Testkopie (nur dev.mwlr.gnotchi.bild):
// Menüknopf per Bedienungshilfen öffnen, Einträge (Titel, Haken) ausgeben, Menü wieder schließen.
//   swiftc -O tools/clipfilter-menu.swift -o <ziel> && <ziel>
import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func find(_ e: AXUIElement, role: String, depth: Int = 0) -> AXUIElement? {
    if attr(e, kAXRoleAttribute) as? String == role { return e }
    guard depth < 25 else { return nil }
    for c in children(e) { if let hit = find(c, role: role, depth: depth + 1) { return hit } }
    return nil
}
guard AXIsProcessTrusted() else { print("FEHLER: kein Bedienungshilfen-Recht"); exit(2) }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.mwlr.gnotchi.bild").first else {
    print("FEHLER: Bild-Kopie läuft nicht"); exit(1)
}
let root = AXUIElementCreateApplication(app.processIdentifier)
let windows = (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
print("Fenster: \(windows.count)")
guard let button = windows.lazy.compactMap({ find($0, role: kAXMenuButtonRole as String) }).first else {
    print("FEHLER: kein Menüknopf"); exit(1)
}
print("Knopf: \(attr(button, kAXDescriptionAttribute) as? String ?? "-") / \(attr(button, kAXTitleAttribute) as? String ?? "-")")
AXUIElementPerformAction(button, kAXPressAction as CFString)
RunLoop.current.run(until: Date().addingTimeInterval(0.8))
guard let menu = find(button, role: kAXMenuRole as String) ?? find(root, role: kAXMenuRole as String) else {
    print("FEHLER: Menü nicht gefunden"); exit(1)
}
for item in children(menu) {
    let title = attr(item, kAXTitleAttribute) as? String ?? ""
    let mark = attr(item, "AXMenuItemMarkChar") as? String ?? ""
    let enabled = (attr(item, kAXEnabledAttribute) as? Bool) ?? false
    print(title.isEmpty ? "  ——" : "  [\(mark.isEmpty ? " " : "✓")] \(title)\(enabled ? "" : " (aus)")")
}
AXUIElementPerformAction(menu, kAXCancelAction as CFString)
