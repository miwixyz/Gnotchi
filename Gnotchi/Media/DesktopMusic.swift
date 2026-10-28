import AppKit
import SwiftUI

/// Musik auf dem Schreibtisch (0.15.0, specs/2026-10-26-gnotchi-0.15.0-schreibtisch-vorschau.md, Vorbild Sleeve).
///
/// Randloses Fenster auf Schreibtischhöhe (über den Schreibtisch-Symbolen, hinter allen Fenstern), nur auf dem
/// Hauptbildschirm, in einer gewählten Ecke. Zeigt dieselben Daten wie die Insel (G4/G5/G6: Fremddaten, ohne
/// Interpretation, Cover begrenzt dekodiert). Sichtbar, solange eine Quelle spielt oder pausiert – nach 10 Min. Pause
/// aus. Keine Berechtigung, kein Netz, nichts gespeichert, nichts protokolliert (G8/G16).
@MainActor
final class DesktopMusicLink: NotchPart {
    nonisolated static let pauseLimit: TimeInterval = 10 * 60
    /// Rand um den Inhalt im Fenster (Platz für den Schatten) – darf über den Bildschirmrand ragen.
    nonisolated static let pad: CGFloat = 20
    /// Plattenspieler: viel Rand, sonst schneidet das Fenster den Schatten hart ab (gemessen 27.10.: dunkles Rechteck).
    nonisolated static let turntablePad: CGFloat = 110
    /// Knopfzeile ganz unten – fest reserviert, damit beim Drüberfahren nichts springt.
    nonisolated static let controlsHeight: CGFloat = 38

    private let media: NowPlayingModel
    private let prefs: Preferences
    private var panel: NSPanel?
    /// 0.17.0 Plattenspieler: Farbverlauf (unter den Symbolen) und Gerät (darüber, mittig).
    private var backdrop: NSPanel?
    private var deck: NSPanel?
    private var timer: Timer?
    private var pausedSince: Date?
    private var screenObserver: NSObjectProtocol?
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?

    init(media: NowPlayingModel, prefs: Preferences) {
        self.media = media
        self.prefs = prefs
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        t.tolerance = 0.1   // Weckzeiten bündeln (Akku, BAMA-Check 28.10.)
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
        pausedSince = nil
    }

    /// Ecke, Größe, Darstellung oder Bildschirm geändert: neu aufbauen.
    func recheck() {
        removePanels()
        update()
    }

