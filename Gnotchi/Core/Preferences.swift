import Foundation
import Observation

/// Einstellungen. Nur Schalter, keine Daten fremder Apps (docs/SECURE-DESIGN.md G14):
/// Titel, Interpret und Cover werden nie gespeichert.
@MainActor
@Observable
final class Preferences {

    enum Key {
        static let notchMedia = "notchMedia"
        /// 0.15.0 Musik auf dem Schreibtisch: Schalter (ab Werk aus), Ecke, Größe.
        static let desktopMusic = "desktopMusic"
        static let desktopMusicCorner = "desktopMusicCorner"
        static let desktopMusicSize = "desktopMusicSize"
        /// Abstand des Covers zur gewählten Ecke (nach dem Ziehen), x/y in Punkten.
        static let desktopMusicInsetX = "desktopMusicInsetX"
        static let desktopMusicInsetY = "desktopMusicInsetY"
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
        /// 0.5.0 Wiedergabe immer groß (Player als Grundlage, andere Aktivitäten als Glas darüber).
        static let playerFirst = "playerFirst"
        /// 0.5.0 Wiedergabe-Knöpfe in der kleinen Insel.
        static let compactControls = "compactControls"
        /// 0.5.0 Aufklappen als Band.
        static let bandStyle = "bandStyle"
        /// Medienfilter: nur Bundle-IDs (G25).
        static let mediaExcluded = "mediaExcluded"
        /// 0.6.0 Mitteilungen und Anrufe in der Notch (G28–G30): Schalter, App-Liste (nur Kennungen), Anrufe.
        static let notifications = "notifications"
        static let notifyApps = "notifyApps"
        static let notifyCalls = "notifyCalls"
        /// 0.9.0 Ungelesen-Zahlen aus dem Dock (G33).
        static let notifyBadges = "notifyBadges"
        static let compactUnread = "compactUnread"
        /// 0.9.0 Code & KI (G34/G35): Claude-Code-Sitzungen in der Notch.
        static let claudeCode = "claudeCode"
        /// 0.7.0 Wetter (G31): Schalter, gewählter Ort (Name, Region, Land, gerundete Koordinaten), Einheit.
        static let weather = "weather"
        static let weatherPlace = "weatherPlace"
        static let weatherUnit = "weatherUnit"
        /// 0.8.0 Dateiablage (G32): Schalter, nach dem Rausziehen entfernen.
        static let shelf = "shelf"
        static let shelfRemoveOnDrag = "shelfRemoveOnDrag"
        static let shelfScreenshots = "shelfScreenshots"
        /// 0.11.0 Zwischenablage (G37–G41): Schalter, ausgeschlossene Apps, Pause, Seitenansicht, Tastenkürzel.
        static let clipboard = "clipboard"
        static let clipboardExcluded = "clipboardExcluded"
        static let clipboardPausedUntil = "clipboardPausedUntil"
        static let clipboardPanelEdge = "clipboardPanelEdge"
        static let clipboardPanelHotKey = "clipboardPanelHotKey"
        /// 0.13.0 Geheimnisse (G43): Schalter, „an seit“, wie viele gespeicherte Geheimnisse schon angeboten wurden.
        /// 0.14.0: Kürzel klappt zuerst aus der Notch herunter, nochmal → große Ansicht am Rand.
        static let clipboardNotchFirst = "clipboardNotchFirst"
        static let clipboardSecrets = "clipboardSecrets"
        static let clipboardSecretsSince = "clipboardSecretsSince"
        static let clipboardSecretsOffered = "clipboardSecretsOffered"
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
    /// 0.15.0: Cover + Titel hinter allen Fenstern auf dem Schreibtisch. Ab Werk **aus** (neue Bildschirmfläche).
    var desktopMusic: Bool { didSet { defaults.set(desktopMusic, forKey: Key.desktopMusic) } }
    var desktopMusicCorner: DesktopCorner {
        didSet { defaults.set(desktopMusicCorner.rawValue, forKey: Key.desktopMusicCorner) }
    }
    var desktopMusicSize: DesktopSize { didSet { defaults.set(desktopMusicSize.rawValue, forKey: Key.desktopMusicSize) } }
    /// Abstand des Covers zur Ecke – frei per Ziehen (Michael 26.10.: „ganz in die rechte untere Ecke“). Lage relativ zur
    /// nächsten Ecke, damit sie beim Bildschirmwechsel in derselben Ecke bleibt.
    var desktopMusicInset: CGSize {
        didSet {
            defaults.set(Double(desktopMusicInset.width), forKey: Key.desktopMusicInsetX)
            defaults.set(Double(desktopMusicInset.height), forKey: Key.desktopMusicInsetY)
        }
    }
    static let desktopMusicDefaultInset = CGSize(width: 24, height: 24)

