import Darwin
import Foundation
import OSLog
import Security

// GnotchiDeck – Stream-Deck-Plugin für Gnotchi (0.35.0, SECURE-DESIGN G59, specs/2026-11-17-gnotchi-stream-deck-plus.md).
// Übersetzt Regler, Tasten und Leiste in Gnotchi-Befehle und zeigt Gnotchis Rückmeldung an. Keine Freigaben, keine eigene
// Audio-Logik. Schreibt nie auf stdout/stderr (Stream Deck protokolliert das je Plugin, M6), nur os_log mit festen Texten.

let log = Logger(subsystem: DeckWire.pluginID, category: "plugin")

/// Gestartet von Elgatos Stream Deck? Sonst still beenden (Gnotchi prüft dasselbe noch einmal, M2).
func parentIsStreamDeck() -> Bool {
    var req: SecRequirement?
    guard SecRequirementCreateWithString(DeckWire.streamDeckRequirement as CFString, [], &req) == errSecSuccess, let req else { return false }
    var code: SecCode?
    let attrs = [kSecGuestAttributePid: NSNumber(value: getppid())] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return false }
    return SecCodeCheckValidity(code, [], req) == errSecSuccess
}

/// Argumente von Stream Deck: `-port N -pluginUUID … -registerEvent … -info …`.
func streamDeckArguments(_ argv: [String]) -> (port: Int, uuid: String, register: String)? {
    var a: [String: String] = [:]
    var i = 1
    while i + 1 < argv.count { a[argv[i]] = argv[i + 1]; i += 2 }
    guard let p = a["-port"].flatMap(Int.init), (1...65_535).contains(p), let u = a["-pluginUUID"], let r = a["-registerEvent"] else {
        return nil
    }
    return (p, u, r)
}

/// Eine Aktion auf dem Gerät.
struct DeckAction {
    enum Kind { case volume, play }
    let kind: Kind
    /// Auf einem Drehregler (Leiste mit Layout) oder einer Taste. „App-Lautstärke“ geht auf beides: Aktionen nur für Regler
    /// zeigte Stream Deck 7.6.1 bei Michael gar nicht in der Liste (gemessen 17.11., Test A/B/C).
    var onDial: Bool
    var app: String
    var what: DeckWire.Play
    var marquee = Marquee()
    /// Titelzeile als Bild (nur auf einem Regler).
    var track: TrackImage?
    var lastFeedback: [String: String] = [:]
}

@MainActor
final class Plugin {

    static let volumeAction = "dev.mwlr.gnotchi.deck.volume"
    static let playAction = "dev.mwlr.gnotchi.deck.play"

    private let task: URLSessionWebSocketTask
    private let gnotchi = GnotchiSocket()
    private var actions: [String: DeckAction] = [:]
    private var status: [String: DeckWire.Status] = [:]
    private var tick: Timer?
    private var reconnect: Timer?
    /// Regler, an denen während des aktuellen Drucks schon gedreht wurde (Titel gesprungen): kein Stumm beim Loslassen.
    private var skippedWhilePressed: Set<String> = []

    /// Gedrückt drehen → `.some(Titelsprung)` beim ersten Drehen, `.some(nil)` bei weiterem Drehen im selben Druck
    /// (geschluckt), `nil` = nicht gedrückt, also Lautstärke.
    nonisolated static func pressGesture(pressed: Bool, ticks: Int, alreadySkipped: Bool) -> DeckWire.Play?? {
        guard pressed else { return nil }
        guard !alreadySkipped else { return .some(nil) }
        return .some(ticks > 0 ? .next : .previous)
    }

