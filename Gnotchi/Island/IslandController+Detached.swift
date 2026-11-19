import AppKit
import SwiftUI

/// Laufzeit der schwebenden Insel je Bildschirm (0.22.0). Ein Feld im Controller, damit dessen Rumpf unter 350 Zeilen bleibt.
struct DetachedRuntime {
    /// Maus über der schwebenden Insel (SwiftUI-`onHover` des zweiten Panels).
    var inside: [CGDirectDisplayID: Bool] = [:]
    /// Seit dem Aufgehen schon einmal drin – bis dahin gilt der Anlauf `DetachedIsland.grace`.
    var entered: Set<CGDirectDisplayID> = []
    var openedAt: [CGDirectDisplayID: ContinuousClock.Instant] = [:]
    /// Ausblenden nach der Schrumpf-Animation.
    var hideTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    /// Ziehen: Mauslage und Panel-Ursprung beim Start.
    var drag: (mouse: CGPoint, origin: CGPoint)?
    /// Ring-Tasten und Randzugabe der zuletzt gezeigten Insel (0.28.0), für Zuklapp-Fläche und Ziehen.
    var ring: [CGDirectDisplayID: RingLayout] = [:]
}

/// Was die schwebende Insel an den Controller meldet (Ziehen auf freiem Hintergrund, Doppelklick, Esc).
enum DetachedEvent { case dragChanged, dragEnded, reset, escape }

extension IslandController {

    /// Zweites Panel je Bildschirm für groß: gleiche Ebene und Art wie die kleine Insel, nimmt nie den Fokus außer fürs
    /// Namensfeld der Timer-Auswahl (`allowsKey`, Esc nur dann – Entschieden 5, Offen 1).
    func makeBigPanel(state: IslandState, displayID: CGDirectDisplayID) -> IslandPanel {
        let p = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false   // Schatten zeichnet SwiftUI im Rand `pad` (runde Ecken, kein eckiger Fensterschatten)
        p.isMovable = false   // Bewegen steuert Gnotchi selbst, sonst nähme ein Regler das Fenster mit
        p.hidesOnDeactivate = false
        p.onEscape = { [weak self] in self?.detachedEvent(.escape, displayID: displayID) }
        let view = IslandView(state: state,
                              onHover: { [weak self] inside in self?.hoverBig(inside, displayID: displayID) },
                              onOutputMenu: { [weak self] in self?.showOutputMenu(displayID: displayID) },
                              onOpenUpdate: { [weak self] app in self?.openUpdate(app) },
                              onOpenEvent: { [weak self] in self?.openEvent() },
                              detached: true,
                              onDetached: { [weak self] event in self?.detachedEvent(event, displayID: displayID) },
                              onRingAction: { [weak self] b in self?.ringAction(b, displayID: displayID) })
            .environment(activity.media)
            .environment(activity)
        let host = ClickableHostingView(rootView: view)
        host.onContextClick = { [weak self] event, view in self?.showContextMenu(event, in: view, displayID: displayID) }
        host.sizingOptions = []
        p.contentView = host
        return p
    }

    /// Insel-Rechteck und äußeres Rechteck mit Ring (beide ohne Schattenrand) für den aktuellen Inhalt, nil = Bildschirm
    /// nicht mehr da. Der Ring gibt dem Panel seitlich und unten Platz (0.28.0); die Insel bleibt mittig unter der Pille.
    func detachedRects(_ entry: Entry, displayID: CGDirectDisplayID) -> (island: CGRect, outer: CGRect, ring: RingLayout)? {
    // swiftlint:disable:previous large_tuple
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
        let ring = Self.ringLayout(activity)
        let outer = DetachedIsland.frame(compact: entry.state.layout.compact, size: ring.outerSize,
                                         offset: DetachedIsland.offset(), visible: screen.visibleFrame)
        return (DetachedIsland.islandRect(outer: outer, margins: ring.margins), outer, ring)
    }

