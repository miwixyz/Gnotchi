import AppKit
import SwiftUI

/// Musik auf dem Schreibtisch (0.15.0, specs/2026-10-26-gnotchi-0.15.0-schreibtisch-vorschau.md, Vorbild Sleeve).
///
/// Zwei Darstellungen. **Widget** (ab 0.26.0, specs/2026-11-13-gnotchi-0.26.0-schreibtisch-widget.md, G49): ein echtes
/// macOS-Widget, das der Nutzer selbst auf den Schreibtisch legt – nur so sieht es aus wie Uhr und Kalender (gedämpft/
/// farbig rechnet macOS selbst; ein eigenes Fenster traf die Farben nie, gemessen 13.11.). Gnotchi liefert nur die Daten
/// (`DesktopWidgetFeed`). **Plattenspieler** (0.17.0): eigene Fenster wie bisher. Daten wie in der Insel (G4/G5/G6).
/// Sichtbar bzw. geliefert, solange eine Quelle spielt oder pausiert – nach 10 Min. Pause aus.
@MainActor
final class DesktopMusicLink: NotchPart {
    nonisolated static let pauseLimit: TimeInterval = 10 * 60
    /// Knopfzeile des Plattenspielers – fest reserviert, damit beim Drüberfahren nichts springt.
    nonisolated static let controlsHeight: CGFloat = 38
    /// Plattenspieler: viel Rand, sonst schneidet das Fenster den Schatten hart ab (gemessen 27.10.: dunkles Rechteck).
    nonisolated static let turntablePad: CGFloat = 110

    private let media: NowPlayingModel
    private let prefs: Preferences
    private let feed: DesktopWidgetFeed
    /// 0.17.0 Plattenspieler: Farbverlauf (unter den Symbolen) und Gerät (darüber, mittig).
    private var backdrop: NSPanel?
    private var deck: NSPanel?
    private var timer: Timer?
    private var pausedSince: Date?
    private var screenObserver: NSObjectProtocol?

