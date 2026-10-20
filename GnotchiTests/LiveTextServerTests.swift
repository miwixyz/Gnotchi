import Darwin
import Security
import XCTest
@testable import Gnotchi

// SYNTHETISCH – erfundene Beispielsätze, keine echten Diktate (Datenschutz-Gate, SECURE-DESIGN G16)

/// 0.3.0 Live-Text-Socket (SECURE-DESIGN G21): Dateisystem-Fälle, Prüfung der Gegenseite, Ablauf.
final class LiveTextServerTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        // Kurzer Pfad: sun_path fasst nur 104 Byte.
        dir = URL(fileURLWithPath: "/tmp/gnt-\(UUID().uuidString.prefix(8))")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Dateisystem

    func testPrepareDirectoryCreates0700() throws {
        XCTAssertTrue(LiveTextServer.prepareDirectory(dir))
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testPrepareDirectoryTightensLooseRights() throws {
        XCTAssertEqual(mkdir(dir.path, 0o755), 0)
        XCTAssertTrue(LiveTextServer.prepareDirectory(dir))
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testPrepareDirectoryRejectsSymlinkAndFile() throws {
        let target = URL(fileURLWithPath: "/tmp/gnt-ziel-\(UUID().uuidString.prefix(8))")
        XCTAssertEqual(mkdir(target.path, 0o700), 0)
        defer { try? FileManager.default.removeItem(at: target) }
        XCTAssertEqual(symlink(target.path, dir.path), 0)
        XCTAssertFalse(LiveTextServer.prepareDirectory(dir), "Link auf einen Ordner")
        try FileManager.default.removeItem(at: dir)
        FileManager.default.createFile(atPath: dir.path, contents: Data())
        XCTAssertFalse(LiveTextServer.prepareDirectory(dir), "Datei statt Ordner")
    }

    func testRemoveStaleSocketLeavesForeignFiles() throws {
        XCTAssertTrue(LiveTextServer.prepareDirectory(dir))
        let path = dir.appendingPathComponent("live.sock").path
        XCTAssertTrue(LiveTextServer.removeStaleSocket(path), "nichts da: in Ordnung")
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        XCTAssertFalse(LiveTextServer.removeStaleSocket(path), "normale Datei bleibt liegen")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testStartFailsOnForeignFileAtSocketPath() throws {
        XCTAssertTrue(LiveTextServer.prepareDirectory(dir))
        FileManager.default.createFile(atPath: dir.appendingPathComponent("live.sock").path, contents: Data())
        let server = LiveTextServer(directory: dir, requirement: try selfRequirement()) { _ in }
        XCTAssertThrowsError(try server.start()) { XCTAssertEqual($0 as? LiveTextServer.StartError, .staleFile) }
    }

    // MARK: Ablauf mit echtem Socket

    func testAcceptedPeerDeliversSanitizedText() throws {
        let got = Box()
        let server = LiveTextServer(directory: dir, requirement: try selfRequirement()) { got.append($0) }
        try server.start()
        defer { server.stop() }
        let fd = try connect(server.socketPath)
        defer { close(fd) }
        XCTAssertEqual(try readAck(fd), true, "geprüfte Verbindung bekommt ok")
        try send(fd, ["v": 1, "text": "Hallo\u{202E} Welt"])
        XCTAssertTrue(waitFor { got.values.contains("Hallo Welt") }, "bereinigt angekommen")
    }

    func testRejectedPeerGetsNothingAndDeliversNothing() throws {
        let got = Box()
        var req: SecRequirement?
        SecRequirementCreateWithString(LiveText.tippiRequirement as CFString, [], &req)
        let server = LiveTextServer(directory: dir, requirement: try XCTUnwrap(req)) { got.append($0) }
        try server.start()
        defer { server.stop() }
        let fd = try connect(server.socketPath)
        defer { close(fd) }
        _ = try? send(fd, ["v": 1, "text": "untergeschoben"])
        XCTAssertNil(try readAck(fd), "kein ok, Verbindung zu")
        XCTAssertFalse(got.values.contains { $0 != nil }, "nichts angezeigt")
    }

    func testInvalidMessageClosesAndClears() throws {
        let got = Box()
        let server = LiveTextServer(directory: dir, requirement: try selfRequirement()) { got.append($0) }
        try server.start()
        defer { server.stop() }
        let fd = try connect(server.socketPath)
        defer { close(fd) }
        _ = try readAck(fd)
        try send(fd, ["v": 1, "text": "erst gut"])
        XCTAssertTrue(waitFor { got.values.contains("erst gut") })
        try send(fd, ["v": 2, "text": "falsche Version"])
        XCTAssertTrue(waitFor { got.values.last == .some(nil) }, "Verbindung zu, Text geleert")
        XCTAssertFalse(got.values.contains("falsche Version"))
    }

    func testThrottleLastWins() throws {
        let got = Box()
        let server = LiveTextServer(directory: dir, requirement: try selfRequirement()) { got.append($0) }
        try server.start()
        defer { server.stop() }
        let fd = try connect(server.socketPath)
        defer { close(fd) }
        _ = try readAck(fd)
        for i in 1...20 { try send(fd, ["v": 1, "text": "Stand \(i)"]) }
        XCTAssertTrue(waitFor { got.values.contains("Stand 20") }, "letzter Stand kommt an")
        XCTAssertLessThan(got.values.compactMap { $0 }.count, 5, "gedrosselt, nicht 20 Mal")
    }

    // MARK: Hilfen

    /// Anforderung, die genau dieser Testlauf erfüllt (seine eigene Designated Requirement).
    private func selfRequirement() throws -> SecRequirement {
        var me: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &me), errSecSuccess)
        var stat: SecStaticCode?
        XCTAssertEqual(SecCodeCopyStaticCode(try XCTUnwrap(me), [], &stat), errSecSuccess)
        var req: SecRequirement?
        XCTAssertEqual(SecCodeCopyDesignatedRequirement(try XCTUnwrap(stat), [], &req), errSecSuccess)
        return try XCTUnwrap(req)
    }

    private func connect(_ path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(r, 0)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private func send(_ fd: Int32, _ obj: [String: Any]) throws {
        let data = try XCTUnwrap(LiveText.frame(obj))
        let n = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        guard n == data.count else { throw POSIXError(.EPIPE) }
    }

    /// `true` = ok erhalten, `nil` = Verbindung ohne Antwort geschlossen.
    private func readAck(_ fd: Int32) throws -> Bool? {
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 256)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return nil }
            buf.append(contentsOf: chunk[0..<n])
            if case .message(let p) = LiveText.nextFrame(&buf) {
                let obj = try JSONSerialization.jsonObject(with: p) as? [String: Any]
                return obj?["ok"] as? Bool
            }
        }
    }

    private func waitFor(_ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}

/// Gesammelte Rückrufe, threadsicher.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String?] = []
    func append(_ s: String?) { lock.lock(); items.append(s); lock.unlock() }
    var values: [String?] { lock.lock(); defer { lock.unlock() }; return items }
}
