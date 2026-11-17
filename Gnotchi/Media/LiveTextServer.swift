import Darwin
import Foundation
import OSLog
import Security

/// Tippis Live-Text (0.3.0, G21): der Server mit bereinigtem Text als Wert.
typealias LiveTextServer = PeerSocketServer<String>

extension PeerSocketServer where Value == String {
    /// `requirement` nur im Test anders als Tippis Developer-ID-Anforderung.
    convenience init(directory: URL, requirement: SecRequirement, onText: @escaping @Sendable (String?) -> Void) {
        self.init(directory: directory, fileName: "live.sock", label: "Live-Text", peer: "Tippi",
                  requirement: requirement, parse: LiveText.parse, onValue: onText)
    }
}

/// Lokaler Socket für eine geprüfte Familien-App (0.3.0 Tippis Live-Text G21, 0.5.0 Kallis Termine G26).
/// Alles auf einer eigenen seriellen Warteschlange; nach außen nur `onValue` (geprüft, gedrosselt, `nil` =
/// getrennt). Jede Verbindung wird **vor dem ersten gelesenen Byte** über das Audit-Token der Gegenseite gegen
/// `requirement` geprüft. Nie Inhalte ins Protokoll.
final class PeerSocketServer<Value: Sendable>: @unchecked Sendable {

    enum StartError: Error, Equatable {
        case directory, staleFile, pathTooLong, socket(Int32)
    }

    /// Höchstens so oft neuen Text an die Ansicht (letzter gewinnt).
    static var minDeliveryInterval: TimeInterval { 0.25 }

    private static var log: Logger { Logger(subsystem: "dev.mwlr.gnotchi", category: "livetext") }

    let socketPath: String
    private let requirement: SecRequirement
    private let label: String
    private let peer: String
    /// Nachricht → Wert; `nil` = ungültig, Verbindung zu.
    private let parse: @Sendable (Data) -> Value?
    private let onValue: @Sendable (Value?) -> Void
    private let queue: DispatchQueue
    /// Größte Nachricht (Länge + JSON); Mitteilungen (0.6.0) brauchen mehr als Live-Text.
    private let maxFrame: Int
    /// `true` (Live-Text, Termine): gedrosselt, der letzte Stand gewinnt. `false` (Mitteilungen, 0.6.0): jede
    /// Nachricht zählt – sofort weitergeben, aber höchstens `maxPerSecond`, der Rest fällt weg.
    private let coalesce: Bool
    nonisolated static var maxPerSecond: Int { 10 }
    /// Ohne `coalesce`: höchstens so viele Nachrichten je Sekunde (Standard `maxPerSecond`; Stream Deck G59: 50).
    private let perSecond: Int
    /// Stream Deck (G59): Zusätzlich muss der **Elternprozess** des Peers diese Anforderung erfüllen. Sonst könnte jedes Programm
    /// das echte, signierte Plugin selbst starten und fernsteuern (gemessen 17.11., M2).
    private let parentRequirement: SecRequirement?
    private let sendBuffer: Int32?

    // Nur auf `queue`:
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var clientFD: Int32 = -1
    private var clientSource: DispatchSourceRead?
    private var buffer = Data()
    private var lastDelivery = Date.distantPast
    private var pending: Value?
    private var flushScheduled = false
    private var windowStart = Date.distantPast
    private var windowCount = 0

    init(directory: URL, fileName: String, label: String, peer: String, requirement: SecRequirement,
         maxFrame: Int = LiveText.maxFrame, coalesce: Bool = true,
         perSecond: Int = 10, parentRequirement: SecRequirement? = nil, sendBuffer: Int32? = nil,
         parse: @escaping @Sendable (Data) -> Value?, onValue: @escaping @Sendable (Value?) -> Void) {
        self.maxFrame = maxFrame
        self.coalesce = coalesce
        self.perSecond = perSecond
        self.parentRequirement = parentRequirement
        self.sendBuffer = sendBuffer
        socketPath = directory.appendingPathComponent(fileName).path
        self.requirement = requirement
        self.label = label
        self.peer = peer
        self.parse = parse
        self.onValue = onValue
        queue = DispatchQueue(label: "dev.mwlr.gnotchi.socket.\(fileName)")
    }

    // MARK: Dateisystem (rein bis auf lstat/mkdir, getestet)

    /// Ordner anlegen bzw. prüfen: echter Ordner (kein Link), gehört uns, Rechte 0700.
    static func prepareDirectory(_ url: URL) -> Bool {
        let path = url.path
        var st = stat()
        if lstat(path, &st) != 0 {
            guard errno == ENOENT, mkdir(path, 0o700) == 0, lstat(path, &st) == 0 else { return false }
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else { return false }
        return chmod(path, 0o700) == 0
    }

    /// Alte Socket-Datei entfernen – aber nur, wenn es wirklich ein Socket ist und uns gehört.
    /// Eine fremde Datei oder ein Link bleibt liegen → Start scheitert (Spec, Grenze f).
    static func removeStaleSocket(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return errno == ENOENT }
        guard (st.st_mode & S_IFMT) == S_IFSOCK, st.st_uid == getuid() else { return false }
        return unlink(path) == 0
    }

    // MARK: Start/Stopp

