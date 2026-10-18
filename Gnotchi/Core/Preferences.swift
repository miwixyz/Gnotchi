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

    /// Musik in der Notch zeigen. Ab Werk an. Noch nicht mit der Insel verdrahtet
    /// (Plan Aufgabe 12); bis dahin startet Gnotchi den Adapter gar nicht.
    var notchMedia: Bool { didSet { defaults.set(notchMedia, forKey: Key.notchMedia) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` statt `bool(forKey:)`: ein fehlender Eintrag heißt „ab Werk“ (an),
        // nicht „aus“.
        notchMedia = defaults.object(forKey: Key.notchMedia) as? Bool ?? true
    }
}
