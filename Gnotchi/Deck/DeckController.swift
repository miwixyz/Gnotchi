import Foundation

/// Stream Deck (G59): übersetzt geprüfte Befehle in die vorhandenen Wege (Mixer, Wiedergabe) und baut die Rückmeldung.
/// Kein eigener Zugriff auf Core Audio oder Apple Events – nur über MixerModel und NowPlayingModel.
@MainActor
final class DeckController {

    private let mixer: MixerModel
    private let media: NowPlayingModel
    /// Was das Plugin gerade anzeigt (`watch`).
    private(set) var watched: [String] = []
    /// Wert vor dem Stummschalten je Bundle-ID (nur im Speicher, nie gemerkt).
    private var beforeMute: [String: Int] = [:]

    init(mixer: MixerModel, media: NowPlayingModel) {
        self.mixer = mixer
        self.media = media
    }

    func reset() {
        watched = []
        beforeMute = [:]
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
            let cmd: MediaAdapter.Command = switch what {
            case .toggle: .toggle
            case .next: .next
            case .previous: .previous
            }
            media.command(cmd, bundleID: app == DeckWire.current ? nil : app)
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
            if v > 0 { beforeMute[id] = v; mixer.setPlayerVolume(bundleID: id, percent: 0) }
            else { mixer.setPlayerVolume(bundleID: id, percent: beforeMute.removeValue(forKey: id) ?? 50) }
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

    func status(_ app: String) -> DeckWire.Status {
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
        guard let id else { return s }
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
