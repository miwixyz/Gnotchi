// M2-Messprogramm (specs/2026-11-17-gnotchi-stream-deck-plus.md): Gnotchi-Seite der Prüfung am Socket.
// Prüft je Verbindung (1) Signatur des Peers über das Audit-Token wie PeerSocketServer.checkPeer und
// (2) ob der Elternprozess des Peers Elgatos Stream Deck ist. Wegwerf-Code, schreibt nur auf stdout.
import Darwin
import Foundation
import Security

let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/GnotchiDeckProbe")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let path = dir.appendingPathComponent("m2.sock").path
unlink(path)

func req(_ s: String) -> SecRequirement {
    var r: SecRequirement?
    precondition(SecRequirementCreateWithString(s as CFString, [], &r) == errSecSuccess)
    return r!
}
let pluginReq = req(#"anchor apple generic and identifier "dev.mwlr.gnotchi.deck" and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "LTKJ6Z2VYB""#)
let deckReq = req(#"anchor apple generic and identifier "com.elgato.StreamDeck" and certificate leaf[subject.OU] = "Y93VXCB8Q5""#)

func out(_ s: String) { print(s); fflush(stdout) }

func peerCheck(_ fd: Int32) -> (OSStatus, pid_t) {
    var token = audit_token_t()
    var len = socklen_t(MemoryLayout<audit_token_t>.size)
    guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return (errSecCSGuestInvalid, -1) }
    let pid = pid_t(bitPattern: token.val.5)
    let data = withUnsafeBytes(of: &token) { Data($0) }
    var code: SecCode?
    let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
    guard st == errSecSuccess, let code else { return (st, pid) }
    return (SecCodeCheckValidity(code, [], pluginReq), pid)
}

func parentCheck(of pid: pid_t) -> (OSStatus, pid_t, String) {
    var info = proc_bsdinfo()
    let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    guard n == Int32(MemoryLayout<proc_bsdinfo>.size) else { return (-2, -1, "?") }
    let ppid = pid_t(info.pbi_ppid)
    var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let p = proc_pidpath(ppid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "?"
    var code: SecCode?
    let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: NSNumber(value: ppid)] as CFDictionary, [], &code)
    guard st == errSecSuccess, let code else { return (st, ppid, p) }
    return (SecCodeCheckValidity(code, [], deckReq), ppid, p)
}

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { raw in
    let b = Array(path.utf8.prefix(raw.count - 1))
    raw.copyBytes(from: b)
    raw[b.count] = 0
}
let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
precondition(bound == 0 && listen(fd, 4) == 0, "bind/listen fehlgeschlagen")
chmod(path, 0o600)
out("SERVER bereit \(path)")

while true {
    let c = accept(fd, nil, nil)
    guard c >= 0 else { continue }
    let (peer, pid) = peerCheck(c)
    let (parent, ppid, ppath) = parentCheck(of: pid)
    let ok = peer == errSecSuccess && parent == errSecSuccess
    out("VERBINDUNG pid=\(pid) peer=\(peer) ppid=\(ppid) eltern=\(ppath) elternCheck=\(parent) → \(ok ? "ANGENOMMEN" : "ABGELEHNT")")
    close(c)
}
