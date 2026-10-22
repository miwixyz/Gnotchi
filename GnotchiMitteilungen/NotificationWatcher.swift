import AppKit
import ApplicationServices
import OSLog

/// Liest Apples Mitteilungsbanner über die Bedienungshilfen (0.6.0, SECURE-DESIGN G28). **Einziges** Gnotchi-Teil mit
/// AX-Zugriff. Beobachtet nur den Prozess `com.apple.notificationcenterui`; schreibt nur zwei Dinge: die Position
/// des Banner-Fensters (verstecken/zurück) und eine von macOS gemeldete Aktion an genau einem Banner. Keine
/// Eingaben, keine Event-Taps, keine anderen Apps, keine Prozesse, kein Netz.
///
/// Gemessen 22.10. (macOS 27.0.1): Fenster `AXSystemDialog` → … → Element mit Unterrolle
/// `AXNotificationCenterBanner`/`…Alert`, Kennung UUID bzw. `FACETIME_NOTIFICATION` (Anruf). Texte als
/// `AXStaticText` mit Kennung `title`/`subtitle`/`body`/`summary-text`. Knöpfe = benannte Aktionen am Banner, beim
/// Anruf echte `AXButton`. Das Banner-Fenster lässt sich per `AXPosition` verschieben und zurückholen.
@MainActor
final class NotificationWatcher {

    struct Filter: Equatable {
        var apps: Set<String> = []
        var calls = false
    }

    private static let log = Logger(subsystem: NotifyWire.helperBundleID, category: "watcher")
    private static let centerBundleID = "com.apple.notificationcenterui"
    private static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    /// Geöffnete Mitteilungszentrale: dann nichts anfassen, alles zurück (Liste sind alte Mitteilungen).
    private static let panelSubrole = "AXNotificationCenterPanel"
    private static let maxNodes = 400
    private static let maxDepth = 14
    private static let hidden = CGPoint(x: -10_000, y: -10_000)

    /// `nil` bis Gnotchi den Filter geschickt hat: bis dahin wird nichts gemeldet (G29).
    var filter: Filter? {
        didSet { if filter != oldValue { resetReported(); scan() } }
    }
    var onNote: (NotifyWire.Note) -> Void = { _ in }
    var onGone: (String) -> Void = { _ in }

    private struct Found {
        let banner: AXUIElement
        let window: AXUIElement
        let subrole: String
    }

    private var pid: pid_t = 0
    private var appElement: AXUIElement?
    private var observer: AXObserver?
    private var observedWindows: [AXUIElement] = []
    private var present: [String: Found] = [:]
    /// An Gnotchi gemeldet (und noch sichtbar).
    private var reported: Set<String> = []
    /// Gesehen, aber nicht ausgewählt/nicht lesbar – bis es verschwindet, nicht neu prüfen.
    private var ignored: Set<String> = []
    /// Gnotchi zeigt es gerade an → darf versteckt werden.
    private var shown: Set<String> = []
    /// Schon einmal in Gnotchi gezeigt (0.9.0, Michael 22.10. „B“): Solche Hinweise dürfen **während eines Anrufs** mit
    /// Apples Fenster weg – sie kommen danach zurück. Nur Kennungen, weg sobald das Banner weg ist.
    private var everShown: Set<String> = []
    /// Banner, deren Inhalt noch nicht steht (seit wann). Gemessen 22.10.: Ein Anruf-Banner ist in der ersten
    /// Zehntelsekunde leer, Knöpfe und Anrufer kommen ~1,4 s später – ohne neuen Versuch blieb die Notch leer.
    private var pending: [String: Date] = [:]
    private static let readableWithin: TimeInterval = 3
    private var parked: [(window: AXUIElement, origin: CGPoint)] = []
    private var poll: Timer?
    private var scanScheduled = false
    private let reader = BannerReader()
    /// Zuletzt gemeldeter Anruf – um geänderte Knöpfe zu erkennen.
    private var lastCall: NotifyWire.Note?
    /// Eigenes „Ablehnen“ mit Folgeaktion (0.9.0, G30 erweitert): Kennung + Zeitpunkt. Höchstens einer, verfällt nach
    /// `NotifyWire.followUpWindow`.
    private var followUpPending: (id: String, at: Date)?
    /// Folgeaktion gerade ausgeführt: Der nächste Durchgang liest oft noch den Mailbox-Zustand – ohne diese Marke gab
    /// `followCall` Apples (gleich leeres) Fenster für 0,5 s frei (Sichttest 22.10., 15:13:27). Gilt 3 s.
    private var followUpDone: (id: String, at: Date)?

