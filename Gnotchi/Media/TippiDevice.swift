import AppKit
import CoreAudio
import CryptoKit
import Darwin
import Foundation
import OSLog
import Security

/// „Läuft gerade“ auf Tippis Schreibtischgerät (0.41.0, G62; Gerät: tippi-firmware SICHERHEIT.md „Entwurf 0.10“).
///
/// Gnotchi meldet dem Gerät im Heimnetz jede Sekunde Titel, Interpret, App und ob gespielt wird. Die Tasten am Gerät
/// kommen in der Antwort zurück; am Mac läuft dafür **kein Server**. Jede Anfrage ist mit HMAC-SHA256 über
/// `zeit + "\n" + body` signiert, jede Antwort ebenso – Gnotchi führt nur Befehle aus einer signierten Antwort aus,
/// und nur aus der festen Liste (Wiedergabe, Weiter, Zurück, Lauter, Leiser, Stumm). Ab Werk aus. Nie Titel ins Protokoll.
enum TippiDevice {
    static let host = "tippi.local"
    /// Feldgrenzen des Geräts (größer kürzt das Gerät selbst; Gnotchi schickt nicht mehr als nötig).
    static let maxTitle = 80, maxArtist = 60, maxApp = 24
    static let volumeStep: Float = 1.0 / 16

    enum Command: String, CaseIterable, Sendable { case prev, toggle, next, lauter, leiser, stumm }

    // MARK: Reine Teile (getestet)

    static func body(info: NowPlayingInfo?, appName: String?) -> Data {
        var o: [String: Any] = ["s": (info?.isPlaying ?? false) ? 1 : 0]
        if let info {
            o["t"] = String(info.title.prefix(maxTitle))
            o["a"] = String((info.artist ?? "").prefix(maxArtist))
            o["q"] = String((appName ?? "").prefix(maxApp))
        }
        return (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func signature(key: String, time: Int, data: Data) -> String {
        HMAC<SHA256>.authenticationCode(for: Data("\(time)\n".utf8) + data, using: SymmetricKey(data: Data(key.utf8)))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Befehle aus der Antwort – nur bei gültiger Signatur, nur bekannte Namen, höchstens 4.
    static func commands(response: Data, signature: String?, key: String, time: Int) -> [Command] {
        guard let signature, signature.count == 64,
              constantTimeEqual(signature, Self.signature(key: key, time: time, data: response)),
              let obj = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let list = obj["k"] as? [String] else { return [] }
        return Array(list.prefix(4).compactMap(Command.init(rawValue:)))
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var d: UInt8 = 0
        for i in x.indices { d |= x[i] ^ y[i] }
        return d == 0
    }

    /// Druckbares ASCII ohne Leerzeichen, 20–128 Zeichen (nimmt das Gerät genau so an).
    static func validKey(_ key: String) -> Bool {
        (20...128).contains(key.count) && key.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }
}

/// Eigener Schlüsselbund-Eintrag, nicht synchronisiert.
enum TippiDeviceKeychain {
    nonisolated(unsafe) private static let query: [String: Any] = [   // nur gelesen, nie verändert
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.mwlr.gnotchi.tippigeraet",
        kSecAttrAccount as String: "hmac",
    ]

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count <= 128,
              let key = String(data: data, encoding: .utf8), TippiDevice.validKey(key) else { return nil }
        return key
    }

    static func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Meldet jede Sekunde den Stand und führt die Tasten aus der signierten Antwort aus.
@MainActor
final class TippiDeviceLink: NotchPart {

    /// Letztes Ergebnis für die Einstellungen (eigene Apps scheitern nie stumm).
    static var status: String?
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "tippigeraet")

    private let media: NowPlayingModel
    private var timer: Timer?
    private var key: String?
    private var sending = false
    private var lastTime = 0
    private var lastCode: Int?
    private var ip: String?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    init(media: NowPlayingModel) { self.media = media }

    func start() {
        guard timer == nil else { return }
        key = TippiDeviceKeychain.read()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        key = nil
        ip = nil
        Self.status = nil
    }

    /// Schlüssel neu gespeichert: neu lesen.
    func recheck() { key = TippiDeviceKeychain.read() }

    private func tick() {
        guard !sending else { return }
        guard let key else { Self.status = "Schlüssel fehlt"; return }
        let now = max(Int(Date().timeIntervalSince1970), lastTime + 1)   // strikt steigend, sonst lehnt das Gerät ab
        lastTime = now
        let info = media.info
        let appName = info?.appBundleID.flatMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        }
        let body = TippiDevice.body(info: info, appName: appName)
        let signature = TippiDevice.signature(key: key, time: now, data: body)
        let cachedIP = ip
        sending = true
        Task.detached { [session] in
            // Nur IPv4: macOS wartet bei .local sonst ~5 s auf IPv6 (gemessen 22.11. in Tippi).
            guard let address = cachedIP ?? Self.ipv4(TippiDevice.host),
                  let url = URL(string: "http://\(address)/jetzt") else {
                await MainActor.run { self.finish(code: nil, commands: [], ip: nil) }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(String(now), forHTTPHeaderField: "x-tippi-zeit")
            request.setValue(signature, forHTTPHeaderField: "x-tippi-sig")
            var code: Int?
            var commands: [TippiDevice.Command] = []
            if let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse {
                code = http.statusCode
                if code == 200 {
                    commands = TippiDevice.commands(response: data, signature: http.value(forHTTPHeaderField: "x-tippi-sig"),
                                                    key: key, time: now)
                }
            }
            await MainActor.run { self.finish(code: code, commands: commands, ip: code == nil ? nil : address) }
        }
    }

    private func finish(code: Int?, commands: [TippiDevice.Command], ip: String?) {
        sending = false
        guard timer != nil else { return }   // inzwischen ausgeschaltet: keine Tasten mehr ausführen, Status bleibt leer
        self.ip = ip   // Adresse merken; bei Fehler neu auflösen (DHCP)
        Self.status = switch code {
        case 200: "Verbunden"
        case 401: "Gerät lehnt den Schlüssel ab"
        case .some(let c): "Gerät antwortet mit Fehler \(c)"
        case nil: "Gerät nicht gefunden"
        }
        if code != lastCode { Self.log.notice("Tippi-Gerät: \(code ?? -1, privacy: .public)") }
        lastCode = code
        for c in commands { perform(c) }
    }

    private func perform(_ c: TippiDevice.Command) {
        Self.log.notice("Tippi-Gerät: Taste \(c.rawValue, privacy: .public)")
        switch c {
        case .prev: media.previous()
        case .toggle: media.playPause()
        case .next: media.next()
        case .lauter, .leiser, .stumm:
            guard let device = MixerAudio.defaultDevice(.output) else { return }
            let scope = kAudioDevicePropertyScopeOutput
            if c == .stumm {
                _ = MixerAudio.setMuted(device, scope: scope, !(MixerAudio.isMuted(device, scope: scope) ?? false))
            } else if let v = MixerAudio.volume(device, scope: scope) {
                let step = c == .lauter ? TippiDevice.volumeStep : -TippiDevice.volumeStep
                _ = MixerAudio.setVolume(device, scope: scope, min(1, max(0, v + step)))
            }
        }
    }

    nonisolated private static func ipv4(_ host: String) -> String? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "80", &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(res) }
        var addr = first.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buf)
    }
}
