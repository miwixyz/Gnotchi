import Foundation

/// Wetter (0.7.0, specs/2026-10-22-gnotchi-0.7.0-wetter.md, SECURE-DESIGN G31): reine Teile. Antworten von Open-Meteo
/// sind Fremddaten – strenges Schema, Bereiche, Bereinigung; unbekannter Wettercode → ganze Antwort verworfen.
enum Weather {

    nonisolated static let maxResponse = 64 * 1024
    nonisolated static let maxEntries = 200
    nonisolated static let maxPlaceName = 60
    nonisolated static let maxQuery = 100
    nonisolated static let forecastHost = "api.open-meteo.com"
    nonisolated static let geocodingHost = "geocoding-api.open-meteo.com"

    enum Unit: String, Sendable, CaseIterable { case celsius, fahrenheit }

    /// Gewählter Ort, Koordinaten auf 2 Nachkommastellen gerundet (≈ 1 km).
    struct Place: Equatable, Sendable, Identifiable {
        let name: String
        let region: String
        let country: String
        let latitude: Double
        let longitude: Double
        var id: String { "\(latitude),\(longitude),\(name)" }
        var label: String { [name, region, country].filter { !$0.isEmpty }.joined(separator: " · ") }
    }

    struct Hour: Equatable, Sendable {
        let time: Date
        let temperature: Double
        let code: Int
    }

    struct Day: Equatable, Sendable {
        let date: Date
        let code: Int
        let max: Double
        let min: Double
    }

    struct Forecast: Equatable, Sendable {
        let fetched: Date
        let timeZone: TimeZone
        let temperature: Double
        let apparent: Double
        let code: Int
        let isDay: Bool
        let humidity: Double
        let wind: Double
        let pressure: Double
        let uvMax: Double
        let sunrise: Date?
        let sunset: Date?
        let hours: [Hour]
        let days: [Day]
        /// Angezeigter Ortsname (setzt WeatherLink aus der Einstellung, nicht aus der Antwort).
        var placeName = ""
    }

    // MARK: Anfragen (feste Hosts, G31)

