import Foundation

/// Netzzugriff fürs Wetter (0.7.0, G31): nur `api.open-meteo.com` und `geocoding-api.open-meteo.com` über HTTPS,
/// flüchtige Sitzung ohne Cookies/Cache, keine Weiterleitungen, 10 s Zeitlimit, Antwort beim Lesen auf 64 KB begrenzt.
final class WeatherClient: NSObject, URLSessionTaskDelegate, Sendable {

    enum Failure: Error, Equatable {
        case url, status(Int), tooLarge, wrongHost, invalid, network
    }

    /// Eine Sitzung für Gnotchi (Review 22.10.: jede Ortssuche legte vorher eine neue an, die nie freigegeben wurde).
    static let shared = WeatherClient()

    private let session: URLSession

    override private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        config.httpAdditionalHeaders = ["User-Agent": "Gnotchi/\(version)"]
        session = URLSession(configuration: config)
        super.init()
    }

    func forecast(_ place: Weather.Place, unit: Weather.Unit) async throws(Failure) -> Weather.Forecast {
        guard let url = Weather.forecastURL(place, unit: unit) else { throw .url }
        let data = try await fetch(url, host: Weather.forecastHost)
        guard let f = Weather.parseForecast(data, unit: unit) else { throw .invalid }
        return f
    }

    func search(_ query: String) async throws(Failure) -> [Weather.Place] {
        guard let url = Weather.searchURL(query) else { throw .url }
        let data = try await fetch(url, host: Weather.geocodingHost)
        guard let places = Weather.parsePlaces(data) else { throw .invalid }
        return places
    }

    private func fetch(_ url: URL, host: String) async throws(Failure) -> Data {
        guard url.scheme == "https", url.host == host else { throw .url }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(from: url, delegate: self)
        } catch {
            throw .network
        }
        guard let http = response as? HTTPURLResponse else { throw .network }
        guard http.url?.host == host else { throw .wrongHost }
        guard http.statusCode == 200 else { throw .status(http.statusCode) }
        guard http.expectedContentLength <= Int64(Weather.maxResponse) else { throw .tooLarge }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > Weather.maxResponse { throw Failure.tooLarge }
            }
        } catch let f as Failure {
            throw f
        } catch {
            throw .network
        }
        return data
    }

    /// Keine Weiterleitungen (G31): eine Antwort 3xx bleibt die Antwort → Status ≠ 200 → verworfen.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
