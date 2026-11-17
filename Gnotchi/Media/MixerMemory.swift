import Foundation

/// Gemerkte Lautstärke je App (Stream Deck, entschieden 17.11.; SECURE-DESIGN G59 „Gemerkte Lautstärken“): Bundle-ID → Prozent.
/// Gilt für den Mixer in Insel und Popover und fürs Stream Deck. 100 % wird nicht gespeichert (das ist „nichts tun“).
enum MixerMemory {

    nonisolated static let key = "appGains"
    nonisolated static let maxEntries = 50
    /// Werte darunter (bis einschließlich) werden nie automatisch angewendet: nie still stumm hängen (G53).
    nonisolated static let autoApplyAbove = 5

    /// Gespeicherten Wert lesen: nur gültige Bundle-IDs, nur 0…200 ohne 100, höchstens `maxEntries`.
    nonisolated static func load(from defaults: UserDefaults) -> [String: Int] {
        validated(defaults.object(forKey: key))
    }

    nonisolated static func validated(_ raw: Any?) -> [String: Int] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (id, value) in dict.sorted(by: { $0.key < $1.key }) {
            guard out.count < maxEntries, DeckWire.isValidApp(id), id != DeckWire.current,
                  let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue == n.doubleValue.rounded(), (0...200).contains(n.intValue), n.intValue != 100 else { continue }
            out[id] = n.intValue
        }
        return out
    }

    /// Neuer Stand nach einem Regler-Wert. 100 % entfernt den Eintrag. Ist die Liste voll, fällt der älteste Eintrag
    /// (Reihenfolge `order`, ältester vorn) heraus.
    nonisolated static func updated(_ memory: [String: Int], order: [String], bundleID: String,
                                    percent: Int) -> (memory: [String: Int], order: [String]) {
        var m = memory
        var o = order.filter { $0 != bundleID && m[$0] != nil }
        guard percent != 100 else { m[bundleID] = nil; return (m, o) }
        m[bundleID] = min(200, max(0, percent))
        o.append(bundleID)
        while m.count > maxEntries, let oldest = o.first { o.removeFirst(); m[oldest] = nil }
        return (m, o)
    }

    nonisolated static func shouldAutoApply(_ percent: Int) -> Bool { percent > autoApplyAbove && percent != 100 }
}
