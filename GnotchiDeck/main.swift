import AppKit
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
    /// `device` = Taste „Ausgabe“ bzw. „Mikrofon“ des ganzen Macs (0.38); `app` ist dann `DeckWire.systemOutput`/`systemInput`.
    enum Kind { case volume, play, output, device }
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
    /// „App-Lautsprecher“: am Regler vorgewähltes, noch nicht übernommenes Gerät (UID).
    var preview: String?
    /// „App-Lautstärke“ auf einer Taste (alle Stream Decks ohne Regler, Michael 17.11.): Stumm, Lauter oder Leiser.
    var keyStep: KeyStep = .mute
    /// „Ausgabe“/„Mikrofon“: festes Gerät (UID) und sein zuletzt bekannter Name; nil = jeder Druck schaltet zum nächsten Gerät.
    var device: String?
    var deviceName: String?
}

enum KeyStep: String { case mute, up, down }

@MainActor
final class Plugin {

    static let volumeAction = "dev.mwlr.gnotchi.deck.volume"
    static let playAction = "dev.mwlr.gnotchi.deck.play"
    static let outputAction = "dev.mwlr.gnotchi.deck.output"
    static let systemOutputAction = "dev.mwlr.gnotchi.deck.system-output"
    static let systemInputAction = "dev.mwlr.gnotchi.deck.system-input"

    /// Nächstes Gerät in der Liste, ringförmig, ab `current` (unbekannt → Anfang). Rein, für den Regler und die Taste.
    nonisolated static func step(_ outputs: [DeckWire.Output], from current: String?, by ticks: Int) -> String? {
        guard !outputs.isEmpty else { return nil }
        let i = outputs.firstIndex { $0.uid == current } ?? 0
        let n = outputs.count
        return outputs[((i + ticks) % n + n) % n].uid
    }

