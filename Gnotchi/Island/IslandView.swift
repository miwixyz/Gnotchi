import AppKit
import SwiftUI

/// Zustand einer Insel, geteilt zwischen Panel (Größe, Mausdurchlass) und Ansicht.
@MainActor
@Observable
final class IslandState {
    /// `notice`: kurzer Hinweis (Kopfhörer), eigene Form unter der Notch (0.2.0).
    /// `live`: Tippis Live-Text, zwei Zeilen unter der Aufnahme-Zeile (0.3.0).
    /// `wide`: Trackwechsel, 3 s breiter mit Titel · Interpret (0.4.0).
    /// `message`/`call`: Mitteilung bzw. eingehender Anruf aus dem Hilfsprogramm (0.6.0).
    /// `shelfDrop`: Ablagefeld, solange irgendwo Dateien gezogen werden (0.8.0).
    enum Mode { case hidden, compact, expanded, notice, live, wide, band, message, call, shelfDrop }
    var mode: Mode = .hidden
    /// Nach dem Ablegen (0.8.0) hochgezählt: Die Insel-Ansicht wird neu aufgebaut, damit SwiftUIs Überfahren-Zustand
    /// stimmt. Während des Ziehens kommt kein „Maus raus“ an – danach hielt die Insel die Maus für drin und klappte
    /// nicht mehr auf (Michael 22.10.: „Ich muss x-mal klicken“).
    var hoverEpoch = 0
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
    /// Klick auf den Termin (0.5.0): IslandController → Apple Kalender.
    var onOpenEvent: () -> Void = {}
    /// Klick auf das Band (0.5.0): volle Insel.
    var onExpandFull: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                let shape = UnevenRoundedRectangle(bottomLeadingRadius: corner, bottomTrailingRadius: corner,
                                                   style: .continuous)
                if activity.pinned && state.mode == .expanded {
                    // Angeheftet: durchscheinendes Glas statt Schwarz (Michael 21.10.: „weniger Deckung“).
                    shape.fill(.black.opacity(0.35)).familyGlass(in: shape)
                } else {
                    shape.fill(.black)
                }
                // Timer-Alarm klein: die ganze Insel pulsiert orange, in ihrer eigenen Form (0.5.0).
                if activity.timerAlarm && state.mode == .compact { AlarmPulse().clipShape(shape) }
                content
            }
            .frame(width: size.width, height: size.height)
            .onHover(perform: onHover)
            .id(state.hoverEpoch)
            Spacer(minLength: 0)
        }
        // Füllt das Panel (klein ODER groß); die Insel hängt oben mittig – beide Rechtecke teilen midX und Oberkante.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.32), value: state.mode)
        // Titelwechsel weich überblenden (Spezifikation „Bewegung“).
        .animation(.smooth, value: model.info?.title)
        .environment(\.colorScheme, .dark)
    }

    private var pill: Bool { state.layout.notch == nil }

    @ViewBuilder private var content: some View {
        switch state.mode {
        case .hidden: EmptyView()
        case .notice: if let n = activity.notice { notice(n) }
        case .live: if let rec = activity.recording { liveText(rec) }
        case .message:
            if let n = activity.currentNote {
                NoteIsland(note: n, queued: activity.queuedNotes, topInset: state.layout.notch?.height ?? 0,
                           onOpen: { activity.openNote() }, onAction: { activity.performNoteAction($0) })
            }
        case .shelfDrop:
            ShelfDropZone(count: activity.shelfItems.count, topInset: state.layout.notch?.height ?? 0) { activity.shelf?.dropDragged($0) }
        case .call:
            if let c = activity.call {
                CallIsland(call: c, armed: activity.callArmed, topInset: state.layout.notch?.height ?? 0,
                           onAnswer: { activity.answerCall($0) }, onDecline: { activity.declineCall() },
                           onScreen: { activity.screenCall() })
            }
        case .compact:
            if let rec = activity.recording {
                recordingCompact(rec)
            } else {
                rotationCompact
            }
        case .band:
            BandView(info: model.isVisible ? model.info : nil, event: activity.upcomingEvent, timer: activity.timer,
                     notchWidth: state.layout.notch?.width, height: state.layout.band.height,
                     onPlayPause: { model.playPause() }, onNext: { model.next() }, onOpenEvent: onOpenEvent,
                     onTimerToggle: { activity.timer?.isPaused == true ? activity.resumeTimer() : activity.pauseTimer() },
                     onExpand: onExpandFull, shelfItems: activity.shelfItems, shelfLink: activity.shelf,
                     onOpenShelf: { activity.selectShelf(); onExpandFull() }, unread: activity.unread,
                     // Auch fertige Sitzungen (Sichttest 22.10.: Band war nach „fertig“ leer, Michael nutzt das Band).
                     claude: activity.claudeOrdered.first,
                     onOpenClaude: { if let s = activity.claudeOrdered.first { ClaudeLink.open(s) } },
                     quota: activity.quotaLine,
                     cover: { cover(18, radius: 4) })
        case .wide:
            if let info = model.info {
                TrackFlash(info: info, notchWidth: state.layout.notch?.width, height: state.layout.wide.height) {
                    cover(18, radius: 4)
                } bars: {
                    LevelBars(playing: info.isPlaying)
                }
            }
        case .expanded:
            // „Eine Sache groß“ (0.5.0): oben die Symbolleiste, darunter nur die gewählte Aktivität.
            let chips = activity.showsChipRow
            VStack(spacing: 0) {
                if chips {
                    ChipRow(items: activity.chipItems,
                            current: activity.highlightedChip,
                            event: activity.upcomingEvent, headphones: activity.headphones,
                            mediaApp: model.info?.appBundleID, privacy: activity.privacy, quota: activity.quotaLine,
                            mirror: activity.mirrorEnabled ? activity.mirrorActive : nil,
                            timerButton: activity.timer == nil ? activity.timerPickerActive : nil,
                            weather: activity.weather.map { ($0, activity.weatherActive) },
                            onWeather: { activity.selectWeather() },
                            shelf: activity.shelfItems.isEmpty ? nil : (activity.shelfItems.count, activity.shelfActive),
                            onShelf: { activity.selectShelf() },
                            onSelect: { activity.select($0) }, onMirror: { activity.selectMirror() },
                            onTimer: { activity.showTimerPicker() },
                            pinned: activity.pinned, onPin: { activity.togglePin() }, unread: activity.unread)
                        .padding(EdgeInsets(top: (state.layout.notch?.height ?? 0) + 8, leading: 16, bottom: 0, trailing: 16))
                }
                big(topInset: chips ? 0 : nil)
                    .frame(maxHeight: .infinity, alignment: .top)
                if activity.showsShelfStrip, let shelf = activity.shelf {
                    ShelfStrip(items: activity.shelfItems, link: shelf)
                        .frame(height: IslandGeometry.shelfStripHeight)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    /// Kleine Insel ohne Aufnahme (0.4.0): die Aktivität, die die Rotation gerade zeigt. Ohne Aktivität die Musik, solange
    /// sie sichtbar ist (spielt / < 5 s Pause), sonst die Punkte bzw. die Ruhe-Insel. Den letzten Titel nach längerer Pause
    /// zeigt sie seit 0.9.0 nicht mehr (Michael 22.10.: „Musik ausblenden“).
    @ViewBuilder private var rotationCompact: some View {
        let height = state.layout.compact.height
        if activity.timerAlarm {
            AlarmCompact(pill: pill, height: height) { activity.dismissTimerAlarm() }
        } else {
            rotationCompactActivity(height: height)
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
            // Ungelesen auch neben Mikrofon/Kamera (Michael 22.10.: „der Zähler fehlt“).
            if activity.compactUnreadTotal > 0 { UnreadDot(total: activity.compactUnreadTotal) }
        }
        .padding(.horizontal, state.layout.notch == nil ? 12 : 14)
        .frame(height: state.layout.compact.height)
        .transition(.opacity)
    }

    private func privacyItem(color: Color, symbol: String, text: String) -> some View {
        ActivityRow(dot: color, symbol: symbol, text: text)
    }

    /// Groß ohne Musik: Mikrofon und Kamera untereinander (nebeneinander kürzte die Kamera den App-Namen),
    /// in Hinweis-Größe (IslandController.panelFrame).
    private func privacyDetails(topInset: CGFloat?) -> some View {
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
            .padding(.top, topInset ?? (state.layout.notch?.height ?? 0))
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
        // Mit Knöpfen enger: zwei Knöpfe müssen in den 40-pt-Flügel neben der Notch (Testbild 21.10.).
        HStack(spacing: activity.compactControls ? 3 : nil) {
            // Ungelesen-Zähler NICHT während der Wiedergabe (Michael 22.10.: „lieber während der Wiedergabe ausblenden“) –
            // er steht in der Ruhe-Insel und bei Mikrofon/Kamera; Band und große Insel zeigen die Zahlen immer.
            cover(18, radius: 4)
                // Kleines App-Abzeichen unten rechts am Cover (wie iOS); außerhalb des Cover-Zuschnitts.
                .overlay(alignment: .bottomTrailing) { appIcon(info.appBundleID, size: 10).offset(x: 3, y: 3) }
            if pill {
                // Ohne Notch ist die Mitte frei (Michael 22.10.: „viel schwarzer ungenutzter Platz“) → Titel. Mit Notch
                // sitzt dort die Kamera.
                Text(verbatim: info.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 3)
            } else {
                Spacer()
            }
            if activity.compactControls {
                // Wiedergabe-Knöpfe dauerhaft (Michael 21.10., Schalter): Pause/Wiedergabe und Weiter statt Pegel.
                // Mikrofon/Kamera dann als Punkt am Cover (siehe unten).
                compactButton(info.isPlaying ? "pause.fill" : "play.fill", label: info.isPlaying ? "Pause" : "Wiedergabe") {
                    model.playPause()
                }
                compactButton("forward.fill", label: "Weiter") { model.next() }
            } else
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
        .overlay(alignment: .topLeading) {
            if activity.compactControls && activity.privacy.isActive {
                Circle().fill(activity.privacy.mic ? Color.orange : .green).frame(width: 6, height: 6).offset(x: -2, y: 1)
            }
        }
        .padding(.horizontal, activity.compactControls ? 8 : 10)
        .frame(height: state.layout.compact.height)
        .transition(.opacity)
    }

    private func compactButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 15, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
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

// „Eine Sache groß“ (0.5.0) – als Erweiterung, Strukturrumpf ≤ 350 Zeilen.
extension IslandView {
    @ViewBuilder fileprivate func rotationCompactActivity(height: CGFloat) -> some View {
        switch activity.currentActivity {
        case .timer?:
            if let t = activity.timer { TimerCompact(timer: t, pill: pill, height: height) }
        case .event?:
            if let ev = activity.upcomingEvent {
                EventCompact(event: ev, privacy: activity.privacy, pill: pill, height: height, onOpen: onOpenEvent)
            }
        case .media?:
            if let info = model.info { compact(info) }
        case .headphones?:
            if let h = activity.headphones {
                HeadphonesCompact(headphones: h, privacy: activity.privacy, pill: pill, height: height)
            }
        case .claude?:
            if let s = activity.claudeHeadline {
                ClaudeCompact(session: s, count: activity.claudeSessions.filter { $0.state != .done }.count, pill: pill,
                              height: height)
            }
        case .update(let app)?:
            if let e = activity.update(for: app) {
                UpdateCompact(entry: e, privacy: activity.privacy, pill: pill, height: height) { onOpenUpdate(app) }
            }
        case nil:
            // Nur sichtbare Musik (spielt oder < 5 s Pause): Hielt etwas anderes die Insel offen (Ungelesen, Wetter),
            // stand sonst der zuletzt gespielte Titel dauerhaft da (Michael 22.10.: „obwohl gerade nichts läuft“).
            if let info = model.info, model.isVisible {
                compact(info)
            } else if activity.privacy.isActive {
                privacyCompact
            } else if activity.hasIdleContent {
                IdleCompact(weather: activity.weather, shelfCount: activity.shelfItems.count, unread: activity.compactUnreadTotal,
                            pill: pill,
                            height: state.layout.compact.height)
            }
        }
    }

    /// „Wiedergabe immer groß“: gewählte Aktivität als Glas über Cover und Titel; rechts bleiben die Player-Knöpfe frei.
    @ViewBuilder func playerOverlay(_ item: LiveActivity, top: CGFloat) -> some View {
        let width = size.width - 32 - 150
        Group {
            switch item {
            case .event:
                if let ev = activity.upcomingEvent {
                    OverlayCard(symbol: "calendar", tint: ev.color.map(Color.init(rgb:)) ?? .white, title: ev.title,
                                subtitle: "\(KalliEvents.timeText(ev)) · in \(KalliEvents.minutesLeft(ev, now: Date())) Min",
                                onTap: onOpenEvent)
                }
            case .timer:
                if let t = activity.timer {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        OverlayCard(symbol: t.isPaused ? "pause.fill" : "timer", tint: .orange,
                                    title: CountdownTimer.clock(t.remaining(now: ctx.date)),
                                    subtitle: t.isPaused ? "pausiert – zum Fortsetzen klicken" : "zum Pausieren klicken",
                                    onTap: { t.isPaused ? activity.resumeTimer() : activity.pauseTimer() })
                    }
                }
            case .headphones:
                if let h = activity.headphones {
                    OverlayCard(symbol: h.symbol, tint: .white, title: h.name, subtitle: "Ton über Bluetooth")
                }
            case .claude:
                if let s = activity.claudeHeadline {
                    OverlayCard(symbol: ClaudeStyle.symbol, tint: ClaudeStyle.color(s.state), title: s.project,
                                subtitle: s.statusLine, onTap: { ClaudeLink.open(s) })
                }
            case .update(let app):
                if let e = activity.update(for: app) {
                    OverlayCard(symbol: "arrow.down.circle.fill", tint: .white, title: e.label,
                                subtitle: "Zum Installieren öffnen", onTap: { onOpenUpdate(app) })
                }
            case .media:
                EmptyView()
            }
        }
        .frame(width: width, height: 56)
        .padding(EdgeInsets(top: top, leading: 16, bottom: 0, trailing: 0))
        .transition(.opacity)
    }

    /// Die große Sache. `topInset` nil = direkt unter der Notch (ohne Symbolleiste).
    @ViewBuilder private func big(topInset: CGFloat?) -> some View {
        let top = topInset ?? (state.layout.notch?.height ?? 0)
        switch activity.bigContent {
        case .media:
            if let info = model.info {
                ZStack(alignment: .topLeading) {
                    expanded(info, topInset: topInset.map { $0 + 4 })
                    if let o = activity.playerOverlay { playerOverlay(o, top: (topInset.map { $0 + 4 }) ?? top + 12) }
                }
            }
        case .event:
            if let ev = activity.upcomingEvent {
                EventCard(event: ev, onOpen: onOpenEvent).padding(.top, top).transition(.opacity)
            }
        case .headphones: headphonesBig(top: top)
        case .claude: claudeBig(top: top)
        case .update(let app):
            if let e = activity.update(for: app) {
                ActivityCard(title: e.label, subtitle: "Zum Installieren öffnen", action: "Öffnen", onTap: { onOpenUpdate(app) },
                             leading: { AppSymbol(bundleID: app.bundleID, size: 44) })
                .padding(.top, top).transition(.opacity)
            }
        case .privacy:
            privacyDetails(topInset: topInset)
        case .timer:
            if let t = activity.timer {
                TimerCard(timer: t, onPauseResume: { t.isPaused ? activity.resumeTimer() : activity.pauseTimer() },
                          onStop: { activity.stopTimer() })
                    .padding(.top, top).transition(.opacity)
            }
        case .alarm:
            AlarmCard { activity.dismissTimerAlarm() }.padding(.top, top).transition(.opacity)
        case .timerPicker:
            TimerPicker { activity.startTimer(minutes: $0) }.padding(.top, top).transition(.opacity)
        case .mirror:
            MirrorView(onSettings: MirrorView.openCameraSettings)
                .padding(EdgeInsets(top: (topInset ?? (state.layout.notch?.height ?? 0)) + 6, leading: 16, bottom: 12,
                                    trailing: 16))
                .transition(.opacity)
        case .weather:
            weatherBig(topInset: topInset)
        case .shelf:
            shelfBig(topInset: topInset)
        case .none:
            EmptyView()
        }
    }

}

// Große Wetter- und Ablage-Ansicht (0.7.0/0.8.0) – ausgelagert, damit der Struct-Rumpf unter 350 Zeilen bleibt.
extension IslandView {
    /// Ablage groß (0.8.0) – eigene Funktion, damit `big` kurz bleibt.
    @ViewBuilder fileprivate func shelfBig(topInset: CGFloat?) -> some View {
        if let shelf = activity.shelf {
            ShelfBig(items: activity.shelfItems, link: shelf)
                .padding(EdgeInsets(top: (topInset ?? (state.layout.notch?.height ?? 0)) + 6, leading: 12, bottom: 10, trailing: 12))
                .transition(.opacity)
        }
    }

    /// Kopfhörer groß – eigene Funktion, damit `big` kurz bleibt (0.9.0).
    @ViewBuilder fileprivate func headphonesBig(top: CGFloat) -> some View {
        if let h = activity.headphones {
            ActivityCard(title: h.name, subtitle: "Ton über Bluetooth") {
                Image(systemName: h.symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.top, top).transition(.opacity)
        }
    }

    /// Claude-Sitzungen groß (0.9.0) – eigene Funktion, damit `big` kurz bleibt.
    fileprivate func claudeBig(top: CGFloat) -> some View {
        ClaudeBig(sessions: activity.claudeOrdered, onOpen: { ClaudeLink.open($0) })
            .padding(EdgeInsets(top: top + 6, leading: 16, bottom: 8, trailing: 16))
    }

    /// Wetter groß (0.7.0) – eigene Funktion, damit `big` kurz bleibt.
    @ViewBuilder fileprivate func weatherBig(topInset: CGFloat?) -> some View {
        if let w = activity.weather {
            WeatherBig(forecast: w)
                .padding(EdgeInsets(top: (topInset ?? (state.layout.notch?.height ?? 0)) + 6, leading: 12, bottom: 10, trailing: 12))
                .transition(.opacity)
        }
    }
}

// Größe und Ecken je Zustand – ausgelagert, damit der Struct-Rumpf unter 350 Zeilen bleibt (0.8.0).
extension IslandView {
    fileprivate var size: CGSize {
        switch state.mode {
        case .hidden: state.layout.notch?.size ?? CGSize(width: IslandGeometry.pillSize.width, height: 0)
        case .compact: state.layout.compact.size
        case .wide: state.layout.wide.size
        case .band: state.layout.band.size
        case .expanded:
            IslandController.bigFrame(layout: state.layout, small: activity.bigContent == .privacy,
                                      chipRow: activity.showsChipRow, mirror: activity.mirrorActive,
                                      weather: activity.bigContent == .weather,
                                      shelf: activity.bigContent == .shelf,
                                      strip: activity.showsShelfStrip)?.size ?? state.layout.expanded.size
        case .notice: state.layout.notice.size
        case .live: state.layout.live.size
        case .message: IslandController.messageFrame(layout: state.layout, note: activity.currentNote).size
        case .call: state.layout.call.size
        case .shelfDrop: state.layout.shelfDrop.size
        }
    }

    fileprivate var corner: CGFloat {
        switch state.mode {
        case .expanded, .message: 22
        case .notice, .live, .call, .shelfDrop: 16
        case .hidden, .compact, .wide, .band: 10
        }
    }
}
