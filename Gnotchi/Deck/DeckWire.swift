import Foundation

/// Stream Deck (SECURE-DESIGN G59, specs/2026-11-17-gnotchi-stream-deck-plus.md): Nachrichtenformat zwischen Gnotchi und dem
/// Plugin „GnotchiDeck“. Dieselbe Datei in beiden Zielen, damit Senden und Prüfen nie auseinanderlaufen. Rahmen wie Live-Text
/// (4 Byte Länge + JSON, `LiveText.frame`/`nextFrame`).
enum DeckWire {

    nonisolated static let socketName = "deck.sock"
    nonisolated static let pluginID = "dev.mwlr.gnotchi.deck"
    /// Ordner des Plugins in Gnotchis Resources und Name des Pakets für Stream Deck.
    nonisolated static let pluginFolder = "dev.mwlr.gnotchi.deck.sdPlugin"
    /// Programmdatei im Plugin-Ordner (Manifest `CodePath`).
    nonisolated static let executable = "gnotchideck"
    /// Größter Rahmen: Rückmeldungen tragen Titel und Interpret (je ≤ 200 Zeichen, UTF-8 bis 4 Byte).
    nonisolated static let maxFrame = 4096
    /// Größte Befehlsnachricht (Plugin → Gnotchi). Befehle sind klein; mehr ist kein Befehl.
    nonisolated static let maxCommandBytes = 512
    nonisolated static let maxWatched = 8
    nonisolated static let maxDelta = 20
    nonisolated static let maxTextChars = 200
    /// Höchstens so viele Befehle je Sekunde (M4: normal gedreht bis 9 Ereignisse/s).
    nonisolated static let maxPerSecond = 50

    /// Elgatos Stream-Deck-App (gemessen 17.11.: `Developer ID Application: Corsair Memory, Inc. (Y93VXCB8Q5)`).
    nonisolated static let streamDeckRequirement =
        #"anchor apple generic and identifier "com.elgato.StreamDeck" and certificate leaf[subject.OU] = "Y93VXCB8Q5""#

    /// Gnotchi selbst (das Plugin prüft den lauschenden Prozess, bevor es sendet).
    nonisolated static let gnotchiRequirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "dev.mwlr.gnotchi" and "#
        + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

    /// Auswahl im Plugin (entschieden 17.11.). `current` = die Quelle, die Gnotchi in der Insel zeigt.
    nonisolated static let current = "current"
    nonisolated static let choices: [(id: String, name: String)] = [
        (current, "Gerade spielend"),
        ("com.spotify.client", "Spotify"),
        ("com.apple.Music", "Musik"),
        ("com.apple.podcasts", "Podcasts"),
        ("com.apple.Safari", "Safari"),
        ("net.imput.helium", "Helium"),
        ("com.microsoft.edgemac", "Edge"),
    ]

    nonisolated static func name(of app: String) -> String? { choices.first { $0.id == app }?.name }

    enum Play: String, Sendable, CaseIterable { case toggle, next, previous }

    enum Command: Equatable, Sendable {
        case hello(version: String)
        case watch([String])
        case gain(app: String, delta: Int)
        case mute(app: String)
        case play(app: String, what: Play)
    }

    /// Zustand einer beobachteten App für die Anzeige.
    enum State: String, Sendable {
        /// Regelbar.
        case ok
        /// Gibt gerade keinen Ton aus (kein Regler möglich).
        case silent
        /// „Lautstärke je App“ ist aus (Browser & Co.).
        case needsSetting
        /// Tap gescheitert (meist Freigabe „Audio-Aufnahme“ fehlt).
        case needsPermission
    }

    struct Status: Equatable, Sendable {
        let app: String
        let name: String
        var title: String?
        var artist: String?
        var percent: Int?
        var muted: Bool
        var playing: Bool
        /// Wiedergabe lässt sich steuern (Spotify/Musik immer, sonst nur als aktive Quelle).
        var canPlay: Bool
        var state: State
    }

    // MARK: Prüfen (Gnotchi-Seite)

