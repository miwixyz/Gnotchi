import Foundation
import OSLog
import UniformTypeIdentifiers

/// Bildschirmfotos automatisch in die Ablage (0.10.0, specs/2026-10-23-gnotchi-0.10.0-bildschirmfotos.md,
/// SECURE-DESIGN G36). Eine Spotlight-Live-Abfrage auf `kMDItemIsScreenCapture` – dieses Merkmal setzen macOS
/// (⇧⌘3/4/5) **und** CleanShot (gemessen 23.10.), also ein Weg für beide, ohne fremde Einstellungen zu lesen.
///
/// Gelesen werden nur Metadaten und Dateieigenschaften, nie der Bildinhalt. Treffer gehen über `ShelfLink` in die
/// Ablage wie eine hineingezogene Datei (nur Verweis, G32). Protokoll: nur Zahlen, nie Namen oder Pfade.
@MainActor
final class ScreenshotWatcher: NotchPart {

    /// Höchstens so viele neue Fotos pro Spotlight-Meldung (eine Flut füllt sonst nur die Ablage).
    nonisolated static let maxPerUpdate = 10
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "ablage")

    private let activity: ActivityModel
    private let copies: URL?
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var since = Date()
    /// Pro Sitzung nur einmal übernehmen: Bearbeitet CleanShot ein Foto nach dem Entfernen, kommt es nicht zurück.
    private var seen: Set<String> = []
    /// Erstellzeitpunkt + Größe übernommener Fotos: Eine Kopie (Finder beim Rausziehen, CleanShots Verlauf) trägt beides
    /// mit – sie kam sonst als „neues“ Bildschirmfoto zurück (gemessen 23.10.: Finder-Kopie 43 s später gemeldet).
    private var prints: Set<String> = []

    init(activity: ActivityModel,
         copies: URL? = LiveTextLink.directory?.appendingPathComponent("Ablage-Kopien", isDirectory: true)) {
        self.activity = activity
        self.copies = copies
    }

    func start() {
        guard query == nil else { return }
        since = Date()
        let q = NSMetadataQuery()
        // Nur der Benutzerordner und iCloud Drive, keine externen Laufwerke. Nur Neues ab jetzt.
        // iCloud Drive AUSDRÜCKLICH dazu: Für Apps schließt der Benutzerordner-Bereich iCloud Drive aus (gemessen 23.10.:
        // Benutzerordner allein 0 iCloud-Treffer, mit dem Ordner 6) – dort speichert CleanShot.
        q.searchScopes = [NSMetadataQueryUserHomeScope, FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)]
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND %K >= %@",
                                  NSMetadataItemFSCreationDateKey, since as NSDate)
        q.notificationBatchingInterval = 0.5
        observers = [Notification.Name.NSMetadataQueryDidUpdate, .NSMetadataQueryDidFinishGathering].map { name in
            NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] note in
                // Nur Pfade (Text) über die Grenze reichen – Notification und Abfrage sind nicht `Sendable`.
                let paths = Self.paths(in: note)
                let kind = note.name == .NSMetadataQueryDidFinishGathering ? "erstes Durchsuchen fertig" : "Meldung"
                // Messpunkt (23.10.: zweites CleanShot-Foto nie gemeldet) – nur Zahlen.
                Self.log.notice("Bildschirmfotos: Spotlight \(kind, privacy: .public), \(paths.count, privacy: .public) Treffer")
                MainActor.assumeIsolated { self?.take(paths) }
            }
        }
        guard q.start() else {
            Self.log.error("Bildschirmfotos: Spotlight-Abfrage startet nicht")
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            return
        }
        query = q
        Self.log.notice("Bildschirmfotos: Abfrage läuft")
        requestFolderAccess()
    }

    /// Ordner, in den macOS Bildschirmfotos legt: Einstellung `location` von `com.apple.screencapture`, sonst Schreibtisch.
    nonisolated static func systemScreenshotFolder() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let raw = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Spotlight verschweigt Treffer in geschützten Ordnern (Schreibtisch), solange Gnotchi keine Freigabe hat – und
    /// macOS fragt nie, weil Gnotchi den Ordner sonst nicht anfasst (gemessen 23.10.). Einmal die Namensliste lesen
    /// löst die Rückfrage aus; die Liste wird sofort verworfen, nichts davon ins Protokoll.
    /// Im Hintergrund: Der Aufruf wartet, bis Michael die Rückfrage beantwortet – auf dem Hauptthread fror die Insel
    /// so lange ein, sogar „Beenden“ lief in eine Zeitüberschreitung (Sichttest 23.10.).
    private func requestFolderAccess() {
        let folder = Self.systemScreenshotFolder()
        let log = Self.log
        DispatchQueue.global(qos: .utility).async {
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
            log.notice("Bildschirmfotos: macOS-Ordner lesbar: \(readable, privacy: .public)")
        }
    }

    func stop() {
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        seen = []
        prints = []
        Self.log.notice("Bildschirmfotos: Abfrage gestoppt")
    }

    /// Neue und geänderte Treffer einer Meldung; beim ersten Sammeln alle bisherigen (nur Fotos ab dem Einschalten).
    nonisolated private static func paths(in note: Notification) -> [String] {
        let raw: [Any]
        if note.name == .NSMetadataQueryDidFinishGathering, let q = note.object as? NSMetadataQuery {
            q.disableUpdates()
            raw = q.results
            q.enableUpdates()
        } else {
            raw = (note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [Any] ?? [])
                + (note.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [Any] ?? [])
        }
        return raw.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String }
    }

    private func take(_ paths: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var fresh: [URL] = []
        var reasons: [String] = []
        for path in paths where fresh.count < Self.maxPerUpdate {
            let place = path.contains("/Library/Mobile Documents/") ? "iCloud" : (path.contains("/Library/") ? "App-intern" : "anderswo")
            guard !seen.contains(path) else { reasons.append("\(place): schon gesehen"); continue }
            let url = URL(fileURLWithPath: path)
            if let why = Self.rejection(url, since: since, home: home, copies: copies) {
                reasons.append("\(place): \(why)"); continue
            }
            seen.insert(path)
            if let print = Self.fingerprint(url), !prints.insert(print).inserted {
                reasons.append("\(place): Kopie"); continue   // Kopie eines schon übernommenen Fotos
            }
            fresh.append(url)
        }
        if !reasons.isEmpty {
            Self.log.notice("Bildschirmfotos verworfen: \(reasons.joined(separator: " · "), privacy: .public)")
        }
        if !paths.isEmpty {
            Self.log.notice("Bildschirmfotos: \(paths.count, privacy: .public) geprüft, \(fresh.count, privacy: .public) neu")
        }
        guard !fresh.isEmpty else { return }
        guard let shelf = activity.shelf else {
            Self.log.error("Bildschirmfotos: \(fresh.count, privacy: .public) gefunden, Ablage läuft nicht")
            return
        }
        shelf.addScreenshots(fresh)
    }

    /// Erstellzeitpunkt (ms) + Größe – bleibt beim Kopieren erhalten, unterscheidet aber zwei echte Fotos.
    nonisolated static func fingerprint(_ url: URL) -> String? {
        guard let v = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
              let created = v.creationDate, let size = v.fileSize else { return nil }
        return "\(Int64(created.timeIntervalSince1970 * 1000))|\(size)"
    }

    /// Reguläre Bilddatei (kein Video, kein Link), erstellt ab `since`, im Benutzerordner, nicht im Papierkorb und
    /// nicht in Gnotchis eigenem Kopien-Ordner. Liest nur Dateieigenschaften, nie den Inhalt.
    nonisolated static func isCandidate(_ url: URL, since: Date, home: URL, copies: URL?) -> Bool {
        rejection(url, since: since, home: home, copies: copies) == nil
    }

    /// `nil` = übernehmen, sonst der Grund als Stichwort (fürs Protokoll – nie Name oder Pfad).
    nonisolated static func rejection(_ url: URL, since: Date, home: URL, copies: URL?) -> String? {
        guard url.isFileURL else { return "keine Datei-URL" }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey, .creationDateKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return "nicht lesbar" }
        guard v.isRegularFile == true, v.isSymbolicLink != true else { return "keine reguläre Datei" }
        guard let type = v.contentType, type.conforms(to: .image) else { return "kein Bild" }
        guard let created = v.creationDate, created >= since.addingTimeInterval(-1) else { return "zu alt" }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(homePath + "/"), !path.hasPrefix(homePath + "/.Trash/") else { return "außerhalb/Papierkorb" }
        // App-interne Ablagen weglassen, iCloud Drive aber nicht: CleanShot legt jedes Foto zusätzlich als Verlaufskopie
        // unter ~/Library/Application Support/CleanShot/media/… ab, mit demselben Merkmal (gemessen 23.10., 43 s später).
        if path.hasPrefix(homePath + "/Library/"), !path.hasPrefix(homePath + "/Library/Mobile Documents/") { return "App-intern" }
        if let copies, path.hasPrefix(copies.standardizedFileURL.resolvingSymlinksInPath().path + "/") { return "eigene Kopie" }
        return nil
    }
}
