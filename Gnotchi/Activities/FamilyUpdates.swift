import AppKit
import OSLog

/// Apps der Familie (0.4.0, specs/2026-10-21-gnotchi-0.4.0-live-aktivitaeten.md). Name und Bundle-ID stehen
/// **fest im Code** (SECURE-DESIGN G23/G24), nie aus einer Meldung. Bundle-IDs gemessen 21.10. an den
/// installierten Apps, alle Team LTKJ6Z2VYB.
enum FamilyApp: String, CaseIterable, Sendable {
    case tippi, kalli, qotti, seam
    /// Gnotchis eigenes Update kommt aus Sparkle im eigenen Prozess, nie über distnoted.
    case gnotchi

    /// Positivliste der Apps, die über distnoted melden dürfen (G23).
    nonisolated static let remote: [FamilyApp] = [.tippi, .kalli, .qotti, .seam]

    var name: String {
        switch self {
        case .tippi: "Tippi"
        case .kalli: "Kalli"
        case .qotti: "Qotti"
        case .seam: "Seam"
        case .gnotchi: "Gnotchi"
        }
    }

    var bundleID: String {
        switch self {
        case .tippi: "com.tippi.app"
        case .kalli: "com.kalli.app"
        case .qotti: "app.qotti.local"
        case .seam: "dev.mwlr.seam"
        case .gnotchi: "dev.mwlr.gnotchi"
        }
    }
}

/// Reine Teile der Update-Meldungen (G23, getestet). Jeder lokale Prozess kann senden und mitlesen:
/// Schema statt Vertrauen, Anzeige nur aus festen Texten und der geprüften Versionsnummer.
enum FamilyUpdates {

    struct Message: Equatable, Sendable {
        let app: FamilyApp
        let version: String
        let ready: Bool
    }

    struct Entry: Equatable, Sendable {
        let app: FamilyApp
        let version: String
        let seen: Date

        /// „Kalli 0.11.0 bereit“ – Name aus der Positivliste, Version in geprüfter Form.
        var label: String { "\(app.name) \(version) bereit" }
    }

    nonisolated static let updateName = Notification.Name("app.mwlr.familie.update")
    /// Nach dem Öffnen: Die App zeigt ihr eigenes Update-Fenster, aber nur, wenn sie selbst eins bereit hat (G24).
    nonisolated static let showName = Notification.Name("app.mwlr.familie.update.show")
    /// Ohne neue Meldung fällt ein Eintrag nach 14 Tagen weg.
    nonisolated static let maxAge: TimeInterval = 14 * 86_400
    /// Je App höchstens eine Meldung pro Sekunde; schnellere werden verworfen.
    nonisolated static let minInterval: TimeInterval = 1