    private let task: URLSessionWebSocketTask
    private let gnotchi = GnotchiSocket()
    private var actions: [String: DeckAction] = [:]
    private var status: [String: DeckWire.Status] = [:]
    /// Cover je App (G59 Punkt 10e): nur im Speicher, nie auf Platte, nie in Elgatos Profile, nie auf stdout/stderr.
    private var covers: [String: Data] = [:]
    /// Zählt je App jedes neue Cover: Teil des Bild-Schlüssels, sonst sähe `renderKey` beim Videowechsel „gleiches Bild“ (Audit 17.11.).
    private var coverGen: [String: Int] = [:]
    private var tick: Timer?
    private var reconnect: Timer?
    /// Kontext, dessen Einstellungsfeld gerade offen ist (bekommt die Geräteliste für „Ausgabe“/„Mikrofon“).
    private var inspector: String?
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
        gnotchi.onCover = { [weak self] app, jpeg in self?.receivedCover(app, jpeg) }
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
        let needed = actions.values.contains { $0.kind != .play && $0.onDial && $0.marquee.scrolls }
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
            let system = action == Self.systemOutputAction ? DeckWire.systemOutput
                : action == Self.systemInputAction ? DeckWire.systemInput : nil
            let kind: DeckAction.Kind = system != nil ? .device
                : action == Self.playAction ? .play : action == Self.outputAction ? .output : .volume
            let settings = payload["settings"] as? [String: Any] ?? [:]
            // Nur die feste Auswahl (17.11.); alles andere → „gerade spielend“. Hält auch `watch` sicher unter 512 Byte.
            let app = system ?? (settings["app"] as? String).flatMap { id in DeckWire.choices.contains { $0.id == id } ? id : nil }
                ?? DeckWire.current
            let what = (settings["what"] as? String).flatMap(DeckWire.Play.init(rawValue:)) ?? .toggle
            let keyStep = (settings["key"] as? String).flatMap(KeyStep.init(rawValue:)) ?? .mute
            let onDial = (payload["controller"] as? String) == "Encoder"
            var a = actions[ctx] ?? DeckAction(kind: kind, onDial: onDial, app: app, what: what)
            if event == "willAppear" { a.onDial = onDial }
            if a.onDial, a.track == nil { a.track = TrackImage() }
            a.app = app
            a.what = what
            a.keyStep = keyStep
            (a.device, a.deviceName) = DeviceKey.fixed(settings)
            a.lastFeedback = [:]
            actions[ctx] = a
            sendWatch()
            render(ctx)
        case "propertyInspectorDidAppear":
            inspector = ctx
            if let ctx { sendDevices(ctx) }
        case "propertyInspectorDidDisappear":
            if inspector == ctx { inspector = nil }
        case "willDisappear":
            guard let ctx else { return }
            actions[ctx] = nil
            sendWatch()
            updateTickTimer()
        case "dialRotate":
            guard let ctx, let a = actions[ctx], let ticks = payload["ticks"] as? Int, ticks != 0 else { return }
            if a.kind == .output || a.kind == .device {
                // Drehen wählt nur vor (Umschalten stört kurz den Ton); übernommen wird beim Drücken.
                let s = status[a.app]
                actions[ctx]?.preview = Self.step(s?.outputs ?? [], from: a.preview ?? s?.output, by: ticks > 0 ? 1 : -1)
                render(ctx)
                return
            }
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
            if a.kind == .output || a.kind == .device {
                if let p = a.preview, p != status[a.app]?.output { gnotchi.send(.route(app: a.app, device: p)) }
                actions[ctx]?.preview = nil
                render(ctx)
                return
            }
            if skippedWhilePressed.remove(ctx) == nil { gnotchi.send(.mute(app: a.app)) }
        case "touchTap":
            guard let ctx, let a = actions[ctx] else { return }
            if a.kind == .device {
                // Tippen: auf das feste Gerät (falls gewählt).
                if let d = a.device { gnotchi.send(.route(app: a.app, device: d)) }
                actions[ctx]?.preview = nil
                render(ctx)
                return
            }
            if a.kind == .output {
                // Tippen: zurück auf das eigene Gerät der App.
                gnotchi.send(.route(app: a.app, device: nil))
                actions[ctx]?.preview = nil
                render(ctx)
                return
            }
            gnotchi.send(.play(app: a.app, what: .toggle))
        case "keyDown":
            guard let ctx, let a = actions[ctx] else { return }
            if !gnotchi.isConnected { sendDeck(["event": "showAlert", "context": ctx]); return }
            switch a.kind {
            case .volume:
                // „App-Lautstärke“ auf einer Taste: je nach Einstellung stumm, lauter oder leiser (±5 % je Druck).
                switch a.keyStep {
                case .mute: gnotchi.send(.mute(app: a.app))
                case .up: gnotchi.send(.gain(app: a.app, delta: 5))
                case .down: gnotchi.send(.gain(app: a.app, delta: -5))
                }
            case .play: gnotchi.send(.play(app: a.app, what: a.what))
            case .output:
                // Taste: jedes Drücken legt die App auf das nächste Gerät.
                let s = status[a.app]
                if let next = Self.step(s?.outputs ?? [], from: s?.output, by: 1) { gnotchi.send(.route(app: a.app, device: next)) }
            case .device:
                // Festes Gerät → genau dieses; sonst das nächste der Liste. Nicht angeschlossen → Warnzeichen (nie stumm).
                let s = status[a.app]
                guard let target = a.device ?? Self.step(s?.outputs ?? [], from: s?.output, by: 1) else {
                    sendDeck(["event": "showAlert", "context": ctx]); return
                }
                gnotchi.send(.route(app: a.app, device: target))
                if !(s?.outputs ?? []).contains(where: { $0.uid == target }) { sendDeck(["event": "showAlert", "context": ctx]) }
            }
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
            gnotchi.send(.hello(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0", cover: true))
            sendWatch()
        } else {
            status = [:]
            covers = [:]
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
        if let ctx = inspector, actions[ctx]?.app == s.app { sendDevices(ctx) }
    }

    private func receivedCover(_ app: String, _ jpeg: Data?) {
        covers[app] = jpeg
        coverGen[app, default: 0] += 1
        coverCache = [:]
        for (ctx, a) in actions where a.app == app { render(ctx) }
    }

    /// Geräteliste ans offene Einstellungsfeld von „Ausgabe“/„Mikrofon“ (Auswahl des festen Geräts).
    private func sendDevices(_ ctx: String) {
        guard let a = actions[ctx], a.kind == .device else { return }
        let s = status[a.app]
        let devices = (s?.outputs ?? []).map { ["uid": $0.uid, "name": $0.name] }
        sendDeck(["event": "sendToPropertyInspector", "context": ctx,
                  "payload": ["devices": devices, "current": s?.output ?? ""]])
    }

    // MARK: Anzeige

    nonisolated static func trackText(_ s: DeckWire.Status?, connected: Bool) -> String {
        guard connected else { return "Gnotchi nicht verbunden" }
        guard let s else { return "…" }
        switch s.state {
        case .needsSetting: return "„Lautstärke je App“ in Gnotchi einschalten"
        case .needsPermission: return "Freigabe „Audio-Aufnahme“ fehlt"
        case .ok, .silent:
            // G59 Punkt 10: Browser-Weg gestört (Schalter im Browser aus oder Automation verweigert) → nie stumm scheitern.
            // Beide Ursachen nennen: Das Plugin erfährt nur „gestört“, nicht welche (Audit 17.11.).
            if s.needsBrowser {
                return "\(s.name): „JavaScript von Apple Events“ einschalten – oder Gnotchi in den Systemeinstellungen die Steuerung von \(s.name) erlauben"
            }
            if let t = s.title { return s.artist.map { "\(t) – \($0)" } ?? t }
            return s.state == .silent ? "kein Ton" : ""
        }
    }

    /// Titel der Wiedergabe-Taste. Browser-Weg gestört → Hinweis statt App-Name (Messung 17.11.: Taste blieb sonst unverändert).
    nonisolated static func playTitle(_ s: DeckWire.Status?, name: String, connected: Bool) -> String {
        guard connected else { return "Gnotchi aus" }
        // Neutral statt „JS erlauben“: Ursache kann auch die verweigerte Steuerung sein, Details stehen auf der Leiste (Audit 17.11.).
        return s?.needsBrowser == true ? "\(name)\nfreigeben" : name
    }

    nonisolated static func percentText(_ s: DeckWire.Status?) -> String {
        guard let s else { return "" }
        if s.muted { return "stumm" }
        return s.percent.map { "\($0) %" } ?? ""
    }

    /// Zeile für „App-Lautsprecher“: vorgewähltes oder aktuelles Gerät.
    nonisolated static func outputText(_ s: DeckWire.Status?, preview: String?, connected: Bool) -> String {
        guard connected else { return "Gnotchi nicht verbunden" }
        guard let s else { return "…" }
        guard s.canRoute else { if DeckWire.isSystem(s.app) { return "…" }; return s.state == .needsSetting ? "„Lautstärke je App“ in Gnotchi einschalten" : "kein Ton" }
        // Stille nach dem Umleiten: pausiert (Browser halten den Ausgang offen) oder Freigabe fehlt – beides nennen (Audit 17.11.).
        if s.needsCapture, preview == nil { return "Kein Ton angekommen – pausiert? Sonst fehlt die Freigabe für Systemaudio" }
        let shown = preview ?? s.output
        let name = s.outputs.first { $0.uid == shown }?.name ?? "?"
        return preview != nil && preview != s.output ? "\(name) · drücken" : name
    }

    // MARK: Tastenbilder (Michael 17.11.: „schöne passende Icons“)

    /// Bild der Taste je Aktion und Zustand (Dateien aus dem Vault-Skill `streamdeck-glas`, Designsprache „Glas“).
    nonisolated static func keyImage(kind: DeckAction.Kind, what: DeckWire.Play, keyStep: KeyStep, playing: Bool, muted: Bool) -> String {
        switch kind {
        case .play:
            switch what {
            case .toggle: playing ? "key-pause" : "key-play"
            case .next: "key-next"
            case .previous: "key-previous"
            }
        case .volume:
            switch keyStep {
            case .mute: muted ? "key-muted" : "key-mute"
            case .up: "key-volume-up"
            case .down: "key-volume-down"
            }
        case .output: "key-output"
        case .device: "key-sysout"
        }
    }

    private var imageCache: [String: String] = [:]
    /// Fertige Cover-Tasten als `data:`-URL, Schlüssel `cover:<App>:<Zustand>` (geleert bei jedem neuen Cover).
    private var coverCache: [String: String] = [:]

    /// Wiedergabe-Taste (Play/Pause) mit Cover: Bild auf 144 × 144 eingepasst, Zustand als kleines Zeichen oben rechts.
    /// Kein Cover, andere Taste oder nicht verbunden → nil (dann das normale Symbol).
    private func coverImage(app: String, what: DeckWire.Play, playing: Bool, connected: Bool) -> String? {
        guard connected, what == .toggle, let jpeg = covers[app] else { return nil }
        let key = "cover:\(app):\(coverGen[app] ?? 0):\(playing ? "p" : "s")"
        if coverCache[key] != nil { return key }
        guard let png = Self.coverKey(jpeg: jpeg, playing: playing) else { return nil }
        coverCache[key] = "data:image/png;base64," + png.base64EncodedString()
        return key
    }

    nonisolated static func coverKey(jpeg: Data, playing: Bool) -> Data? {
        let side = 144
        guard let src = NSImage(data: jpeg), src.size.width > 0, src.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        defer { NSGraphicsContext.restoreGraphicsState() }
        let full = NSRect(x: 0, y: 0, width: side, height: side)
        NSColor.black.setFill()
        full.fill()
        let scale = min(Double(side) / src.size.width, Double(side) / src.size.height)
        let w = src.size.width * scale, h = src.size.height * scale
        src.draw(in: NSRect(x: (Double(side) - w) / 2, y: (Double(side) - h) / 2, width: w, height: h))
        // Zustand: dunkler Kreis + weißes Zeichen oben rechts (wie die Taste ohne Cover: spielt → Pause-Zeichen).
        let badge = NSRect(x: side - 44, y: side - 44, width: 36, height: 36)
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(ovalIn: badge).fill()
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        if let glyph = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let tinted = NSImage(size: glyph.size, flipped: false) { r in
                glyph.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: badge.midX - glyph.size.width / 2, y: badge.midY - glyph.size.height / 2,
                                   width: glyph.size.width, height: glyph.size.height))
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// PNG aus dem Plugin-Ordner als `data:`-URL (einmal gelesen, dann aus dem Speicher).
    private func imageData(_ name: String) -> String? {
        if let hit = imageCache[name] { return hit }
        let dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("imgs/\(name)@2x.png")) else { return nil }
        let url = "data:image/png;base64," + d.base64EncodedString()
        imageCache[name] = url
        return url
    }