    // MARK: Start/Stopp

    func start() {
        guard appElement == nil else { return }
        guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: Self.centerBundleID).first else {
            Self.log.error("Mitteilungszentrale läuft nicht")
            return startPolling()
        }
        pid = center.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        appElement = element
        recoverParkedWindows(element)
        installObserver()
        startPolling()
        scan()
        Self.log.notice("Beobachtung gestartet")
    }

    /// Alles Versteckte zurück, Beobachtung aus. Auch beim Beenden (SIGTERM, Gnotchi getrennt).
    func stop() {
        restoreAll()
        poll?.invalidate()
        poll = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedWindows = []
        appElement = nil
        present = [:]
        reported = []
        ignored = []
        shown = []
        everShown = []
        pending = [:]
        followUpPending = nil
        followUpDone = nil
    }

    /// Sicherheitsnetz: Ereignisse der Mitteilungszentrale kommen nicht immer (neues Fenster, Neustart des
    /// Prozesses). 1 s Abstand; ein Durchgang sind wenige AX-Abfragen an einen Prozess.
    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.tick() }
        }
    }

    private func tick() {
        if appElement == nil || NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true {
            restartIfCenterChanged()
        }
        scan()
    }

    private func restartIfCenterChanged() {
        guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: Self.centerBundleID).first,
              center.processIdentifier != pid || appElement == nil else { return }
        stop()   // Filter bleibt
        start()
    }

    // MARK: Beobachter

    private func installObserver() {
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue()
            // Quelle hängt an der Hauptschleife → Rückruf auf dem Hauptthread.
            MainActor.assumeIsolated { watcher.scheduleScan() }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs, let appElement else {
            return Self.log.error("Beobachter nicht angelegt – nur Abfrage im Sekundentakt")
        }
        observer = obs
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(obs, appElement, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    private func observeWindows(_ windows: [AXUIElement]) {
        guard let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for w in windows where !observedWindows.contains(where: { CFEqual($0, w) }) {
            for n in [kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXLayoutChangedNotification] {
                AXObserverAddNotification(observer, w, n as CFString, refcon)
            }
            observedWindows.append(w)
        }
        observedWindows.removeAll { o in !windows.contains { CFEqual($0, o) } }
    }

    private func scheduleScan(after delay: TimeInterval = 0.05) {
        guard !scanScheduled else { return }
        scanScheduled = true
        // Kurz sammeln: Ein neues Banner meldet mehrere Ereignisse, und die Texte stehen erst danach.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { [weak self] in
                self?.scanScheduled = false
                self?.scan()
            }
        }
    }

    // MARK: Abtasten

    private func scan() {
        guard let appElement else { return }
        let windows = AXQuery.children(appElement, kAXWindowsAttribute)
            .filter { AXQuery.string($0, kAXSubroleAttribute) == "AXSystemDialog" }
        observeWindows(windows)
        let (found, panelOpen) = collectBanners(in: windows)
        present = found
        if panelOpen {
            // Nutzer schaut in die Mitteilungszentrale: alte Mitteilungen sind keine neuen.
            restoreAll()
            for id in reported { onGone(id) }
            reported = []
            shown = []
            ignored = Set(found.keys)
            return
        }
        for id in reported where found[id] == nil {
            reported.remove(id)
            shown.remove(id)
            onGone(id)
        }
        ignored.formIntersection(found.keys)
        pending = pending.filter { found[$0.key] != nil }
        if let filter { captureNew(found, filter) }
        runFollowUp(found)
        followCall(found)
        releaseAfterFollowUp(found)
        updateParking()
    }

    /// Neue Banner lesen. Noch leer → bis `readableWithin` alle 0,2 s erneut; danach (oder nicht ausgewählt) übergehen.
    /// Protokoll nur Art, Zahl der Knöpfe und Wartezeit – nie Inhalte (G29).
    private func captureNew(_ found: [String: Found], _ filter: Filter) {
        for (id, f) in found where !reported.contains(id) && !ignored.contains(id) {
            let since = pending[id] ?? Date()
            let waited = Int(Date().timeIntervalSince(since) * 1000)
            guard let note = capture(id: id, f) else {
                if Date().timeIntervalSince(since) < Self.readableWithin {
                    pending[id] = since
                    scheduleScan(after: 0.2)
                } else {
                    pending[id] = nil
                    ignored.insert(id)
                    Self.log.notice("Banner nach \(waited, privacy: .public) ms nicht lesbar – bleibt bei Apple")
                }
                continue
            }
            pending[id] = nil
            guard allowed(note, filter) else {
                ignored.insert(id)
                continue
            }
            reported.insert(id)
            if note.kind == .call { lastCall = note }
            onNote(note)
            Self.log.notice("Gemeldet: \(note.kind.rawValue, privacy: .public), \(note.actions.count, privacy: .public) Knöpfe, nach \(waited, privacy: .public) ms")
        }
    }

    /// Alle Banner der Fenster (begrenzt: Knoten, Tiefe), dazu: ist die Mitteilungszentrale geöffnet?
    private func collectBanners(in windows: [AXUIElement]) -> (found: [String: Found], panelOpen: Bool) {
        var found: [String: Found] = [:]
        var panelOpen = false
        for w in windows {
            var nodes = 0
            var stack: [(AXUIElement, Int)] = [(w, 0)]
            while let (e, depth) = stack.popLast(), nodes < Self.maxNodes {
                nodes += 1
                let subrole = AXQuery.string(e, kAXSubroleAttribute)
                if subrole == Self.panelSubrole { panelOpen = true }
                if Self.bannerSubroles.contains(subrole) {
                    let id = AXQuery.string(e, kAXIdentifierAttribute)
                    if NotifyWire.isValidID(id) { found[id] = Found(banner: e, window: w, subrole: subrole) }
                    continue   // Inhalt erst beim Erfassen lesen
                }
                if depth < Self.maxDepth { stack.append(contentsOf: AXQuery.children(e).map { ($0, depth + 1) }) }
            }
        }
        return (found, panelOpen)
    }

    private func allowed(_ note: NotifyWire.Note, _ f: Filter) -> Bool {
        switch note.kind {
        case .call: f.calls
        case .note: note.bundle.map { f.apps.contains($0) } ?? false
        }
    }

    private func resetReported() {
        for id in reported { onGone(id) }
        reported = []
        shown = []
        ignored = []
        updateParking()
    }

    // MARK: Erfassen

    private func capture(id: String, _ f: Found) -> NotifyWire.Note? {
        id == NotifyWire.callIdentifier ? reader.call(id: id, f.banner) : reader.note(id: id, f.banner)
    }

    // MARK: Befehle von Gnotchi (G30)

    func markShown(_ id: String) {
        guard reported.contains(id) else { return }
        shown.insert(id)
        everShown.insert(id)
        updateParking()
    }

    func release(_ id: String) {
        shown.remove(id)
        updateParking()
    }

    /// Nur an einem gerade sichtbaren, gemeldeten Banner und nur eine Aktion, die macOS **jetzt** dafür meldet.
    func perform(id: String, action: String, stopVoicemail: Bool = false) {
        guard reported.contains(id), let f = present[id] else {
            return Self.log.notice("Aktion verworfen: Mitteilung nicht mehr da")
        }
        let result: AXError
        if action == NotifyWire.openAction {
            result = AXUIElementPerformAction(f.banner, kAXPressAction as CFString)
        } else if id == NotifyWire.callIdentifier {
            guard NotifyWire.callActions.contains(action), let button = findButton(in: f.banner, matching: [action]) else {
                return Self.log.notice("Aktion verworfen: Knopf nicht gefunden")
            }
            result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            // Folgeaktion nur nach genau diesem, gerade ausgeführten Ablehnen (G30 erweitert).
            followUpPending = stopVoicemail && result == .success && NotifyWire.declineActions.contains(action)
                ? (id, Date()) : nil
        } else {
            guard !NotifyWire.hiddenActions.contains(action),
                  let raw = AXQuery.actions(f.banner).first(where: { $0.name == action })?.raw else {
                return Self.log.notice("Aktion verworfen: nicht gemeldet")
            }
            result = AXUIElementPerformAction(f.banner, raw as CFString)
        }
        // Aktionsname ist eine Beschriftung von macOS („Annehmen“, „Erledigt“), kein Inhalt.
        Self.log.notice("Aktion „\(NotifyWire.logLabel(action), privacy: .public)“ ausgeführt (AXError \(result.rawValue, privacy: .public))")
        // Anruf: Gnotchi zeigt den nächsten Zustand (Mailbox) weiter – Apples Banner bleibt versteckt; followCall gibt es
        // im Gespräch/bei unbekanntem Zustand frei. Mitteilung: zurück (sie ist bei Apple erledigt oder geöffnet).
        if id != NotifyWire.callIdentifier { shown.remove(id) }
        updateParking()
        scheduleScan()
    }

    private func findButton(in banner: AXUIElement, matching descriptions: Set<String>) -> AXUIElement? {
        var stack = AXQuery.children(banner)
        var nodes = 0
        while let e = stack.popLast(), nodes < 80 {
            nodes += 1
            if AXQuery.string(e, kAXRoleAttribute) == kAXButtonRole as String,
               descriptions.contains(AXQuery.string(e, kAXDescriptionAttribute)) {
                return e
            }
            stack.append(contentsOf: AXQuery.children(e))
        }
        return nil
    }

    // MARK: Verstecken (G28, fail-open)

    /// Ein Fenster wird nur versteckt, wenn **alle** seine Banner gerade in Gnotchi zu sehen sind – sonst
    /// verschwände eine nicht ausgewählte Mitteilung mit. Ohne Banner → zurück (Mitteilungszentrale muss gehen).
    /// Ausnahme Anruf (0.9.0, „B“): Zeigt Gnotchi gerade den Anruf, dürfen Banner mit, die Gnotchi früher schon gezeigt
    /// hat (z. B. eine stehengebliebene Kalender-Erinnerung) – nach dem Anruf ist das Fenster wieder da.
    private func updateParking() {
        everShown.formIntersection(present.keys)
        var groups: [(window: AXUIElement, ids: [String])] = []
        for (id, f) in present {
            if let i = groups.firstIndex(where: { CFEqual($0.window, f.window) }) {
                groups[i].ids.append(id)
            } else {
                groups.append((f.window, [id]))
            }
        }
        for g in groups {
            let park = NotifyWire.mayHideWindow(ids: g.ids, shown: shown, everShown: everShown)
            let isParked = parked.contains { CFEqual($0.window, g.window) }
            if park && !isParked { hide(g.window) }
            if !park && isParked { restore(g.window) }
        }
        for p in parked where !groups.contains(where: { CFEqual($0.window, p.window) }) {
            restore(p.window)
        }
    }

    private func hide(_ window: AXUIElement) {
        guard let origin = AXQuery.point(window, kAXPositionAttribute) else { return }
        guard AXQuery.setPoint(window, kAXPositionAttribute, Self.hidden) == .success else {
            return Self.log.error("Verstecken fehlgeschlagen")
        }
        parked.append((window, origin))
    }

    private func restore(_ window: AXUIElement) {
        guard let i = parked.firstIndex(where: { CFEqual($0.window, window) }) else { return }
        let origin = parked.remove(at: i).origin
        let result = AXQuery.setPoint(window, kAXPositionAttribute, origin)
        // Gemessen 22.10.: Läuft Apples letztes Banner ab, löscht macOS das Fenster selbst – dann gibt es nichts zurückzuholen.
        if result != .success && result != .invalidUIElement {
            Self.log.error("Zurückholen fehlgeschlagen (AXError \(result.rawValue, privacy: .public))")
        }
    }

    /// Wurde das Hilfsprogramm hart beendet (SIGKILL, Absturz), während ein Fenster versteckt war, stünde es weiter
    /// bei −10000 – bei einer dauerhaften Mitteilung (Erinnerung) bliebe sie unsichtbar. Beim Start zurück auf den
    /// gemessenen Platz (0,0), Review 22.10.
    private func recoverParkedWindows(_ app: AXUIElement) {
        for w in AXQuery.children(app, kAXWindowsAttribute) where AXQuery.point(w, kAXPositionAttribute) == Self.hidden {
            if AXQuery.setPoint(w, kAXPositionAttribute, .zero) == .success {
                Self.log.notice("Verstecktes Fenster aus einem früheren Lauf zurückgeholt")
            }
        }
    }

    func restoreAll() {
        for p in parked { _ = AXQuery.setPoint(p.window, kAXPositionAttribute, p.origin) }
        parked = []
    }
}

