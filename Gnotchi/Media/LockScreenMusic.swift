import AppKit
import os
import SwiftUI

/// Musik auf dem Sperrbildschirm (0.20.0, specs/2026-11-06-gnotchi-0.20.0-sperrbildschirm.md, G46, Vorbild Droppy).
///
/// Nur bei **gesperrtem** Mac und nur, solange Musik spielt oder seit weniger als 10 Min. pausiert: kleine Karte
/// (Cover, Titel, Interpret, Fortschritt, ⏮ ⏯ ⏭) mittig zwischen Uhr und Anmeldung. Klick aufs Cover → großes Cover,
/// zurück per Klick oder nach 30 s. Ab Werk aus.
///
/// Sicherheit (G46): neue Grenze „Person am gesperrten Mac“. Ein Klick kann nur ⏮ ⏯ ⏭ auslösen und zwischen klein und
/// groß wechseln – kein App-Aktivieren, kein Menü, keine Texteingabe. In den Sperr-Space kommt nur dieses eine Fenster.
/// Titel nie ins Protokoll (G8/G16).
@MainActor
final class LockScreenMusicLink: NotchPart {
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "lockscreen")
    /// Breite des Fensters (Platz für das große Cover samt Schatten).
    nonisolated static let windowWidth: CGFloat = 480
    nonisolated static let cardSize = CGSize(width: 360, height: 96)
    nonisolated static let bigCoverMax: CGFloat = 440   // Michael 06.11.: „darf ruhig größer sein“ (vorher 280)
    /// Platz unter dem großen Cover für Titel, Interpret und Knöpfe.
    nonisolated static let bigFooter: CGFloat = 120
    nonisolated static let collapseAfter: TimeInterval = 30

    private let media: NowPlayingModel
    private let prefs: Preferences
    private var panel: NSPanel?
    private var space: LockScreenSpace?
    /// Aufbau einmal gescheitert → in diesem Lauf kein zweiter Versuch (Spec, Verhalten 6).
    private var failed = false
    private var timer: Timer?
    private var pausedSince: Date?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(media: NowPlayingModel, prefs: Preferences) {
        self.media = media
        self.prefs = prefs
    }

    func start() {
        guard timer == nil else { return }
        guard LockScreenSpace.isAvailable else {
            Self.log.notice("Sperrbildschirm: unter dieser macOS-Version nicht verfügbar")
            return
        }
        // Takt 1 s: Rückfall, falls eine Sperr-/Entsperr-Meldung fehlt (Ebene 400 liegt über allem, G46).
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append((dnc, dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }))
        }
        let nc = NotificationCenter.default
        observers.append((nc, nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }))
        update()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        removePanel()
        space?.tearDown()
        space = nil
        pausedSince = nil
    }

    /// „Titel verbergen“ umgeschaltet: neu aufbauen.
    func recheck() {
        removePanel()
        update()
    }

    // MARK: - Regeln (getestet)

    /// Gesperrt und Musik da (spielt oder < 10 Min. pausiert, wie die Schreibtisch-Anzeige).
    nonisolated static func shouldShow(locked: Bool, hasInfo: Bool, playing: Bool, pausedSince: Date?, now: Date) -> Bool {
        locked && DesktopMusicLink.shouldShow(hasInfo: hasInfo, playing: playing, pausedSince: pausedSince, now: now)
    }

    /// Ist die Sitzung gesperrt? Liest dasselbe Feld, das loginwindow setzt – unabhängig von verpassten Meldungen.
    nonisolated static func sessionLocked(_ dict: [String: Any]?) -> Bool {
        (dict?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// Fenster mittig, unter der Uhr (oberstes Viertel bleibt frei) und über der Anmeldung (unterste 30 % bleiben frei).
    nonisolated static func frame(screen: CGRect) -> CGRect {
        let top = screen.maxY - screen.height * 0.25
        let bottom = screen.minY + screen.height * 0.30
        let height = max(cardSize.height, min(bigCoverMax + bigFooter + 40, top - bottom))
        return CGRect(x: screen.midX - windowWidth / 2, y: top - height, width: windowWidth, height: height)
    }

    /// Großes Cover: höchstens 440 pt, kleiner, wenn das Fenster nicht reicht.
    nonisolated static func bigCover(windowHeight: CGFloat) -> CGFloat {
        max(cardSize.height, min(bigCoverMax, windowHeight - bigFooter - 40))
    }

    // MARK: - Intern

    private func update() {
        let info = media.info
        let now = Date()
        let playing = info?.isPlaying ?? false
        pausedSince = DesktopMusicLink.nextPausedSince(hasInfo: info != nil, playing: playing, current: pausedSince, now: now)
        let locked = Self.sessionLocked(CGSessionCopyCurrentDictionary() as? [String: Any])
        let show = Self.shouldShow(locked: locked, hasInfo: info != nil, playing: playing, pausedSince: pausedSince, now: now)
        if show, panel == nil, !failed {
            showPanel()
        } else if !show, panel != nil {
            removePanel()
        }
    }

    private func showPanel() {
        if space == nil { space = LockScreenSpace() }
        guard let space else {
            failed = true
            Self.log.error("Sperrbildschirm: Space nicht verfügbar, Funktion in diesem Lauf aus")
            return
        }
        let p = LockScreenPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                defer: false)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = FirstClickHostingView(rootView: LockScreenMusicView(media: media, hideTitle: prefs.lockScreenHideTitle))
        panel = p
        place()
        p.orderFrontRegardless()
        space.host(p)
        Self.log.notice("Sperrkarte gezeigt")
    }

    private func removePanel() {
        guard let panel else { return }
        space?.release()
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        Self.log.notice("Sperrkarte entfernt")
    }

    private func place() {
        guard let panel, let screen = NSScreen.screens.first else { return }   // Hauptbildschirm
        panel.setFrame(Self.frame(screen: screen.frame), display: true)
    }
}

