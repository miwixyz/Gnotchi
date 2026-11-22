import SwiftUI

/// Einstellungen → Aktivitäten → Tippi-Gerät (G62): Schlüssel eintragen, Ergebnis des letzten Sendens.
struct TippiDeviceKeyRow: View {
    let saved: () -> Void
    @State private var key = ""
    @State private var feedback: String?
    @State private var status = TippiDeviceLink.status
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SecureField(TippiDeviceKeychain.read() == nil ? "Schlüssel" : "Schlüssel (gespeichert, leer = behalten)",
                            text: $key)
                    .textFieldStyle(.roundedBorder)
                Button("Speichern") { save() }
            }
            Text(feedback ?? status ?? "Sendet Titel, Interpret und App an tippi.local, jede Sekunde. Tasten am Gerät steuern die Wiedergabe.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onReceive(tick) { _ in status = TippiDeviceLink.status }
    }

    private func save() {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TippiDevice.validKey(k), TippiDeviceKeychain.save(k) else {
            feedback = "Schlüssel ungültig (20–128 Zeichen, keine Leerzeichen)"
            return
        }
        key = ""
        feedback = nil
        saved()
    }
}