    enum DesktopCorner: String, CaseIterable { case bottomLeft, bottomRight, topLeft, topRight }
    /// Covergröße in Punkten.
    enum DesktopSize: String, CaseIterable {
        case small, medium, large
        var cover: CGFloat {
            switch self {
            case .small: 120
            case .medium: 180
            case .large: 260
            }
        }
    }

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

    /// Wiedergabe immer groß (0.5.0): Player bleibt die große Ansicht, andere Aktivitäten als Glas-Schicht. Ab Werk aus.
    var playerFirst: Bool { didSet { defaults.set(playerFirst, forKey: Key.playerFirst) } }

    /// Wiedergabe-Knöpfe (Pause/Wiedergabe, Weiter) dauerhaft in der kleinen Insel (0.5.0). Ab Werk aus.
    var compactControls: Bool { didSet { defaults.set(compactControls, forKey: Key.compactControls) } }

    /// Aufklappen als Band (0.5.0): seitlich breit in Menüleisten-Höhe statt nach unten. Ab Werk aus (Insel).
    var bandStyle: Bool { didSet { defaults.set(bandStyle, forKey: Key.bandStyle) } }

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

    /// Mitteilungen in der Notch (0.6.0). Ab Werk **aus**: braucht das Hilfsprogramm mit Bedienungshilfen (G28).
    var notifications: Bool { didSet { defaults.set(notifications, forKey: Key.notifications) } }
    /// Anrufe in der Notch (0.6.0), wirkt nur bei eingeschalteten Mitteilungen.
    var notifyCalls: Bool { didSet { defaults.set(notifyCalls, forKey: Key.notifyCalls) } }
    /// Ungelesen-Zahlen der ausgewählten Apps (0.9.0, G33), wirkt nur bei eingeschalteten Mitteilungen. Ab Werk aus.
    var notifyBadges: Bool { didSet { defaults.set(notifyBadges, forKey: Key.notifyBadges) } }
    /// Zähler auch in der kleinen Insel (0.9.0). Ab Werk an, wirkt nur mit `notifyBadges`.
    var compactUnread: Bool { didSet { defaults.set(compactUnread, forKey: Key.compactUnread) } }
    /// Claude-Code-Sitzungen in der Notch (0.9.0). Ab Werk **aus**: trägt Hooks in `~/.claude/settings.json` ein (G35).
    var claudeCode: Bool { didSet { defaults.set(claudeCode, forKey: Key.claudeCode) } }
    /// Apps, deren Mitteilungen in die Notch dürfen (G29) – nur Kennungen, gleiche Regeln wie G25. Nur über
    /// `setNotifyApp`; `nil` = noch nie eingeschaltet (dann schlägt Gnotchi einmal Nachrichten-Apps vor).
    private(set) var notifyApps: [String]? { didSet { defaults.set(notifyApps, forKey: Key.notifyApps) } }

    /// Wetter in der Notch (0.7.0). Ab Werk **aus**: erster Netzzugriff außer Updates (G31).
    var weather: Bool { didSet { defaults.set(weather, forKey: Key.weather) } }
    /// Dateiablage (0.8.0). Ab Werk an: keine Freigabe, kein Netz (G32).
    var shelf: Bool { didSet { defaults.set(shelf, forKey: Key.shelf) } }
    var shelfRemoveOnDrag: Bool { didSet { defaults.set(shelfRemoveOnDrag, forKey: Key.shelfRemoveOnDrag) } }
    /// 0.10.0 (G36): Bildschirmfotos automatisch ablegen. Ab Werk aus (Michael 23.10.).
    var shelfScreenshots: Bool { didSet { defaults.set(shelfScreenshots, forKey: Key.shelfScreenshots) } }
    var weatherUnit: Weather.Unit { didSet { defaults.set(weatherUnit.rawValue, forKey: Key.weatherUnit) } }
    /// 0.11.0 Zwischenablage-Verlauf (G37). Ab Werk **aus**: liest mit, was der Nutzer kopiert (Michael 24.10.).
    var clipboard: Bool { didSet { defaults.set(clipboard, forKey: Key.clipboard) } }
    /// Apps, aus denen nie etwas in den Verlauf kommt (nur Kennungen, Regeln wie G25).
    private(set) var clipboardExcluded: [String] {
        didSet { defaults.set(clipboardExcluded, forKey: Key.clipboardExcluded) }
    }
    /// „30 Min. nicht mitlesen“ – bis zu diesem Zeitpunkt; nil = läuft.
    var clipboardPausedUntil: Date? {
        didSet { defaults.set(clipboardPausedUntil, forKey: Key.clipboardPausedUntil) }
    }
    var clipboardPanelEdge: PanelEdge { didSet { defaults.set(clipboardPanelEdge.rawValue, forKey: Key.clipboardPanelEdge) } }
    /// Seitenansicht öffnen (Vorschlag Ctrl+<, Tastencode wird aufgenommen, nicht fest eingetragen – 24.10. gemessen).
    var clipboardPanelHotKey: HotKey? {
        didSet { defaults.set(clipboardPanelHotKey?.stored, forKey: Key.clipboardPanelHotKey) }
    }

