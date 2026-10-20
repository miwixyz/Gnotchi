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
    /// Klick auf das Ausgabe-Symbol oben rechts (groß): IslandController zeigt die Geräteliste.
    var onOutputMenu: () -> Void = {}

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
                // Kleines App-Abzeichen unten rechts am Cover (wie iOS); außerhalb des Cover-Zuschnitts.
                .overlay(alignment: .bottomTrailing) { appIcon(info.appBundleID, size: 10).offset(x: 3, y: 3) }
            Spacer()
            // Pegel heißt „Ton kommt hier raus“ – bei anderem Gerät oder AirPlay dasselbe Symbol wie groß.
            if model.route.replacesLevelBars {
                Image(systemName: model.route.symbol ?? "hifispeaker.fill").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: 14)
                    .accessibilityHidden(true)
            } else {
                LevelBars(playing: info.isPlaying)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: state.layout.compact.height)
        .transition(.opacity)
    }

    /// Aufbau wie die Wiedergabe im Kontrollzentrum: Cover · App/Titel/Interpret · Tasten rechts, darunter
    /// der Fortschritt. Die Kopfzeile (Symbol + Name der Quell-App) ersetzt das frühere Symbol oben rechts. So passt alles in 110 pt (Cover-, Tasten- und Fortschrittszeile übereinander
    /// bräuchten ~130 pt). Mit Notch beginnt der Inhalt erst unter ihr (IslandGeometry.expandedSize).
    private func expanded(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                cover(56, radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    appHeader(info.appBundleID)
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
            // Als Überlagerung: ein Gerätename über der Tastenspalte soll den Titel nicht schmaler machen.
            .overlay(alignment: .topTrailing) { outputButton }
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

    @ViewBuilder private func appIcon(_ id: String?, size: CGFloat) -> some View {
        if let id, let icon = AppIcons.icon(for: id) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    /// Ausgabe-Knopf oben rechts auf Höhe der App-Kopfzeile (0.2.0): immer das Ausgabe-Symbol, bei
    /// AirPlay/Bluetooth/anderem Gerät dazu wie bisher der Name. Klick → Liste der Ausgabegeräte.
    /// Gerätenamen vergibt der Nutzer frei → `Text(verbatim:)`.
    private var outputButton: some View {
        Button(action: onOutputMenu) {
            HStack(spacing: 4) {
                Image(systemName: model.route.symbol ?? "airplayaudio").font(.system(size: 10, weight: .semibold))
                if let text = model.route.label {
                    Text(verbatim: text).font(.system(size: 11, weight: .medium))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(height: 16)
            // Klickfläche nur über Symbol und Name, nicht über die volle Breite.
            .contentShape(Rectangle())
            .frame(maxWidth: Self.routeMaxWidth, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        // Gleiche Höhe wie die App-Kopfzeile (Textspalte ist 52 pt hoch, mittig in 56 pt).
        .padding(.top, 2)
        .accessibilityLabel(Text(verbatim: "Ausgabe wählen"))
        .accessibilityValue(Text(verbatim: model.route.label ?? ""))
    }

    /// Welche App spielt: Symbol 16 pt + lokalisierter Name aus dem lokalen Bundle (AppIcons.name), Grau.
    /// Unbekannte App: weder Symbol noch Name, die Zeile entfällt (außer als Platzhalter neben dem Wiedergabeweg).
    private static let routeMaxWidth: CGFloat = 130
    /// So weit ragt der Wiedergabeweg höchstens über die Tastenspalte (3 × 22 + 2 × 16 pt) nach links.
    private static let routeOverhang: CGFloat = routeMaxWidth - 98 + 6

    @ViewBuilder private func appHeader(_ id: String?) -> some View {
        let name = id.flatMap(AppIcons.name(for:))
        if let id, AppIcons.icon(for: id) != nil || name != nil {
            HStack(spacing: 5) {
                appIcon(id, size: 16)
                if let name {
                    Text(verbatim: name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(height: 16)
            // Langer App-Name kürzt sich, statt unter den Wiedergabeweg oben rechts zu laufen.
            .padding(.trailing, model.route == .local ? 0 : Self.routeOverhang)
        } else if model.route != .local {
            // Leere Kopfzeile: Sonst rutschte der Titel nach oben unter den Wiedergabeweg.
            Color.clear.frame(height: 16)
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
/// Dünner Balken wie im Kontrollzentrum statt Regler mit festem Knopf (Michael, 18.10.).
struct ProgressRow: View {
    let info: NowPlayingInfo
    let onSeek: (TimeInterval) -> Void
    /// Wert während des Ziehens.
    @State private var dragValue: Double?
    /// Nach dem Loslassen: Zielwert halten, bis die nächste Meldung kommt (sonst springt der Balken kurz zurück).
    @State private var pending: PendingSeek?

    /// Anzeige, wenn es keine sinnvolle Zeit gibt (keine Dauer, unbrauchbarer Wert).
    nonisolated static let placeholder = "–:––"
    /// Schritt für VoiceOver (Erhöhen/Verringern).
    nonisolated static let accessibilityStep: TimeInterval = 10

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let shown = dragValue ?? pending?.value(for: info, now: ctx.date) ?? info.elapsed(at: ctx.date)
            let d = Self.display(elapsed: shown, duration: info.duration)
            HStack(spacing: 8) {
                Text(verbatim: d.elapsedLabel).monospacedDigit()
                ScrubBar(fraction: d.fraction, enabled: d.seekable,
                         onDrag: { x, width in dragValue = Self.seconds(atX: x, width: width, upper: d.sliderUpper) },
                         onRelease: { x, width in seek(Self.seconds(atX: x, width: width, upper: d.sliderUpper)) },
                         // Ziehen ohne Ende abgebrochen (Insel zu, Panel weg): Balken nicht eingefroren lassen.
                         onDragStateReset: { dragValue = nil })
                    .accessibilityRepresentation {
                        // Für VoiceOver ein echter Regler: Wert, Erhöhen/Verringern wie zuvor beim Slider.
                        Slider(value: Binding(get: { d.sliderValue }, set: { seek($0) }), in: 0...d.sliderUpper,
                               step: Self.accessibilityStep)
                            .disabled(!d.seekable)
                    }
                    .accessibilityLabel(Text(verbatim: "Position"))
                    .accessibilityValue(Text(verbatim: d.accessibilityValue))
                Text(verbatim: d.durationLabel).monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    private func seek(_ v: TimeInterval) {
        onSeek(v)
        pending = PendingSeek(value: v, info: info, released: Date())
        dragValue = nil
    }

    /// Mausposition im Balken → Sekunden, festgehalten auf [0, upper]. Unbrauchbare Werte (Breite 0,
    /// NaN, ∞) ergeben 0 – der Balken hat beim ersten Layout-Durchlauf noch keine Breite.
    nonisolated static func seconds(atX x: CGFloat, width: CGFloat, upper: TimeInterval) -> TimeInterval {
        guard x.isFinite, width.isFinite, width > 0, upper.isFinite, upper > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * upper
    }

    struct Display: Equatable {
        let elapsedLabel: String
        let durationLabel: String
        let sliderValue: Double
        let sliderUpper: Double
        let seekable: Bool
        let accessibilityValue: String

        /// Füllstand des Balkens 0…1; ohne Dauer leer (nicht voll wie der gesperrte Regler vorher).
        var fraction: Double {
            guard seekable, sliderUpper > 0 else { return 0 }
            return min(max(sliderValue / sliderUpper, 0), 1)
        }
    }

    /// Begrenzt wird nur der Balken (Wertebereich); die Zeit links zeigt die echte Position.
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

/// Dünner Balken (Kapsel, Weiß 20 % / Weiß gefüllt). Den Knopf gibt es nur beim Überfahren oder Ziehen.
/// Klick oder Ziehen meldet die Position laufend (`onDrag`), gespult wird erst bei `onRelease` – mit der
/// Endposition, unabhängig davon, ob `onDragStateReset` vorher oder nachher kommt. `@GestureState` setzt
/// sich auch zurück, wenn SwiftUI das Ziehen ohne `onEnded` abbricht; dann meldet `onDragStateReset`.
/// Funktioniert mit dem ersten Klick im nie aktiven Panel (ClickableHostingView.acceptsFirstMouse).
private struct ScrubBar: View {
    let fraction: Double
    let enabled: Bool
    let onDrag: (CGFloat, CGFloat) -> Void
    let onRelease: (CGFloat, CGFloat) -> Void
    let onDragStateReset: () -> Void
    @State private var hovering = false
    @GestureState private var dragging = false

    private var active: Bool { enabled && (hovering || dragging) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = width * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Rectangle().fill(.white).frame(width: max(0, x))
            }
            .frame(height: active ? 4 : 3)
            .clipShape(Capsule())
            .overlay(alignment: .leading) {
                Circle().fill(.white)
                    .frame(width: 9, height: 9)
                    .offset(x: x - 4.5)
                    .opacity(active ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            // Greifbar über die ganze Höhe, nicht nur über die 3 pt der Linie.
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { g in onDrag(g.location.x, width) }
                .onEnded { g in onRelease(g.location.x, width) })
        }
        .onChange(of: dragging) { _, now in if !now { onDragStateReset() } }
        .frame(height: 12)
        .opacity(enabled ? 1 : 0.4)
        .allowsHitTesting(enabled)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: active)
    }
}
