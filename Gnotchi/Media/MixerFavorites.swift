import Foundation

/// Favoriten-Geräte im Mixer (0.31.0): je Liste (Ausgabe, Mikrofon) bis zu `maxPerList` Geräte, gemerkt an der festen
/// Geräte-UID (nicht an Name oder Objektnummer, die sich ändern). Ein nicht angeschlossenes Favoriten-Gerät bleibt gemerkt,
/// erscheint aber nicht in der Reihe. Die Reihenfolge ist die des Festlegens.
enum MixerFavorites {
    enum List: String, Sendable {
        case output = "mixerFavoritesOutput"
        case input = "mixerFavoritesInput"
    }

    nonisolated static let maxPerList = 6

    /// Die Favoriten, die gerade angeschlossen sind, in Favoriten-Reihenfolge.
    nonisolated static func shown(_ uids: [String], in devices: [OutputDevices.Device]) -> [OutputDevices.Device] {
        uids.compactMap { uid in devices.first { $0.uid == uid } }
    }

    /// Setzt oder entfernt `uid`. Neue Favoriten kommen ans Ende; ist die Liste voll, bleibt sie unverändert.
    nonisolated static func toggled(_ uids: [String], uid: String) -> [String] {
        if uids.contains(uid) { return uids.filter { $0 != uid } }
        guard uids.count < maxPerList else { return uids }
        return uids + [uid]
    }

    nonisolated static func load(_ list: List, from defaults: UserDefaults) -> [String] {
        let raw = defaults.stringArray(forKey: list.rawValue) ?? []
        var seen = Set<String>()
        return raw.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(maxPerList).map { $0 }
    }

    nonisolated static func save(_ uids: [String], _ list: List, to defaults: UserDefaults) {
        defaults.set(uids, forKey: list.rawValue)
    }
}