// Anruf verfolgen und Folgeaktion (0.6.0/0.9.0) – als Erweiterung, Klassenrumpf ≤ 350 Zeilen.
extension NotificationWatcher {
    /// Nach Annehmen wird dasselbe Banner zur Gesprächsleiste mit neuen Knöpfen (gemessen 22.10., ~5 s nach dem Klick).
    /// Deshalb einen gemeldeten Anruf bei jedem Durchgang neu lesen und Änderungen melden. Anrufer und Anrufart vom
    /// Klingeln behalten – an deren Stelle steht im Gespräch „Von deinem iPhone – 0:00“.
    ///
    /// 0.9.0: Apples Anruf-Banner bleibt nur beim Klingeln versteckt. Zurück kommt es: beim Mitlesen (die Abschrift
    /// steht nur in Apples Fenster – Review 22.10.; außer Gnotchi stoppt gleich selbst, sonst blitzte es kurz auf), im
    /// Gespräch (Apples Leiste hat Stumm, Ziffernblock …) und bei unbekanntem Zustand (keine bekannten Knöpfe, andere
    /// Sprache) – fail-open, Gnotchi zeigt dann „in macOS beantworten“ (leere Knopfliste).
    private func followCall(_ found: [String: Found]) {
        let id = NotifyWire.callIdentifier
        guard reported.contains(id), let f = found[id], let last = lastCall else { return }
        let actions = reader.call(id: id, f.banner)?.actions ?? []
        guard actions != last.actions else { return }
        let next = NotifyWire.Note(id: id, kind: .call, app: last.app, bundle: nil, title: last.title, subtitle: "",
                                   body: "", actions: actions)
        lastCall = next
        let justStopped = followUpDone.map { $0.id == id && Date().timeIntervalSince($0.at) < 3 } ?? false
        let stoppingSoon = followUpPending?.id == id || justStopped
        if (actions.isEmpty && !justStopped) || NotifyWire.isOngoing(next) || (NotifyWire.isScreening(next) && !stoppingSoon) {
            shown.remove(id)
        }
        onNote(next)
        Self.log.notice("Anruf geändert: Knöpfe \(actions.joined(separator: ", "), privacy: .public)")
    }

