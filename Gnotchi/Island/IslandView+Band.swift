import SwiftUI

// Band (0.5.0, Michael 21.10., Vorbild-Video): seitlich breit in Menüleisten-Höhe statt nach unten.
// Links Musik (Cover, „Interpret – Titel“), rechts im Wechsel alle 4 s: Wiedergabe (Zeit, Balken, Pause,
// Weiter), Termin, Timer. Klick links öffnet die volle Insel. Titel nur `Text(verbatim:)` (G5).

/// Rechte Seite des Bands: welche Seite gerade dran ist (alle 4 s die nächste).
enum BandPage: Equatable {
    case media, event, timer, claude

    nonisolated static func pages(media: Bool, event: Bool, timer: Bool, claude: Bool = false) -> [BandPage] {
        (media ? [.media] : []) + (event ? [.event] : []) + (timer ? [.timer] : []) + (claude ? [.claude] : [])
    }

    nonisolated static func current(_ pages: [BandPage], at date: Date, interval: TimeInterval = 4) -> BandPage? {
        guard !pages.isEmpty else { return nil }
        return pages[Int(date.timeIntervalSince1970 / interval) % pages.count]
    }
}

struct BandView<Cover: View>: View {
    let info: NowPlayingInfo?
    let event: KalliEvents.Event?
    let timer: CountdownTimer?
    /// Breite der Notch; nil = Bildschirm ohne Notch.
    let notchWidth: CGFloat?
    let height: CGFloat
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onOpenEvent: () -> Void
    let onTimerToggle: () -> Void
    let onExpand: () -> Void
    /// Ablage im Band (0.8.0, Michael 22.10.: im Band kam man nur mit mehreren Klicks an die Ablage).
    var shelfItems: [ShelfStore.Item] = []
    var shelfLink: ShelfLink?
    var onOpenShelf: () -> Void = {}
    /// Ungelesen-Zahlen (0.9.0, Michael nutzt „Band“ – jede neue Anzeige auch hier).
    var unread: [NotifyWire.Badge] = []
    /// Claude-Code-Sitzung, die arbeitet oder wartet (0.9.0 Code & KI).
    var claude: ClaudeSession?
    var onOpenClaude: () -> Void = {}
    @ViewBuilder let cover: () -> Cover

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 10) {
                // Ablage und Ungelesen gehören zur linken Hälfte – als eigene Elemente daneben schoben sie die
                // Notch-Lücke aus der Mitte (Bildprüfung 22.10.: „12“ lag unter der Notch).
                HStack(spacing: 10) {
                    // Steht links nur Claude, ist die Zeile selbst der Knopf (Sichttest 22.10.: der Klick öffnete sonst
                    // die große Insel statt der Sitzung – im Protokoll kam nie ein Klick an).
                    if info == nil, event == nil, timer == nil, let claude {
                        Button(action: onOpenClaude) {
                            ClaudeBandLabel(session: claude).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "Claude-Sitzung \(claude.project) öffnen"))
                    } else {
                        Button(action: onExpand) { left.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: "Große Ansicht öffnen"))
                    }
                    if let shelfLink, !shelfItems.isEmpty {
                        ShelfMini(items: shelfItems, link: shelfLink, onOpen: onOpenShelf).fixedSize()
                    }
                    if !unread.isEmpty { UnreadMini(badges: unread).fixedSize() }
                }
                .frame(maxWidth: .infinity)
                if let notchWidth { Color.clear.frame(width: notchWidth) }
                // Mit Notch zwei gleiche Hälften (die Lücke bleibt mittig über der Kamera). Ohne Notch nimmt rechts nur, was es
                // braucht – sonst blieb die Mitte leer und der Titel wurde früh gekürzt (Michael 22.10., Bildschirmfoto).
                right(at: ctx.date).frame(maxWidth: notchWidth == nil ? nil : .infinity, alignment: .trailing)
                    .fixedSize(horizontal: notchWidth == nil, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(height: height)
        }
        .transition(.opacity)
    }

    @ViewBuilder private var left: some View {
        if let info {
            HStack(spacing: 8) {
                cover()
                Text(verbatim: [info.artist, info.title].compactMap { $0 }.joined(separator: " – "))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail)
            }
        } else if let event {
            eventLabel(event)
        } else if timer != nil {
            Text(verbatim: "Timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        }
    }

    @ViewBuilder private func right(at date: Date) -> some View {
        let pages = BandPage.pages(media: info != nil, event: event != nil && info != nil, timer: timer != nil,
                                   claude: claude != nil && (info != nil || event != nil || timer != nil))
        switch BandPage.current(pages, at: date) {
        case .claude?:
            if let claude { Button(action: onOpenClaude) { ClaudeBandLabel(session: claude) }.buttonStyle(.plain) }
        case .media?:
            if let info { mediaControls(info, now: date) }
        case .event?:
            if let event { Button(action: onOpenEvent) { eventLabel(event) }.buttonStyle(.plain) }
        case .timer?:
            if let timer {
                Button(action: onTimerToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: timer.isPaused ? "pause.fill" : "timer").foregroundStyle(.orange)
                        Text(verbatim: CountdownTimer.clock(timer.remaining(now: date)))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: timer.isPaused ? "Timer fortsetzen" : "Timer pausieren"))
            }
        case nil:
            EmptyView()
        }
    }

    private func eventLabel(_ e: KalliEvents.Event) -> some View {
        HStack(spacing: 6) {
            Circle().fill(e.color.map(Color.init(rgb:)) ?? .white).frame(width: 7, height: 7)
            Text(verbatim: e.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
            Text(verbatim: KalliEvents.timeText(e)).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
        }
    }

    private func mediaControls(_ info: NowPlayingInfo, now: Date) -> some View {
        let d = ProgressRow.display(elapsed: info.elapsed(at: now), duration: info.duration)
        return HStack(spacing: 8) {
            Text(verbatim: d.elapsedLabel).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: g.size.width * min(1, d.sliderValue / max(d.sliderUpper, 1)))
                }
            }
            .frame(width: 90, height: 3)
            .accessibilityHidden(true)
            button(info.isPlaying ? "pause.fill" : "play.fill", label: info.isPlaying ? "Pause" : "Wiedergabe",
                   action: onPlayPause)
            button("forward.fill", label: "Weiter", action: onNext)
        }
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}
