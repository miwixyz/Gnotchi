import AppKit

/// Kleiner Zwischenspeicher mit fester Obergrenze; bei Überlauf fliegt der älteste Eintrag.
/// Bewusst simpel (FIFO statt LRU): Es wechseln selten mehr als zwei, drei Quell-Apps.
struct BoundedCache<Key: Hashable, Value> {
    let limit: Int
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []

    init(limit: Int) { self.limit = max(1, limit) }

    var count: Int { storage.count }

    subscript(key: Key) -> Value? { storage[key] }

    mutating func insert(_ value: Value, for key: Key) {
        guard storage.updateValue(value, forKey: key) == nil else { return }
        order.append(key)
        if order.count > limit { storage[order.removeFirst()] = nil }
    }
}

/// App-Symbole und -Namen je Bundle-ID. Ohne Zwischenspeicher fragte jede Darstellung der großen Insel
/// LaunchServices ab und lud das Symbol neu (Review 18.10.). Auch „nicht installiert“ wird gemerkt.
/// Der Name kommt aus dem LOKALEN App-Bundle (lokalisiert, z. B. „Musik“), nie aus dem Wiedergabe-Strom.
@MainActor
enum AppIcons {
    private static var cache = BoundedCache<String, NSImage?>(limit: 16)
    private static var names = BoundedCache<String, String?>(limit: 16)

    nonisolated static let maxNameLength = 40

    static func icon(for bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache.insert(image, for: bundleID)
        return image
    }

    static func name(for bundleID: String) -> String? {
        if let hit = names[bundleID] { return hit }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { cleanName(FileManager.default.displayName(atPath: $0.path)) }
        names.insert(name, for: bundleID)
        return name
    }

    /// „.app“ weg (zeigt displayName bei eingeblendeten Suffixen), bereinigt wie Strom-Texte (Bundle-Namen
    /// sind frei wählbar), höchstens `maxNameLength` Zeichen. Leer → nil (Kopfzeile ohne Namen).
    nonisolated static func cleanName(_ raw: String?) -> String? {
        guard var s = raw else { return nil }
        if s.lowercased().hasSuffix(".app") { s.removeLast(4) }
        return NowPlayingInfo.sanitize(s).map { String($0.prefix(maxNameLength)) }
    }
}
