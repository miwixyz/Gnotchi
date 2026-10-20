// SYNTHETISCH – Testwerkzeug, erfundene Werte (SECURE-DESIGN G16/G22)
// Sichttest 0.3.0: spielt Qottis Kontingent-Meldungen nach (app.qotti.local.kontingent).
// Aufruf: swift tools/fake-qotti.swift [normal|warnung|drossel|kaputt]
//   normal  – Claude 42 %, GPT 17 % (Zeile in der großen Insel; Musik muss laufen, sonst klappt nichts auf)
//   warnung – Claude 50 → 82 → 96 % im Abstand von 5 s: erwartet zwei Hinweise (80 %, 95 %)
//   drossel – Claude gedrosselt: erwartet ein Hinweis „Claude gedrosselt“
//   kaputt  – nur ungültige Nachrichten: Gnotchi darf nichts zeigen
import Foundation

let center = DistributedNotificationCenter.default()
let name = Notification.Name("app.qotti.local.kontingent")
func send(_ info: [String: Any]) {
    center.postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
}
func log(_ s: String) { print("\(Date().formatted(date: .omitted, time: .standard)) \(s)") }
let reset = Date().addingTimeInterval(65 * 60).timeIntervalSince1970

switch CommandLine.arguments.dropFirst().first ?? "normal" {
case "warnung":
    for p in [50, 82, 96] {
        log("Claude \(p) %")
        send(["v": 1, "claude5h": p, "claudeReset5h": reset, "codex5h": 17])
        Thread.sleep(forTimeInterval: 5)
    }
case "drossel":
    log("Claude gedrosselt")
    send(["v": 1, "claude5h": 100, "claudeReset5h": reset, "claudeState": "throttled"])
case "kaputt":
    log("sende ungültige Nachrichten")
    for info: [String: Any] in [["claude5h": 99], ["v": 2, "claude5h": 99], ["v": true, "claude5h": 99],
                                ["v": 1, "claude5h": true], ["v": 1, "claude5h": "99"],
                                ["v": 1, "claude5h": 99, "claudeState": "kaputt"], ["v": 1]] {
        send(info)
        Thread.sleep(forTimeInterval: 1.2)
    }
default:
    log("Claude 42 %, GPT 17 %")
    send(["v": 1, "claude5h": 42, "claudeReset5h": reset, "codex5h": 17])
}
log("fertig")