    /// 0.13.0 (G43): Schlüssel und Tokens erkennen, verdecken, lose nach 5 Min. löschen. Ab Werk **an** – speichert
    /// nur weniger, gibt nichts preis (Michael 26.10.). Einschalten setzt „an seit“ neu (Altbestand: volle 5 Min.).
    var clipboardSecrets: Bool {
        didSet {
            defaults.set(clipboardSecrets, forKey: Key.clipboardSecrets)
            if clipboardSecrets != oldValue { clipboardSecretsSince = clipboardSecrets ? Date() : nil }
        }
    }
    var clipboardSecretsSince: Date? { didSet { defaults.set(clipboardSecretsSince, forKey: Key.clipboardSecretsSince) } }
    /// Anzahl gespeicherter Geheimnisse beim letzten „Später“/Verschieben – das Angebot kommt erst bei mehr wieder.
    var clipboardSecretsOffered: Int { didSet { defaults.set(clipboardSecretsOffered, forKey: Key.clipboardSecretsOffered) } }

    /// Wo die große Ansicht sitzt. `notch` (0.14.0) ist nur intern die heruntergeklappte Stufe – gespeichert wird
    /// nur rechts/links/unten; ob zuerst aus der Notch, entscheidet `clipboardNotchFirst` (Michael 26.10.).
    enum PanelEdge: String, CaseIterable { case right, left, bottom, notch }
    /// 0.14.0: ⌃< klappt zuerst aus der Notch herunter; nochmal ⌃< oder „Mehr“ → große Ansicht am Rand. Ab Werk an.
    var clipboardNotchFirst: Bool { didSet { defaults.set(clipboardNotchFirst, forKey: Key.clipboardNotchFirst) } }

    /// Tastenkürzel als Carbon-Tastencode + Carbon-Modifikatoren. Gespeichert als zwei Zahlen.
    struct HotKey: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        var stored: [String: Int] { ["key": Int(keyCode), "mods": Int(modifiers)] }
        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
        /// Nur Tastencodes 0…127 und mindestens eine der vier Modifikator-Tasten (sonst würde jede Taste abgefangen).
        init?(stored: Any?) {
            guard let d = stored as? [String: Any], let key = d["key"] as? Int, let mods = d["mods"] as? Int,
                  (0...127).contains(key), mods & Self.allowedModifiers != 0, mods & ~Self.allowedModifiers == 0 else {
                return nil
            }
            self.init(keyCode: UInt32(key), modifiers: UInt32(mods))
        }
        /// cmdKey | shiftKey | optionKey | controlKey (Carbon).
        static let allowedModifiers = 0x0100 | 0x0200 | 0x0800 | 0x1000
    }

    var isClipboardPaused: Bool { (clipboardPausedUntil ?? .distantPast) > Date() }

    func isClipboardExcluded(_ bundleID: String) -> Bool { clipboardExcluded.contains(bundleID) }