/// Nimmt nie den Tastaturfokus (keine Texteingabe auf dem Sperrbildschirm, G46).
private final class LockScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Erster Klick zählt sofort (Fenster ist nie aktiv) – gemessen 06.11. mit `acceptsFirstMouse` in KlickProbe.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Kleine Karte oder großes Cover. Nur ⏮ ⏯ ⏭ und Umschalten – sonst nichts (G46).
struct LockScreenMusicView: View {
    let media: NowPlayingModel
    let hideTitle: Bool
    @State private var expanded: Bool
    @State private var lastTouch = Date()

    init(media: NowPlayingModel, hideTitle: Bool, expanded: Bool = false) {
        self.media = media
        self.hideTitle = hideTitle
        _expanded = State(initialValue: expanded)   // Testbild
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if expanded && !hideTitle {
                    big(cover: LockScreenMusicLink.bigCover(windowHeight: geo.size.height))
                } else {
                    card
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
        }
        .foregroundStyle(.white)
        .animation(.spring(duration: 0.35), value: expanded)
        // Zurück zur kleinen Karte nach 30 s ohne Bedienung; jeder Klick setzt `lastTouch` neu.
        .task(id: lastTouch) {
            guard expanded else { return }
            try? await Task.sleep(for: .seconds(LockScreenMusicLink.collapseAfter))
            if !Task.isCancelled { expanded = false }
        }
    }

    // MARK: Kleine Karte

    private var card: some View {
        let info = media.info
        let size = LockScreenMusicLink.cardSize
        return HStack(spacing: 12) {
            artwork(64)
                .onTapGesture { toggle() }
            VStack(alignment: .leading, spacing: 3) {
                if !hideTitle {
                    Text(verbatim: info?.title ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(verbatim: info?.artist ?? "").font(.system(size: 11)).opacity(0.75).lineLimit(1)
                }
                progress
                controls(size: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: size.width, height: size.height)
        .familyGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Großes Cover

    private func big(cover: CGFloat) -> some View {
        let info = media.info
        return VStack(spacing: 10) {
            artwork(cover)
                // Bewusst ohne Schatten: Auf dem Sperrbildschirm zeichnet macOS ihn als Rechteck ums Cover – am Bild
                // und an einer runden Fläche dahinter gleich; ohne Schatten sauber (Sichttest Michael 06.11.).
                .onTapGesture { toggle() }
            VStack(spacing: 2) {
                Text(verbatim: info?.title ?? "").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(verbatim: info?.artist ?? "").font(.system(size: 12)).opacity(0.75).lineLimit(1)
            }
            .frame(width: cover)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            controls(size: 20)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .familyGlass(in: Capsule())
                .environment(\.colorScheme, .dark)
        }
        .padding(.top, 8)
    }

    // MARK: Teile

    /// Bei „Titel verbergen“ nie das Cover, nur die Musiknote (Entschieden 1).
    @ViewBuilder private func artwork(_ side: CGFloat) -> some View {
        Group {
            if !hideTitle, let image = media.artwork {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.15)
                    Image(systemName: "music.note").font(.system(size: side * 0.4)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.12, style: .continuous))
        .contentShape(Rectangle())
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let info = media.info
            let total = info?.duration ?? 0
            let part = total > 0 ? min(1, (info?.elapsed(at: ctx.date) ?? 0) / total) : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white.opacity(0.9)).frame(width: geo.size.width * part)
                }
            }
            .frame(height: 3)
        }
    }

    private func controls(size: CGFloat) -> some View {
        let playing = media.info?.isPlaying ?? false
        return HStack(spacing: size * 1.2) {
            button("backward.fill", label: "Zurück", size: size) { media.previous() }
            button(playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Wiedergabe", size: size) {
                media.playPause()
            }
            button("forward.fill", label: "Weiter", size: size) { media.next() }
        }
    }

    private func button(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            lastTouch = Date()
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .frame(width: size * 1.8, height: size * 1.8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func toggle() {
        guard !hideTitle else { return }   // kein großes Cover ohne Titel (Entschieden 2)
        expanded.toggle()
        lastTouch = Date()
    }
}
