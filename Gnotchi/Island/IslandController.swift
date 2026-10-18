import AppKit
import SwiftUI

/// Ein Panel je Bildschirm. Ohne Fokus, über der Menüleiste und über normalen Fenstern.
/// Das Panel ist immer nur so groß wie der sichtbare Zustand (klein oder groß), damit die
/// Menüleiste daneben klickbar bleibt; im Zustand „unsichtbar“ ist es weg und lässt Klicks durch.
@MainActor
final class IslandController {

    /// Ein Fenster aus der Fensterliste: nur Ebene, Lage, ob es einer normalen App gehört, und die PID.
    struct WindowInfo: Equatable {
        let layer: Int
        let bounds: CGRect
        let isRegularApp: Bool
        var pid: pid_t = 0
    }

    /// Zweite Prüfung, bevor der Hinweis erscheint (kurz aufblitzende Fenster lösen nichts aus).
    private static let competitorConfirmDelay: Duration = .milliseconds(1500)

    private struct Entry {
        let panel: NSPanel
        let state: IslandState
    }

    private let model: NowPlayingModel
    private var panels: [CGDirectDisplayID: Entry] = [:]
    /// Getrennt nach Zentrum: Ein Token lässt sich nur dort abmelden, wo es angemeldet wurde.
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Je Bildschirm: Sonst bräche das Aufgehen auf Bildschirm B das Zuklappen auf A ab.
    private var collapseTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    /// Je Bildschirm: Aufklappen erst nach der gewählten Verzögerung (Preferences.expandDelay).
    private var expandTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    /// Je Bildschirm: Ist die Maus gerade über der Insel? Gilt nach Ablauf der Verzögerung.
    private var pointerInside: [CGDirectDisplayID: Bool] = [:]
    /// Aufklapp-Verzögerung in Sekunden, bei jedem Überfahren neu gelesen (Einstellung wirkt sofort).
    private let expandDelay: @MainActor () -> TimeInterval
    private var spaceRecheck: Task<Void, Never>?
    /// Läuft, solange ein gefundener Konkurrent auf die bestätigende zweite Prüfung wartet.
    private var competitorCheck: Task<Void, Never>?
    /// Kandidat, für den `competitorCheck` gerade die Bestätigung abwartet.
    private var pendingCompetitor: String?
    private var screenDebounce: Task<Void, Never>?
    private var running = false
    /// Zählt Starts: Eine Beobachtung aus einem früheren Lauf meldet sich nach stop()/start() nicht neu an.
    private var generation = 0

    /// Wie lange die Maus weg sein muss, bevor die Insel zuklappt, und wie lange die Animation läuft.
    private static let collapseDelay: Duration = .milliseconds(300)
    private static let animationTail: Duration = .milliseconds(350)
    /// Bildschirm-Änderungen kommen oft in Salven (Anstecken, Auflösung, Menüleiste ein/aus) – sammeln.
    private static let screenDebounceDelay: Duration = .milliseconds(300)

    init(model: NowPlayingModel, expandDelay: @escaping @MainActor () -> TimeInterval = { 0 }) {
        self.model = model
        self.expandDelay = expandDelay
    }