    private func removePanels() {
        for p in [panel, backdrop, deck] {
            p?.orderOut(nil)
            p?.contentView = nil
        }
        panel = nil
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

    /// Fenster so, dass der **Inhalt** (Cover + Text) `inset` von der Ecke des sichtbaren Bereichs entfernt ist (ohne
    /// Dock und Menüleiste). Der Schattenrand `pad` darf über den Rand ragen – so geht das Cover bündig in die Ecke.
    nonisolated static func frame(corner: Preferences.DesktopCorner, inset: CGSize, size: CGSize,
                                  in area: CGRect) -> CGRect {
        let x = switch corner {
        case .bottomLeft, .topLeft: area.minX + inset.width - pad
        case .bottomRight, .topRight: area.maxX - inset.width + pad - size.width
        }
        let y = switch corner {
        case .bottomLeft, .bottomRight: area.minY + inset.height - pad
        case .topLeft, .topRight: area.maxY - inset.height + pad - size.height
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Nach dem Ziehen: nächste Ecke und Abstand des Inhalts dazu, begrenzt auf den sichtbaren Bereich.
    nonisolated static func anchor(for window: CGRect, in area: CGRect)
        -> (corner: Preferences.DesktopCorner, inset: CGSize) {
        let content = window.insetBy(dx: pad, dy: pad)
        let left = content.midX < area.midX
        let bottom = content.midY < area.midY
        let corner: Preferences.DesktopCorner = bottom ? (left ? .bottomLeft : .bottomRight)
                                                       : (left ? .topLeft : .topRight)
        let dx = left ? content.minX - area.minX : area.maxX - content.maxX
        let dy = bottom ? content.minY - area.minY : area.maxY - content.maxY
        let inset = CGSize(width: min(max(0, dx), max(0, area.width - content.width)),
                           height: min(max(0, dy), max(0, area.height - content.height)))
        return (corner, inset)
    }

    /// Erlaubter Bereich: ganzer Bildschirm bis unter die Menüleiste – auch auf Höhe des Docks (Michael 26.10.:
    /// „kann ruhig in Höhe des Docks“). Das Dock liegt immer darüber, die Anzeige verdeckt es also nie.
    @MainActor
    static func area(of screen: NSScreen) -> CGRect {
        let f = screen.frame
        return CGRect(x: f.minX, y: f.minY, width: f.width, height: screen.visibleFrame.maxY - f.minY)
    }

    nonisolated static func windowSize(_ size: Preferences.DesktopSize) -> CGSize {
        // Platz für Schatten rundum, zwei Textzeilen und die Knopfzeile ganz unten (Michael 26.10.).
        CGSize(width: size.cover + 2 * pad, height: size.cover + 2 * pad + 46 + 8 + controlsHeight)
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
        if show {
            if panel == nil {
                let p = makePanel()
                p.contentView = NSHostingView(rootView: makeView())
                panel = p
                place()
            }
            if panel?.isVisible == false { panel?.orderFront(nil) }
        } else if panel?.isVisible == true {
            panel?.orderOut(nil)
        }
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
            return
        }
        guard let panel, let screen = NSScreen.screens.first else { return }   // Hauptbildschirm (Menüleiste)
        panel.setFrame(Self.frame(corner: prefs.desktopMusicCorner, inset: prefs.desktopMusicInset,
                                  size: Self.windowSize(prefs.desktopMusicSize), in: Self.area(of: screen)), display: true)
    }

    private func makeView() -> DesktopMusicView {
        DesktopMusicView(media: media, cover: prefs.desktopMusicSize.cover,
                         onDrag: { [weak self] in self?.dragChanged() }, onDragEnd: { [weak self] in self?.dragEnded() })
    }

    /// Ziehen mit der Maus (Michael 26.10.): Fenster folgt dem Mauszeiger; am Ende Ecke + Abstand merken.
    private func dragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let start = dragStart ?? (mouse, panel.frame.origin)
        dragStart = start
        panel.setFrameOrigin(CGPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
    }

    private func dragEnded() {
        dragStart = nil
        guard let panel, let screen = NSScreen.screens.first else { return }
        let (corner, inset) = Self.anchor(for: panel.frame, in: Self.area(of: screen))
        prefs.desktopMusicCorner = corner
        prefs.desktopMusicInset = inset
        place()   // in den sichtbaren Bereich zurück, falls darüber hinaus gezogen
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
}

/// Cover, Titel, „Interpret · Album“. Beim Drüberfahren ⏮ ⏯ ⏭; Klick aufs Cover holt die laufende App nach vorne.
struct DesktopMusicView: View {
    let media: NowPlayingModel
    let cover: CGFloat
    var onDrag: () -> Void = {}
    var onDragEnd: () -> Void = {}
    @State private var hovering: Bool
    init(media: NowPlayingModel, cover: CGFloat, onDrag: @escaping () -> Void = {}, onDragEnd: @escaping () -> Void = {},
         hovering: Bool = false) {
        self.media = media
        self.cover = cover
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
        _hovering = State(initialValue: hovering)   // Testbild mit sichtbaren Knöpfen
    }

    var body: some View {
        let info = media.info
        let playing = info?.isPlaying ?? false
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                artwork
                    .frame(width: cover, height: cover)
                    .clipShape(RoundedRectangle(cornerRadius: cover * 0.07, style: .continuous))
                    .overlay(Color.black.opacity(playing ? 0 : 0.35)
                        .clipShape(RoundedRectangle(cornerRadius: cover * 0.07, style: .continuous)))
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                    .onTapGesture { Self.bringToFront(info?.appBundleID) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: info?.title ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(verbatim: [info?.artist, info?.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11)).opacity(0.75).lineLimit(1)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .frame(width: cover, alignment: .leading)
            // Knöpfe ganz unten, gut erreichbar (Michael 26.10.); nur beim Drüberfahren sichtbar, Platz bleibt.
            controls(playing: playing)
                .frame(width: cover, height: DesktopMusicLink.controlsHeight)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
        }
        .padding(DesktopMusicLink.pad)
        .contentShape(Rectangle())
        // Ziehen verschiebt das Fenster; ein einfacher Klick aufs Cover bleibt „App nach vorne“.
        .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in onDrag() }.onEnded { _ in onDragEnd() })
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: info?.title ?? ""))
    }

    @ViewBuilder private var artwork: some View {
        if let image = media.artwork {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color(white: 0.15)
                Image(systemName: "music.note").font(.system(size: cover * 0.35)).foregroundStyle(.secondary)
            }
        }
    }

    private func controls(playing: Bool) -> some View {
        HStack(spacing: cover * 0.08) {
            button("backward.fill", label: "Zurück") { media.previous() }
            button(playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Wiedergabe") { media.playPause() }
            button("forward.fill", label: "Weiter") { media.next() }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.55)))
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: max(14, cover * 0.1), weight: .semibold))
                .foregroundStyle(.white).frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    /// Nur eine **schon laufende** App mit dieser Kennung nach vorne holen, nie starten: Die Kennung stammt aus dem
    /// Medienstrom (Fremddaten, G4).
    static func bringToFront(_ bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate()
    }
}
