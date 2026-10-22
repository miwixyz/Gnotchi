import XCTest
@testable import Gnotchi

// SYNTHETISCH – erfundene Werte im gemessenen Aufbau von Open-Meteo (22.10.), keine echten Daten.

/// 0.7.0 Wetter (SECURE-DESIGN G31): Anfragen nur an feste Hosts, Antworten als Fremddaten, Anzeige-Zuordnungen.
@MainActor
final class WeatherTests: XCTestCase {

    private let place = Weather.Place(name: "Beispielstadt", region: "Land", country: "DE", latitude: 48.137_43,
                                      longitude: 11.575_49)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC

    private func forecastJSON(_ change: (inout [String: Any]) -> Void = { _ in }) -> Data {
        let hours = (0..<24).map { String(format: "2027-01-15T%02d:00", $0) }
        let days = (15..<22).map { "2027-01-\($0)" }
        var obj: [String: Any] = [
            "utc_offset_seconds": 3600,
            "current": ["time": "2027-01-15T09:00", "temperature_2m": 2.4, "apparent_temperature": -1.0, "weather_code": 71,
                        "relative_humidity_2m": 80, "wind_speed_10m": 12.5, "is_day": 1, "pressure_msl": 1012.3],
            "hourly": ["time": hours, "temperature_2m": hours.map { _ in 1.5 }, "weather_code": hours.map { _ in 3 }],
            "daily": ["time": days, "weather_code": days.map { _ in 61 }, "temperature_2m_max": days.map { _ in 4.0 },
                      "temperature_2m_min": days.map { _ in -2.0 }, "sunrise": days.map { "\($0)T08:01" },
                      "sunset": days.map { "\($0)T16:40" }, "uv_index_max": days.map { _ in 0.9 }],
        ]
        change(&obj)
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    // MARK: Anfragen (G31)

    func testForecastURLFixedHostRoundedCoordinates() throws {
        let url = try XCTUnwrap(Weather.forecastURL(place, unit: .celsius))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertEqual(url.path, "/v1/forecast")
        let q = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(q.first { $0.name == "latitude" }?.value, "48.14", "auf 2 Stellen gerundet")
        XCTAssertEqual(q.first { $0.name == "longitude" }?.value, "11.58")
        XCTAssertNil(q.first { $0.name == "temperature_unit" })
        let f = try XCTUnwrap(Weather.forecastURL(place, unit: .fahrenheit))
        XCTAssertTrue(f.absoluteString.contains("temperature_unit=fahrenheit"))
    }

    func testSearchURLOnlyQueryValueEncodedAndCapped() throws {
        let url = try XCTUnwrap(Weather.searchURL("Köln/../../etc?x=1&host=evil.example"))
        XCTAssertEqual(url.host, "geocoding-api.open-meteo.com", "Eingabe ändert nie den Host")
        XCTAssertEqual(url.path, "/v1/search")
        let q = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(q.first { $0.name == "name" }?.value, "Köln/../../etc?x=1&host=evil.example", "nur als Wert")
        XCTAssertNil(q.first { $0.name == "host" })
        let long = try XCTUnwrap(Weather.searchURL(String(repeating: "a", count: 500)))
        let name = try XCTUnwrap(URLComponents(url: long, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
        XCTAssertEqual(name.count, Weather.maxQuery)
        XCTAssertNil(Weather.searchURL("  \u{202E} "), "leer nach Bereinigung")
    }

    // MARK: Vorhersage

    func testValidForecastParses() throws {
        let f = try XCTUnwrap(Weather.parseForecast(forecastJSON(), unit: .celsius, now: now))
        XCTAssertEqual(f.temperature, 2.4)
        XCTAssertEqual(f.code, 71)
        XCTAssertTrue(f.isDay)
        XCTAssertEqual(f.days.count, 7)
        XCTAssertEqual(f.hours.count, 8, "nur die nächsten 8 Stunden")
        XCTAssertEqual(f.timeZone.secondsFromGMT(), 3600)
        XCTAssertEqual(WeatherBig.time(try XCTUnwrap(f.sunrise), f.timeZone), "08:01", "Ortszeit")
        XCTAssertEqual(WeatherBig.hour(f.hours[0].time, f.timeZone), "09", "ab der laufenden Stunde (jetzt 09:00 Ortszeit)")
    }

    func testOutOfRangeNaNAndWrongTypesAreRejected() {
        let cases: [(inout [String: Any]) -> Void] = [
            { o in var c = o["current"] as! [String: Any]; c["temperature_2m"] = 999; o["current"] = c },   // swiftlint:disable:this force_cast
            { o in var c = o["current"] as! [String: Any]; c["relative_humidity_2m"] = 140; o["current"] = c },   // swiftlint:disable:this force_cast
            { o in var c = o["current"] as! [String: Any]; c["weather_code"] = 42; o["current"] = c },   // swiftlint:disable:this force_cast
            { o in var c = o["current"] as! [String: Any]; c["is_day"] = true; o["current"] = c },   // swiftlint:disable:this force_cast
            { o in var c = o["current"] as! [String: Any]; c["wind_speed_10m"] = "schnell"; o["current"] = c },   // swiftlint:disable:this force_cast
            { o in var d = o["daily"] as! [String: Any]; d["temperature_2m_max"] = [4.0]; o["daily"] = d },   // swiftlint:disable:this force_cast
            // swiftlint:disable:next force_cast
            { o in var h = o["hourly"] as! [String: Any]; h["time"] = (0..<300).map { _ in "2027-01-15T00:00" }; o["hourly"] = h },
            // swiftlint:disable:next force_cast
            { o in var d = o["daily"] as! [String: Any]; d["sunrise"] = (0..<7).map { _ in "morgens" }; o["daily"] = d },
            { o in o["utc_offset_seconds"] = 999_999 },
            { o in o["current"] = nil },
        ]
        for (i, change) in cases.enumerated() {
            XCTAssertNil(Weather.parseForecast(forecastJSON(change), unit: .celsius, now: now), "Fall \(i)")
        }
        XCTAssertNil(Weather.parseForecast(Data(repeating: 0x20, count: Weather.maxResponse + 1), unit: .celsius), "zu groß")
        XCTAssertNil(Weather.number(Double.nan, -10...10))
    }

    func testFahrenheitRangeAllowsWarmValues() {
            // swiftlint:disable:next force_cast
        let hot = forecastJSON { o in var c = o["current"] as! [String: Any]; c["temperature_2m"] = 104; o["current"] = c }
        XCTAssertNil(Weather.parseForecast(hot, unit: .celsius, now: now), "104 °C gibt es nicht")
        XCTAssertNotNil(Weather.parseForecast(hot, unit: .fahrenheit, now: now))
    }

    // MARK: Ortssuche

    func testPlacesParsedSanitizedAndCapped() throws {
        let list: [[String: Any]] = (0..<8).map { i in
            ["name": "Ort\u{202E}\(i)", "latitude": 50.123_456, "longitude": 8.654_321, "admin1": "Region", "country_code": "DE"]
        }
        let places = try XCTUnwrap(Weather.parsePlaces(try JSONSerialization.data(withJSONObject: ["results": list])))
        XCTAssertEqual(places.count, 5, "höchstens 5")
        XCTAssertEqual(places[0].name, "Ort0", "Richtungszeichen raus")
        XCTAssertEqual(places[0].latitude, 50.12)
        XCTAssertEqual(places[0].label, "Ort0 · Region · DE")
        XCTAssertEqual(Weather.parsePlaces(try JSONSerialization.data(withJSONObject: ["generationtime_ms": 0.1])), [],
                       "kein Treffer = leer (gemessen: `results` fehlt)")
        let bad: [[String: Any]] = [["name": "X", "latitude": 400, "longitude": 0]]
        XCTAssertEqual(Weather.parsePlaces(try JSONSerialization.data(withJSONObject: ["results": bad])), [])
        XCTAssertNil(Weather.parsePlaces(Data("kein json".utf8)))
    }

    func testStoredPlaceValidated() {
        XCTAssertEqual(Preferences.validPlace(["name": "A", "lat": 48.137, "lon": 11.575])?.latitude, 48.14)
        XCTAssertNil(Preferences.validPlace(["name": "A", "lat": 91, "lon": 0]))
        XCTAssertNil(Preferences.validPlace(["name": "\u{202E}", "lat": 1, "lon": 1]))
        XCTAssertNil(Preferences.validPlace("München"))
    }

    // MARK: Anzeige

    func testEveryCodeHasTextAndSymbol() {
        for code in Weather.codeTexts.keys {
            XCTAssertFalse(Weather.text(code).isEmpty)
            XCTAssertFalse(Weather.symbol(code).isEmpty)
            XCTAssertEqual(Weather.gradient(code, day: true).count, 2)
        }
        XCTAssertEqual(Weather.symbol(0, day: false), "moon.stars.fill")
        XCTAssertEqual(Weather.sky(95), .storm)
        XCTAssertEqual(WeatherBig.deg(-0.4), "0°")
        XCTAssertEqual(WeatherBig.deg(nil), "–")
    }

    func testWeatherShowsBigOnlyWhenSelected() throws {
        let m = ActivityModel(media: NowPlayingModel())
        m.selectWeather()
        XCTAssertFalse(m.weatherActive, "ohne Vorhersage nichts")
        let f = try XCTUnwrap(Weather.parseForecast(forecastJSON(), unit: .celsius, now: now))
        m.setWeather(f)
        XCTAssertTrue(m.isVisible, "Ruhe-Insel (0.8.0, Michael 22.10.): Wetter an → kleine Insel bleibt mit Temperatur")
        XCTAssertEqual(m.bigContent, .weather, "Überfahren ohne andere Aktivität → Wetter groß")
        m.selectWeather()
        XCTAssertEqual(m.bigContent, .weather)
        XCTAssertNil(m.highlightedChip)
        m.selectMirror()
        XCTAssertFalse(m.weatherActive)
        m.selectWeather()
        m.endMirror()   // Einklappen
        XCTAssertFalse(m.weatherActive)
        m.selectWeather()
        m.setWeather(nil)
        XCTAssertFalse(m.weatherActive)
    }
}
