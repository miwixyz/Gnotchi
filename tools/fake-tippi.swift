// SYNTHETISCH – Testwerkzeug, enthält keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
// Sichttest 0.2.0: spielt Tippis Aufnahme-Meldungen nach (com.tippi.app.aufnahme), solange Tippi selbst
// noch nicht sendet. Aufruf: swift tools/fake-tippi.swift [ablauf|haengen|kaputt]
//   ablauf  – 4 s Aufnahme (10 Hz, Pegel), 2 s Umwandeln (1 Hz), dann idle   (Standard)
//   haengen – 2 s Aufnahme, dann nichts mehr (Gnotchi muss nach 3 s selbst ausblenden)
//   kaputt  – nur ungültige Nachrichten (Gnotchi darf nichts zeigen)
import Foundation

let center = DistributedNotificationCenter.default()
let name = Notification.Name("com.tippi.app.aufnahme")
func send(_ info: [String: Any]) {
    center.postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
}
func log(_ s: String) { print("\(Date().formatted(date: .omitted, time: .standard)) \(s)") }

let mode = CommandLine.arguments.dropFirst().first ?? "ablauf"
switch mode {
case "kaputt":
    log("sende ungültige Nachrichten")
    for info: [String: Any] in [["state": "recording"], ["v": 2, "state": "recording"], ["v": true, "state": "recording"],
                                ["v": 1, "state": "RECORDING"], ["v": 1, "state": 7], ["v": 1]] {
        send(info)
        Thread.sleep(forTimeInterval: 0.2)
    }
    log("fertig")
case "haengen":
    log("Aufnahme 2 s, dann Stille")
    for i in 0..<20 {
        send(["v": 1, "state": "recording", "level": 0.5 + 0.4 * sin(Double(i) / 3)])
        Thread.sleep(forTimeInterval: 0.1)
    }
    log("verstummt")
default:
    log("Aufnahme 4 s")
    for i in 0..<40 {
        send(["v": 1, "state": "recording", "level": 0.5 + 0.4 * sin(Double(i) / 3)])
        Thread.sleep(forTimeInterval: 0.1)
    }
    log("Umwandeln 2 s")
    for _ in 0..<2 {
        send(["v": 1, "state": "transcribing"])
        Thread.sleep(forTimeInterval: 1)
    }
    send(["v": 1, "state": "idle"])
    log("idle")
}
