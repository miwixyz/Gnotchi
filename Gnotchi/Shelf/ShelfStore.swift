import Foundation
import OSLog

/// Dateiablage (0.8.0, specs/2026-10-22-gnotchi-0.8.0-ablage.md, SECURE-DESIGN G32): merkt sich **Verweise**
/// (Lesezeichen). Gespeichert in `~/Library/Application Support/Gnotchi/ablage.json` (Ordner 0700,
/// Datei 0600), höchstens 50 Einträge, beim Lesen geprüft. Nie Namen ins Protokoll.
/// 0.9.1 (specs/2026-10-23-gnotchi-0.9.1-fotos-ablage.md): Dateiversprechen (Fotos) landen als **Kopie** in
/// `Ablage-Kopien/<UUID>/`. Entfernen löscht nur solche eigenen Kopien – nie etwas außerhalb dieses Ordners.
@MainActor
final class ShelfStore {

    struct Item: Equatable, Sendable, Identifiable {
        let id: UUID
        let bookmark: Data
        /// Angezeigter Name (Dateiname, bereinigt) – nur Anzeige.
        let name: String
    }

    nonisolated static let maxItems = 50
    nonisolated static let maxFile = 1_048_576
    nonisolated static let maxBookmark = 16_384
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "ablage")

    private(set) var items: [Item] = []
    private let file: URL?
    /// Eigene Kopien aus Dateiversprechen (0.9.1).
    let copies: URL?
    /// UUID-Ordner, die das Aufräumen in dieser Sitzung stehen lässt: eine App schreibt gerade hinein, oder die Kopie
    /// wurde eben rausgezogen und die Ziel-App liest sie vielleicht noch (Review 23.10.) – dann erst beim nächsten Start.
    private var pending: Set<String> = []
    /// `ablage.json` war lesbar und vollständig. Sonst kennen wir nicht alle Einträge → nichts löschen (Review 23.10.).
    private var trusted = true

    /// `directory` nur im Test anders (Standard: Gnotchis Ordner in Application Support).
    /// Räumt verwaiste Kopien gleich beim Anlegen auf – auch wenn die Ablage ausgeschaltet ist (Review 23.10.).
    init(directory: URL? = LiveTextLink.directory) {
        file = directory?.appendingPathComponent("ablage.json")
        copies = directory?.appendingPathComponent("Ablage-Kopien", isDirectory: true)
        load()
        cleanCopies()
    }

    // MARK: Ändern

    /// Nur existierende Datei-URLs; Doppelte (gleicher aufgelöster Pfad) und alles über 50 fallen weg.
    /// Liefert die Zahl der neu abgelegten.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL && items.count < Self.maxItems {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard FileManager.default.fileExists(atPath: path), !contains(url),
                  let mark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                  mark.count <= Self.maxBookmark else { continue }
            items.append(Item(id: UUID(), bookmark: mark, name: Self.cleanName(url.lastPathComponent)))
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    /// Liegt (gleicher aufgelöster Pfad) schon in der Ablage.
    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return items.contains { resolve($0)?.standardizedFileURL.resolvingSymlinksInPath().path == path }
    }

    /// Entfernt den Eintrag; war es eine eigene Kopie (liegt noch im Kopien-Ordner), wird sie gelöscht.
    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
        cleanCopies()
    }

    func clear() {
        items = []
        save()
        cleanCopies()
    }

    /// Rausgezogen: Eintrag weg, eine eigene Kopie aber erst beim nächsten Start löschen – Browser-Upload, Mail & Co.
    /// lesen die Datei womöglich erst nach dem Loslassen (Review 23.10.).
    func removeAfterDrag(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }), let copies, let url = resolve(item),
           let folder = Self.copyFolder(of: url, in: copies) {
            pending.insert(folder.lastPathComponent)
        }
        remove(id)
    }

    // MARK: Kopien aus Dateiversprechen (0.9.1)

    /// Frischer eigener Unterordner (0700) für ein Versprechen; bleibt beim Aufräumen stehen bis `release`.
    func newCopyFolder() -> URL? {
        guard let copies, PeerSocketServer<String>.prepareDirectory(copies.deletingLastPathComponent()),
              PeerSocketServer<String>.prepareDirectory(copies) else { return nil }
        let name = UUID().uuidString
        let folder = copies.appendingPathComponent(name, isDirectory: true)
        guard PeerSocketServer<String>.prepareDirectory(folder) else { return nil }
        pending.insert(name)
        return folder
    }

    /// Versprechen abgeschlossen (oder gescheitert) – danach räumt `cleanCopies` den Ordner weg, falls nichts darauf zeigt.
    func release(_ folder: URL) {
        pending.remove(folder.lastPathComponent)
    }

    /// Von der App geschriebene Datei: liegt direkt im eigenen UUID-Ordner, ist kein Link und gehört uns.
    func isValidCopy(_ url: URL, in folder: URL) -> Bool {
        guard let copies, let own = Self.copyFolder(of: url, in: copies),
              own.path == folder.standardizedFileURL.resolvingSymlinksInPath().path else { return false }
        var st = stat()
        return lstat(url.path, &st) == 0 && (st.st_mode & S_IFMT) != S_IFLNK && st.st_uid == getuid()
    }

    /// UUID-Ordner im Kopien-Ordner löschen, auf die kein Eintrag (mehr) zeigt und in die gerade niemand schreibt.
    /// Löscht nur direkte Unterordner mit UUID-Namen. Eine rausgeschobene Kopie liegt draußen und bleibt.
    /// Nichts, wenn `ablage.json` unvollständig war oder der Ordner (bzw. Gnotchis Ordner) kein eigener echter Ordner ist.
    func cleanCopies() {
        guard trusted, let copies, Self.isOwnDirectory(copies.deletingLastPathComponent()), Self.isOwnDirectory(copies),
              let names = try? FileManager.default.contentsOfDirectory(atPath: copies.path) else { return }
        let used = Set(items.compactMap(resolve).compactMap { Self.copyFolder(of: $0, in: copies)?.lastPathComponent })
        var removed = 0
        for name in names where UUID(uuidString: name) != nil && !used.contains(name) && !pending.contains(name) {
            if (try? FileManager.default.removeItem(at: copies.appendingPathComponent(name))) != nil { removed += 1 }
        }
        if removed > 0 { Self.log.notice("\(removed, privacy: .public) Kopien gelöscht") }
    }

    /// Echter Ordner (kein Link), gehört uns – wie `prepareDirectory`, aber ohne anzulegen.
    nonisolated static func isOwnDirectory(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR && st.st_uid == getuid()
    }

    /// `<copies>/<UUID>/<Name>` → der UUID-Ordner (Links im Ordnerpfad aufgelöst, der Name selbst nicht); sonst nil.
    nonisolated static func copyFolder(of url: URL, in copies: URL) -> URL? {
        let root = copies.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parent = url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
        guard parent.count == root.count + 1, Array(parent.prefix(root.count)) == root,
              let name = parent.last, UUID(uuidString: name) != nil else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: parent), isDirectory: true)
    }

    /// Lesezeichen → aktuelle URL (folgt Umbenennen/Verschieben). Nicht auflösbar oder Datei weg → nil.
    func resolve(_ item: Item) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Einträge, deren Datei verschwunden ist, entfernen (beim Zeigen der Ablage).
    func prune() {
        let before = items.count
        items.removeAll { resolve($0) == nil }
        if items.count != before { save() }
        cleanCopies()
    }

    // MARK: Speichern (G32)

    private func load() {
        guard let file, let data = try? Data(contentsOf: file) else { return }
        items = Self.decode(data)
        let raw = data.count <= Self.maxFile
            ? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["items"] as? [Any] : nil
        trusted = raw?.count == items.count
        if !trusted { Self.log.error("Ablage unvollständig gelesen – Kopien werden nicht aufgeräumt") }
    }

    private func save() {
        guard let file, PeerSocketServer<String>.prepareDirectory(file.deletingLastPathComponent()) else {
            return Self.log.error("Ablage nicht gespeichert (Ordner)")
        }
        let list = items.map { ["id": $0.id.uuidString, "bookmark": $0.bookmark.base64EncodedString(), "name": $0.name] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["v": 1, "items": list]) else { return }
        do {
            try data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            Self.log.error("Ablage nicht gespeichert")
        }
    }

    /// Schema statt Vertrauen: `v` = 1, ≤ 50 Einträge, UUID, Lesezeichen ≤ 16 KB, Name bereinigt. Kaputt → leer.
    nonisolated static func decode(_ data: Data) -> [Item] {
        guard data.count <= maxFile, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              KalliEvents.isNumber(obj["v"], equalTo: 1), let list = obj["items"] as? [[String: Any]] else { return [] }
        return list.prefix(maxItems).compactMap { d in
            guard let idText = d["id"] as? String, let id = UUID(uuidString: idText),
                  let b64 = d["bookmark"] as? String, let mark = Data(base64Encoded: b64), !mark.isEmpty,
                  mark.count <= maxBookmark, let name = d["name"] as? String else { return nil }
            return Item(id: id, bookmark: mark, name: cleanName(name))
        }
    }

    nonisolated static func cleanName(_ s: String) -> String {
        let c = NotifyWire.clean(s, max: 80)
        return c.isEmpty ? "Datei" : c
    }
}