    nonisolated static func rounded(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    nonisolated static func forecastURL(_ place: Place, unit: Unit) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = forecastHost
        c.path = "/v1/forecast"
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", rounded(place.latitude))),
            .init(name: "longitude", value: String(format: "%.2f", rounded(place.longitude))),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7"),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,relative_humidity_2m,"
                  + "wind_speed_10m,is_day,pressure_msl"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max"),
        ] + (unit == .fahrenheit ? [.init(name: "temperature_unit", value: "fahrenheit")] : [])
        return c.url
    }

    nonisolated static func searchURL(_ query: String) -> URL? {
        let q = String(LiveText.sanitize(query).prefix(maxQuery))
        guard !q.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = geocodingHost
        c.path = "/v1/search"
        c.queryItems = [.init(name: "name", value: q), .init(name: "count", value: "5"),
                        .init(name: "language", value: "de"), .init(name: "format", value: "json")]
        return c.url
    }

    // MARK: Antworten

    /// Ortssuche → höchstens 5 Orte. `nil` = ungültig; keine Treffer = leere Liste.
    nonisolated static func parsePlaces(_ data: Data) -> [Place]? {
        guard data.count <= maxResponse, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let raw = obj["results"] else { return [] }   // Open-Meteo lässt `results` ohne Treffer weg
        guard let list = raw as? [[String: Any]], list.count <= 20 else { return nil }
        return list.prefix(5).compactMap { r in
            guard let name = r["name"] as? String, let lat = number(r["latitude"], -90...90),
                  let lon = number(r["longitude"], -180...180) else { return nil }
            let clean = NotifyWire.clean(name, max: maxPlaceName)
            guard !clean.isEmpty else { return nil }
            return Place(name: clean, region: NotifyWire.clean(r["admin1"] as? String ?? "", max: maxPlaceName),
                         country: NotifyWire.clean(r["country_code"] as? String ?? "", max: 3),
                         latitude: rounded(lat), longitude: rounded(lon))
        }
    }

    /// Vorhersage. `nil` bei allem, was nicht dem gemessenen Aufbau entspricht (Spec „Gemessen 22.10.“).
    nonisolated static func parseForecast(_ data: Data, unit: Unit, now: Date = Date()) -> Forecast? {
        guard data.count <= maxResponse, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let offset = number(obj["utc_offset_seconds"], -50_400...50_400),
              let tz = TimeZone(secondsFromGMT: Int(offset)),
              let cur = obj["current"] as? [String: Any], let hourly = obj["hourly"] as? [String: Any],
              let daily = obj["daily"] as? [String: Any] else { return nil }
        let tempRange: ClosedRange<Double> = unit == .celsius ? -90...60 : -130...140
        guard let temp = number(cur["temperature_2m"], tempRange), let apparent = number(cur["apparent_temperature"], tempRange),
              let code = code(cur["weather_code"]), let isDay = number(cur["is_day"], 0...1),
              let humidity = number(cur["relative_humidity_2m"], 0...100), let wind = number(cur["wind_speed_10m"], 0...500),
              let pressure = number(cur["pressure_msl"], 800...1100) else { return nil }
        guard let hTimes = strings(hourly["time"]), let hTemps = numbers(hourly["temperature_2m"], tempRange),
              let hCodes = codes(hourly["weather_code"]), hTimes.count == hTemps.count, hTimes.count == hCodes.count,
              let dTimes = strings(daily["time"]), let dCodes = codes(daily["weather_code"]),
              let dMax = numbers(daily["temperature_2m_max"], tempRange), let dMin = numbers(daily["temperature_2m_min"], tempRange),
              let rises = strings(daily["sunrise"]), let sets = strings(daily["sunset"]),
              let uv = numbers(daily["uv_index_max"], 0...20),
              [dCodes.count, dMax.count, dMin.count, rises.count, sets.count, uv.count].allSatisfy({ $0 == dTimes.count }),
              !dTimes.isEmpty else { return nil }
        let minute = formatter("yyyy-MM-dd'T'HH:mm", tz)
        let day = formatter("yyyy-MM-dd", tz)
        var hours: [Hour] = []
        for i in hTimes.indices {
            guard let t = minute.date(from: hTimes[i]) else { return nil }
            // Ab der laufenden Stunde, die nächsten 8.
            if t > now.addingTimeInterval(-3600), hours.count < 8 { hours.append(Hour(time: t, temperature: hTemps[i], code: hCodes[i])) }
        }
        var days: [Day] = []
        for i in dTimes.indices {
            // Auch Sonnenauf-/-untergang müssen lesbar sein – sonst ganze Antwort verworfen (Test 22.10., G31).
            guard let d = day.date(from: dTimes[i]), minute.date(from: rises[i]) != nil, minute.date(from: sets[i]) != nil else {
                return nil
            }
            days.append(Day(date: d, code: dCodes[i], max: dMax[i], min: dMin[i]))
        }
        return Forecast(fetched: now, timeZone: tz, temperature: temp, apparent: apparent, code: code, isDay: isDay == 1,
                        humidity: humidity, wind: wind, pressure: pressure, uvMax: uv[0],
                        sunrise: minute.date(from: rises[0]), sunset: minute.date(from: sets[0]), hours: hours, days: days)
    }

    // MARK: Wettercodes (WMO, Liste von open-meteo.com/en/docs, 22.10.)

    nonisolated static let codeTexts: [Int: String] = [
        0: "Klar", 1: "Überwiegend klar", 2: "Teilweise bewölkt", 3: "Bedeckt", 45: "Nebel", 48: "Reifnebel",
        51: "Leichter Nieselregen", 53: "Nieselregen", 55: "Starker Nieselregen", 56: "Gefrierender Niesel",
        57: "Starker gefrierender Niesel", 61: "Leichter Regen", 63: "Regen", 65: "Starker Regen",
        66: "Gefrierender Regen", 67: "Starker gefrierender Regen", 71: "Leichter Schneefall", 73: "Schneefall",
        75: "Starker Schneefall", 77: "Schneegriesel", 80: "Leichte Regenschauer", 81: "Regenschauer",
        82: "Heftige Regenschauer", 85: "Leichte Schneeschauer", 86: "Schneeschauer", 95: "Gewitter",
        96: "Gewitter mit Hagel", 97: "Schweres Gewitter", 99: "Gewitter mit starkem Hagel",
    ]

    nonisolated static func text(_ code: Int) -> String { codeTexts[code] ?? "" }

    nonisolated static func symbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66: "cloud.rain.fill"
        case 65, 67, 82: "cloud.heavyrain.fill"
        case 80, 81: day ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        default: "cloud.bolt.rain.fill"
        }
    }

    /// Himmel als Farbverlauf (Fahrplan: keine Fotos) – Zustandsgruppe × Tag/Nacht, Farben als RGB 0…1.
    enum Sky: Equatable { case clear, cloudy, rain, snow, storm, fog }

    nonisolated static func sky(_ code: Int) -> Sky {
        switch code {
        case 0, 1: .clear
        case 2, 3: .cloudy
        case 45, 48: .fog
        case 71, 73, 75, 77, 85, 86: .snow
        case 95, 96, 97, 99: .storm
        default: .rain
        }
    }

    struct RGB: Equatable, Sendable {
        let r, g, b: Double
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    }

    nonisolated static func gradient(_ code: Int, day: Bool) -> [RGB] {
        switch (sky(code), day) {
        case (.clear, true): [RGB(0.20, 0.50, 0.90), RGB(0.45, 0.72, 0.98)]
        case (.cloudy, true): [RGB(0.36, 0.47, 0.60), RGB(0.58, 0.66, 0.75)]
        case (.fog, true): [RGB(0.52, 0.56, 0.60), RGB(0.70, 0.72, 0.74)]
        case (.rain, true): [RGB(0.24, 0.30, 0.40), RGB(0.40, 0.46, 0.55)]
        case (.snow, true): [RGB(0.55, 0.62, 0.72), RGB(0.80, 0.84, 0.90)]
        case (.storm, true): [RGB(0.20, 0.18, 0.32), RGB(0.36, 0.33, 0.48)]
        case (.storm, false): [RGB(0.10, 0.08, 0.18), RGB(0.20, 0.16, 0.30)]
        case (_, false): [RGB(0.05, 0.08, 0.20), RGB(0.14, 0.20, 0.38)]
        }
    }

    // MARK: Hilfen

    nonisolated private static func formatter(_ format: String, _ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = format
        return f
    }

    /// Endliche Zahl (kein Wahrheitswert) im Bereich.
    nonisolated static func number(_ v: Any?, _ range: ClosedRange<Double>) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite && range.contains(d) ? d : nil
    }

    nonisolated private static func code(_ v: Any?) -> Int? {
        guard let d = number(v, 0...99), d == d.rounded(), codeTexts[Int(d)] != nil else { return nil }
        return Int(d)
    }

    nonisolated private static func numbers(_ v: Any?, _ range: ClosedRange<Double>) -> [Double]? {
        guard let a = v as? [Any], a.count <= maxEntries else { return nil }
        let out = a.compactMap { number($0, range) }
        return out.count == a.count ? out : nil
    }

    nonisolated private static func codes(_ v: Any?) -> [Int]? {
        guard let a = v as? [Any], a.count <= maxEntries else { return nil }
        let out = a.compactMap(code)
        return out.count == a.count ? out : nil
    }

    nonisolated private static func strings(_ v: Any?) -> [String]? {
        guard let a = v as? [Any], a.count <= maxEntries else { return nil }
        let out = a.compactMap { ($0 as? String).flatMap { $0.count <= 20 ? $0 : nil } }
        return out.count == a.count ? out : nil
    }
}
