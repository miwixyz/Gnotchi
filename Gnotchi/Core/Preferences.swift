import Foundation
import Observation

/// Einstellungen. Nur Schalter, keine Daten fremder Apps (docs/SECURE-DESIGN.md G14):
/// Titel, Interpret und Cover werden nie gespeichert.
@MainActor
@Observable
final class Preferences {

    enum Key {
        static let notchMedia = "notchMedia"
    }

    private let defaults: UserDefaults

    /// Musik in der Notch zeigen. Ab Werk an. Aus = weder Adapter noch Insel laufen
    /// (`AppModel.applyNotchSetting`).
    var notchMedia: Bool { didSet { defaults.set(notchMedia, forKey: Key.notchMedia) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` statt `bool(forKey:)`: ein fehlender Eintrag heißt „ab Werk“ (an),
        // nicht „aus“.
        notchMedia = defaults.object(forKey: Key.notchMedia) as? Bool ?? true
    }
}
