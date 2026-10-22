import Darwin
import Foundation
import OSLog
import Security

/// Verbindung zu Gnotchis Socket `notify.sock` (G29). Bevor ein einziger Inhalt rausgeht, prüft das Hilfsprogramm den
/// lauschenden Prozess über sein Audit-Token gegen Gnotchis **Developer-ID**-Anforderung und wartet auf Gnotchis `ok`.
/// Ein falscher „Gnotchi“ bekäme sonst alle Mitteilungen – das ist die wichtigste Prüfung dieser Stufe.
@MainActor
final class GnotchiConnection {

    private static let log = Logger(subsystem: NotifyWire.helperBundleID, category: "verbindung")
    static let ackTimeout: TimeInterval = 0.5

    var onCommand: (NotifyWire.Command) -> Void = { _ in }
    var onClose: () -> Void = {}

    private let path: String
    private let requirement: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var buffer = Data()

    init(path: String, requirement: String) {
        self.path = path
        self.requirement = requirement
    }

    var isConnected: Bool { fd >= 0 }

    /// true = verbunden, Gegenseite geprüft, `ok` erhalten.
    func connect() -> Bool {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, len) }
        }
        guard connected == 0 else { Darwin.close(s); return false }
        let status = Self.checkServer(s, requirement)
        guard status == errSecSuccess else {
            Darwin.close(s)
            Self.log.error("Gegenseite ist kein echtes Gnotchi (OSStatus \(status, privacy: .public)) – nichts gesendet")
            return false
        }
        guard readAck(s) else {
            Darwin.close(s)
            Self.log.notice("Gnotchi hat nicht bestätigt")
            return false
        }
        _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)
        fd = s
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readIncoming() } }
        src.resume()
        source = src
        Self.log.notice("mit Gnotchi verbunden")
        return true
    }

    /// Audit-Token des lauschenden Prozesses → Code → Anforderung (Audit-Token statt PID: kein Wettlauf).
    nonisolated static func checkServer(_ fd: Int32, _ requirement: String) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
        guard st == errSecSuccess, let code else { return st == errSecSuccess ? errSecCSGuestInvalid : st }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else {
            return errSecCSReqInvalid
        }
        return SecCodeCheckValidity(code, [], req)
    }

    private func readAck(_ s: Int32) -> Bool {
        var tv = timeval(tv_sec: 0, tv_usec: Int32(Self.ackTimeout * 1_000_000))
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 256)
        while true {
            let n = read(s, &chunk, chunk.count)
            guard n > 0 else { return false }
            buf.append(contentsOf: chunk[0..<n])
            switch NotifyWire.nextFrame(&buf) {
            case .needMore: continue
            case .invalid: return false
            case .message(let payload):
                guard NotifyWire.isAck(payload) else { return false }
                buffer = buf   // was nach dem `ok` schon kam, nicht verlieren
                return true
            }
        }
    }

    func send(_ message: NotifyWire.HelperMessage) {
        guard fd >= 0, let data = NotifyWire.frame(NotifyWire.encode(message)) else { return }
        let n = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        if n != data.count { close(reason: "Schreibfehler") }
    }

    private func readIncoming() {
        var chunk = [UInt8](repeating: 0, count: NotifyWire.maxFrame)
        let n = read(fd, &chunk, chunk.count)
        if n == 0 { return close(reason: "Gnotchi getrennt") }
        if n < 0 { return errno == EAGAIN ? () : close(reason: "Lesefehler") }
        buffer.append(contentsOf: chunk[0..<n])
        while fd >= 0 {
            switch NotifyWire.nextFrame(&buffer) {
            case .needMore: return
            case .invalid: return close(reason: "ungültiger Rahmen")
            case .message(let payload):
                guard let command = NotifyWire.parseCommand(payload) else { return close(reason: "ungültige Nachricht") }
                onCommand(command)
            }
        }
    }

    func close(reason: String) {
        guard fd >= 0 else { return }
        source?.cancel()
        source = nil
        Darwin.close(fd)
        fd = -1
        Self.log.notice("\(reason, privacy: .public)")
        onClose()
    }
}