    init(media: NowPlayingModel, prefs: Preferences) {
        self.media = media
        self.prefs = prefs
        feed = DesktopWidgetFeed { [weak media] action in
            switch action {
            case .previous: media?.previous()
            case .playPause: media?.playPause()
            case .next: media?.next()
            }
        }
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        t.tolerance = 0.1   // Weckzeiten bündeln (Akku, BAMA-Check 28.10.)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        feed.startListening()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.place() }
            }
        update()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        removePanels()
        feed.stopListening()
        feed.clear()
        pausedSince = nil
    }

    /// Ecke, Größe, Darstellung oder Bildschirm geändert: neu aufbauen.
    func recheck() {
        removePanels()
        if prefs.desktopMusicStyle == .turntable { feed.clear() }
        update()
    }

    private func removePanels() {
        for p in [backdrop, deck] {
            p?.orderOut(nil)
            p?.contentView = nil
        }
        backdrop = nil
        deck = nil
    }

    // MARK: - Sichtbarkeit (getestet)

    nonisolated static func shouldShow(hasInfo: Bool, playing: Bool, pausedSince: Date?, now: Date) -> Bool {
        guard hasInfo else { return false }
        if playing { return true }
        guard let pausedSince else { return true }
        return now.timeIntervalSince(pausedSince) < pauseLimit
    }

    nonisolated static func nextPausedSince(hasInfo: Bool, playing: Bool, current: Date?, now: Date) -> Date? {
        guard hasInfo, !playing else { return nil }
        return current ?? now
    }

    /// Erlaubter Bereich: ganzer Bildschirm bis unter die Menüleiste – auch auf Höhe des Docks (Michael 26.10.:
    /// „kann ruhig in Höhe des Docks“). Das Dock liegt immer darüber, die Anzeige verdeckt es also nie.
    @MainActor
    static func area(of screen: NSScreen) -> CGRect {
        let f = screen.frame
        return CGRect(x: f.minX, y: f.minY, width: f.width, height: screen.visibleFrame.maxY - f.minY)
    }

    // MARK: - Intern

    private func update() {
        let info = media.info
        pausedSince = Self.nextPausedSince(hasInfo: info != nil, playing: info?.isPlaying ?? false,
                                           current: pausedSince, now: Date())
        let show = Self.shouldShow(hasInfo: info != nil, playing: info?.isPlaying ?? false,
                                   pausedSince: pausedSince, now: Date())
        if prefs.desktopMusicStyle == .turntable {
            if show && deck == nil { makeTurntable() }
            Self.fade(backdrop, visible: show)
            Self.fade(deck, visible: show)
            return
        }
        // Widget: nur Daten liefern, zeichnen tut macOS.
        feed.publish(info: show ? info : nil, artwork: media.artwork)
    }

    // MARK: - Plattenspieler (0.17.0)

    private func makeTurntable() {
        let b = makePanel()
        // Unter den Schreibtisch-Symbolen, über dem Hintergrundbild (gemessen 27.10., tools/desktop-layers.swift).
        b.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        b.ignoresMouseEvents = true
        b.contentView = NSHostingView(rootView: TurntableBackdrop(media: media))
        let d = makePanel()
        backdrop = b
        deck = d
        place()
    }

    /// Gewählter Bildschirm (UUID), sonst – auch wenn er abgesteckt ist – der Hauptbildschirm.
    static func turntableScreen(_ uuid: String) -> NSScreen? {
        NSScreen.screens.first { !uuid.isEmpty && Self.uuid(of: $0) == uuid } ?? NSScreen.screens.first
    }

    static func uuid(of screen: NSScreen) -> String {
        guard let id = screen.displayID, let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, ref) as String
    }

    /// Fenster für den Plattenspieler: ein Drittel der Bildschirmbreite, mittig im sichtbaren Bereich.
    nonisolated static func turntableLayout(screen: CGRect, visible: CGRect, neon: Bool = false)
        -> (window: CGRect, deckWidth: CGFloat) {
        let width = min(screen.width / 3, visible.height * 1.6)
        let deckWidth = width / TurntableView.rowWidthRatio
        let height = deckWidth * TurntableView.rowHeightRatio + deckWidth * 0.12 + 110
            + (neon ? TurntableNeon.height(deckWidth: deckWidth) : 0)
        let p = turntablePad
        let frame = CGRect(x: visible.midX - width / 2 - p, y: visible.midY - height / 2 - p,
                           width: width + 2 * p, height: height + 2 * p)
        return (frame, deckWidth)
    }

    /// Weich ein- und ausblenden (Michael 27.10.: „Farbe blendet langsam aus“).
    /// Läuft jede Sekunde: `alphaValue` ist schon der Zielwert einer laufenden Animation – gleiches Ziel → nichts tun,
    /// sonst startete das 1,5-s-Ausblenden jede Sekunde neu und endete nie.
    static func fade(_ p: NSPanel?, visible: Bool) {
        guard let p else { return }
        if visible {
            if p.isVisible && p.alphaValue == 1 { return }
            if !p.isVisible {
                p.alphaValue = 0
                p.orderFront(nil)
            }
        } else if !p.isVisible || p.alphaValue == 0 {
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = visible ? 0.8 : 1.5
            p.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: {
            // Inzwischen wieder eingeblendet? Dann nicht wegnehmen.
            MainActor.assumeIsolated { if p.alphaValue == 0 { p.orderOut(nil) } }
        })
    }

    private func place() {
        if let deck, let backdrop, let screen = Self.turntableScreen(prefs.desktopMusicScreen) {
            backdrop.setFrame(screen.frame, display: true)
            let layout = Self.turntableLayout(screen: screen.frame, visible: Self.area(of: screen), neon: prefs.desktopMusicNeon)
            deck.setFrame(layout.window, display: true)
            deck.contentView = NSHostingView(rootView: TurntableView(media: media, deckWidth: layout.deckWidth,
                                                                     neon: prefs.desktopMusicNeon,
                                                                     tonearm: prefs.desktopMusicTonearm)
                .padding(Self.turntablePad).frame(maxWidth: .infinity, maxHeight: .infinity))
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Über den Schreibtisch-Symbolen, unter allen normalen Fenstern.
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        return p
    }

    /// Nur eine **schon laufende** App mit dieser Kennung nach vorne holen, nie starten: Die Kennung stammt aus dem
    /// Medienstrom (Fremddaten, G4).
    static func bringToFront(_ bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate()
    }
}
