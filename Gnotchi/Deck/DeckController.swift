import AppKit
import OSLog

/// Stream Deck (G59): übersetzt geprüfte Befehle in die vorhandenen Wege (Mixer, Wiedergabe) und baut die Rückmeldung.
/// Kein eigener Zugriff auf Core Audio oder Apple Events – nur über MixerModel und NowPlayingModel.
@MainActor
final class DeckController {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "streamdeck")

    private let mixer: MixerModel
    private let media: NowPlayingModel
    /// Was das Plugin gerade anzeigt (`watch`).
    private(set) var watched: [String] = []
    /// Wert vor dem Stummschalten je Bundle-ID (nur im Speicher, nie gemerkt).
    private var beforeMute: [String: Int] = [:]
    /// Browser-Weg (G59 Punkt 10), je Browser eine Instanz. Leer = Einstellung „Browser-Tab steuern“ aus: Kein Browser bekommt
    /// dann je ein Apple Event.
    var browsers: [String: BrowserTab] = [:]

    init(mixer: MixerModel, media: NowPlayingModel) {
        self.mixer = mixer
        self.media = media
    }

    func reset() {
        watched = []
        beforeMute = [:]
        artCache = nil
    }

    /// Zuletzt skaliertes Insel-Cover: dasselbe Bild wird nicht bei jeder Meldung neu kodiert.
    /// Hält das Bild selbst (Vergleich per `===`): eine bloße Adresse könnte nach dem Freigeben an ein neues Bild gehen.
    private var artCache: (image: NSImage, data: Data?)?

    /// Cover für eine beobachtete App (G59 Punkt 10e). Browser mit Browser-Weg und YouTube-Tab: Bild aus dem Tab. Sonst das Cover
    /// der Insel, aber nur für die App, die gerade spielt (der Adapter kennt nur die aktive Quelle). Kein Bild → nil.
    func cover(_ app: String) -> Data? {
        if let browser = browsers[app], browser.shown != nil { return browser.cover }
        guard let id = resolve(app), media.info?.appBundleID == id, let art = media.artwork else { return nil }
        if let c = artCache, c.image === art { return c.data }
        let data = DeckCover.render(art)
        artCache = (art, data)
        return data
    }

    /// `current` → Bundle-ID der aktiven Quelle (oder nil), sonst die Bundle-ID selbst.
    private func resolve(_ app: String) -> String? {
        app == DeckWire.current ? media.info?.appBundleID : app
    }

    private func row(_ id: String?) -> MixerAppRow? {
        guard let id else { return nil }
        return mixer.apps.first { $0.bundleID == id }
    }

    private static func isPlayer(_ id: String) -> Bool { AppleScriptSource.supported.contains(id) }

    // MARK: Befehle

    func handle(_ c: DeckWire.Command) {
        switch c {
        case .hello:
            break
        case .watch(let apps):
            watched = apps
        case .gain(let app, let delta):
            guard let id = resolve(app) else { return }
            gain(id, delta: delta)
        case .mute(let app):
            guard let id = resolve(app) else { return }
            toggleMute(id)
        case .play(let app, let what):
            // Browser mit eingeschaltetem Browser-Weg: gezielt am YouTube-Tab, egal welche Quelle macOS als aktiv führt.
            // Kein Tab bekannt (andere Seite spielt) → normaler Weg wie bisher.
            if what == .toggle, browsers[app]?.toggle() == true { return }
            let cmd: MediaAdapter.Command = switch what {
            case .toggle: .toggle
            case .next: .next
            case .previous: .previous
            }
            media.command(cmd, bundleID: app == DeckWire.current ? nil : app)
        case .route(let app, let device) where DeckWire.isSystem(app):
            // Ausgabe bzw. Mikrofon des Macs (0.38). `nil` hat hier keine Bedeutung (es gibt kein „eigenes Gerät“).
            guard let device else { return }
            if !mixer.selectDevice(uid: device, input: app == DeckWire.systemInput) {
                Self.log.notice("Stream Deck: Gerät gerade nicht angeschlossen, nichts umgestellt")
            }
        case .route(let app, let device):
            // Stufe 2 (G59): MixerModel prüft gegen die frische Geräteliste und „Lautstärke je App“.
            guard let id = resolve(app), let row = row(id) else {
                // Messpunkt 17.11.: nie still verwerfen.
                return Self.log.notice("Stream Deck: Umleiten – App gibt gerade keinen Ton aus oder spielt nichts")
            }
            mixer.setAppRoute(row, outputUID: device)
        }
    }

    private func gain(_ id: String, delta: Int) {
        guard let row = row(id) else { return }
        if Self.isPlayer(id) {
            guard let v = row.volume else { return }
            mixer.setPlayerVolume(bundleID: id, percent: min(100, max(0, v + delta)))
            beforeMute[id] = nil
            return
        }
        guard mixer.appVolumeEnabled, row.canTap else { return }
        let now = Self.percent(mixer.engine.gain(for: row.id))
        mixer.setAppGain(row, percent: Self.nextTapPercent(now, delta: delta))
        beforeMute[id] = nil
    }

    private func toggleMute(_ id: String) {
        guard let row = row(id) else { return }
        if Self.isPlayer(id) {
            guard let v = row.volume else { return }
            if v > 0 {
                beforeMute[id] = v
                mixer.setPlayerVolume(bundleID: id, percent: 0)
            } else {
                mixer.setPlayerVolume(bundleID: id, percent: beforeMute.removeValue(forKey: id) ?? 50)
            }
            return
        }
        guard mixer.appVolumeEnabled, row.canTap else { return }
        let now = Self.percent(mixer.engine.gain(for: row.id))
        if now > 0 {
            beforeMute[id] = now
            mixer.setAppGain(row, percent: 0, remember: false)
        } else {
            let back = beforeMute.removeValue(forKey: id) ?? mixer.remembered[id] ?? 100
            mixer.setAppGain(row, percent: back, remember: false)
        }
    }

    /// Titel, Zustand und Steuerbarkeit aus dem YouTube-Tab statt aus MediaRemote (das nur die aktive Quelle kennt).
    private func applyBrowser(to s: inout DeckWire.Status, app: String) {
        guard let browser = browsers[app] else { return }
        if let tab = browser.shown {
            s.title = tab.title
            s.artist = tab.artist
            s.playing = !tab.paused
            s.canPlay = true
        }
        s.needsBrowser = browser.latest.failure == .javascriptOff || browser.latest.failure == .denied
    }

    nonisolated static func percent(_ gain: Float) -> Int { Int((gain * 100).rounded()) }

    /// Nächster Wert für einen Tap-Regler. Der Mixer rastet ±3 um 100 % ein (dann kein Tap); in 2-%-Schritten käme man von 100
    /// nie weg. Deshalb springt der erste Schritt aus 100 heraus auf 96 bzw. 104.
    nonisolated static func nextTapPercent(_ now: Int, delta: Int) -> Int {
        let next = min(200, max(0, now + delta))
        if now == 100, MixerRows.snap(next) == 100, delta != 0 { return delta > 0 ? 104 : 96 }
        return next
    }

    // MARK: Rückmeldung

    func statuses() -> [DeckWire.Status] { watched.map(status) }

    /// Ausgabe oder Mikrofon des Macs: Geräte der Liste (Favoriten zuerst, wie im Mixer) und das gerade eingestellte.
    func systemStatus(_ app: String) -> DeckWire.Status {
        let input = app == DeckWire.systemInput
        var s = DeckWire.Status(app: app, name: input ? "Mikrofon" : "Ausgabe", title: nil, artist: nil, percent: nil,
                                muted: false, playing: false, canPlay: false, state: .ok)
        let favorites = mixer.favorites(input ? .input : .output)
        let rest = (input ? mixer.inputs : mixer.outputs).filter { d in !favorites.contains { $0.uid == d.uid } }
        let all = (favorites + rest).compactMap { d in d.uid.map { DeckWire.Output(uid: $0, name: d.name) } }
        s.outputs = Array(all.prefix(DeckWire.maxOutputs))
        // Das eingestellte Gerät immer mitschicken, auch wenn es hinter den ersten acht steht.
        if let current = (input ? mixer.input : mixer.output).device, let uid = current.uid {
            s.output = uid
            if !s.outputs.contains(where: { $0.uid == uid }) {
                s.outputs = [DeckWire.Output(uid: uid, name: current.name)] + s.outputs.prefix(DeckWire.maxOutputs - 1)
            }
        }
        s.canRoute = !s.outputs.isEmpty
        return s
    }

    func status(_ app: String) -> DeckWire.Status {
        if DeckWire.isSystem(app) { return systemStatus(app) }
        let id = resolve(app)
        let r = row(id)
        let info = media.info.flatMap { $0.appBundleID == id ? $0 : nil }
        let name = app == DeckWire.current
            ? (id.flatMap(DeckWire.name(of:)) ?? r?.name ?? (id == nil ? "Nichts spielt" : "Quelle"))
            : (DeckWire.name(of: app) ?? r?.name ?? app)
        let canPlay = id != nil && (id == media.info?.appBundleID
            || (Self.isPlayer(id ?? "") && AutomationStatus.shared.isAllowed(id ?? "")))
        var s = DeckWire.Status(app: app, name: name, title: info?.title, artist: info?.artist, percent: nil, muted: false,
                                playing: info?.isPlaying ?? false, canPlay: canPlay, state: .silent)
        applyBrowser(to: &s, app: app)
        guard let id else { return s }
        if let r, mixer.appVolumeEnabled, r.canTap {
            // Stufe 2: Auswahl = alle Ausgabegeräte, Favoriten zuerst (Michael 17.11.: nur Favoriten war zu eng, die
            // Lautsprecher fehlten). Dazu das Gerät, auf dem die App spielt.
            let favorites = mixer.favorites(.output)
            let rest = mixer.outputs.filter { d in !favorites.contains { $0.uid == d.uid } }
            s.outputs = (favorites + rest).prefix(DeckWire.maxOutputs)
                .compactMap { d in d.uid.map { DeckWire.Output(uid: $0, name: d.name) } }
            if let own = r.deviceUID, !s.outputs.contains(where: { $0.uid == own }), let dev = r.devices.first {
                s.outputs.insert(DeckWire.Output(uid: own, name: dev.name), at: 0)
            }
            s.outputs = Array(s.outputs.prefix(DeckWire.maxOutputs))
            s.output = r.route ?? r.deviceUID
            s.canRoute = true
            s.needsCapture = mixer.tapFailures[r.id] == .noSignal
        }
        if Self.isPlayer(id) {
            s.percent = r?.volume
            s.state = r?.volume == nil ? .silent : .ok
        } else if !mixer.appVolumeEnabled {
            s.state = .needsSetting
        } else if let r, r.canTap {
            s.percent = Self.percent(mixer.engine.gain(for: r.id))
            s.state = mixer.tapFailures[r.id] == .noSignal ? .needsPermission : .ok
        } else {
            s.percent = mixer.remembered[id]
        }
        s.muted = s.percent == 0
        return s
    }
}
