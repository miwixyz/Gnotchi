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

/// App-Symbole je Bundle-ID. Ohne Zwischenspeicher fragte jede Darstellung der großen Insel
/// LaunchServices ab und lud das Symbol neu (Review 18.10.). Auch „nicht installiert“ wird gemerkt.
@MainActor
enum AppIcons {
    private static var cache = BoundedCache<String, NSImage?>(limit: 16)

    static func icon(for bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache.insert(image, for: bundleID)
        return image
    }
}
