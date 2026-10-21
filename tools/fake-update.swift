// SYNTHETISCH – Testwerkzeug, erfundene Versionen (SECURE-DESIGN G16/G23)
// Sichttest 0.4.0: spielt die Update-Meldung einer Familien-App nach (app.mwlr.familie.update).
// Aufruf: swift tools/fake-update.swift [bereit|erledigt|mehrere|kaputt|zeigen] [app] [version]
//   bereit   – „Kalli 0.99.0 bereit“ (oder angegebene App/Version): erscheint in der Rotation, Klick öffnet Kalli
//   erledigt – dieselbe Meldung mit ready:false: Eintrag verschwindet
//   mehrere  – Kalli, Seam und Tippi bereit (je 1,2 s Abstand, Drossel gilt je App)
//   kaputt   – nur ungültige Nachrichten: Gnotchi darf nichts zeigen
//   zeigen   – lauscht auf app.mwlr.familie.update.show und druckt, was Gnotchi nach dem Klick sendet
import Foundation

setbuf(stdout, nil)   // ungepuffert: im Hintergrund in eine Datei umgeleitet ginge die Ausgabe sonst beim Beenden verloren
let center = DistributedNotificationCenter.default()
let name = Notification.Name("app.mwlr.familie.update")
func send(_ info: [String: Any]) {
    center.postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
}
func log(_ s: String) { print("\(Date().formatted(date: .omitted, time: .standard)) \(s)") }

let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "bereit"
let app = args.count > 1 ? args[1] : "kalli"
let version = args.count > 2 ? args[2] : "0.99.0"

switch mode {
case "erledigt":
    log("\(app) \(version) erledigt")
    send(["v": 1, "app": app, "version": version, "ready": false])
case "mehrere":
    for (a, v) in [("kalli", "0.99.0"), ("seam", "9.9.0"), ("tippi", "9.9.0")] {
        log("\(a) \(v) bereit")
        send(["v": 1, "app": a, "version": v, "ready": true])
        Thread.sleep(forTimeInterval: 1.2)
    }
case "kaputt":
    log("sende ungültige Nachrichten")
    for info: [String: Any] in [["app": "kalli", "version": "9.9", "ready": true],
                                ["v": true, "app": "kalli", "version": "9.9", "ready": true],
                                ["v": 1, "app": "gnotchi", "version": "9.9", "ready": true],
                                ["v": 1, "app": "finder", "version": "9.9", "ready": true],
                                ["v": 1, "app": "kalli", "version": "9.9\u{202E}evil", "ready": true],
                                ["v": 1, "app": "kalli", "version": "9.9", "ready": 1]] {
        send(info)
        Thread.sleep(forTimeInterval: 1.2)
    }
case "zeigen":
    log("lausche auf app.mwlr.familie.update.show (Strg-C beendet)")
    let token = center.addObserver(forName: Notification.Name("app.mwlr.familie.update.show"), object: nil,
                                   queue: .main) { note in
        log("empfangen: \(note.userInfo ?? [:])")
    }
    withExtendedLifetime(token) { RunLoop.main.run() }
default:
    log("\(app) \(version) bereit")
    send(["v": 1, "app": app, "version": version, "ready": true])
}
log("fertig")
