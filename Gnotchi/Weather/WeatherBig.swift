import SwiftUI

/// Wetter groß (0.7.0, Fahrplan): Kopf mit Temperatur und Zustand, nächste 8 Stunden, 7 Tage, Einzelwerte, auf einem
/// Farbverlauf aus Zustand und Tag/Nacht. Quellenangabe ist Pflicht (Open-Meteo, CC BY 4.0). Ortsname kommt aus der
/// Einstellung → `Text(verbatim:)`.
struct WeatherBig: View {
    let forecast: Weather.Forecast

    var body: some View {
        let f = forecast
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: Weather.symbol(f.code, day: f.isDay)).symbolRenderingMode(.multicolor)
                    .font(.system(size: 38))
                Text(verbatim: Self.deg(f.temperature)).font(.system(size: 44, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: Weather.text(f.code)).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text(verbatim: "gefühlt \(Self.deg(f.apparent)) · H \(Self.deg(f.days.first?.max)) T \(Self.deg(f.days.first?.min))")
                        .font(.system(size: 14, weight: .medium)).opacity(0.9).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: f.placeName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(verbatim: "Stand \(Self.time(f.fetched, TimeZone.current))").font(.system(size: 12)).opacity(0.8)
                }
            }
            HStack(spacing: 0) {
                ForEach(f.hours, id: \.time) { h in
                    column(top: Self.hour(h.time, f.timeZone), symbol: Weather.symbol(h.code, day: Self.isDay(h.time, f)),
                           bottom: Self.deg(h.temperature))
                }
            }
            Rectangle().fill(.white.opacity(0.18)).frame(height: 0.6)
            HStack(spacing: 0) {
                ForEach(Array(f.days.enumerated()), id: \.offset) { i, d in
                    column(top: i == 0 ? "Heute" : Self.weekday(d.date, f.timeZone), symbol: Weather.symbol(d.code),
                           bottom: "\(Self.deg(d.max)) \(Self.deg(d.min))")
                }
            }
            HStack(spacing: 16) {
                detail("humidity.fill", "\(Int(f.humidity.rounded())) %")
                detail("wind", "\(Int(f.wind.rounded())) km/h")
                detail("sun.max.fill", "UV \(Int(f.uvMax.rounded()))")
                detail("barometer", "\(Int(f.pressure.rounded())) hPa")
                if let r = f.sunrise { detail("sunrise.fill", Self.time(r, f.timeZone)) }
                if let s = f.sunset { detail("sunset.fill", Self.time(s, f.timeZone)) }
                Spacer(minLength: 0)
            }
            HStack {
                Spacer()
                Text(verbatim: "Wetterdaten: Open-Meteo.com").font(.system(size: 11)).opacity(0.75)
            }
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(
            colors: Weather.gradient(f.code, day: f.isDay).map { Color(red: $0.r, green: $0.g, blue: $0.b) },
            startPoint: .top, endPoint: .bottom)))
        .accessibilityElement(children: .combine)
    }

    private func column(top: String, symbol: String, bottom: String) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: top).font(.system(size: 13, weight: .medium)).opacity(0.9).lineLimit(1)
            Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.system(size: 19)).frame(height: 22)
            Text(verbatim: bottom).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 13))
            Text(verbatim: text).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
        .opacity(0.9)
    }

    // MARK: Formate (Zeitzone des Orts)

    nonisolated static func deg(_ v: Double?) -> String {
        guard let v else { return "–" }
        return "\(Int(v.rounded()))°"
    }

    nonisolated static func time(_ d: Date, _ tz: TimeZone) -> String { format(d, tz, "HH:mm") }
    nonisolated static func hour(_ d: Date, _ tz: TimeZone) -> String { format(d, tz, "HH") }
    nonisolated static func weekday(_ d: Date, _ tz: TimeZone) -> String { format(d, tz, "EEEEEE") }

    nonisolated private static func format(_ d: Date, _ tz: TimeZone, _ f: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.timeZone = tz
        df.dateFormat = f
        return df.string(from: d)
    }

    /// Stunde bei Tag? Zwischen Sonnenauf- und -untergang des ersten Tages (Uhrzeit verglichen), sonst Nacht.
    nonisolated static func isDay(_ t: Date, _ f: Weather.Forecast) -> Bool {
        guard let rise = f.sunrise, let set = f.sunset else { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = f.timeZone
        func minutes(_ d: Date) -> Int {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let m = minutes(t)
        return m >= minutes(rise) && m < minutes(set)
    }
}