    /// Sicherung (fail-open): Steht das Anruf-Banner 3 s nach der Folgeaktion noch da, kommt Apples Fenster zurück –
    /// sonst bliebe ein Anruf versteckt, den Gnotchi nach Rot nicht mehr zeigt.
    private func releaseAfterFollowUp(_ found: [String: Found]) {
        guard let d = followUpDone else { return }
        if found[d.id] == nil {
            followUpDone = nil
        } else if Date().timeIntervalSince(d.at) >= 3 {
            followUpDone = nil
            shown.remove(d.id)
            Self.log.notice("Anruf-Banner nach Folgeaktion noch da – zurückgeholt")
        } else {
            scheduleScan(after: 0.5)
        }
    }

    /// Folgeaktion nach eigenem „Ablehnen“ (G30 erweitert): einmal „Live-Voicemail stoppen“ im **selben** Banner, nur
    /// solange die Frist läuft. Regel rein und getestet in `NotifyWire.followUp`.
    private func runFollowUp(_ found: [String: Found]) {
        guard let p = followUpPending else { return }
        let banner = found[p.id]?.banner
        let actions = banner.flatMap { reader.call(id: p.id, $0)?.actions }
        switch NotifyWire.followUp(pending: p, id: p.id, actions: actions, now: Date()) {
        case .press?:
            followUpPending = nil
            guard let banner, let button = findButton(in: banner, matching: NotifyWire.voicemailStopActions) else {
                return Self.log.notice("Folgeaktion verworfen: Knopf nicht gefunden")
            }
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            followUpDone = (p.id, Date())
            Self.log.notice("Folgeaktion „Live-Voicemail stoppen“ ausgeführt (AXError \(result.rawValue, privacy: .public))")
            scheduleScan(after: 0.2)
        case .wait?:
            scheduleScan(after: 0.2)
        case .expire?:
            followUpPending = nil
            // Fenster blieb (z. B. Live-Voicemail aus und Banner schon weg, oder Apple zeigt etwas anderes) → zurück.
            shown.remove(p.id)
            Self.log.notice("Folgeaktion verfallen")
        case nil:
            followUpPending = nil
        }
    }
}

