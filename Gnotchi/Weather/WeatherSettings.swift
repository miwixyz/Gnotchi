import SwiftUI

/// Ort und Einheit fürs Wetter (0.7.0, G31). Gesucht wird nur auf Klick „Suchen“; gespeichert nur der gewählte Ort.
/// Treffer-Namen kommen aus dem Netz → `Text(verbatim:)`.
struct WeatherSettings: View {
    @Environment(Preferences.self) private var prefs
    let onChange: () -> Void

    @State private var query = ""
    @State private var results: [Weather.Place] = []
    @State private var searching = false
    @State private var message: String?

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 0) {
            if prefs.weather {
                HStack(spacing: FamilyTheme.Space.m) {
                    Text("Ort").foregroundStyle(FamilyTheme.textPrimary)
                    Spacer(minLength: FamilyTheme.Space.m)
                    Text(verbatim: prefs.weatherPlace?.label ?? "noch keiner").lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(prefs.weatherPlace == nil ? FamilyTheme.warning : FamilyTheme.textSecondary)
                }
                .frame(minHeight: 34)
                HStack(spacing: FamilyTheme.Space.s) {
                    TextField("Stadt suchen", text: $query).textFieldStyle(.roundedBorder).onSubmit(search)
                    Button(searching ? "Sucht …" : "Suchen", action: search)
                        .buttonStyle(CardButtonStyle()).disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, FamilyTheme.Space.xs)
                ForEach(results) { place in
                    Button {
                        prefs.weatherPlace = place
                        results = []
                        query = ""
                        onChange()
                    } label: {
                        Label { Text(verbatim: place.label) } icon: { Image(systemName: "mappin.and.ellipse") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
                if let message {
                    Label { Text(verbatim: message) } icon: { Image(systemName: "info.circle") }
                        .font(FamilyTheme.font(.callout)).foregroundStyle(FamilyTheme.textSecondary)
                        .padding(.vertical, FamilyTheme.Space.xs)
                }
                HStack(spacing: FamilyTheme.Space.m) {
                    Text("Einheit").foregroundStyle(FamilyTheme.textPrimary)
                    Spacer(minLength: FamilyTheme.Space.m)
                    Picker("Einheit", selection: $prefs.weatherUnit) {
                        Text(verbatim: "°C").tag(Weather.Unit.celsius)
                        Text(verbatim: "°F").tag(Weather.Unit.fahrenheit)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                    .onChange(of: prefs.weatherUnit) { onChange() }
                }
                .frame(minHeight: 34)
            }
            Label { Text(verbatim: "Wetterdaten von Open-Meteo.com. Gesendet wird nur der gewählte Ort, nicht dein Standort.") }
                icon: { Image(systemName: "info.circle") }
                .font(FamilyTheme.font(.callout)).foregroundStyle(FamilyTheme.textSecondary)
                .padding(.vertical, FamilyTheme.Space.xs)
        }
    }

    private func search() {
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty, !searching else { return }
        searching = true
        message = nil
        Task {
            do {
                let found = try await WeatherClient.shared.search(q)
                results = found
                message = found.isEmpty ? "Kein Ort gefunden" : nil
            } catch {
                results = []
                message = "Suche fehlgeschlagen – Internet?"
            }
            searching = false
        }
    }
}
