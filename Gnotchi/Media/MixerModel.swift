import CoreAudio
import Foundation

/// Eine App mit Ton im Mixer (0.30.0, G54): eine Zeile je App, nicht je Prozess (Browser spielen aus Helfer-Prozessen).
/// Lautstärke nur für Spotify und Musik (AppleScript, wenn erlaubt); für alle anderen steht das Gerät da, der Regler je App
/// braucht Prozess-Taps (Mixer Stufe 2, eigene Freigabe).
struct MixerAppRow: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let bundleID: String?
    let devices: [OutputDevices.Device]
    var volume: Int?
}

enum MixerRows {
    nonisolated static let maxRows = 12

    /// Nur Prozesse, die gerade Ton ausgeben, nur solche in einer App (kein Systemdienst), nicht Gnotchi selbst; Prozesse
    /// derselben App werden zusammengefasst, Geräte vereinigt. Sortiert nach Name.
    nonisolated static func rows(_ processes: [MixerAudio.Process], devices: [AudioObjectID: OutputDevices.Device],
                                 ownPID: pid_t, name: (String) -> String?, bundle: (String) -> String?) -> [MixerAppRow] {
        var order: [String] = []
        var byApp: [String: (path: String, devices: [AudioObjectID])] = [:]
        for p in processes where p.outputting && p.pid != ownPID {
            guard let app = PrivacyMonitor.outermostApp(path: p.path) else { continue }
            if byApp[app] == nil { order.append(app); byApp[app] = (app, []) }
            for d in p.devices where !(byApp[app]?.devices.contains(d) ?? false) { byApp[app]?.devices.append(d) }
        }
        let rows = order.compactMap { app -> MixerAppRow? in
            guard let entry = byApp[app], let n = name(app) else { return nil }
            return MixerAppRow(id: app, name: n, bundleID: bundle(app), devices: entry.devices.compactMap { devices[$0] }, volume: nil)
        }
        return Array(rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.prefix(maxRows))
    }

    /// Prozent aus 0…1, begrenzt.
    nonisolated static func percent(_ v: Float?) -> Int? { v.map { Int((min(1, max(0, $0)) * 100).rounded()) } }
}

/// Zustand des Mixers. Läuft nur, solange er sichtbar ist (`start`/`stop`): kein Dauer-Beobachter.
@MainActor
@Observable
final class MixerModel {

    struct Endpoint: Equatable {
        var device: OutputDevices.Device?
        var volume: Float?
        var muted: Bool?
        var canSetVolume = false
        var canMute = false
    }

    private(set) var output = Endpoint()
    private(set) var systemOutput: OutputDevices.Device?
    private(set) var input = Endpoint()
    private(set) var outputs: [OutputDevices.Device] = []
    private(set) var inputs: [OutputDevices.Device] = []
    private(set) var apps: [MixerAppRow] = []

    @ObservationIgnored private let script: AppleScriptSource
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Nach einer Eingabe kurz nicht überschreiben, damit der Regler beim Ziehen nicht zurückspringt.
    @ObservationIgnored private var holdUntil: Date = .distantPast
    @ObservationIgnored private let interval: Duration
    /// Beim Ziehen am App-Regler: je App höchstens ein Aufruf gleichzeitig, immer mit dem neuesten Wert (kein Stau von Apple Events).
    @ObservationIgnored private var pendingPlayer: [String: Int] = [:]
    @ObservationIgnored private var sendingPlayer: Set<String> = []