/// Dünne Hülle um die AX-Abfragen – nur lesen, außer `setPoint`.
enum AXQuery {
    static func value(_ e: AXUIElement, _ attr: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v : nil
    }

    static func string(_ e: AXUIElement, _ attr: String) -> String {
        let v = value(e, attr)
        return (v as? String) ?? (v as? NSAttributedString)?.string ?? ""
    }

    static func children(_ e: AXUIElement, _ attr: String = kAXChildrenAttribute) -> [AXUIElement] {
        guard let v = value(e, attr), CFGetTypeID(v) == CFArrayGetTypeID() else { return [] }
        return (v as? [AnyObject] ?? []).compactMap { o in
            CFGetTypeID(o) == AXUIElementGetTypeID() ? (o as! AXUIElement) : nil   // swiftlint:disable:this force_cast
        }
    }

    static func point(_ e: AXUIElement, _ attr: String) -> CGPoint? {
        guard let v = value(e, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let ax = v as! AXValue   // swiftlint:disable:this force_cast
        var p = CGPoint.zero
        return AXValueGetType(ax) == .cgPoint && AXValueGetValue(ax, .cgPoint, &p) ? p : nil
    }

    static func setPoint(_ e: AXUIElement, _ attr: String, _ p: CGPoint) -> AXError {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
        return AXUIElementSetAttributeValue(e, attr as CFString, v)
    }

    /// Benannte Aktionen: macOS liefert „Name:Schließen\nTarget:…\nSelector:…“; Standardaktionen (`AX…`) fallen weg.
    static func actions(_ e: AXUIElement) -> [(name: String, raw: String)] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success, let list = names as? [String] else { return [] }
        return list.compactMap { raw in
            guard raw.hasPrefix("Name:") else { return nil }
            let name = raw.dropFirst(5).prefix { $0 != "\n" }
            return name.isEmpty ? nil : (String(name), raw)
        }
    }

    /// Teil vor dem ersten Komma, ohne Richtungszeichen (Anrufernamen kommen mit U+202A … U+202C).
    static func firstPart(_ s: String) -> String {
        LiveText.sanitize(String(s.split(separator: ",", maxSplits: 1).first ?? ""))
    }
}