    init(port: Int, uuid: String, register: String) {
        task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()
        sendDeck(["event": register, "uuid": uuid])
        gnotchi.onStatus = { [weak self] s in self?.received(s) }
        gnotchi.onConnectionChange = { [weak self] up in self?.connectionChanged(up) }
        receiveLoop()
        tryConnect()
        reconnect = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.tryConnect() }
        }
        reconnect?.tolerance = 0.5
    }

    /// Lauftext-Takt nur, solange ein Regler wirklich scrollt: 12 Weckrufe je Sekunde rund um die Uhr kosteten Akku
    /// (Stream Deck läuft praktisch immer). 12 Bilder je Sekunde, 3 Pixel je Bild (pixelweise, Michael 17.11.).
    private func updateTickTimer() {
        let needed = actions.values.contains { $0.kind == .volume && $0.onDial && $0.marquee.scrolls }
        if needed, tick == nil {
            tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { _ in
                MainActor.assumeIsolated { [weak self] in self?.scrollTick() }
            }
            tick?.tolerance = 0.01
        } else if !needed, let t = tick {
            t.invalidate()
            tick = nil
        }
    }

    // MARK: Stream Deck

    private func sendDeck(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { error in if error != nil { log.error("Senden an Stream Deck fehlgeschlagen") } }
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .failure:
                    log.notice("Stream Deck getrennt – Ende")
                    exit(0)
                case .success(let msg):
                    if case .string(let s) = msg, let d = s.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        self?.handle(obj)
                    }
                    self?.receiveLoop()
                }
            }
        }
    }

    private func handle(_ obj: [String: Any]) {
        guard let event = obj["event"] as? String else { return }
        let ctx = obj["context"] as? String
        let payload = obj["payload"] as? [String: Any] ?? [:]
        switch event {
        case "willAppear", "didReceiveSettings":
            guard let ctx, let action = obj["action"] as? String else { return }
            let kind: DeckAction.Kind = action == Self.playAction ? .play : .volume
            let settings = payload["settings"] as? [String: Any] ?? [:]
            // Nur die feste Auswahl (17.11.); alles andere → „gerade spielend“. Hält auch `watch` sicher unter 512 Byte.
            let app = (settings["app"] as? String).flatMap { id in DeckWire.choices.contains { $0.id == id } ? id : nil }
                ?? DeckWire.current
            let what = (settings["what"] as? String).flatMap(DeckWire.Play.init(rawValue:)) ?? .toggle
            let onDial = (payload["controller"] as? String) == "Encoder"
            var a = actions[ctx] ?? DeckAction(kind: kind, onDial: onDial, app: app, what: what)
            if event == "willAppear" { a.onDial = onDial }
            if a.onDial, a.track == nil { a.track = TrackImage() }
            a.app = app
            a.what = what
            a.lastFeedback = [:]
            actions[ctx] = a
            sendWatch()
            render(ctx)
        case "willDisappear":
            guard let ctx else { return }
            actions[ctx] = nil
            sendWatch()
            updateTickTimer()
        case "dialRotate":
            guard let ctx, let a = actions[ctx], let ticks = payload["ticks"] as? Int, ticks != 0 else { return }
            if let gesture = Self.pressGesture(pressed: payload["pressed"] as? Bool ?? false, ticks: ticks,
                                               alreadySkipped: skippedWhilePressed.contains(ctx)) {
                // Gedrückt drehen: ein Titelsprung je Druck (Michael 17.11.: „nächsten und vorherigen Titel“).
                skippedWhilePressed.insert(ctx)
                if let what = gesture { gnotchi.send(.play(app: a.app, what: what)) }
                return
            }
            gnotchi.send(.gain(app: a.app, delta: min(DeckWire.maxDelta, max(-DeckWire.maxDelta, ticks * 2))))
        case "dialDown":
            guard let ctx else { return }
            skippedWhilePressed.remove(ctx)
        case "dialUp":
            // Stumm erst beim Loslassen – und nur, wenn nicht gedrückt gedreht (= Titel gesprungen) wurde.
            guard let ctx, let a = actions[ctx] else { return }
            if skippedWhilePressed.remove(ctx) == nil { gnotchi.send(.mute(app: a.app)) }
        case "touchTap":
            guard let ctx, let a = actions[ctx] else { return }
            gnotchi.send(.play(app: a.app, what: .toggle))
        case "keyDown":
            guard let ctx, let a = actions[ctx] else { return }
            if !gnotchi.isConnected { sendDeck(["event": "showAlert", "context": ctx]); return }
            // „App-Lautstärke“ auf einer Taste: drücken = stumm.
            gnotchi.send(a.kind == .volume ? .mute(app: a.app) : .play(app: a.app, what: a.what))
        default:
            break
        }
    }

    // MARK: Gnotchi

    private func tryConnect() {
        guard !gnotchi.isConnected, !actions.isEmpty else { return }
        gnotchi.connect()
    }

    private func connectionChanged(_ up: Bool) {
        if up {
            gnotchi.send(.hello(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"))
            sendWatch()
        } else {
            status = [:]
        }
        for ctx in actions.keys { actions[ctx]?.lastFeedback = [:]; render(ctx) }
    }

    private func sendWatch() {
        let apps = Array(NSOrderedSet(array: actions.values.map(\.app))) as? [String] ?? []
        if gnotchi.isConnected { gnotchi.send(.watch(Array(apps.prefix(DeckWire.maxWatched)))) } else { tryConnect() }
    }

    private func received(_ s: DeckWire.Status) {
        status[s.app] = s
        for (ctx, a) in actions where a.app == s.app { render(ctx) }
    }

    // MARK: Anzeige

    nonisolated static func trackText(_ s: DeckWire.Status?, connected: Bool) -> String {
        guard connected else { return "Gnotchi nicht verbunden" }
        guard let s else { return "…" }
        switch s.state {
        case .needsSetting: return "„Lautstärke je App“ in Gnotchi einschalten"
        case .needsPermission: return "Freigabe „Audio-Aufnahme“ fehlt"
        case .ok, .silent:
            if let t = s.title { return s.artist.map { "\(t) – \($0)" } ?? t }
            return s.state == .silent ? "kein Ton" : ""
        }
    }

    nonisolated static func percentText(_ s: DeckWire.Status?) -> String {
        guard let s else { return "" }
        if s.muted { return "stumm" }
        return s.percent.map { "\($0) %" } ?? ""
    }

    private func render(_ ctx: String) {
        guard var a = actions[ctx] else { return }
        let s = status[a.app]
        let connected = gnotchi.isConnected
        let name = s?.name ?? DeckWire.name(of: a.app) ?? "Gnotchi"
        switch a.kind {
        case .volume where !a.onDial:
            let title = connected ? "\(name)\n\n\(Self.percentText(s))" : "Gnotchi\n\naus"
            if a.lastFeedback["title"] != title {
                sendDeck(["event": "setTitle", "context": ctx, "payload": ["title": title, "target": 0]])
                a.lastFeedback["title"] = title
            }
        case .volume:
            let text = Self.trackText(s, connected: connected)
            let width = a.track?.prepare(text, gap: a.marquee.gap) ?? 0
            a.marquee.set(key: text, contentWidth: width)
            let bar = min(100, max(0, (s?.percent ?? 0) / 2))
            // `track` im Vergleich nur als Text + Versatz: das Bild selbst ändert sich genau dann.
            let fb: [String: String] = ["name": name, "pct": Self.percentText(s), "track": "\(text)|\(a.marquee.offset)", "bar": String(bar)]
            if fb != a.lastFeedback {
                var payload: [String: Any] = ["name": name, "pct": Self.percentText(s), "bar": ["value": bar]]
                if fb["track"] != a.lastFeedback["track"], let img = a.track?.frame(offset: a.marquee.offset) { payload["track"] = img }
                sendDeck(["event": "setFeedback", "context": ctx, "payload": payload])
                a.lastFeedback = fb
            }
        case .play:
            let symbol = switch a.what {
            case .toggle: (s?.playing ?? false) ? "❚❚" : "▶"
            case .next: "▶▶"
            case .previous: "◀◀"
            }
            let title = connected ? "\(name)\n\n\(symbol)" : "Gnotchi\n\naus"
            if a.lastFeedback["title"] != title {
                sendDeck(["event": "setTitle", "context": ctx, "payload": ["title": title, "target": 0]])
                a.lastFeedback["title"] = title
            }
        }
        actions[ctx] = a
        updateTickTimer()
    }

    private func scrollTick() {
        for (ctx, a) in actions where a.kind == .volume && a.onDial && a.marquee.scrolls {
            var m = a.marquee
            let moved = m.tick()
            actions[ctx]?.marquee = m   // auch in der Pause zurückschreiben, sonst zählt die Pause nie herunter (Fund 17.11.)
            guard moved else { continue }
            guard let img = a.track?.frame(offset: m.offset) else { continue }
            sendDeck(["event": "setFeedback", "context": ctx, "payload": ["track": img]])
            actions[ctx]?.lastFeedback["track"] = "\(m.key)|\(m.offset)"
        }
    }
}

guard parentIsStreamDeck() else {
    log.error("Nicht von Stream Deck gestartet – Ende")
    exit(0)
}
guard let args = streamDeckArguments(CommandLine.arguments) else {
    log.error("Argumente von Stream Deck fehlen – Ende")
    exit(1)
}
let plugin = Plugin(port: args.port, uuid: args.uuid, register: args.register)
withExtendedLifetime(plugin) { RunLoop.main.run() }
