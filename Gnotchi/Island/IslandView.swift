import AppKit
import SwiftUI

/// Zustand einer Insel, geteilt zwischen Panel (Größe, Mausdurchlass) und Ansicht.
@MainActor
@Observable
final class IslandState {
    /// `notice`: kurzer Hinweis (Kopfhörer), eigene Form unter der Notch (0.2.0).
    /// `live`: Tippis Live-Text, zwei Zeilen unter der Aufnahme-Zeile (0.3.0).
    /// `wide`: Trackwechsel, 3 s breiter mit Titel · Interpret (0.4.0).
    enum Mode { case hidden, compact, expanded, notice, live, wide }
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
    @Environment(ActivityModel.self) private var activity
    let state: IslandState
    let onHover: (Bool) -> Void
    /// Klick auf das Ausgabe-Symbol oben rechts (groß): IslandController zeigt die Geräteliste.
    var onOutputMenu: () -> Void = {}
    /// Klick auf ein Update (0.4.0): IslandController → AppModel.openUpdate (G24).
    var onOpenUpdate: (FamilyApp) -> Void = { _ in }

    private var size: CGSize {
        switch state.mode {
        case .hidden: state.layout.notch?.size ?? CGSize(width: IslandGeometry.pillSize.width, height: 0)
        case .compact: state.layout.compact.size
        case .wide: state.layout.wide.size
        case .expanded:
            IslandController.panelFrame(mode: .expanded, layout: state.layout, hasMedia: model.info != nil,
                                        privacy: activity.privacy.isActive,
                                        quota: activity.quotaLine != nil, updates: activity.allUpdates.count,
                                        rows: detailRows)?.size ?? state.layout.expanded.size
        case .notice: state.layout.notice.size
        case .live: state.layout.live.size
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

    private var corner: CGFloat {
        switch state.mode {
        case .expanded: 22
        case .notice, .live: 16
        case .hidden, .compact, .wide: 10
        }
    }

    private var detailRows: Int {
        IslandController.detailRows(headphones: activity.headphones != nil, updates: activity.allUpdates.count,
                                    mic: activity.privacy.mic, camera: activity.privacy.camera)
    }

    private var pill: Bool { state.layout.notch == nil }

    @ViewBuilder private var content: some View {
        switch state.mode {
        case .hidden: EmptyView()
        case .notice: if let n = activity.notice { notice(n) }
        case .live: if let rec = activity.recording { liveText(rec) }
        case .compact:
            if let rec = activity.recording {
                recordingCompact(rec)
            } else {
                rotationCompact
            }
        case .wide:
            if let info = model.info {
                TrackFlash(info: info, notchWidth: state.layout.notch?.width, height: state.layout.wide.height) {
                    cover(18, radius: 4)
                } bars: {
                    LevelBars(playing: info.isPlaying)
                }
            }
        case .expanded:
            if let info = model.info {
                let hasLines = activity.privacy.isActive || activity.quotaLine != nil || !activity.allUpdates.isEmpty
                VStack(spacing: 0) {
                    if hasLines {
                        // Zeilen über der Musik: Mikrofon/Kamera, Qotti, je Update eine (klickbar).
                        VStack(spacing: 4) {
                            if activity.privacy.isActive { privacyLine }
                            if let q = activity.quotaLine { QuotaLine(text: q) }
                            ForEach(activity.allUpdates, id: \.app) { e in
                                UpdateLine(entry: e) { onOpenUpdate(e.app) }
                            }
                        }
                        .padding(EdgeInsets(top: (state.layout.notch?.height ?? 0) + 8, leading: 16, bottom: 0, trailing: 16))
                    }
                    expanded(info, topInset: hasLines ? 4 : nil)
                }
            } else if activity.headphones != nil || !activity.allUpdates.isEmpty {
                ActivityDetails(headphones: activity.headphones, updates: activity.allUpdates, privacy: activity.privacy,
                                topInset: state.layout.notch?.height ?? 0,
                                height: IslandGeometry.noticeSize.height
                                    + CGFloat(max(0, detailRows - 2)) * IslandGeometry.privacyLineHeight,
                                onOpen: onOpenUpdate)
            } else if activity.privacy.isActive {
                privacyDetails
            }
        }
    }

    /// Kleine Insel ohne Aufnahme (0.4.0): die Aktivität, die die Rotation gerade zeigt. Ohne Aktivität wie bisher
    /// der letzte Titel (pausiert, Insel offen wegen Mikrofon/Kamera) bzw. nur die Punkte.
    @ViewBuilder private var rotationCompact: some View {
        let height = state.layout.compact.height
        switch activity.currentActivity {
        case .media?:
            if let info = model.info { compact(info) }
        case .headphones?:
            if let h = activity.headphones {
                HeadphonesCompact(headphones: h, privacy: activity.privacy, pill: pill, height: height)
            }
        case .update(let app)?:
            if let e = activity.update(for: app) {
                UpdateCompact(entry: e, privacy: activity.privacy, pill: pill, height: height) { onOpenUpdate(app) }
            }
        case nil:
            if let info = model.info {
                compact(info)
            } else if activity.privacy.isActive {
                privacyCompact
            }
        }
    }

    // MARK: Tippi-Aufnahme (0.2.0)

    /// Mit Notch: links Mikrofon (rot) bzw. Wellenform, rechts Pegel bzw. Ladekreisel. Ohne Notch dazu
    /// „nimmt auf“ mit Laufzeit bzw. „wandelt um“ – feste Texte, nichts aus Tippis Nachricht.
    private func recordingCompact(_ rec: ActivityModel.Recording) -> some View {
        let pill = state.layout.notch == nil
        return HStack(spacing: 6) {
            switch rec {
            case .recording(let since):
                Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.red)
                if pill {
                    Text(verbatim: "nimmt auf").font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    TimelineView(.periodic(from: since, by: 1)) { ctx in
                        Text(verbatim: TippiLink.elapsedLabel(ctx.date.timeIntervalSince(since)))
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                LiveLevelBars(level: activity.recordingLevel)
            case .transcribing:
                Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                if pill {
                    Text(verbatim: "wandelt um").font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                WorkingDots()
            }
        }
        .padding(.horizontal, pill ? 12 : 10)
        .frame(height: state.layout.compact.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: rec == .transcribing ? "Tippi wandelt um" : "Tippi nimmt auf"))
        .transition(.opacity)
    }

    /// Live-Text (0.3.0): eigene Ansicht in IslandView+LiveText.swift.
    private func liveText(_ rec: ActivityModel.Recording) -> some View {
        LiveTextIsland(recording: rec, text: activity.liveText ?? "", level: activity.recordingLevel,
                       topInset: state.layout.notch?.height ?? 0)
    }

    // MARK: Mikrofon/Kamera (0.2.0)

    /// Orange = Mikrofon, Grün = Kamera – dieselben Farben wie macOS in der Menüleiste.
    private var privacyDots: some View {
        PrivacyDots(privacy: activity.privacy)
    }

    /// Klein ohne Musik: mit Notch nur die Punkte im linken Flügel, ohne Notch Punkte + „Mikrofon“/„Kamera“.
    private var privacyCompact: some View {
        HStack(spacing: 6) {
            privacyDots
            if state.layout.notch == nil, let label = activity.privacy.compactLabel {
                Text(verbatim: label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, state.layout.notch == nil ? 12 : 14)
        .frame(height: state.layout.compact.height)
        .transition(.opacity)
    }

    /// Eine Zeile: Mikrofon mit App-Namen, Kamera. App-Namen kommen aus dem lokalen Bundle → `Text(verbatim:)`.
    private var privacyLine: some View {
        HStack(spacing: 12) {
            if let apps = activity.privacy.micLine {
                privacyItem(color: .orange, symbol: "mic.fill", text: apps)
            }
            if activity.privacy.camera {
                privacyItem(color: .green, symbol: "video.fill", text: "Kamera")
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }

    private func privacyItem(color: Color, symbol: String, text: String) -> some View {
        ActivityRow(dot: color, symbol: symbol, text: text)
    }

    /// Groß ohne Musik: Mikrofon und Kamera untereinander (nebeneinander kürzte die Kamera den App-Namen),
    /// in Hinweis-Größe (IslandController.panelFrame).
    private var privacyDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let apps = activity.privacy.micLine {
                privacyItem(color: .orange, symbol: "mic.fill", text: apps)
            }
            if activity.privacy.camera {
                privacyItem(color: .green, symbol: "video.fill", text: "Kamera")
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(height: IslandGeometry.noticeSize.height)
            .padding(.top, state.layout.notch?.height ?? 0)
            .transition(.opacity)
    }

    /// Kopfhörer verbunden/getrennt: Symbol · Gerätename · Zustand, Inhalt unter der Notch.
    /// Gerätenamen vergibt der Nutzer frei → `Text(verbatim:)`.
    private func notice(_ n: ActivityModel.Notice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: n.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: n.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(verbatim: n.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(height: IslandGeometry.noticeSize.height)
        .padding(.top, state.layout.notch?.height ?? 0)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    private func compact(_ info: NowPlayingInfo) -> some View {
        HStack {
            cover(18, radius: 4)
                // Kleines App-Abzeichen unten rechts am Cover (wie iOS); außerhalb des Cover-Zuschnitts.
                .overlay(alignment: .bottomTrailing) { appIcon(info.appBundleID, size: 10).offset(x: 3, y: 3) }
            Spacer()
            // Mikrofon/Kamera an: Punkte statt Pegel – links neben dem Cover drückten sie es unter die
            // Hardware-Notch (Testbild 20.10.), und der Pegel ist nur Animation, kein Signal.
            if activity.privacy.isActive {
                privacyDots.frame(height: 14)
            } else if model.route.replacesLevelBars {
            // Pegel heißt „Ton kommt hier raus“ – bei anderem Gerät oder AirPlay dasselbe Symbol wie groß.
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
    private func expanded(_ info: NowPlayingInfo, topInset: CGFloat? = nil) -> some View {
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
        .padding(EdgeInsets(top: topInset ?? (state.layout.notch?.height ?? 0) + 12, leading: 16, bottom: 12, trailing: 16))
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

/// Echter Pegel aus Tippis Meldung (0…1), vier Balken unterschiedlich stark – wie Tippis eigene Pille.
struct LiveLevelBars: View {
    let level: Double
    private static let weights: [Double] = [0.55, 1, 0.8, 0.45]
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Self.weights.indices, id: \.self) { i in
                Capsule().fill(.white).frame(width: 2.5, height: 4 + 10 * level * Self.weights[i])
            }
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

/// „Wandelt um“: drei Punkte, die nacheinander aufleuchten. Reines SwiftUI statt ProgressView (der
/// Testrenderer zeichnet AppKit-Bausteine nicht); 15 Bilder/s reichen, die Ansicht gibt es nur beim Umwandeln.
struct WorkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(.white)
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 4 - Double(i) * 0.9)))
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

/// Animierter Pegel – reine Animation, kein Audiosignal (Spezifikation „Nicht in diesem Schritt“).
struct LevelBars: View {
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
