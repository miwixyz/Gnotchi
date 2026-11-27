import AppKit
import Foundation
import Observation
import OSLog

/// Türklingel-Livebild in der Insel (Michael 27.11.). Gnotchi liest **kein RTSP** (AVFoundation kann es nicht, ffmpeg
/// wäre eine fremde Abhängigkeit), sondern holt Einzelbilder (JPEG/PNG) per HTTP von einer selbst eingetragenen Adresse,
/// z. B. einem kleinen Dienst im Heimnetz, der den Kamera-Stream schon offen hält. Gemessen 27.11.: Die Kamera verträgt
/// einen zweiten Abrufer nur schlecht – der erste Dienst stockte danach –, deshalb bewusst nicht direkt an die Kamera.
///
/// - Adresse ab Werk leer = aus. Nur `http`/`https`, ohne Zugangsdaten in der Adresse (stünden sonst im Klartext in den
///   Einstellungen), keine Weiterleitungen, kein Cache, keine Cookies.
/// - Abruf nur, solange eine Insel den Klingel-Hinweis zeigt. Das Bild liegt nur im Arbeitsspeicher, nie auf der Platte,
///   und verschwindet mit dem Hinweis.
/// - Fehler stehen sichtbar in der Insel (eigene Apps scheitern nie stumm), ins Protokoll nur der Statuscode, nie die Adresse.
enum DoorbellCamera {
    /// Größtes angenommenes Bild (ein 640×480-JPEG hat ~50 KB).
    static let maxBytes = 4 * 1024 * 1024
    /// Größte angenommene Kantenlänge in Pixeln (Kamera liefert 640 × 480).
    static let maxPixels = 4096
    static let maxURLLength = 2048
    /// Abstand zwischen zwei Abrufen; nach einem Fehler länger (schont Dienst und Kamera).
    static let interval: Duration = .milliseconds(500)
    static let retryInterval: Duration = .seconds(2)

    /// Gültige Bildadresse oder nil (leer, kaputt, falsches Schema, Zugangsdaten enthalten).
    static func validURL(_ text: String) -> URL? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= maxURLLength, let c = URLComponents(string: s),
              let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil else { return nil }
        return c.url
    }

    /// Warum eine eingetragene Adresse nicht geht (für die Einstellungen), nil = leer oder gültig.
    static func problem(_ text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || validURL(s) != nil { return nil }
        if let c = URLComponents(string: s), c.user != nil || c.password != nil {
            return "Bitte ohne Benutzername und Passwort in der Adresse."
        }
        return "Keine gültige Adresse. Erwartet wird http:// oder https:// mit Rechnername."
    }

    enum FetchError: Error, Equatable {
        case status(Int), tooLarge, notImage, unreachable
        var text: String {
            switch self {
            case .status(let c): "Kamerabild: Fehler \(c)"
            case .tooLarge: "Kamerabild zu groß"
            case .notImage: "Kamerabild: kein JPEG oder PNG"
            case .unreachable: "Kamerabild nicht erreichbar"
            }
        }
    }

    /// Prüft die Antwort und baut das Bild. Nur JPEG und PNG (Dateianfang), damit nicht jeder Bilddecoder fremde
    /// Daten zu sehen bekommt.
    static func image(data: Data, status: Int) -> Result<NSImage, FetchError> {
        guard status == 200 else { return .failure(.status(status)) }
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        let jpeg = data.starts(with: [0xFF, 0xD8, 0xFF])
        let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard jpeg || png, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w >= 1, h >= 1 else { return .failure(.notImage) }
        // Pixelmaße vor dem Entpacken prüfen: wenige KB können 30000 × 30000 Pixel ansagen (Speicher voll).
        guard w <= maxPixels, h <= maxPixels else { return .failure(.tooLarge) }
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return .failure(.notImage) }
        return .success(NSImage(cgImage: cg, size: NSSize(width: w, height: h)))
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Holt Bilder, solange mindestens eine Insel den Klingel-Hinweis zeigt (`attach`/`detach` aus der Ansicht).
/// Mehrere Bildschirme teilen sich einen Abruf.
@MainActor
@Observable
final class DoorbellFeed {
    private(set) var frame: NSImage?
    private(set) var error: String?

    /// Abrufadresse; nil = aus. NotifyLink setzt sie vor jeder Mitteilung aus den Einstellungen.
    @ObservationIgnored var url: URL?
    /// Austauschbar für Tests: liefert (Daten, Statuscode) oder wirft.
    @ObservationIgnored var load: @Sendable (URL) async throws -> (Data, Int) = DoorbellFeed.liveLoad

    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastLogged: Int?
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "tuerklingel")

    var isRunning: Bool { task != nil }

    func attach() {
        viewers += 1
        guard task == nil, let url else { return }
        task = Task { [weak self] in await self?.run(url) }
    }

    func detach() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { stop() }
    }

    /// Alles verwerfen (Hinweis weg, Schalter aus): kein Bild bleibt im Speicher.
    func stop() {
        viewers = 0
        task?.cancel()
        task = nil
        frame = nil
        error = nil
    }

    private func run(_ url: URL) async {
        while !Task.isCancelled {
            let result: Result<NSImage, DoorbellCamera.FetchError>
            do {
                let (data, status) = try await load(url)
                result = DoorbellCamera.image(data: data, status: status)
                log(status)
            } catch let e as DoorbellCamera.FetchError {
                result = .failure(e)
            } catch {
                result = .failure(.unreachable)
                log(-1)
            }
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let image):
                frame = image
                error = nil
            case .failure(let e):
                // Letztes Bild nicht stehen lassen: ein altes Bild sähe aus wie live.
                frame = nil
                error = e.text
            }
            try? await Task.sleep(for: error == nil ? DoorbellCamera.interval : DoorbellCamera.retryInterval)
        }
    }

    private func log(_ status: Int) {
        guard status != lastLogged else { return }
        lastLogged = status
        Self.log.notice("Türklingel-Bild: \(status, privacy: .public)")
    }

    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    /// Liest höchstens `maxBytes + 1` Bytes, dann `tooLarge` – ein Dienst, der endlos sendet, füllt nicht den Speicher.
    nonisolated static let liveLoad: @Sendable (URL) async throws -> (Data, Int) = { url in
        var request = URLRequest(url: url)
        request.setValue("image/jpeg, image/png", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return (Data(), status) }
        if response.expectedContentLength > Int64(DoorbellCamera.maxBytes) { throw DoorbellCamera.FetchError.tooLarge }
        var data = Data()
        data.reserveCapacity(Int(max(0, min(response.expectedContentLength, Int64(DoorbellCamera.maxBytes)))))
        for try await byte in bytes {
            data.append(byte)
            if data.count > DoorbellCamera.maxBytes { throw DoorbellCamera.FetchError.tooLarge }
        }
        return (data, status)
    }
}
