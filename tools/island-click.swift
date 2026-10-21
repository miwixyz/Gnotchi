// SYNTHETISCH – Testwerkzeug, enthält keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
// Sichttest 0.4.0: echter Mausklick (CGEvent) auf die Insel eines Prozesses (erstes Fenster oben am Bildschirm).
// Aufruf: swift tools/island-click.swift <pid> [klein|gross] [abstand-oben=0]
//   klein – 0,3 s über die kleine Insel (vor Ablauf der Aufklapp-Verzögerung 0,6 s), dann Klick in die Mitte.
//           Ohne Verweilen löst der Klick nichts aus (gemessen 21.10.) – das tut auch kein Mensch.
//   gross – 1,5 s über die kleine Insel (klappt auf), dann Klick auf „Öffnen“ der ersten Zeile (rechts, 16 pt unter
//           der Oberkante; mit Notch deren Höhe als abstand-oben angeben).
// Braucht für den aufrufenden Prozess die Bedienungshilfen-Freigabe (Ereignisse senden).
import CoreGraphics
import Foundation

setbuf(stdout, nil)
let args = Array(CommandLine.arguments.dropFirst())
let pid = Int32(args.first ?? "") ?? 0
let big = args.count > 1 && args[1] == "gross"
let topExtra = Double(args.count > 2 ? args[2] : "") ?? 0

func island() -> CGRect? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.lazy.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        .compactMap { w -> CGRect? in
            guard let d = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: d)
        }
        .first { $0.minY < 40 }
}
let src = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
guard let small = island() else { print("keine Insel oben gefunden"); exit(1) }
let hover = CGPoint(x: small.midX, y: small.midY)
post(.mouseMoved, hover)
usleep(big ? 1_500_000 : 300_000)
var target = hover
if big {
    guard let r = island(), r.width > small.width else { print("nicht aufgeklappt"); exit(1) }
    target = CGPoint(x: r.maxX - 36, y: r.minY + 16 + topExtra)
    post(.mouseMoved, target)
    usleep(200_000)
}
post(.leftMouseDown, target)
usleep(60_000)
post(.leftMouseUp, target)
print("\(Date().formatted(date: .omitted, time: .standard)) geklickt bei \(Int(target.x)),\(Int(target.y))")