    /// Bundle-ID oder `current`, nur erlaubte Zeichen, nicht leer, höchstens 128.
    nonisolated static func isValidApp(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 128 else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "." || $0 == "-" }
    }

    /// Eine Befehlsnachricht. `v` muss die Zahl 1 sein. Alles andere oder Unbekanntes → nil (Verbindung zu).
    nonisolated static func parse(_ payload: Data) -> Command? {
        guard payload.count <= maxCommandBytes,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let v = obj["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(), v.doubleValue == 1 else { return nil }
        if let version = obj["hello"] as? String {
            return version.count <= 32 ? .hello(version: version) : nil
        }
        if let list = obj["watch"] as? [Any] {
            let apps = list.compactMap { $0 as? String }
            guard apps.count == list.count, apps.count <= maxWatched, apps.allSatisfy(isValidApp) else { return nil }
            return .watch(Array(NSOrderedSet(array: apps)) as? [String] ?? apps)
        }
        guard let cmd = obj["cmd"] as? String, let app = obj["app"] as? String, isValidApp(app) else { return nil }
        switch cmd {
        case "gain":
            guard let d = obj["delta"] as? NSNumber, CFGetTypeID(d) != CFBooleanGetTypeID(),
                  d.doubleValue == d.doubleValue.rounded(), abs(d.doubleValue) <= Double(maxDelta) else { return nil }
            return .gain(app: app, delta: d.intValue)
        case "mute":
            return .mute(app: app)
        case "play":
            guard let w = obj["what"] as? String, let what = Play(rawValue: w) else { return nil }
            return .play(app: app, what: what)
        default:
            return nil
        }
    }

    nonisolated static func encode(_ c: Command) -> [String: Any] {
        switch c {
        case .hello(let version): ["v": 1, "hello": version]
        case .watch(let apps): ["v": 1, "watch": apps]
        case .gain(let app, let delta): ["v": 1, "cmd": "gain", "app": app, "delta": delta]
        case .mute(let app): ["v": 1, "cmd": "mute", "app": app]
        case .play(let app, let what): ["v": 1, "cmd": "play", "app": app, "what": what.rawValue]
        }
    }

    // MARK: Rückmeldung (Gnotchi → Plugin)

    nonisolated static func encode(_ s: Status) -> [String: Any] {
        var o: [String: Any] = ["v": 1, "app": s.app, "name": s.name, "muted": s.muted, "playing": s.playing,
                                "canPlay": s.canPlay, "state": s.state.rawValue]
        if let t = s.title { o["title"] = String(t.prefix(maxTextChars)) }
        if let a = s.artist { o["artist"] = String(a.prefix(maxTextChars)) }
        if let p = s.percent { o["percent"] = p }
        return o
    }

    /// Plugin-Seite: Rückmeldung lesen. Texte werden erneut bereinigt und gekürzt (das Plugin vertraut nur der Form).
    nonisolated static func parseStatus(_ payload: Data) -> Status? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let v = obj["v"] as? NSNumber, v.doubleValue == 1,
              let app = obj["app"] as? String, isValidApp(app),
              let name = obj["name"] as? String,
              let state = (obj["state"] as? String).flatMap(State.init(rawValue:)) else { return nil }
        let clean = { (s: String?) in s.map { String(LiveText.sanitize($0).prefix(maxTextChars)) }.flatMap { $0.isEmpty ? nil : $0 } }
        let percent = (obj["percent"] as? NSNumber).map { min(200, max(0, $0.intValue)) }
        return Status(app: app, name: clean(name) ?? app, title: clean(obj["title"] as? String),
                      artist: clean(obj["artist"] as? String), percent: percent,
                      muted: obj["muted"] as? Bool ?? false, playing: obj["playing"] as? Bool ?? false,
                      canPlay: obj["canPlay"] as? Bool ?? false, state: state)
    }

    nonisolated static func isAck(_ payload: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return false }
        return (obj["v"] as? NSNumber)?.doubleValue == 1 && obj["ok"] as? Bool == true
    }
}