    func setClipboardExcluded(_ bundleID: String, _ excluded: Bool) {
        var list = clipboardExcluded.filter { $0 != bundleID }
        if excluded { list.append(bundleID) }
        let valid = Self.validExcluded(list)
        if valid != clipboardExcluded { clipboardExcluded = valid }
    }
    /// Gewählter Ort; nur über die Ortssuche gesetzt. Gespeichert nur Name, Region, Land, gerundete Koordinaten.
    var weatherPlace: Weather.Place? {
        didSet {
            guard let p = weatherPlace else { return defaults.removeObject(forKey: Key.weatherPlace) }
            defaults.set(["name": p.name, "region": p.region, "country": p.country, "lat": p.latitude, "lon": p.longitude],
                         forKey: Key.weatherPlace)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` statt `bool(forKey:)`: ein fehlender Eintrag heißt „ab Werk“ (an),
        // nicht „aus“.
        notchMedia = defaults.object(forKey: Key.notchMedia) as? Bool ?? true
        desktopMusic = defaults.object(forKey: Key.desktopMusic) as? Bool ?? false
        desktopMusicCorner = defaults.string(forKey: Key.desktopMusicCorner).flatMap(DesktopCorner.init(rawValue:))
            ?? .bottomLeft
        desktopMusicSize = defaults.string(forKey: Key.desktopMusicSize).flatMap(DesktopSize.init(rawValue:)) ?? .medium
        let insetX = defaults.object(forKey: Key.desktopMusicInsetX) as? Double
        let insetY = defaults.object(forKey: Key.desktopMusicInsetY) as? Double
        desktopMusicInset = CGSize(width: max(0, min(insetX ?? 24, 4000)), height: max(0, min(insetY ?? 24, 4000)))
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
        playerFirst = defaults.object(forKey: Key.playerFirst) as? Bool ?? false
        compactControls = defaults.object(forKey: Key.compactControls) as? Bool ?? false
        bandStyle = defaults.object(forKey: Key.bandStyle) as? Bool ?? false
        mediaExcluded = Self.validExcluded(defaults.object(forKey: Key.mediaExcluded))
        notifications = defaults.object(forKey: Key.notifications) as? Bool ?? false
        notifyCalls = defaults.object(forKey: Key.notifyCalls) as? Bool ?? true
        notifyBadges = defaults.object(forKey: Key.notifyBadges) as? Bool ?? false
        compactUnread = defaults.object(forKey: Key.compactUnread) as? Bool ?? true
        claudeCode = defaults.object(forKey: Key.claudeCode) as? Bool ?? false
        notifyApps = defaults.object(forKey: Key.notifyApps).map { Self.validExcluded($0) }
        weather = defaults.object(forKey: Key.weather) as? Bool ?? false
        shelf = defaults.object(forKey: Key.shelf) as? Bool ?? true
        shelfRemoveOnDrag = defaults.object(forKey: Key.shelfRemoveOnDrag) as? Bool ?? true
        shelfScreenshots = defaults.object(forKey: Key.shelfScreenshots) as? Bool ?? false
        weatherUnit = (defaults.string(forKey: Key.weatherUnit)).flatMap(Weather.Unit.init(rawValue:)) ?? .celsius
        weatherPlace = Self.validPlace(defaults.object(forKey: Key.weatherPlace))
        clipboard = defaults.object(forKey: Key.clipboard) as? Bool ?? false
        clipboardExcluded = Self.validExcluded(defaults.object(forKey: Key.clipboardExcluded))
        clipboardPausedUntil = defaults.object(forKey: Key.clipboardPausedUntil) as? Date
        clipboardPanelEdge = defaults.string(forKey: Key.clipboardPanelEdge).flatMap(PanelEdge.init(rawValue:))
            .flatMap { $0 == .notch ? nil : $0 } ?? .right
        clipboardNotchFirst = defaults.object(forKey: Key.clipboardNotchFirst) as? Bool ?? true
        clipboardPanelHotKey = HotKey(stored: defaults.object(forKey: Key.clipboardPanelHotKey))
        clipboardSecrets = defaults.object(forKey: Key.clipboardSecrets) as? Bool ?? true
        clipboardSecretsOffered = max(0, defaults.integer(forKey: Key.clipboardSecretsOffered))
        // Erster Start mit 0.13.0 (oder Wert fehlt): ab jetzt zählen, nie rückwirkend sofort löschen.
        let since = defaults.object(forKey: Key.clipboardSecretsSince) as? Date
        clipboardSecretsSince = clipboardSecrets ? min(since ?? Date(), Date()) : nil
        // didSet läuft in init nicht – sonst bekäme jeder Neustart wieder volle 5 Minuten.
        defaults.set(clipboardSecretsSince, forKey: Key.clipboardSecretsSince)
    }

    /// Gespeicherter Ort nur mit gültigen Werten (per `defaults write` gesetzt → verworfen).
    nonisolated static func validPlace(_ stored: Any?) -> Weather.Place? {
        guard let d = stored as? [String: Any], let name = d["name"] as? String,
              let lat = Weather.number(d["lat"], -90...90), let lon = Weather.number(d["lon"], -180...180) else { return nil }
        let clean = NotifyWire.clean(name, max: Weather.maxPlaceName)
        guard !clean.isEmpty else { return nil }
        return Weather.Place(name: clean, region: NotifyWire.clean(d["region"] as? String ?? "", max: Weather.maxPlaceName),
                             country: NotifyWire.clean(d["country"] as? String ?? "", max: 3),
                             latitude: Weather.rounded(lat), longitude: Weather.rounded(lon))
    }

    func isNotifyApp(_ bundleID: String) -> Bool {
        notifyApps?.contains(bundleID) ?? false
    }

    func setNotifyApp(_ bundleID: String, _ on: Bool) {
        var list = (notifyApps ?? []).filter { $0 != bundleID }
        if on { list.append(bundleID) }
        let valid = Self.validExcluded(list)
        if valid != notifyApps { notifyApps = valid }
    }

    /// Beim ersten Einschalten: vorgeschlagene Apps übernehmen (nur einmal; danach entscheidet der Nutzer).
    func seedNotifyApps(_ ids: [String]) {
        guard notifyApps == nil else { return }
        notifyApps = Self.validExcluded(ids)
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