    func start() {
        guard !running else { return }
        running = true
        generation += 1
        rebuild()
        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        })
        let ws = NSWorkspace.shared.notificationCenter
        // Space-Wechsel, App gestartet oder beendet: jetzt prüfen und nach dem Einschwingen noch einmal.
        // Start/Ende, damit der Hinweis auf eine zweite Notch-App kommt bzw. verschwindet, wenn sie endet.
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAndRecheck() }
            })
        }
        workspaceObservers.append(ws.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observeModel(generation: generation)
    }

    func stop() {
        guard running else { return }
        running = false
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appObservers.removeAll()
        workspaceObservers.removeAll()
        cancelTasks()
        panels.values.forEach { $0.panel.orderOut(nil) }
        panels.removeAll()
        model.setCompetingNotchApp(nil)
        model.setIslandShown(false)
    }

    /// Von außen (Einstellungen öffnen): Zustand und Hinweis neu prüfen.
    func recheck() {
        guard running else { return }
        refresh()
    }

    // MARK: Reine Rechnungen (getestet)

    /// AppKit (Ursprung unten links am Hauptbildschirm) → CGWindow-Koordinaten (Ursprung oben links).
    nonisolated static func cgWindowRect(fromAppKit r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Vollbild-App auf diesem Bildschirm: ein Fenster auf Ebene 0 einer normalen App, volle Breite,
    /// unten bündig, oben am Rand – oder mit Notch höchstens `topInset + 2` pt darunter. Gemessen 18.10.
    /// (MacBook Air M5, macOS 27.0.1): Vollbild beginnt auf Notch-Bildschirmen UNTER Notch/Menüleiste
    /// (0, 33, 1470 × 923), nicht am Rand. Ohne Notch (`topInset` 0) gilt nur der ganze Rahmen.
    /// Bekannte Grenze: maximiert bei ausgeblendetem Dock hat auf Notch-Bildschirmen dieselbe Lage wie
    /// Vollbild → die Insel blendet dann aus (hingenommen). Maximiert mit Dock endet unten früher und zählt nicht.
    /// Nur normale Apps: Seams Abdunkel-Fenster liegt ebenfalls auf Ebene 0 und deckt den Bildschirm
    /// exakt ab (gemessen 18.10.) – ohne diese Bedingung verschwände die Insel bei jedem Abdunkeln.
    /// Koordinaten: CGWindow (Ursprung oben links), 1 pt Toleranz für Rundung.
    nonisolated static func coversScreen(windows: [WindowInfo], target: CGRect, topInset: CGFloat) -> Bool {
        windows.contains { w in
            let b = w.bounds
            let top = b.minY - target.minY
            let topOK = abs(top) <= 1 || (topInset > 0 && top >= 0 && top <= topInset + 2)
            return w.layer == 0 && w.isRegularApp && topOK
                && abs(b.minX - target.minX) <= 1 && abs(b.width - target.width) <= 1
                && abs(b.maxY - target.maxY) <= 1
        }
    }

    /// Fensterliste → Ebene, Lage, normale App. Liest aus jedem Eintrag NUR Prozessnummer, Ebene und Lage
    /// (SECURE-DESIGN G10) – nie Namen oder Titel. Mit der PID erkennt Gnotchi normale Apps; den Namen
    /// einer zweiten Notch-App holt es nur über NSRunningApplication(PID), nie aus der Fensterliste.
    /// Eigene Fenster zählen nie als normale App. `isRegular` wird je Prozess nur einmal gefragt.
    nonisolated static func windows(from list: [[String: Any]], ownPID: pid_t,
                                    isRegular: (pid_t) -> Bool) -> [WindowInfo] {
        var cache: [pid_t: Bool] = [:]
        return list.compactMap { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            let regular: Bool
            if pid == ownPID {
                regular = false
            } else if let known = cache[pid] {
                regular = known
            } else {
                regular = isRegular(pid)
                cache[pid] = regular
            }
            return WindowInfo(layer: layer, bounds: bounds, isRegularApp: regular, pid: pid)
        }
    }

    /// Nach der Verzögerung aufklappen? Nur wenn die Maus noch über der Insel ist, keine Taste gedrückt
    /// ist (Fenster an den oberen Rand ziehen, Spezifikation) und die Insel klein ist (nicht weg, nicht schon groß).
    nonisolated static func shouldExpand(stillInside: Bool, mouseDown: Bool, mode: IslandState.Mode) -> Bool {
        stillInside && !mouseDown && mode == .compact
    }

    /// Neu aufbauen nur, wenn sich Bildschirme oder deren Inselmaße wirklich geändert haben.
    nonisolated static func layoutsChanged(old: [CGDirectDisplayID: IslandGeometry.Layout],
                                           new: [CGDirectDisplayID: IslandGeometry.Layout]) -> Bool {
        old != new
    }

    /// Panelgröße je Zustand; nil = Panel ist weg.
    nonisolated static func panelFrame(mode: IslandState.Mode, layout: IslandGeometry.Layout) -> CGRect? {
        switch mode {
        case .hidden: nil
        case .compact: layout.compact
        case .expanded: layout.expanded
        }
    }

    // MARK: Ablauf

    /// Beobachtet `isVisible`. `withObservationTracking` meldet nur die erste Änderung,
    /// danach wird neu angemeldet – aber nur, solange derselbe Lauf aktiv ist.
    private func observeModel(generation gen: Int) {
        withObservationTracking {
            _ = model.isVisible
        } onChange: { [weak self] in
            // onChange kommt VOR dem Setzen des neuen Werts – deshalb erst im nächsten Durchlauf lesen.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.running, self.generation == gen else { return }
                    self.refresh()
                    self.observeModel(generation: gen)
                }
            }
        }
    }

    private func cancelTasks() {
        collapseTasks.values.forEach { $0.cancel() }
        collapseTasks.removeAll()
        expandTasks.values.forEach { $0.cancel() }
        expandTasks.removeAll()
        pointerInside.removeAll()
        spaceRecheck?.cancel()
        spaceRecheck = nil
        competitorCheck?.cancel()
        competitorCheck = nil
        pendingCompetitor = nil
        screenDebounce?.cancel()
        screenDebounce = nil
    }

    private static func currentLayouts() -> [CGDirectDisplayID: IslandGeometry.Layout] {
        var result: [CGDirectDisplayID: IslandGeometry.Layout] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            result[id] = IslandGeometry.layout(for: IslandGeometry.metrics(of: screen))
        }
        return result
    }

    private func screenParametersChanged() {
        screenDebounce?.cancel()
        screenDebounce = Task { [weak self] in
            try? await Task.sleep(for: Self.screenDebounceDelay)
            guard !Task.isCancelled, let self, self.running else { return }
            let new = Self.currentLayouts()
            if Self.layoutsChanged(old: self.panels.mapValues { $0.state.layout }, new: new) {
                self.rebuild(layouts: new)
            } else {
                self.refresh()
            }
        }
    }

    /// Bildschirme dazu/weg, Auflösung geändert: alle Panels neu, Maße frisch gemessen.
    private func rebuild(layouts: [CGDirectDisplayID: IslandGeometry.Layout] = currentLayouts()) {
        cancelTasks()
        panels.values.forEach { $0.panel.orderOut(nil) }
        panels.removeAll()
        for (id, layout) in layouts {
            let state = IslandState(layout: layout)
            panels[id] = Entry(panel: makePanel(state: state, displayID: id), state: state)
        }
        refresh()
    }

    private func makePanel(state: IslandState, displayID: CGDirectDisplayID) -> NSPanel {
        let p = NSPanel(contentRect: state.layout.compact, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        // Über der Menüleiste; Gnotchi hat keinen eigenen Abdunkler wie Seam, normale Fenster reichen als Untergrenze.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.ignoresMouseEvents = true
        // Bei .nonactivatingPanel ab Werk schon false (gemessen 18.10.), bei anderen Panel-Stilen true – ausdrücklich
        // gesetzt, damit ein geänderter styleMask die Insel nicht beim App-Wechsel verschwinden lässt.
        p.hidesOnDeactivate = false
        let view = IslandView(state: state) { [weak self] inside in self?.hover(inside, displayID: displayID) }
            .environment(model)
        let host = ClickableHostingView(rootView: view)
        // Die Größe bestimmt der Controller (setFrame), nicht der SwiftUI-Inhalt.
        host.sizingOptions = []
        p.contentView = host
        return p
    }

    private func refreshAndRecheck() {
        refresh()
        spaceRecheck?.cancel()
        spaceRecheck = Task { [weak self] in
            var elapsed: Duration = .zero
            for delay in Self.recheckDelays {
                try? await Task.sleep(for: delay - elapsed)
                elapsed = delay
                guard !Task.isCancelled, let self, self.running else { return }
                self.refresh()
            }
        }
    }

    /// Sichtbarkeit je Bildschirm: Musik läuft, und auf diesem Bildschirm ist keine App im Vollbild.
    /// Im selben Durchgang: zeichnet eine zweite Notch-App über unserer Fläche? (Nur bei sichtbarer Insel –
    /// sonst läuft keine Fensterliste, und ohne Insel gibt es auch keinen Konflikt.)
    private func refresh() {
        let windows = model.isVisible ? Self.onScreenWindows() : []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        updateCompetitor(model.isVisible ? competitor(in: windows) : nil)
        defer { model.setIslandShown(panels.values.contains { $0.state.mode != .hidden }) }
        for (id, entry) in panels {
            let screen = NSScreen.screens.first { $0.displayID == id }
            let fullscreen = screen.map {
                Self.coversScreen(windows: windows,
                                  target: Self.cgWindowRect(fromAppKit: $0.frame, primaryHeight: primaryHeight),
                                  topInset: entry.state.layout.notch?.height ?? 0)
            } ?? false
            if !model.isVisible || fullscreen {
                entry.state.mode = .hidden
                entry.panel.ignoresMouseEvents = true
                entry.panel.orderOut(nil)
                continue
            }
            if entry.state.mode == .hidden { entry.state.mode = .compact }
            entry.panel.ignoresMouseEvents = false
            if let f = Self.panelFrame(mode: entry.state.mode, layout: entry.state.layout) {
                entry.panel.setFrame(f, display: true)
            }
            entry.panel.orderFrontRegardless()
        }
    }

    /// Konkurrent in dieser Fensterliste (Notch bzw. Pille jedes Bildschirms).
    private func competitor(in windows: [WindowInfo]) -> String? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let targets: [NotchTarget] = panels.compactMap { id, entry in
            guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return nil }
            return NotchTarget(
                notch: Self.cgWindowRect(fromAppKit: entry.state.layout.notch ?? entry.state.layout.compact,
                                         primaryHeight: primaryHeight),
                screen: Self.cgWindowRect(fromAppKit: screen.frame, primaryHeight: primaryHeight))
        }
        return Self.competingNotchApp(windows: windows, ownPID: ProcessInfo.processInfo.processIdentifier,
                                      targets: targets, app: Self.otherApp)
    }

    /// Kein Konkurrent → Hinweis sofort weg. Neuer Konkurrent → erst nach bestätigender zweiter Prüfung;
    /// taucht währenddessen eine andere App auf, bekommt sie ihre eigene Bestätigung.
    private func updateCompetitor(_ candidate: String?) {
        guard let candidate else {
            competitorCheck?.cancel()
            competitorCheck = nil
            pendingCompetitor = nil
            model.setCompetingNotchApp(nil)
            return
        }
        guard Self.needsConfirmation(candidate: candidate, shown: model.competingNotchApp,
                                     pending: pendingCompetitor) else { return }
        competitorCheck?.cancel()
        pendingCompetitor = candidate
        competitorCheck = Task { [weak self] in
            try? await Task.sleep(for: Self.competitorConfirmDelay)
            guard !Task.isCancelled, let self, self.running else { return }
            self.competitorCheck = nil
            self.pendingCompetitor = nil
            let second = self.model.isVisible ? self.competitor(in: Self.onScreenWindows()) : nil
            self.model.setCompetingNotchApp(Self.confirmedCompetitor(first: candidate, second: second))
        }
    }

    private func hover(_ inside: Bool, displayID: CGDirectDisplayID) {
        guard let entry = panels[displayID], entry.state.mode != .hidden else { return }
        pointerInside[displayID] = inside
        collapseTasks[displayID]?.cancel()
        collapseTasks[displayID] = nil
        // Maus vor Ablauf der Verzögerung wieder weg: nicht aufklappen.
        expandTasks[displayID]?.cancel()
        expandTasks[displayID] = nil
        if inside {
            guard entry.state.mode == .compact else { return }
            let delay = expandDelay()
            guard delay > 0 else { return expandIfStillInside(displayID) }
            expandTasks[displayID] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.expandIfStillInside(displayID)
            }
            return
        }
        collapseTasks[displayID] = Task { [weak self] in
            try? await Task.sleep(for: Self.collapseDelay)
            // Zieht man den Fortschrittsbalken über den Inselrand hinaus, nicht mitten im Ziehen zuklappen
            // (das Ende des Ziehens und damit das Spulen ginge verloren) – erst nach dem Loslassen.
            while !Task.isCancelled, NSEvent.pressedMouseButtons != 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            // Ist die Insel inzwischen weg, bleibt sie weg.
            guard !Task.isCancelled, let self, let e = self.panels[displayID] else { return }
            if e.state.mode == .expanded {
                e.state.mode = .compact
                try? await Task.sleep(for: Self.animationTail)   // Animation auslaufen lassen, dann Panel verkleinern
            }
            // Auch „klein, Panel noch groß“ verkleinern: Kurz wieder drüber während des Zuklappens und vor
            // Ablauf der Aufklapp-Verzögerung wieder weg – sonst finge das große Panel Menüleisten-Klicks ab.
            guard !Task.isCancelled, e.state.mode == .compact else { return }
            e.panel.setFrame(e.state.layout.compact, display: true)
        }
    }

    private func expandIfStillInside(_ displayID: CGDirectDisplayID) {
        expandTasks[displayID] = nil
        guard let e = panels[displayID],
              Self.shouldExpand(stillInside: pointerInside[displayID] == true,
                                mouseDown: NSEvent.pressedMouseButtons != 0, mode: e.state.mode) else { return }
        // Erst das Panel groß, dann der Zustand: sonst schnitte das kleine Panel die Animation ab.
        e.panel.setFrame(e.state.layout.expanded, display: true)
        e.state.mode = .expanded
    }

    /// Name, Bundle-ID, Bundle-Pfad und Art einer fremden App – nur über NSRunningApplication(PID) aus dem
    /// lokalen Bundle, nie aus der Fensterliste.
    private static func otherApp(_ pid: pid_t) -> OtherApp? {
        guard let a = NSRunningApplication(processIdentifier: pid) else { return nil }
        return OtherApp(name: a.localizedName, bundleID: a.bundleIdentifier, bundlePath: a.bundleURL?.path,
                        isAccessory: a.activationPolicy == .accessory)
    }

    /// Ebene, Lage und Eigentümer-Art aller sichtbaren Fenster. Ohne Bildschirmaufnahme-Freigabe liefert
    /// macOS keine Fenstertitel – Gnotchi liest aus der Fensterliste bewusst nur Prozessnummer, Ebene und
    /// Lage (keine Titel, keine App-Namen), braucht also keine Freigabe und erfährt nichts über Fensterinhalte.
    /// Den Namen einer zweiten Notch-App holt es nur über NSRunningApplication(PID) (`otherApp`).
    private static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return windows(from: list, ownPID: ProcessInfo.processInfo.processIdentifier) { pid in
            NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
        }
    }
}

/// `acceptsFirstMouse` ist ab Werk false; vorsorglich gesetzt, damit die Tasten auf den ersten Klick
/// reagieren, obwohl das Panel nie Key wird (Tippi-Muster).
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
