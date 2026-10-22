import AppKit
import Darwin
import Foundation
import OSLog
import Security

// „Gnotchi Claude“ (0.9.0, SECURE-DESIGN G34): Hook-Programm für Claude Code. Wird je Ereignis kurz gestartet
// (`"async": true` – Claude wartet nicht), liest die Hook-Eingabe von stdin, macht daraus EINE bereinigte Nachricht
// (ClaudeWire), prüft Gnotchi über das Audit-Token, schickt und endet. Gibt NIE etwas auf stdout aus – also nie eine
// Entscheidung an Claude Code (Michael 22.10.: Erlauben/Ablehnen nur anzeigen). Läuft Gnotchi nicht: still Exit 0.
// Keine Oberfläche, kein NSApplication-Lauf, keine Kindprozesse, kein Netz.

let gnotchiRequirement = LiveText.peerRequirement(identifier: NotifyWire.gnotchiBundleID)
/// Nur Ereignis-Name und Ergebnis ins Protokoll (Messpunkt), nie Inhalte (G34).
let log = Logger(subsystem: ClaudeWire.hookBundleID, category: "hook")
let ackTimeout: TimeInterval = 0.5

/// stdin bis `ClaudeWire.maxInput`; mehr → nil (dann nichts senden).
func readInput() -> Data? {
    var data = Data()
    var chunk = [UInt8](repeating: 0, count: 65_536)
    while true {
        let n = read(STDIN_FILENO, &chunk, chunk.count)
        if n < 0 { return nil }
        if n == 0 { return data }
        data.append(contentsOf: chunk[0..<n])
        if data.count > ClaudeWire.maxInput { return nil }
    }
}

/// Eltern-Prozesse hoch bis zur ersten normalen App (Terminal, Obsidian, Claude-App): deren Kennung + PID.
func hostApp() -> (String, Int32)? {
    var pid = getppid()
    for _ in 0..<24 {
        guard pid > 1 else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
           let id = app.bundleIdentifier, NotifyWire.isValidBundleID(id) {
            return (id, pid)
        }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        pid = info.kp_eproc.e_ppid
    }
    return nil
}

/// Verbinden, Gnotchi prüfen (Audit-Token gegen Developer ID), auf `ok` warten. -1 = nicht senden.
func connectToGnotchi() -> Int32 {
    guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return -1 }
    let path = dir.appendingPathComponent("Gnotchi/\(ClaudeWire.socketName)").path
    var addr = sockaddr_un()
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return -1 }
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }
    let s = socket(AF_UNIX, SOCK_STREAM, 0)
    guard s >= 0 else { return -1 }
    var one: Int32 = 1
    setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard ok == 0, checkServer(s) == errSecSuccess, readAck(s) else { close(s); return -1 }
    return s
}

func checkServer(_ fd: Int32) -> OSStatus {
    var token = audit_token_t()
    var len = socklen_t(MemoryLayout<audit_token_t>.size)
    guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
    let data = withUnsafeBytes(of: &token) { Data($0) }
    var code: SecCode?
    let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
    guard st == errSecSuccess, let code else { return st == errSecSuccess ? errSecCSGuestInvalid : st }
    var req: SecRequirement?
    guard SecRequirementCreateWithString(gnotchiRequirement as CFString, [], &req) == errSecSuccess, let req else {
        return errSecCSReqInvalid
    }
    return SecCodeCheckValidity(code, [], req)
}

func readAck(_ s: Int32) -> Bool {
    var tv = timeval(tv_sec: 0, tv_usec: Int32(ackTimeout * 1_000_000))
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var buf = Data()
    var chunk = [UInt8](repeating: 0, count: 256)
    while true {
        let n = read(s, &chunk, chunk.count)
        guard n > 0 else { return false }
        buf.append(contentsOf: chunk[0..<n])
        switch LiveText.nextFrame(&buf, max: ClaudeWire.maxFrame) {
        case .needMore: continue
        case .invalid: return false
        case .message(let payload): return NotifyWire.isAck(payload)
        }
    }
}

// MARK: Ablauf

guard let input = readInput(), let obj = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
    log.notice("Eingabe nicht lesbar")
    exit(0)
}
let hookName = obj["hook_event_name"] as? String ?? "?"
guard var message = ClaudeWire.message(fromHookInput: obj) else {
    let known = ClaudeWire.event(forHook: hookName) != nil
    log.notice("\(known ? hookName : "anderes Ereignis", privacy: .public): nicht gesendet (Feld fehlt/ungültig)")
    exit(0)
}
if let (app, pid) = hostApp() {
    message.app = app
    message.pid = pid
}
let fd = connectToGnotchi()
guard fd >= 0 else {
    log.notice("\(hookName, privacy: .public): Gnotchi nicht erreichbar")
    exit(0)
}
guard let frame = LiveText.frame(ClaudeWire.encode(message), max: ClaudeWire.maxFrame) else {
    log.notice("\(hookName, privacy: .public): Nachricht zu groß")
    exit(0)
}
let written = frame.withUnsafeBytes { write(fd, $0.baseAddress, frame.count) }
log.notice("\(hookName, privacy: .public): gesendet (\(written == frame.count ? "ok" : "unvollständig", privacy: .public))")
close(fd)
exit(0)
