import SwiftUI

/// Geschwindigkeitstest groß (0.28.0, G51): zwei große Zahlen, darunter Latenz und Antwortfähigkeit. Nur Zahlen aus
/// `networkQuality`, nichts davon von Fremden → trotzdem `Text(verbatim:)` wie überall in der Insel.
struct SpeedTestCard: View {
    let speed: SpeedTest
    let onAgain: () -> Void

    var body: some View {
        Group {
            switch speed.state {
            case .idle, .running:
                HStack(spacing: 12) {
                    Image(systemName: "speedometer").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Misst …").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        Text(verbatim: "Apples Testserver, höchstens 20 Sekunden").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    WorkingDots()
                }
            case .done(let r):
                HStack(alignment: .center, spacing: 24) {
                    value("arrow.down", SpeedTest.mbpsText(r.downMbps), "Download")
                    value("arrow.up", SpeedTest.mbpsText(r.upMbps), "Upload")
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        if let l = r.latencyMs { detail("Latenz", "\(Int(l.rounded())) ms") }
                        if let q = r.responsiveness { detail("Antwortfähigkeit", "\(q) RPM") }
                        again
                    }
                }
            case .failed(let why):
                HStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    Text(verbatim: why).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    again
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: IslandGeometry.expandedSize.height - 30)
        .accessibilityElement(children: .combine)
    }

    private func value(_ symbol: String, _ number: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                Text(verbatim: number).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
                Text(verbatim: "Mbit/s").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(verbatim: label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(verbatim: value).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
        }
    }

    private var again: some View {
        Button(action: onAgain) {
            Text(verbatim: "Nochmal").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
