import Foundation
import OSLog

/// Dateiablage (0.8.0, specs/2026-10-22-gnotchi-0.8.0-ablage.md, SECURE-DESIGN G32): merkt sich **Verweise**
/// (Lesezeichen), keine Kopien. Gespeichert in `~/Library/Application Support/Gnotchi/ablage.json` (Ordner 0700,
/// Datei 0600), höchstens 50 Einträge, beim Lesen geprüft. Entfernen löscht nie eine Datei. Nie Namen ins Protokoll.
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

    /// `directory` nur im Test anders (Standard: Gnotchis Ordner in Application Support).
    init(directory: URL? = LiveTextLink.directory) {
        file = directory?.appendingPathComponent("ablage.json")
        load()
    }

    // MARK: Ändern

    /// Nur existierende Datei-URLs; Doppelte (gleicher aufgelöster Pfad) und alles über 50 fallen weg.
    /// Liefert die Zahl der neu abgelegten.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL && items.count < Self.maxItems {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard FileManager.default.fileExists(atPath: path),
                  !items.contains(where: { resolve($0)?.standardizedFileURL.resolvingSymlinksInPath().path == path }),
                  let mark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                  mark.count <= Self.maxBookmark else { continue }
            items.append(Item(id: UUID(), bookmark: mark, name: Self.cleanName(url.lastPathComponent)))
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items = []
        save()
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
    }

    // MARK: Speichern (G32)

    private func load() {
        guard let file, let data = try? Data(contentsOf: file) else { return }
        items = Self.decode(data)
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