    func start() throws(StartError) {
        let dir = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        guard Self.prepareDirectory(dir) else { throw .directory }
        guard Self.removeStaleSocket(socketPath) else { throw .staleFile }
        var addr = sockaddr_un()
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw .pathTooLong }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .socket(errno) }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(fd, 2) == 0 else {
            let e = errno
            close(fd)
            unlink(socketPath)
            throw .socket(e)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        queue.sync {
            listenFD = fd
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.acceptPending() }
            src.resume()
            listenSource = src
        }
        Self.log.notice("\(self.label, privacy: .public) bereit")
    }

    func stop() {
        queue.sync {
            closeClient(reason: nil)
            listenSource?.cancel()
            listenSource = nil
            if listenFD >= 0 { close(listenFD); listenFD = -1; unlink(socketPath) }
            pending = nil
        }
    }

    // MARK: Verbindungen (auf queue)

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var status = Self.checkPeer(fd, requirement)
            if status == errSecSuccess, let parentRequirement { status = Self.checkParent(fd, parentRequirement) }
            guard status == errSecSuccess else {
                close(fd)
                Self.log.error("\(self.label, privacy: .public): Verbindung abgelehnt (OSStatus \(status, privacy: .public))")
                continue
            }
            // Eine geprüfte neue Verbindung ersetzt die alte.
            closeClient(reason: nil)
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            // Größerer Sendepuffer, wo einzelne Nachrichten groß sind (Deck-Cover ≈ 7 KB): lokale Sockets puffern ab Werk nur
            // 8 KB (gemessen 17.11.: net.local.stream.sendspace = 8192); ein Teil-Schreiben schließt die Verbindung.
            if var size = sendBuffer { setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size)) }
            clientFD = fd
            buffer = Data()
            if let ack = LiveText.frame(["v": 1, "ok": true]) { _ = ack.withUnsafeBytes { write(fd, $0.baseAddress, ack.count) } }
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.readClient() }
            src.resume()
            clientSource = src
            Self.log.notice("\(self.label, privacy: .public): \(self.peer, privacy: .public) verbunden")
        }
    }

    /// Audit-Token der Gegenseite → Code → Anforderung. Audit-Token statt PID: kein Wettlauf mit
    /// wiederverwendeten Prozessnummern.
    static func checkPeer(_ fd: Int32, _ requirement: SecRequirement) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
        guard st == errSecSuccess, let code else { return st == errSecSuccess ? errSecCSGuestInvalid : st }
        return SecCodeCheckValidity(code, [], requirement)
    }

    /// Elternprozess des Peers gegen `requirement` (G59). PID aus dem Audit-Token, Eltern-PID aus `proc_pidinfo`, Elterncode per
    /// PID – für den Elternprozess gibt es kein Audit-Token. Restrisiko PID-Wiederverwendung: SECURE-DESIGN G59.
    static func checkParent(_ fd: Int32, _ requirement: SecRequirement) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let pid = pid_t(bitPattern: token.val.5)
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else {
            return errSecCSGuestInvalid
        }
        var code: SecCode?
        let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: NSNumber(value: info.pbi_ppid)] as CFDictionary, [], &code)
        guard st == errSecSuccess, let code else { return st == errSecSuccess ? errSecCSGuestInvalid : st }
        return SecCodeCheckValidity(code, [], requirement)
    }

    private func readClient() {
        var chunk = [UInt8](repeating: 0, count: maxFrame)
        let n = read(clientFD, &chunk, chunk.count)
        if n == 0 { return closeClient(reason: "getrennt") }
        if n < 0 { return errno == EAGAIN ? () : closeClient(reason: "Lesefehler") }
        buffer.append(contentsOf: chunk[0..<n])
        while true {
            switch LiveText.nextFrame(&buffer, max: maxFrame) {
            case .needMore:
                return
            case .invalid:
                return closeClient(reason: "ungültiger Rahmen")
            case .message(let payload):
                guard let value = parse(payload) else { return closeClient(reason: "ungültige Nachricht") }
                deliver(value)
            }
        }
    }

    private func closeClient(reason: String?) {
        clientSource?.cancel()
        clientSource = nil
        if clientFD >= 0 { close(clientFD); clientFD = -1 }
        buffer = Data()
        pending = nil
        if let reason { Self.log.notice("\(self.label, privacy: .public): \(reason, privacy: .public)") }
        onValue(nil)
    }

    /// An den verbundenen, geprüften Client schreiben (Mitteilungen: Filter und Befehle, G29/G30). Ohne Client nichts.
    func send(_ object: [String: Any], max: Int? = nil) {
        guard let data = LiveText.frame(object, max: max ?? maxFrame) else { return }
        queue.async { [weak self] in
            guard let self, clientFD >= 0 else { return }
            let n = data.withUnsafeBytes { write(self.clientFD, $0.baseAddress, data.count) }
            if n != data.count { closeClient(reason: "Schreibfehler") }
        }
    }

    /// Drosseln: höchstens alle 0,25 s, der letzte Stand gewinnt. Ohne `coalesce` jede Nachricht, höchstens
    /// `maxPerSecond` je Sekunde (Flut → der Rest fällt weg; das Hilfsprogramm lässt Apples Banner dann stehen).
    private func deliver(_ value: Value) {
        guard coalesce else {
            let now = Date()
            if now.timeIntervalSince(windowStart) >= 1 { windowStart = now; windowCount = 0 }
            windowCount += 1
            if windowCount <= perSecond { onValue(value) }
            return
        }
        let wait = Self.minDeliveryInterval - Date().timeIntervalSince(lastDelivery)
        guard wait > 0 else {
            lastDelivery = Date()
            return onValue(value)
        }
        pending = value
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            flushScheduled = false
            guard let p = pending, clientFD >= 0 else { return }
            pending = nil
            lastDelivery = Date()
            onValue(p)
        }
    }
}
