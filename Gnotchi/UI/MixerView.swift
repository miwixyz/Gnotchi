import CoreAudio
import SwiftUI

/// Mixer (0.30.0, G54): Ausgabe, Systemtöne, Mikrofon und eine Zeile je App mit Ton, samt Gerät und Übertragungsart
/// (AirPlay, Bluetooth, USB, eingebaut). Dieselbe Ansicht im Menüleisten-Popover. Nur Standard-Core-Audio ohne Freigabe;
/// Regler je App nur für Spotify und Musik (AppleScript, wenn erlaubt). Gerätenamen vergibt der Nutzer frei → `verbatim`.
struct MixerView: View {
    let model: MixerModel
    /// In der Insel (600 pt breit): zwei Spalten, links Ausgabe und Mikrofon, rechts die Apps; im Popover untereinander.
    var wide = false

    var body: some View {
        if wide {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) { outputCard; micCard }.frame(width: 270)
                ScrollView { appsCard }.scrollIndicators(.hidden)
            }
            .frame(maxHeight: IslandGeometry.mixerHeight - 24)
        } else {
            VStack(spacing: 10) { outputCard; micCard; appsCard }
        }
    }

    private var outputCard: some View {
        card("Ausgabe") {
            deviceMenu(model.outputs, current: model.output.device) { model.selectOutput($0) }
            volumeRow(model.output, mutedSymbol: "speaker.slash.fill", symbol: "speaker.wave.2.fill",
                      onVolume: { model.setOutputVolume($0) }, onMute: { model.toggleOutputMute() })
            if let sys = model.systemOutput, sys.id != model.output.device?.id || model.outputs.count > 1 {
                Divider().opacity(0.4)
                HStack {
                    Label { Text(verbatim: "Systemtöne").lineLimit(1) } icon: { Image(systemName: "bell.fill") }
                        .font(.system(size: 12)).foregroundStyle(FamilyTheme.textSecondary)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    deviceMenu(model.outputs, current: sys, compact: true) { model.selectSystemOutput($0) }
                }
            }
        }
    }

    private var micCard: some View {
        card("Mikrofon") {
            deviceMenu(model.inputs, current: model.input.device, mic: true) { model.selectInput($0) }
            volumeRow(model.input, mutedSymbol: "mic.slash.fill", symbol: "mic.fill",
                      onVolume: { model.setInputVolume($0) }, onMute: { model.toggleInputMute() })
        }
    }

    private var appsCard: some View {
        card("Apps mit Ton") {
            if model.apps.isEmpty {
                Text(verbatim: "Gerade gibt keine App Ton aus.").font(.system(size: 12)).foregroundStyle(FamilyTheme.textSecondary)
            } else {
                ForEach(Array(model.apps.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Divider().opacity(0.4) }
                    appRow(row)
                }
                if !model.appVolumeEnabled, model.apps.contains(where: { $0.volume == nil }) {
                    // swiftlint:disable:next line_length
                    Text(verbatim: "Regler gibt es für Spotify und Musik. Für andere Apps: Einstellungen → Aktivitäten → „Lautstärke je App“ (braucht die Freigabe „Audio-Aufnahme“).")
                        .font(.system(size: 11)).foregroundStyle(FamilyTheme.textSecondary)
                }
            }
        }
    }

    // MARK: Bausteine

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(FamilyTheme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FamilyTheme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FamilyTheme.cardStroke.opacity(0.6), lineWidth: 0.5))
    }

    /// Symbol eines Geräts; Eingabegeräte zeigen ein Mikrofon (Bluetooth: Kopfhörer), nicht den Lautsprecher.
    private func symbol(_ d: OutputDevices.Device?, mic: Bool) -> String {
        guard let d else { return mic ? "mic.slash" : "speaker.slash" }
        return mic && d.kind != .bluetooth ? "mic" : d.kind.symbol
    }

    private func deviceMenu(_ devices: [OutputDevices.Device], current: OutputDevices.Device?, compact: Bool = false,
                            mic: Bool = false, pick: @escaping (AudioObjectID) -> Void) -> some View {
        Menu {
            ForEach(devices) { d in
                Button { pick(d.id) } label: {
                    Label { Text(verbatim: d.name) } icon: { Image(systemName: d.id == current?.id ? "checkmark" : symbol(d, mic: mic)) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol(current, mic: mic)).foregroundStyle(kindTint(current?.kind))
                Text(verbatim: current?.name ?? "Kein Gerät").lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(devices.count < 2 ? 0.25 : 0.55)))
            .frame(maxWidth: compact ? 140 : .infinity, alignment: compact ? .trailing : .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: compact, vertical: false)
        .disabled(devices.count < 2)
    }

    private func volumeRow(_ e: MixerModel.Endpoint, mutedSymbol: String, symbol: String,
                           onVolume: @escaping (Float) -> Void, onMute: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: onMute) {
                Image(systemName: e.muted == true ? mutedSymbol : symbol).font(.system(size: 13))
                    .foregroundStyle(e.muted == true ? Color.red : FamilyTheme.textSecondary).frame(width: 20)
            }
            .buttonStyle(.plain)
            .disabled(!e.canMute)
            .accessibilityLabel(Text(verbatim: e.muted == true ? "Stumm aufheben" : "Stumm"))
            Slider(value: Binding(get: { Double(e.volume ?? 0) }, set: { onVolume(Float($0)) }), in: 0...1)
                .disabled(!e.canSetVolume)
            Text(verbatim: MixerRows.percent(e.volume).map { "\($0) %" } ?? "–").font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(FamilyTheme.textSecondary).frame(width: 40, alignment: .trailing)
        }
    }

    private func appRow(_ row: MixerAppRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let id = row.bundleID, let icon = AppIcons.icon(for: id) {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
                } else {
                    Image(systemName: "app.dashed").frame(width: 22, height: 22).foregroundStyle(FamilyTheme.textSecondary)
                }
                Text(verbatim: row.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                ForEach(row.devices) { d in
                    HStack(spacing: 4) {
                        Image(systemName: d.kind.symbol).foregroundStyle(kindTint(d.kind))
                        Text(verbatim: d.name).lineLimit(1).truncationMode(.tail)
                    }
                    .font(.system(size: 11)).foregroundStyle(FamilyTheme.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary.opacity(0.5)))
                    .frame(maxWidth: 150)
                }
            }
            if let id = row.bundleID, let v = row.volume {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(FamilyTheme.textSecondary).frame(width: 20)
                    Slider(value: Binding(get: { Double(v) }, set: { model.setPlayerVolume(bundleID: id, percent: Int($0.rounded())) }),
                           in: 0...100)
                    Text(verbatim: "\(v) %").font(.system(size: 12)).monospacedDigit().foregroundStyle(FamilyTheme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            } else if model.appVolumeEnabled, row.canTap {
                // Stufe 2 (G55): Regler je App über einen Tap, 0…200 %, nahe 100 % rastet er ein (dann kein Tap).
                let percent = Int((row.gain * 100).rounded())
                HStack(spacing: 10) {
                    Image(systemName: percent > 100 ? "speaker.wave.3.fill" : "speaker.fill").font(.system(size: 11))
                        .foregroundStyle(percent == 100 ? FamilyTheme.textSecondary : FamilyTheme.iris).frame(width: 20)
                    Slider(value: Binding(get: { Double(percent) }, set: { model.setAppGain(row, percent: Int($0.rounded())) }), in: 0...200)
                    Text(verbatim: "\(percent) %").font(.system(size: 12)).monospacedDigit().foregroundStyle(FamilyTheme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            if let f = model.tapFailures[row.id] {
                Text(verbatim: tapHint(f)).font(.system(size: 11)).foregroundStyle(FamilyTheme.warning)
            }
        }
    }

    private func tapHint(_ f: AppTapEngine.Failure) -> String {
        switch f {
        // swiftlint:disable:next line_length
        case .noSignal: "Kein Ton angekommen: Prüfe die Freigabe „Audio-Aufnahme“ (Systemeinstellungen → Datenschutz & Sicherheit). Die App spielt unverändert."
        case .setup: "Regler nicht verfügbar. Die App spielt unverändert."
        case .tooMany: "Zu viele Regler gleichzeitig (höchstens \(AppTapEngine.maxTaps)). Die App spielt unverändert."
        case .noTarget: "Diese App gibt gerade keinen Ton aus. Die App spielt unverändert."
        case .reset: "Gerät gewechselt: Der Regler wurde auf 100 % zurückgesetzt, die App spielt wieder direkt."
        }
    }

    /// AirPlay und Bluetooth fallen auf: dort läuft der Ton nicht über die Lautsprecher des Macs.
    private func kindTint(_ kind: OutputDevices.Kind?) -> Color {
        switch kind {
        case .airPlay, .bluetooth: FamilyTheme.iris
        default: FamilyTheme.textSecondary
        }
    }
}
