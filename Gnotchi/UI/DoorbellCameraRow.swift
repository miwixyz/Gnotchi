import SwiftUI

/// Einstellungen → Mitteilungen → Türklingel-Kamera (27.11.): Bildadresse eintragen und einmal testen.
struct DoorbellCameraRow: View {
    @Binding var address: String
    /// „Insel testen“: zeigt einen erfundenen Klingel-Hinweis mit Bild in der Insel.
    let showTest: (URL) -> Void
    @State private var result: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Kamera-Bildadresse, z. B. http://192.168.1.10:8080/bild.jpg", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: address) { result = nil }
                Button(testing ? "Teste …" : "Testen") { Task { await test() } }
                    .disabled(testing || DoorbellCamera.validURL(address) == nil)
                Button("Insel testen") { if let url = DoorbellCamera.validURL(address) { showTest(url) } }
                    .disabled(DoorbellCamera.validURL(address) == nil)
                    .help("Zeigt einen erfundenen Klingel-Hinweis mit dem Kamerabild, ohne dass jemand klingelt.")
            }
            Text(verbatim: DoorbellCamera.problem(address) ?? result
                 ?? "Beim Klingeln zeigt die Insel das Bild dieser Adresse (JPEG oder PNG, z. B. von einem Dienst im Heimnetz). Leer = aus. Nichts wird gespeichert.")
                .font(.caption)
                .foregroundStyle(DoorbellCamera.problem(address) == nil ? Color.secondary : Color.orange)
        }
    }

    private func test() async {
        guard let url = DoorbellCamera.validURL(address) else { return }
        testing = true
        defer { testing = false }
        let outcome: Result<NSImage, DoorbellCamera.FetchError>
        do {
            let (data, status) = try await DoorbellFeed.liveLoad(url)
            outcome = DoorbellCamera.image(data: data, status: status)
        } catch let e as DoorbellCamera.FetchError {
            outcome = .failure(e)
        } catch {
            outcome = .failure(.unreachable)
        }
        result = switch outcome {
        case .success(let image): "Bild empfangen (\(Int(image.size.width)) × \(Int(image.size.height)))."
        case .failure(let e): e.text
        }
    }
}