    /// Bild und Titel einer Taste setzen – nur bei Änderung. `cover:`-Namen kommen aus `coverImage`, alle anderen aus `imgs/`.
    private func renderKey(_ ctx: String, _ a: inout DeckAction, image: String, title: String) {
        let data = image.hasPrefix("cover:") ? coverCache[image] : imageData(image)
        if a.lastFeedback["image"] != image, let data {
            sendDeck(["event": "setImage", "context": ctx, "payload": ["image": data, "target": 0]])
            a.lastFeedback["image"] = image
        }
        if a.lastFeedback["title"] != title {
            sendDeck(["event": "setTitle", "context": ctx, "payload": ["title": title, "target": 0]])
            a.lastFeedback["title"] = title
        }
    }

    private func render(_ ctx: String) {
        guard var a = actions[ctx] else { return }
        let s = status[a.app]
        let connected = gnotchi.isConnected
        let name = s?.name ?? DeckWire.name(of: a.app) ?? "Gnotchi"
        switch a.kind {
        case .volume where !a.onDial:
            let pct = Self.percentText(s)
            // Zwei Zeilen statt „App · Prozent“ (abgeschnitten auf der Taste, Screenshot 17.11.).
            let title = connected ? (pct.isEmpty ? name : "\(name)\n\(pct)") : "Gnotchi aus"
            renderKey(ctx, &a, image: Self.keyImage(kind: .volume, what: a.what, keyStep: a.keyStep, playing: false,
                                                   muted: s?.muted ?? false), title: title)
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
        case .output where !a.onDial:
            let device = Self.outputText(s, preview: nil, connected: connected)
            // Nur das Gerät: App + Gerät passte nicht auf die Taste (Screenshot 17.11.: „Externe Kopfhö…“).
            renderKey(ctx, &a, image: "key-output", title: connected ? device : "Gnotchi aus")
        case .device where !a.onDial:
            let k = DeviceKey.look(s, input: a.app == DeckWire.systemInput, fixed: a.device, fixedName: a.deviceName,
                                   connected: connected)
            renderKey(ctx, &a, image: k.image, title: k.title)
        case .output, .device:
            let text = Self.outputText(s, preview: a.preview, connected: connected)
            let width = a.track?.prepare(text, gap: a.marquee.gap) ?? 0
            a.marquee.set(key: text, contentWidth: width)
            let fb: [String: String] = ["name": name, "pct": "", "track": "\(text)|\(a.marquee.offset)", "bar": "0"]
            if fb != a.lastFeedback {
                var payload: [String: Any] = ["name": name, "pct": "", "bar": ["value": 0]]
                if fb["track"] != a.lastFeedback["track"], let img = a.track?.frame(offset: a.marquee.offset) { payload["track"] = img }
                sendDeck(["event": "setFeedback", "context": ctx, "payload": payload])
                a.lastFeedback = fb
            }
        case .play:
            let playing = s?.playing ?? false
            let image = coverImage(app: a.app, what: a.what, playing: playing, connected: connected)
                ?? Self.keyImage(kind: .play, what: a.what, keyStep: a.keyStep, playing: playing, muted: false)
            renderKey(ctx, &a, image: image, title: Self.playTitle(s, name: name, connected: connected))
        }
        actions[ctx] = a
        updateTickTimer()
    }

    private func scrollTick() {
        for (ctx, a) in actions where a.kind != .play && a.onDial && a.marquee.scrolls {
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
