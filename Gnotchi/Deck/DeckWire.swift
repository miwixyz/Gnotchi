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
    /// Cover (G59 Punkt 10e): fertig skaliertes JPEG ≤ 5000 Byte (Base64 ≈ 6,7 KB). Eigene Nachricht mit eigenem, größerem Rahmen
    /// nur in Richtung Gnotchi → Plugin; Befehle bleiben bei `maxCommandBytes`. Nur an Plugins, die im `hello` `cover` melden –
    /// ein älteres Plugin würde den größeren Rahmen als ungültig werten und die Verbindung schließen.
    nonisolated static let maxCoverBytes = 5000
    nonisolated static let maxCoverFrame = 7168
    /// Längste Seite des Covers, das Gnotchi sendet (Taste 144 × 144 px bei @2x).
    nonisolated static let coverPixels = 144

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
        ("com.google.Chrome", "Chrome"),
        ("net.imput.helium", "Helium"),
        ("com.microsoft.edgemac", "Edge"),
        // 0.38: Teams für „App-Lautsprecher“ (Michael 18.11.: Teams bietet keinen Systemstandard, die Taste „Ausgabe“ erreicht
        // es nicht). Helfer-Prozesse (WebView, ModuleHost) fasst der Mixer unter der Haupt-App zusammen.
        ("com.microsoft.teams2", "Teams"),
    ]

    nonisolated static func name(of app: String) -> String? { choices.first { $0.id == app }?.name }

    /// Ausgabe und Mikrofon des ganzen Macs (0.38, Tasten „Ausgabe“ und „Mikrofon“, z. B. AirPods). Stehen in `watch` und `route`
    /// an der Stelle einer App, damit das Format gleich bleibt (ein älteres Gnotchi meldet sie nur als „kein Ton“). Kennungen aus
    /// Gnotchis eigenem Namensraum: keine fremde App trägt sie. In der Rückmeldung stehen in `outputs` dann die Geräte dieser
    /// Liste (beim Mikrofon die Eingänge) und in `output` das gerade eingestellte Gerät.
    nonisolated static let systemOutput = "dev.mwlr.gnotchi.system-output"
    nonisolated static let systemInput = "dev.mwlr.gnotchi.system-input"
    nonisolated static func isSystem(_ app: String) -> Bool { app == systemOutput || app == systemInput }

    enum Play: String, Sendable, CaseIterable { case toggle, next, previous }

    enum Command: Equatable, Sendable {
        /// `cover`: Plugin kann Cover-Nachrichten lesen (ab Plugin 0.36.0.3; fehlt das Feld → nein).
        case hello(version: String, cover: Bool = false)
        case watch([String])
        case gain(app: String, delta: Int)
        case mute(app: String)
        case play(app: String, what: Play)
        /// Stufe 2 (0.36.0): App auf ein Ausgabegerät legen; `nil` = zurück auf ihr eigenes.
        case route(app: String, device: String?)
    }

    /// Ein Ausgabegerät für die Auswahl am Regler.
    struct Output: Equatable, Sendable {
        let uid: String
        let name: String
    }
    nonisolated static let maxOutputs = 8

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
        /// Stufe 2: wählbare Ausgabegeräte (Favoriten, sonst alle) und das Gerät, auf dem die App gerade spielt. Zusätzliche
        /// Felder in derselben Nachricht – ein Plugin 0.35 ignoriert sie (neue Nachrichtenarten würden es trennen).
        var outputs: [Output] = []
        var output: String?
        /// Lässt sich die App umleiten (braucht „Lautstärke je App“ und genau ein Gerät)?
        var canRoute = false
        /// Der letzte Tap dieser App brachte nur Stille: Freigabe für Systemaudio fehlt (macOS fragt bei Gnotchi nicht
        /// selbst, gemessen 17.11. am Mac mini). Zusätzliches Feld, ältere Plugins ignorieren es.
        var needsCapture = false
        /// Browser-Weg (G59 Punkt 10): „Browser-Tab steuern“ ist an, aber der Browser lässt kein JavaScript zu oder Gnotchi darf ihn
        /// nicht steuern. Zusätzliches Feld, ältere Plugins ignorieren es (ein neuer `state`-Wert würde sie trennen).
        var needsBrowser = false
    }

    /// Geräte-UID von Core Audio: druckbares ASCII ohne Steuerzeichen, 1…200 Zeichen (z. B. „BuiltInSpeakerDevice“,
    /// „AppleUSBAudioEngine:…“). Gnotchi prüft zusätzlich gegen die frische Geräteliste (G20).
    nonisolated static func isValidDeviceUID(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 200 && s.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7F }
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
            guard version.count <= 32 else { return nil }
            return .hello(version: version, cover: obj["cover"] as? Bool ?? false)
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
        case "route":
            if obj["device"] is NSNull { return .route(app: app, device: nil) }
            guard let d = obj["device"] as? String, isValidDeviceUID(d) else { return nil }
            return .route(app: app, device: d)
        default:
            return nil
        }
    }

    nonisolated static func encode(_ c: Command) -> [String: Any] {
        switch c {
        case .hello(let version, let cover): cover ? ["v": 1, "hello": version, "cover": true] : ["v": 1, "hello": version]
        case .watch(let apps): ["v": 1, "watch": apps]
        case .gain(let app, let delta): ["v": 1, "cmd": "gain", "app": app, "delta": delta]
        case .mute(let app): ["v": 1, "cmd": "mute", "app": app]
        case .play(let app, let what): ["v": 1, "cmd": "play", "app": app, "what": what.rawValue]
        case .route(let app, let device): ["v": 1, "cmd": "route", "app": app, "device": device ?? NSNull()]
        }
    }

    // MARK: Rückmeldung (Gnotchi → Plugin)

    nonisolated static func encode(_ s: Status) -> [String: Any] {
        var o: [String: Any] = ["v": 1, "app": s.app, "name": s.name, "muted": s.muted, "playing": s.playing,
                                "canPlay": s.canPlay, "state": s.state.rawValue]
        if let t = s.title { o["title"] = String(t.prefix(maxTextChars)) }
        if let a = s.artist { o["artist"] = String(a.prefix(maxTextChars)) }
        if let p = s.percent { o["percent"] = p }
        if !s.outputs.isEmpty {
            o["outputs"] = s.outputs.prefix(maxOutputs).map { ["uid": $0.uid, "name": String($0.name.prefix(60))] }
        }
        if let out = s.output { o["output"] = out }
        if s.canRoute { o["canRoute"] = true }
        if s.needsCapture { o["needsCapture"] = true }
        if s.needsBrowser { o["needsBrowser"] = true }
        return o
    }

    // MARK: Cover (Gnotchi → Plugin, G59 Punkt 10e)

    /// Cover einer beobachteten App; `nil` = keines (mehr). Gnotchi schickt nur Bilder aus `DeckCover.render`.
    nonisolated static func encodeCover(app: String, jpeg: Data?) -> [String: Any] {
        ["v": 1, "cover": app, "img": jpeg.map { $0.base64EncodedString() } ?? NSNull()]
    }

    /// Plugin-Seite: Cover-Nachricht lesen. Nur JPEG (FF D8 FF), höchstens `maxCoverBytes`; sonst nil (Nachricht ungültig).
    /// Ist es keine Cover-Nachricht, ebenfalls nil – der Aufrufer versucht dann `parseStatus`.
    nonisolated static func parseCover(_ payload: Data) -> (app: String, jpeg: Data?)? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let v = obj["v"] as? NSNumber, v.doubleValue == 1,
              let app = obj["cover"] as? String, isValidApp(app) else { return nil }
        if obj["img"] is NSNull { return (app, nil) }
        guard let b64 = obj["img"] as? String, b64.utf8.count <= (maxCoverBytes + 2) / 3 * 4,
              let d = Data(base64Encoded: b64), d.count <= maxCoverBytes, d.starts(with: [0xFF, 0xD8, 0xFF]) else { return nil }
        return (app, d)
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
        var s = Status(app: app, name: clean(name) ?? app, title: clean(obj["title"] as? String),
                       artist: clean(obj["artist"] as? String), percent: percent,
                       muted: obj["muted"] as? Bool ?? false, playing: obj["playing"] as? Bool ?? false,
                       canPlay: obj["canPlay"] as? Bool ?? false, state: state)
        s.outputs = ((obj["outputs"] as? [[String: Any]]) ?? []).prefix(maxOutputs).compactMap { o in
            guard let uid = o["uid"] as? String, isValidDeviceUID(uid), let n = clean(o["name"] as? String) else { return nil }
            return Output(uid: uid, name: String(n.prefix(60)))
        }
        s.output = (obj["output"] as? String).flatMap { isValidDeviceUID($0) ? $0 : nil }
        s.canRoute = obj["canRoute"] as? Bool ?? false
        s.needsCapture = obj["needsCapture"] as? Bool ?? false
        s.needsBrowser = obj["needsBrowser"] as? Bool ?? false
        return s
    }

    /// Ist die gemeldete Plugin-Version älter als die eigene? Zahlenweise verglichen („0.35.0“ < „0.36.0“ < „0.100.0“).
    /// Unlesbare Versionen gelten als veraltet (dann lieber einmal neu installieren).
    nonisolated static func isOutdated(plugin: String, current: String) -> Bool {
        let parts = { (s: String) -> [Int]? in
            guard s.range(of: #"^\d{1,6}(\.\d{1,6}){0,3}$"#, options: .regularExpression) != nil else { return nil }
            return s.split(separator: ".").compactMap { Int($0) }
        }
        guard let p = parts(plugin) else { return true }
        guard let c = parts(current) else { return false }
        let n = max(p.count, c.count)
        let pad = { (a: [Int]) in a + Array(repeating: 0, count: n - a.count) }
        return pad(p).lexicographicallyPrecedes(pad(c))
    }

    nonisolated static func isAck(_ payload: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return false }
        return (obj["v"] as? NSNumber)?.doubleValue == 1 && obj["ok"] as? Bool == true
    }
}