    /// Schwebende Insel an den Zustand der kleinen angleichen: groß → zeigen (und Lage/Größe nachführen), sonst
    /// schrumpfen lassen und nach der Animation ausblenden.
    func syncBig(_ id: CGDirectDisplayID) {
        guard let e = panels[id] else { return }
        guard e.state.mode == .expanded, let rects = detachedRects(e, displayID: id) else { return hideBig(id) }
        detached.ring[id] = rects.ring
        detached.hideTasks[id]?.cancel()
        detached.hideTasks[id] = nil
        e.big.allowsKey = activity.bigContent == .timerPicker
        if detached.drag == nil {
            let panel = rects.outer.insetBy(dx: -DetachedIsland.pad, dy: -DetachedIsland.pad)
            if e.big.frame != panel { e.big.setFrame(panel, display: true) }
            if e.bigState.mode != .expanded {
                e.bigState.anchor = DetachedIsland.growAnchor(compact: e.state.layout.compact, panel: panel)
            }
        }
        e.big.orderFrontRegardless()
        if e.bigState.mode != .expanded { e.bigState.mode = .expanded }
    }

    func hideBig(_ id: CGDirectDisplayID) {
        guard let e = panels[id], e.bigState.mode != .hidden || e.big.isVisible else { return }
        e.big.allowsKey = false
        detached.inside[id] = false
        guard e.bigState.mode != .hidden else { return e.big.orderOut(nil) }
        e.bigState.mode = .hidden
        detached.hideTasks[id]?.cancel()
        detached.hideTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.animationTail)
            guard !Task.isCancelled, let self, let e = self.panels[id], e.bigState.mode == .hidden else { return }
            e.big.orderOut(nil)
            self.detached.hideTasks[id] = nil
        }
    }

    /// Gerade aufgegangen: Anlauf neu starten.
    func noteOpened(_ id: CGDirectDisplayID) {
        detached.openedAt[id] = .now
        detached.entered.remove(id)
        detached.inside[id] = false
    }

    func hoverBig(_ inside: Bool, displayID id: CGDirectDisplayID) {
        guard !menuOpen.contains(id), let e = panels[id], e.state.mode == .expanded else { return }
        detached.inside[id] = inside
        if inside { detached.entered.insert(id) }
        activity.setRotationPaused(pointerInside.values.contains(true) || detached.inside.values.contains(true))
        collapseTasks[id]?.cancel()
        collapseTasks[id] = nil
        guard !inside, pointerInside[id] != true, !activity.pinned else { return }
        startCollapse(id, shrank: false)
    }

    /// Zuklappen, sobald die Maus die Fläche (kleine Insel, Lücke, große Insel) verlassen hat. Weil die Lücke zu keinem
    /// Panel gehört, meldet dort niemand „Maus rein/raus“ – deshalb fragt die Schleife die Mauslage selbst ab (50 ms).
    /// Klick daneben (neuer Druck außerhalb der Fläche) klappt sofort zu; ein Druck, der schon beim Verlassen lief
    /// (Fortschrittsbalken über den Rand gezogen), zählt nicht und wird wie bisher bis zum Loslassen abgewartet.
    /// Kein Ereignis-Mithörer (G1): nur `NSEvent.mouseLocation`/`pressedMouseButtons`, nur während dieser Schleife (G48).
    func startCollapse(_ id: CGDirectDisplayID, shrank: Bool) {
        collapseTasks[id] = Task { [weak self] in
            let start = ContinuousClock.now
            let delay = Self.collapseDelay(shrankAwayFromPointer: shrank)
            var held = NSEvent.pressedMouseButtons != 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self, let e = self.panels[id] else { return }
                let pressed = NSEvent.pressedMouseButtons != 0
                if held { held = pressed; continue }
                let inZone = DetachedIsland.contains(NSEvent.mouseLocation, self.zones(e, id))
                if pressed && !inZone && e.state.mode == .expanded { break }   // Klick daneben
                guard !inZone, ContinuousClock.now - start >= delay else { continue }
                let opened = self.detached.openedAt[id] ?? start
                guard e.state.mode != .expanded || self.detached.entered.contains(id)
                        || ContinuousClock.now - opened >= DetachedIsland.grace else { continue }
                break
            }
            guard !Task.isCancelled, let self else { return }
            await self.collapse(id)
        }
    }

    private func zones(_ e: Entry, _ id: CGDirectDisplayID) -> [CGRect] {
        let ring = detached.ring[id]
        let island = e.state.mode == .expanded && e.big.isVisible
            ? DetachedIsland.islandRect(outer: e.big.frame.insetBy(dx: DetachedIsland.pad, dy: DetachedIsland.pad),
                                        margins: ring?.margins ?? .zero) : nil
        return DetachedIsland.zones(compact: e.panel.frame, island: island,
                                    ring: island.map { Ring.zones(buttons: ring?.buttons ?? [], island: $0) } ?? [])
    }

    /// Zu wie bisher (`hover`): groß/Band → klein, Animation auslaufen lassen, Panel klein.
    func collapse(_ id: CGDirectDisplayID) async {
        guard let e = panels[id] else { return }
        if e.state.mode == .expanded || e.state.mode == .band {
            activity.endMirror()   // Spiegel nur, solange groß sichtbar (G27)
            e.state.mode = .compact
            hideBig(id)
            try? await Task.sleep(for: Self.animationTail)
        }
        // Auch „klein, Panel noch groß“ verkleinern: Kurz wieder drüber während des Zuklappens und vor
        // Ablauf der Aufklapp-Verzögerung wieder weg – sonst finge das große Panel Menüleisten-Klicks ab.
        guard !Task.isCancelled, e.state.mode == .compact else { return }
        e.panel.setFrame(e.state.layout.compact, display: true)
    }

    func detachedEvent(_ event: DetachedEvent, displayID id: CGDirectDisplayID) {
        guard let e = panels[id] else { return }
        switch event {
        case .dragChanged:
            let mouse = NSEvent.mouseLocation
            let start = detached.drag ?? (mouse, e.big.frame.origin)
            detached.drag = start
            e.big.setFrameOrigin(CGPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                         y: start.origin.y + mouse.y - start.mouse.y))
        case .dragEnded:
            detached.drag = nil
            let island = DetachedIsland.islandRect(outer: e.big.frame.insetBy(dx: DetachedIsland.pad, dy: DetachedIsland.pad),
                                                   margins: detached.ring[id]?.margins ?? .zero)
            DetachedIsland.setOffset(DetachedIsland.offset(island: island, compact: e.state.layout.compact))
            syncBig(id)   // eingerastet bzw. in den sichtbaren Bereich zurück
        case .reset:
            resetDetachedOffset()
        case .escape:
            collapseTasks[id]?.cancel()
            Task { await self.collapse(id) }
        }
    }

    /// Ring-Tasten, die Fenster oder andere Apps öffnen (0.28.0): Einstellungen, Bildschirmfoto. Die übrigen wirken im Modell.
    func ringAction(_ b: RingButton, displayID id: CGDirectDisplayID) {
        switch b {
        case .settings:
            openWindow(AppModel.WindowID.settings)
        case .screenshot:
            // Die Screenshot-App des Systems: Gnotchi bekommt keine Bildschirmaufnahme-Freigabe (G51/Spec A2).
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
            collapseTasks[id]?.cancel()
            Task { await self.collapse(id) }
        case .quickEntry:
            // Schnelleingabe (G61): Insel zu, Zeile aus der Notch auf.
            collapseTasks[id]?.cancel()
            Task { await self.collapse(id) }
            activity.openQuickEntry?()
        default:
            break
        }
    }

    func resetDetachedOffset() {
        DetachedIsland.setOffset(.zero)
        for id in panels.keys { syncBig(id) }
    }
}
