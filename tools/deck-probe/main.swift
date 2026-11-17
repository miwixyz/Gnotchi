// M1-Messprogramm (specs/2026-11-17-gnotchi-stream-deck-plus.md): Startet Stream Deck ein natives, Developer-ID-signiertes
// Swift-Plugin? Wegwerf-Code, nicht Teil von Gnotchi. Protokoll: ~/Library/Logs/GnotchiDeckProbe.log (keine Inhalte, nur Ereignisnamen).
import Darwin
import Foundation
import Security

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GnotchiDeckProbe.log")

func log(_ s: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

func path(of pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "?"
}

/// Vorgeschmack auf M2 (Plugin-Seite): Erfüllt der Elternprozess Elgatos Signatur?
func parentIsStreamDeck(_ pid: pid_t) -> OSStatus {
    let req = #"anchor apple generic and identifier "com.elgato.StreamDeck" and certificate leaf[subject.OU] = "Y93VXCB8Q5""#
    var r: SecRequirement?
    guard SecRequirementCreateWithString(req as CFString, [], &r) == errSecSuccess, let r else { return -1 }
    var code: SecCode?
    let attrs = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
    let s = SecCodeCopyGuestWithAttributes(nil, attrs, [], &code)
    guard s == errSecSuccess, let code else { return s }
    return SecCodeCheckValidity(code, [], r)
}

var args: [String: String] = [:]
var i = 1
let argv = CommandLine.arguments
while i + 1 < argv.count { args[argv[i]] = argv[i + 1]; i += 2 }

let ppid = getppid()
log("START pid=\(getpid()) ppid=\(ppid) parent=\(path(of: ppid)) parentCheck=\(parentIsStreamDeck(ppid)) args=\(args.keys.sorted())")

/// M2: zum Prüf-Server (m2-server.swift) verbinden, bevor irgendetwas anderes passiert – auch beim Start ohne Stream Deck.
func connectM2() {
    let p = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/GnotchiDeckProbe/m2.sock").path
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        let b = Array(p.utf8.prefix(raw.count - 1)); raw.copyBytes(from: b); raw[b.count] = 0
    }
    let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    log("M2 connect=\(r == 0 ? "ok" : "fehler \(errno)")")
    close(fd)
}
connectM2()

guard let port = args["-port"], let uuid = args["-pluginUUID"], let reg = args["-registerEvent"],
      let url = URL(string: "ws://127.0.0.1:\(port)") else {
    log("ABBRUCH: Argumente fehlen"); exit(1)
}

let task = URLSession.shared.webSocketTask(with: url)
var presses = 0

func send(_ obj: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: obj)
    task.send(.string(String(data: data, encoding: .utf8)!)) { err in if let err { log("SENDEFEHLER \(err)") } }
}

func receive() {
    task.receive { result in
        switch result {
        case .failure(let err):
            log("VERBINDUNG ZU \(err)"); exit(0)
        case .success(let msg):
            if case .string(let s) = msg, let d = s.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                let event = obj["event"] as? String ?? "?"
                log("EREIGNIS \(event)")
                if event == "keyDown" || event == "dialDown" || event == "touchTap", let ctx = obj["context"] as? String {
                    presses += 1
                    send(["event": "setTitle", "context": ctx, "payload": ["title": "Hallo \(presses)", "target": 0]])
                    send(["event": "showOk", "context": ctx])
                }
                if event == "willAppear", let ctx = obj["context"] as? String {
                    send(["event": "setTitle", "context": ctx, "payload": ["title": "Probe", "target": 0]])
                    // M6: erkennbarer Testtext über den Leisten-Weg; danach Elgatos Protokolle danach durchsuchen.
                    send(["event": "setFeedback", "context": ctx,
                          "payload": ["title": "M6-FEEDBACK-7Q3Z", "value": "M6-WERT-7Q3Z", "indicator": 42]])
                }
                if event == "dialRotate", let ctx = obj["context"] as? String,
                   let p = obj["payload"] as? [String: Any], let t = p["ticks"] as? Int {
                    log("TICKS \(t)")
                    send(["event": "setFeedback", "context": ctx, "payload": ["value": "M6-DREH-7Q3Z \(t)"]])
                }
            }
            receive()
        }
    }
}

task.resume()
send(["event": reg, "uuid": uuid])
log("REGISTRIERT gesendet")
receive()
dispatchMain()
