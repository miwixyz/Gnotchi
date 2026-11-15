import SwiftUI

/// Tasten-Ring (0.28.0): runde Glas-Tasten links, rechts und unten um die schwebende große Insel. Plätze und Randzugabe
/// rechnet `Ring` (getestet); hier nur das Zeichnen. Die Tasten sind Glas wie die Insel (Systemstil), keine
/// Nachbildung fremder Gestaltung.
extension IslandView {

    @ViewBuilder func ringLayer(_ ring: RingLayout) -> some View {
        let rects = Ring.rects(buttons: ring.buttons, island: ring.island)
        ForEach(ring.buttons, id: \.self) { b in
            if let r = rects[b] {
                RingButtonView(button: b, symbol: ringSymbol(b), selected: activity.ringSelected(b),
                               running: activity.ringRunning(b), count: b == .shelf ? activity.shelfItems.count : nil,
                               multicolor: b == .weather, dot: b == .mic ? .red : .orange, onHover: onHover) {
                    activity.ringTap(b)
                    if b == .settings || b == .screenshot { onRingAction(b) }
                }
                .offset(x: ring.margins.side + r.minX, y: r.minY)
            }
        }
    }

    private func ringSymbol(_ b: RingButton) -> String {
        switch b {
        case .timer: "timer"
        case .awake: activity.awake?.isActive == true ? "cup.and.saucer.fill" : "cup.and.saucer"
        case .mirror: "web.camera.fill"
        case .weather: activity.weather.map { Weather.symbol($0.code, day: $0.isDay) } ?? "cloud.sun"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard"
        case .pin: activity.pinned ? "pin.fill" : "pin"
        case .mic: activity.mic.isMuted ? "mic.slash.fill" : "mic.fill"
        case .screenshot: "camera.viewfinder"
        case .speedtest: "speedometer"
        case .settings: "gearshape"
        }
    }
}

/// Eine Taste: Glas-Kreis 40 pt. Gewählt = hellere Füllung, läuft = Punkt oben rechts, Ablage mit Zahl.
struct RingButtonView: View {
    let button: RingButton
    let symbol: String
    let selected: Bool
    let running: Bool
    var count: Int?
    var multicolor = false
    /// Farbe des Punkts „läuft“: orange, beim stummen Mikrofon rot.
    var dot: Color = .orange
    /// Mauslage an die Insel melden, damit der Weg Insel → Taste sie nicht zuklappt.
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(multicolor ? .multicolor : .monochrome)
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.88))
                .frame(width: Ring.button, height: Ring.button)
                .background(Circle().fill(.white.opacity(selected ? 0.24 : 0)))
                .glassEffect(.regular.tint(.black.opacity(DetachedIsland.glassTint)), in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                .overlay(alignment: .topTrailing) {
                    if running {
                        Circle().fill(dot).frame(width: 8, height: 8).offset(x: -4, y: 4)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let count, count > 0 {
                        Text(verbatim: "\(min(count, 99))")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .offset(x: 2, y: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .help(button.label)
        .accessibilityLabel(Text(verbatim: button.label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
