import AppKit
import SwiftUI

/// Zustand einer Insel, geteilt zwischen Panel (Größe, Mausdurchlass) und Ansicht.
@MainActor
@Observable
final class IslandState {
    enum Mode { case hidden, compact, expanded }
    var mode: Mode = .hidden
    var layout: IslandGeometry.Layout
    init(layout: IslandGeometry.Layout) { self.layout = layout }
}

/// Die Insel. Tiefschwarz, oben bündig, unten weich gerundet – soll aussehen wie ein Teil
/// von macOS (Michael, 18.10.: „seamless wie macOS“). Bewusst Systemschrift (SF Pro) statt
/// Familien-Design; kein Rand, kein Schatten, kein Glas.
/// Titel/Interpret kommen von beliebigen Websites → nur `Text(verbatim:)` (SECURE-DESIGN G5).
struct IslandView: View {
    @Environment(NowPlayingModel.self) private var model
    let state: IslandState
    let onHover: (Bool) -> Void

    private var size: CGSize {
        switch state.mode {
        case .hidden: state.layout.notch?.size ?? CGSize(width: IslandGeometry.pillSize.width, height: 0)
        case .compact: state.layout.compact.size
        case .expanded: state.layout.expanded.size
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: corner, bottomTrailingRadius: corner, style: .continuous)
                    .fill(.black)
                content
            }
            .frame(width: size.width, height: size.height)
            .onHover(perform: onHover)
            Spacer(minLength: 0)
        }
        // Füllt das Panel (klein ODER groß); die Insel hängt oben mittig – beide Rechtecke teilen midX und Oberkante.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.32), value: state.mode)
        // Titelwechsel weich überblenden (Spezifikation „Bewegung“).
        .animation(.smooth, value: model.info?.title)
        .environment(\.colorScheme, .dark)
    }

    private var corner: CGFloat { state.mode == .expanded ? 22 : 10 }

    @ViewBuilder private var content: some View {
        if let info = model.info, state.mode != .hidden {
            if state.mode == .compact { compact(info) } else { expanded(info) }
        }
    }

    private func compact(_ info: NowPlayingInfo) -> some View {
        HStack {
            cover(18, radius: 4)
            Spacer()
            LevelBars(playing: info.isPlaying)
        }
        .padding(.horizontal, 10)
        .frame(height: state.layout.compact.height)
        .transition(.opacity)
    }

    /// Aufbau wie die Wiedergabe im Kontrollzentrum: Cover · Titel/Interpret · Tasten rechts, darunter
    /// der Fortschritt. So passt alles in 110 pt (Cover-, Tasten- und Fortschrittszeile übereinander
    /// bräuchten ~130 pt). Mit Notch beginnt der Inhalt erst unter ihr (IslandGeometry.expandedSize).
    private func expanded(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                cover(56, radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: info.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .contentTransition(.opacity)
                    if let a = info.artist {
                        Text(verbatim: a).font(.system(size: 12)).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                // Text nimmt allen freien Platz (ein Spacer teilte ihn sonst hälftig, Titel früh gekürzt).
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    appIcon(info.appBundleID)
                    Spacer(minLength: 0)
                    HStack(spacing: 16) {
                        button("backward.fill", label: "Zurück") { model.previous() }
                        button(info.isPlaying ? "pause.fill" : "play.fill", label: "Wiedergabe/Pause") { model.playPause() }
                        button("forward.fill", label: "Weiter") { model.next() }
                    }
                }
                .frame(height: 56)
            }
            ProgressRow(info: info) { model.seek(to: $0) }
        }
        .padding(EdgeInsets(top: (state.layout.notch?.height ?? 0) + 12, leading: 16, bottom: 12, trailing: 16))
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    @ViewBuilder private func cover(_ side: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let img = model.artwork {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: side * 0.5)).foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder private func appIcon(_ id: String?) -> some View {
        if let id, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                .accessibilityHidden(true)
        }
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Animierter Pegel – reine Animation, kein Audiosignal (Spezifikation „Nicht in diesem Schritt“).
private struct LevelBars: View {
    let playing: Bool
    var body: some View {
        TimelineView(.animation(paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(.white)
                        .frame(width: 2.5, height: playing ? 5 + 7 * abs(sin(t * (3 + Double(i)) + Double(i))) : 4)
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

/// Fortschritt mit Zeiten, spulbar. Gespult wird erst beim Loslassen (sonst ein Befehl je Mausbewegung).
struct ProgressRow: View {
    let info: NowPlayingInfo
    let onSeek: (TimeInterval) -> Void
    @State private var dragValue: Double?

    /// Anzeige, wenn es keine sinnvolle Zeit gibt (keine Dauer, unbrauchbarer Wert).
    static let placeholder = "–:––"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let dur = info.duration ?? 0
            let upper = max(dur, 1)
            let now = min(dragValue ?? info.elapsed(at: ctx.date), upper)
            HStack(spacing: 8) {
                Text(verbatim: Self.clock(now)).monospacedDigit()
                Slider(value: Binding(get: { now }, set: { dragValue = $0 }), in: 0...upper) { editing in
                    if !editing, let v = dragValue { onSeek(v); dragValue = nil }
                }
                .controlSize(.mini)
                // Weiß statt Akzentfarbe: wie die Wiedergabe-Steuerung im Kontrollzentrum.
                .tint(.white)
                .disabled(dur == 0)
                .accessibilityLabel(Text(verbatim: "Position"))
                Text(verbatim: dur > 0 ? Self.clock(dur) : Self.placeholder).monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    /// m:ss bzw. h:mm:ss. NowPlayingInfo liefert nur endliche Werte ≤ 48 h; die Grenze hier
    /// sorgt trotzdem dafür, dass `Int(...)` nie abstürzen kann (NaN, ∞, 1e300).
    static func clock(_ s: TimeInterval) -> String {
        guard s.isFinite, s <= NowPlayingInfo.maxDuration else { return placeholder }
        let t = Int(max(0, s).rounded(.down))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }
}
