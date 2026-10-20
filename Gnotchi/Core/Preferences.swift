import Foundation
import Observation

/// Einstellungen. Nur Schalter, keine Daten fremder Apps (docs/SECURE-DESIGN.md G14):
/// Titel, Interpret und Cover werden nie gespeichert.
@MainActor
@Observable
final class Preferences {

    enum Key {
        static let notchMedia = "notchMedia"
        static let expandDelay = "expandDelay"
        static let headphoneNotice = "headphoneNotice"
        static let micCamera = "micCamera"
        /// Tippi liest diesen Schlüssel (CFPreferences, Domäne dev.mwlr.gnotchi) – nicht umbenennen.
        static let tippiRecording = "tippiRecording"
        /// Qotti liest diesen Schlüssel (CFPreferences, Domäne dev.mwlr.gnotchi) – nicht umbenennen.
        static let qottiQuota = "qottiQuota"
    }

    /// Auswahl „Aufklappen nach“ in Sekunden (Sofort, 0,3 s, 0,6 s, 1 s).
    nonisolated static let expandDelayChoices: [TimeInterval] = [0, 0.3, 0.6, 1.0]
    nonisolated static let defaultExpandDelay: TimeInterval = 0.6

    private let defaults: UserDefaults

    /// Musik in der Notch zeigen. Ab Werk an. Aus = weder Adapter noch Insel laufen
    /// (`AppModel.applyNotchSetting`).
    var notchMedia: Bool { didSet { defaults.set(notchMedia, forKey: Key.notchMedia) } }

    /// Wie lange die Maus über der kleinen Insel bleiben muss, bevor sie aufgeht (Michael, 18.10.:
    /// „damit das Überfahren nicht zu schnell auslöst und stört“). Wirkt sofort, ohne Neustart.
    var expandDelay: TimeInterval { didSet { defaults.set(expandDelay, forKey: Key.expandDelay) } }

    /// Kopfhörer verbunden/getrennt 3 s in der Insel zeigen (0.2.0). Ab Werk an.
    var headphoneNotice: Bool { didSet { defaults.set(headphoneNotice, forKey: Key.headphoneNotice) } }

    /// Punkt an der Insel, solange eine App Mikrofon oder Kamera nutzt (0.2.0). Ab Werk an.
    var micCamera: Bool { didSet { defaults.set(micCamera, forKey: Key.micCamera) } }

    /// Tippis Diktat in der Insel zeigen; Tippi blendet dann seine eigene Pille aus (0.2.0). Ab Werk an.
    var tippiRecording: Bool { didSet { defaults.set(tippiRecording, forKey: Key.tippiRecording) } }

    /// Qotti-Kontingent: Warnung bei 80/95 %/Drosselung, Zeile in der großen Insel (0.3.0). Ab Werk an.
    var qottiQuota: Bool { didSet { defaults.set(qottiQuota, forKey: Key.qottiQuota) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` statt `bool(forKey:)`: ein fehlender Eintrag heißt „ab Werk“ (an),
        // nicht „aus“.
        notchMedia = defaults.object(forKey: Key.notchMedia) as? Bool ?? true
        expandDelay = Self.validExpandDelay(defaults.object(forKey: Key.expandDelay))
        headphoneNotice = defaults.object(forKey: Key.headphoneNotice) as? Bool ?? true
        micCamera = defaults.object(forKey: Key.micCamera) as? Bool ?? true
        tippiRecording = defaults.object(forKey: Key.tippiRecording) as? Bool ?? true
        qottiQuota = defaults.object(forKey: Key.qottiQuota) as? Bool ?? true
    }

    /// Nur Werte aus der Auswahl; alles andere (anderer Typ, per `defaults write` gesetzt) → ab Werk.
    nonisolated static func validExpandDelay(_ stored: Any?) -> TimeInterval {
        guard let n = stored as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return defaultExpandDelay }
        let v = n.doubleValue
        return expandDelayChoices.first { abs($0 - v) < 0.001 } ?? defaultExpandDelay
    }
}
