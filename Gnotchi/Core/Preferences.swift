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
        /// 0.4.0 Live-Aktivitäten.
        static let liveRotation = "liveRotation"
        static let headphoneActivity = "headphoneActivity"
        /// Familien-Apps lesen diesen Schlüssel (CFPreferences, Domäne dev.mwlr.gnotchi) – nicht umbenennen.
        static let familyUpdates = "familyUpdates"
        /// 0.5.0 Termine aus Kalli (G26).
        static let kalliEvents = "kalliEvents"
        /// 0.5.0 Spiegel (G27).
        static let mirror = "mirror"
        /// 0.5.0 Ton bei Ablauf des Timers (Name aus CountdownTimer.sounds, leer = kein Ton).
        static let timerSound = "timerSound"
        /// 0.5.0 Timer-Ablauf: Insel pulsiert bis Klick (aus = kurzer Hinweis).
        static let timerAlarm = "timerAlarm"
        /// Medienfilter: nur Bundle-IDs (G25).
        static let mediaExcluded = "mediaExcluded"
    }

    /// G25: höchstens so viele ausgeschlossene Apps, je Kennung höchstens so lang.
    nonisolated static let maxExcluded = 64
    nonisolated static let maxBundleIDLength = 255

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

    /// Kleine Insel wechselt alle 4 s zwischen den Aktivitäten (0.4.0). Aus = immer die erste. Ab Werk an.
    var liveRotation: Bool { didSet { defaults.set(liveRotation, forKey: Key.liveRotation) } }

    /// Solange der Ton über Bluetooth läuft, ist das eine eigene Aktivität (0.4.0). Ab Werk an.
    var headphoneActivity: Bool { didSet { defaults.set(headphoneActivity, forKey: Key.headphoneActivity) } }

    /// Updates der App-Familie in der Insel (0.4.0, G23). Ab Werk an.
    var familyUpdates: Bool { didSet { defaults.set(familyUpdates, forKey: Key.familyUpdates) } }

    /// Nächster Termin aus Kalli, 15 Minuten vor Beginn (0.5.0, G26). Aus = Socket weg. Ab Werk an.
    var kalliEvents: Bool { didSet { defaults.set(kalliEvents, forKey: Key.kalliEvents) } }

    /// Spiegel in der großen Insel (0.5.0, G27). Kamera nur nach Klick und nur, solange er sichtbar ist. Ab Werk an.
    var mirror: Bool { didSet { defaults.set(mirror, forKey: Key.mirror) } }

    /// Timer-Ablauf bis Klick anzeigen (0.5.0): Insel pulsiert, Ton wiederholt sich höchstens 1 Minute. Ab Werk an.
    var timerAlarm: Bool { didSet { defaults.set(timerAlarm, forKey: Key.timerAlarm) } }

    /// Ton bei Ablauf des Timers (0.5.0). Nur Namen aus `CountdownTimer.sounds`; leer = kein Ton.
    var timerSound: String {
        didSet {
            let valid = CountdownTimer.validSound(timerSound)
            if valid != timerSound { timerSound = valid; return }
            defaults.set(timerSound, forKey: Key.timerSound)
        }
    }

    /// Medienfilter (0.4.0, G25): Wiedergabe dieser Apps erscheint nie in der Insel. Nur über `setMediaExcluded`.
    private(set) var mediaExcluded: [String] { didSet { defaults.set(mediaExcluded, forKey: Key.mediaExcluded) } }

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
        liveRotation = defaults.object(forKey: Key.liveRotation) as? Bool ?? true
        headphoneActivity = defaults.object(forKey: Key.headphoneActivity) as? Bool ?? true
        familyUpdates = defaults.object(forKey: Key.familyUpdates) as? Bool ?? true
        kalliEvents = defaults.object(forKey: Key.kalliEvents) as? Bool ?? true
        mirror = defaults.object(forKey: Key.mirror) as? Bool ?? true
        timerSound = CountdownTimer.validSound(defaults.object(forKey: Key.timerSound))
        timerAlarm = defaults.object(forKey: Key.timerAlarm) as? Bool ?? true
        mediaExcluded = Self.validExcluded(defaults.object(forKey: Key.mediaExcluded))
    }

    func isMediaExcluded(_ bundleID: String) -> Bool {
        mediaExcluded.contains(bundleID)
    }

    /// Schalter je App. Ungültige Kennungen werden nie gespeichert.
    func setMediaExcluded(_ bundleID: String, _ excluded: Bool) {
        var list = mediaExcluded.filter { $0 != bundleID }
        if excluded { list.append(bundleID) }
        let valid = Self.validExcluded(list)
        if valid != mediaExcluded { mediaExcluded = valid }
    }

    /// G25: nur `[A-Za-z0-9.-]`, je 1…255 Zeichen, ohne Doppelte, höchstens 64. Alles andere (per `defaults write`
    /// gesetzt, anderer Typ) fällt weg.
    nonisolated static func validExcluded(_ stored: Any?) -> [String] {
        guard let raw = stored as? [Any] else { return [] }
        var out: [String] = []
        for case let id as String in raw where isValidBundleID(id) && !out.contains(id) {
            out.append(id)
            if out.count == maxExcluded { break }
        }
        return out
    }

    nonisolated static func isValidBundleID(_ id: String) -> Bool {
        (1...maxBundleIDLength).contains(id.utf8.count) && id.unicodeScalars.allSatisfy { s in
            ("a"..."z").contains(s) || ("A"..."Z").contains(s) || ("0"..."9").contains(s) || s == "." || s == "-"
        }
    }

    /// Nur Werte aus der Auswahl; alles andere (anderer Typ, per `defaults write` gesetzt) → ab Werk.
    nonisolated static func validExpandDelay(_ stored: Any?) -> TimeInterval {
        guard let n = stored as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return defaultExpandDelay }
        let v = n.doubleValue
        return expandDelayChoices.first { abs($0 - v) < 0.001 } ?? defaultExpandDelay
    }
}
