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
                        // Beschriftung nennt, was der Knopf JETZT tut (VoiceOver).
                        button(info.isPlaying ? "pause.fill" : "play.fill",
                               label: info.isPlaying ? "Pause" : "Wiedergabe") { model.playPause() }
                        button("forward.fill", label: "Weiter") { model.next() }
                    }
                    // Ohne Animation-Transaktion springt das Symbol; `.replace` braucht sie zum Überblenden.
                    .animation(.snappy, value: info.isPlaying)
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
        if let id, let icon = AppIcons.icon(for: id) {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
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
        // 30 Bilder/s reichen für einen Pegel; ungebremst liefe er mit der Bildschirmrate (bis 120 Hz).
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { ctx in
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
    /// Wert während des Ziehens.
    @State private var dragValue: Double?
    /// Nach dem Loslassen: Zielwert halten, bis die nächste Meldung kommt (sonst springt der Regler kurz zurück).
    @State private var pending: PendingSeek?

    /// Anzeige, wenn es keine sinnvolle Zeit gibt (keine Dauer, unbrauchbarer Wert).
    nonisolated static let placeholder = "–:––"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let shown = dragValue ?? pending?.value(for: info, now: ctx.date) ?? info.elapsed(at: ctx.date)
            let d = Self.display(elapsed: shown, duration: info.duration)
            HStack(spacing: 8) {
                Text(verbatim: d.elapsedLabel).monospacedDigit()
                Slider(value: Binding(get: { d.sliderValue }, set: { dragValue = $0 }), in: 0...d.sliderUpper) { editing in
                    guard !editing, let v = dragValue else { return }
                    onSeek(v)
                    pending = PendingSeek(value: v, info: info, released: Date())
                    dragValue = nil
                }
                .controlSize(.mini)
                // Weiß statt Akzentfarbe: wie die Wiedergabe-Steuerung im Kontrollzentrum.
                .tint(.white)
                .disabled(!d.seekable)
                .accessibilityLabel(Text(verbatim: "Position"))
                .accessibilityValue(Text(verbatim: d.accessibilityValue))
                Text(verbatim: d.durationLabel).monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    struct Display: Equatable {
        let elapsedLabel: String
        let durationLabel: String
        let sliderValue: Double
        let sliderUpper: Double
        let seekable: Bool
        let accessibilityValue: String
    }

    /// Begrenzt wird nur der Regler (Slider-Bereich); die Zeit links zeigt die echte Position.
    /// Sonst stünde sie ohne Dauer (Livestream) bei 0:01 still (Review 18.10.).
    nonisolated static func display(elapsed: TimeInterval, duration: TimeInterval?) -> Display {
        let dur = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let upper = dur ?? 1
        let value = elapsed.isFinite ? min(max(elapsed, 0), upper) : 0
        let e = clock(elapsed)
        let d = dur.map(clock) ?? placeholder
        return Display(elapsedLabel: e, durationLabel: d, sliderValue: value, sliderUpper: upper,
                       seekable: dur != nil, accessibilityValue: dur == nil ? e : "\(e) von \(d)")
    }

    /// Gespulter Zielwert, gültig bis zur nächsten Meldung (anderer Zeitstempel), höchstens `maxWait`
    /// (geht der Befehl verloren, darf die Zeit nicht stehen bleiben) und nur für denselben Titel.
    struct PendingSeek: Equatable {
        /// Gemessen 18.10.: Connect folgt nach ~3 s – darunter spränge der Regler kurz zurück.
        nonisolated static let maxWait: TimeInterval = 4
        let value: TimeInterval
        let stamp: Date
        let track: String?
        let released: Date

        init(value: TimeInterval, info: NowPlayingInfo, released: Date) {
            self.value = value
            stamp = info.stamp
            track = NowPlayingModel.artworkKey(for: info)
            self.released = released
        }

        func value(for info: NowPlayingInfo, now: Date) -> TimeInterval? {
            guard info.stamp == stamp, NowPlayingModel.artworkKey(for: info) == track,
                  now.timeIntervalSince(released) <= Self.maxWait else { return nil }
            return value
        }
    }

    /// m:ss bzw. h:mm:ss. NowPlayingInfo liefert nur endliche Werte ≤ 48 h; die Grenze hier
    /// sorgt trotzdem dafür, dass `Int(...)` nie abstürzen kann (NaN, ∞, 1e300).
    nonisolated static func clock(_ s: TimeInterval) -> String {
        guard s.isFinite, s <= NowPlayingInfo.maxDuration else { return placeholder }
        let t = Int(max(0, s).rounded(.down))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }
}