    init(script: AppleScriptSource = AppleScriptSource(), interval: Duration = .milliseconds(1500)) {
        self.script = script
        self.interval = interval
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.interval ?? .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh() async {
        guard Date() >= holdUntil else { return }
        outputs = OutputDevices.ordered(OutputDevices.list())
        inputs = MixerAudio.inputDevices()
        output = endpoint(.output)
        input = endpoint(.input)
        systemOutput = MixerAudio.defaultDevice(.systemOutput).flatMap { OutputDevices.device($0) }
        let byID = Dictionary(uniqueKeysWithValues: outputs.map { ($0.id, $0) })
        var rows = MixerRows.rows(MixerAudio.audioProcesses(), devices: byID, ownPID: ProcessInfo.processInfo.processIdentifier,
                                  name: { AppIcons.cleanName(FileManager.default.displayName(atPath: $0)) },
                                  bundle: { Bundle(path: $0)?.bundleIdentifier })
        for i in rows.indices {
            guard let id = rows[i].bundleID, AppleScriptSource.supported.contains(id) else { continue }
            rows[i].volume = await script.volume(.read, bundleID: id)
        }
        if rows != apps { apps = rows }
    }

    private func endpoint(_ which: MixerAudio.Selector) -> Endpoint {
        guard let id = MixerAudio.defaultDevice(which) else { return Endpoint() }
        return Endpoint(device: OutputDevices.device(id), volume: MixerAudio.volume(id, scope: which.scope),
                        muted: MixerAudio.isMuted(id, scope: which.scope),
                        canSetVolume: MixerAudio.canSetVolume(id, scope: which.scope),
                        canMute: MixerAudio.canSetMute(id, scope: which.scope))
    }

    /// Nur für Vorschau und Tests: feste Werte statt Core Audio.
    func setPreview(output: Endpoint, systemOutput: OutputDevices.Device?, input: Endpoint, outputs: [OutputDevices.Device],
                    inputs: [OutputDevices.Device], apps: [MixerAppRow]) {
        self.output = output
        self.systemOutput = systemOutput
        self.input = input
        self.outputs = outputs
        self.inputs = inputs
        self.apps = apps
    }

    // MARK: Eingaben (nur auf Klick/Ziehen)

    private func touch() { holdUntil = Date().addingTimeInterval(1.2) }

    func setOutputVolume(_ v: Float) {
        guard let id = output.device?.id else { return }
        touch()
        output.volume = v
        MixerAudio.setVolume(id, scope: kAudioObjectPropertyScopeOutput, v)
    }

    func toggleOutputMute() {
        guard let id = output.device?.id, let muted = output.muted else { return }
        touch()
        output.muted = !muted
        MixerAudio.setMuted(id, scope: kAudioObjectPropertyScopeOutput, !muted)
    }

    func setInputVolume(_ v: Float) {
        guard let id = input.device?.id else { return }
        touch()
        input.volume = v
        MixerAudio.setVolume(id, scope: kAudioObjectPropertyScopeInput, v)
    }

    func toggleInputMute() {
        guard let id = input.device?.id, let muted = input.muted else { return }
        touch()
        input.muted = !muted
        MixerAudio.setMuted(id, scope: kAudioObjectPropertyScopeInput, !muted)
    }

    func selectOutput(_ id: AudioObjectID) {
        holdUntil = .distantPast
        OutputDevices.select(id)
        Task { await refresh() }
    }

    func selectSystemOutput(_ id: AudioObjectID) {
        holdUntil = .distantPast
        MixerAudio.setDefault(.systemOutput, id)
        Task { await refresh() }
    }

    func selectInput(_ id: AudioObjectID) {
        holdUntil = .distantPast
        MixerAudio.setDefault(.input, id)
        Task { await refresh() }
    }

    /// Spotify/Musik: nur, wenn macOS die Steuerung erlaubt hat (kein Dialog); Wert 0…100.
    func setPlayerVolume(bundleID: String, percent: Int) {
        touch()
        if let i = apps.firstIndex(where: { $0.bundleID == bundleID }) { apps[i].volume = percent }
        pendingPlayer[bundleID] = percent
        guard sendingPlayer.insert(bundleID).inserted else { return }
        Task { [weak self] in
            while let self, let next = self.pendingPlayer.removeValue(forKey: bundleID) {
                _ = await self.script.volume(.set(next), bundleID: bundleID)
            }
            self?.sendingPlayer.remove(bundleID)
        }
    }
}
