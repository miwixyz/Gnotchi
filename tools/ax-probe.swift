// ax-probe.swift — fragt die Bedienungshilfen-Oberfläche einer App ab (nur lesend: Fensterzahl).
//
// Sichttest 18.10.: Im TCC-Protokoll stand, Gnotchi prüfe die Bedienungshilfen-Freigabe von Seam
// und Vorssaint. Hypothese: Das ist macOS' AX-Server IN Gnotchi, der prüft, ob ein abfragendes
// Programm (Fenster-Manager) die Freigabe hat. Dieses Werkzeug spielt so ein Programm.
// Liest keine Titel und keine Inhalte, nur die Anzahl der AXWindows.
//
// Aufruf: swift tools/ax-probe.swift <pid>

import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 2, let pid = pid_t(CommandLine.arguments[1]) else {
    print("Aufruf: swift tools/ax-probe.swift <pid>"); exit(2)
}
print("vertraut (AXIsProcessTrusted): \(AXIsProcessTrusted())")
let app = AXUIElementCreateApplication(pid)
var value: CFTypeRef?
let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
let count = (value as? [AXUIElement])?.count ?? -1
print("pid \(pid): AXError \(err.rawValue), Fenster \(count)")