    /// `{"v":1, "app":"kalli", "version":"0.11.0", "ready":true}`. `v` Zahl 1 (kein Wahrheitswert), `app` aus der
    /// Positivliste, `version` in der Form 1.2 oder 1.2.3 (je höchstens drei Ziffern), `ready` Wahrheitswert.
    /// Unbekannte Schlüssel ignoriert, alles andere verworfen.
    nonisolated static func parse(_ info: [AnyHashable: Any]?) -> Message? {
        guard let info,
              let v = info["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(),
              v.intValue == 1, v.doubleValue == 1,
              let raw = info["app"] as? String, let app = FamilyApp(rawValue: raw), FamilyApp.remote.contains(app),
              let version = info["version"] as? String, isValidVersion(version),
              let ready = info["ready"] as? NSNumber, CFGetTypeID(ready) == CFBooleanGetTypeID() else { return nil }
        return Message(app: app, version: version, ready: ready.boolValue)
    }

    /// `^[0-9]{1,3}(\.[0-9]{1,3}){1,2}$` – nur ASCII-Ziffern (keine arabisch-indischen o. Ä.).
    nonisolated static func isValidVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return false }
        return parts.allSatisfy { p in
            (1...3).contains(p.count) && p.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
        }
    }

    /// Zahlenweise vergleichen, fehlende Stellen zählen als 0 („0.11“ == „0.11.0“). Nur für geprüfte Versionen.
    nonisolated static func isAtLeast(_ installed: String, _ wanted: String) -> Bool {
        let a = installed.split(separator: ".").map { Int($0) ?? 0 }
        let b = wanted.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return true
    }

    /// Drossel je App: annehmen, wenn die letzte angenommene Meldung mindestens `minInterval` her ist.
    nonisolated static func accepts(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minInterval
    }

    /// Erledigt-Regel: `ready:false` entfernt; `ready:true` setzt den Eintrag, außer die installierte App hat
    /// diese Version schon.
    nonisolated static func apply(_ m: Message, to entries: [FamilyApp: Entry], installed: String?,
                                  now: Date) -> [FamilyApp: Entry] {
        var out = entries
        if m.ready, !(installed.map { isAtLeast($0, m.version) } ?? false) {
            out[m.app] = Entry(app: m.app, version: m.version, seen: now)
        } else {
            out[m.app] = nil
        }
        return out
    }

    /// Abgelaufene (14 Tage ohne Meldung) und schon installierte Einträge raus.
    nonisolated static func prune(_ entries: [FamilyApp: Entry], installed: (FamilyApp) -> String?,
                                  now: Date) -> [FamilyApp: Entry] {
        entries.filter { app, e in
            guard now.timeIntervalSince(e.seen) < maxAge else { return false }
            return !(installed(app).map { isAtLeast($0, e.version) } ?? false)
        }
    }

    /// In fester Reihenfolge der Familie (nicht nach Eingang): Die Rotation springt sonst bei jeder Meldung.
    nonisolated static func sorted(_ entries: [FamilyApp: Entry]) -> [Entry] {
        FamilyApp.allCases.compactMap { entries[$0] }
    }

    /// Gnotchis eigenes Update aus Sparkle (Feed signiert, über HTTPS): Version trotzdem nur in geprüfter Form.
    nonisolated static func ownEntry(_ version: String?, now: Date) -> Entry? {
        guard let version, isValidVersion(version) else { return nil }
        return Entry(app: .gnotchi, version: version, seen: now)
    }

    /// Installierte Version aus der Info.plist der App, die LaunchServices für die Bundle-ID kennt. Direkt gelesen,
    /// nicht über `Bundle(url:)` (zwischengespeichert, nach einem Update veraltet). Nur in geprüfter Form.
    /// Bewusst ohne Signaturprüfung: Eine Attrappe mit hoher Version kann höchstens eine Anzeige unterdrücken.
    @MainActor
    static func installedVersion(_ app: FamilyApp) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID),
              let plist = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist")),
              let v = plist["CFBundleShortVersionString"] as? String, isValidVersion(v) else { return nil }
        return v
    }
}

/// Empfängt die Update-Meldungen der Familien-Apps und hält die Liste aktuell (G23).
@MainActor
final class FamilyUpdateLink: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "familie")
    /// Zusätzlich zur Prüfung bei jeder Meldung und bei jedem App-Start: 14-Tage-Regel auch ohne Ereignis.
    private static let pruneInterval: Duration = .seconds(3600)

    private let activity: ActivityModel
    private let installed: @MainActor (FamilyApp) -> String?
    private var entries: [FamilyApp: FamilyUpdates.Entry] = [:]
    private var lastAccepted: [FamilyApp: Date] = [:]
    private var observer: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var pruneTask: Task<Void, Never>?

    init(activity: ActivityModel,
         installed: @escaping @MainActor (FamilyApp) -> String? = FamilyUpdates.installedVersion) {
        self.activity = activity
        self.installed = installed
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: FamilyUpdates.updateName, object: nil, queue: .main
        ) { [weak self] note in
            // Schema-Abbruch vor jeder weiteren Verarbeitung (G23, STRIDE D).
            let message = FamilyUpdates.parse(note.userInfo)
            MainActor.assumeIsolated { self?.receive(message) }
        }
        // Nach einem Update startet die App neu: dann prüfen, ob der Eintrag erledigt ist.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, FamilyApp.remote.contains(where: { $0.bundleID == id }) else { return }
                self.prune()
            }
        }
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pruneInterval)
                guard !Task.isCancelled else { return }
                self?.prune()
            }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        observer = nil
        launchObserver = nil
        pruneTask?.cancel()
        pruneTask = nil
        entries = [:]
        lastAccepted = [:]
        activity.setFamilyUpdates([])
    }

    /// Nur für Tests: dieselbe Verarbeitung wie eine echte Meldung, mit festem Zeitpunkt.
    func receive(_ message: FamilyUpdates.Message?, now: Date = Date()) {
        guard let message, FamilyUpdates.accepts(last: lastAccepted[message.app], now: now) else { return }
        lastAccepted[message.app] = now
        let before = entries[message.app]
        entries = FamilyUpdates.apply(message, to: entries, installed: installed(message.app), now: now)
        if before == nil, entries[message.app] != nil {
            Self.log.notice("Update gemeldet: \(message.app.rawValue, privacy: .public)")
        }
        publish()
    }

    func prune(now: Date = Date()) {
        let pruned = FamilyUpdates.prune(entries, installed: installed, now: now)
        guard pruned != entries else { return }
        entries = pruned
        publish()
    }

    private func publish() {
        activity.setFamilyUpdates(FamilyUpdates.sorted(entries))
    }
}
