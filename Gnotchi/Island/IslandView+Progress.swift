import SwiftUI

// Fortschrittsbalken der großen Insel (0.5.0 aus IslandView.swift ausgelagert: Datei ≤ 650 Zeilen).

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
