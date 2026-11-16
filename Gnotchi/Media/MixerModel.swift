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
    /// Für den Regler je App (Stufe 2): Audio-Prozesse dieser App und Geräte-UID, wenn sie auf **genau einem** Gerät spielt.
    var processes: [AudioObjectID] = []
    var deviceUID: String?
    /// Verstärkung des laufenden Taps (1 = unverändert).
    var gain: Float = 1

    var canTap: Bool { !processes.isEmpty && deviceUID != nil && devices.count == 1 }
}

enum MixerRows {
    nonisolated static let maxRows = 12

    /// Nur Prozesse, die gerade Ton ausgeben, nur solche in einer App (kein Systemdienst), nicht Gnotchi selbst; Prozesse
    /// derselben App werden zusammengefasst, Geräte vereinigt. Sortiert nach Name.
    nonisolated static func rows(_ processes: [MixerAudio.AudioApp], devices: [AudioObjectID: OutputDevices.Device],
                                 ownPID: pid_t, name: (String) -> String?, bundle: (String) -> String?,
                                 uid: (AudioObjectID) -> String? = { _ in nil }) -> [MixerAppRow] {
        var order: [String] = []
        // swiftlint:disable:next large_tuple
        var byApp: [String: (path: String, devices: [AudioObjectID], processes: [AudioObjectID])] = [:]
        for p in processes where p.outputting && p.pid != ownPID {
            guard let app = PrivacyMonitor.outermostApp(path: p.path) else { continue }
            if byApp[app] == nil { order.append(app); byApp[app] = (app, [], []) }
            byApp[app]?.processes.append(p.object)
            for d in p.devices where !(byApp[app]?.devices.contains(d) ?? false) { byApp[app]?.devices.append(d) }
        }
        let rows = order.compactMap { app -> MixerAppRow? in
            guard let entry = byApp[app], let n = name(app) else { return nil }
            let known = entry.devices.compactMap { devices[$0] }
            var row = MixerAppRow(id: app, name: n, bundleID: bundle(app), devices: known, volume: nil)
            row.processes = entry.processes
            if known.count == 1, entry.devices.count == 1 { row.deviceUID = uid(entry.devices[0]) }
            return row
        }
        return Array(rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.prefix(maxRows))
    }

    /// Regler nahe 100 % rastet auf 100 % ein (±3): Dann endet der Tap und die App spielt wieder direkt.
    nonisolated static func snap(_ percent: Int) -> Int { abs(percent - 100) <= 3 ? 100 : min(200, max(0, percent)) }

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
    /// Warnton-Lautstärke in Prozent (0.33.0, G57); nil, solange macOS keine meldet.
    private(set) var alertVolume: Int?
    @ObservationIgnored private var pendingAlert: Int?
    /// Setzt die Warnton-Lautstärke wirklich; in Tests ersetzt, damit sie nie die echte Einstellung ändern.
    @ObservationIgnored private let alertSetter: @Sendable (Int) async -> Bool
    @ObservationIgnored private var sendingAlert = false
    private(set) var input = Endpoint()
    private(set) var outputs: [OutputDevices.Device] = []
    private(set) var inputs: [OutputDevices.Device] = []
    private(set) var apps: [MixerAppRow] = []
    /// Favoriten-UIDs (0.31.0), je Liste in der Reihenfolge des Festlegens.
    private(set) var outputFavorites: [String]
    private(set) var inputFavorites: [String]
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored private let script: AppleScriptSource
    /// Regler je App über Prozess-Taps (Stufe 2, G55). Gehört dem Mixer, lebt so lange wie die App (der Tap muss das Popover überdauern).
    @ObservationIgnored let engine: AppTapEngine
    /// Einstellung „Lautstärke je App“: ab Werk aus. Ohne sie gibt es keinen Tap und keine Freigabe-Anfrage.
    private(set) var appVolumeEnabled = false
    private(set) var tapFailures: [String: AppTapEngine.Failure] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Nach einer Eingabe kurz nicht überschreiben, damit der Regler beim Ziehen nicht zurückspringt.
    @ObservationIgnored private var holdUntil: Date = .distantPast
    @ObservationIgnored private let interval: Duration
    /// Beim Ziehen am App-Regler: je App höchstens ein Aufruf gleichzeitig, immer mit dem neuesten Wert (kein Stau von Apple Events).
    @ObservationIgnored private var pendingPlayer: [String: Int] = [:]
    @ObservationIgnored private var sendingPlayer: Set<String> = []

    init(script: AppleScriptSource = AppleScriptSource(), engine: AppTapEngine = AppTapEngine(),
         interval: Duration = .milliseconds(1500), defaults: UserDefaults = .standard,
         alertSetter: @escaping @Sendable (Int) async -> Bool = { await SystemAlertVolume.set($0) }) {
        self.alertSetter = alertSetter
        self.defaults = defaults
        outputFavorites = MixerFavorites.load(.output, from: defaults)
        inputFavorites = MixerFavorites.load(.input, from: defaults)
        self.script = script
        self.engine = engine
        self.interval = interval
        engine.onProcessListChanged = { [weak self] in Task { await self?.retargetTaps() } }
    }

    /// Wer den Mixer gerade zeigt (Popover, Insel): Er fragt ab, solange mindestens einer ihn zeigt.
    @ObservationIgnored private var viewers: Set<String> = []

    func setVisible(_ owner: String, _ visible: Bool) {
        if visible { viewers.insert(owner) } else { viewers.remove(owner) }
        if viewers.isEmpty { stop() } else { start() }
    }

    /// Fragt der Mixer gerade ab? (Tests)
    var isPolling: Bool { task != nil }

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
        // Nach dem await erneut gegen `holdUntil` prüfen: kein Zurückspringen mitten im Ziehen.
        if let alert = await SystemAlertVolume.read(), Date() >= holdUntil, alert != alertVolume { alertVolume = alert }
        var rows = currentRows()
        for i in rows.indices {
            rows[i].gain = engine.gain(for: rows[i].id)
            guard let id = rows[i].bundleID, AppleScriptSource.supported.contains(id) else { continue }
            rows[i].volume = await script.volume(.read, bundleID: id)
        }
        if rows != apps { apps = rows }
        if engine.failures != tapFailures { tapFailures = engine.failures }
    }

    /// Apps mit Ton jetzt (ohne Player-Lautstärken).
    private func currentRows() -> [MixerAppRow] {
        let byID = Dictionary(uniqueKeysWithValues: OutputDevices.list().map { ($0.id, $0) })
        var rows = MixerRows.rows(MixerAudio.audioProcesses(), devices: byID, ownPID: ProcessInfo.processInfo.processIdentifier,
                                  name: { AppIcons.cleanName(FileManager.default.displayName(atPath: $0)) },
                                  bundle: { Bundle(path: $0)?.bundleIdentifier }, uid: { MixerAudio.deviceUID($0) })
        for i in rows.indices { rows[i].gain = engine.gain(for: rows[i].id) }
        return rows
    }

    /// Die Prozessliste hat sich geändert, während Regler laufen: Bekommt eine App neue Audio-Prozesse (neuer Browser-Tab), müssen
    /// auch sie unter dem Regler liegen – sonst zeigte der Regler 50 % und die neue Quelle spielte mit 100 %. Tap neu aufbauen.
    func retargetTaps() async {
        guard appVolumeEnabled, engine.hasTaps else { return }
        for row in currentRows() where row.canTap {
            let g = engine.gain(for: row.id)
            guard g != 1, let uid = row.deviceUID else { continue }
            engine.setGain(g, for: .init(appID: row.id, processes: row.processes, deviceUID: uid))   // nur bei geändertem Ziel neu gebaut
        }
        tapFailures = engine.failures
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
    // swiftlint:disable:previous function_parameter_count
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

    /// Die gerade angeschlossenen Favoriten der Liste, in Favoriten-Reihenfolge.
    func favorites(_ list: MixerFavorites.List) -> [OutputDevices.Device] {
        list == .output ? MixerFavorites.shown(outputFavorites, in: outputs) : MixerFavorites.shown(inputFavorites, in: inputs)
    }

    func isFavorite(_ d: OutputDevices.Device, _ list: MixerFavorites.List) -> Bool {
        guard let uid = d.uid else { return false }
        return (list == .output ? outputFavorites : inputFavorites).contains(uid)
    }

    func toggleFavorite(_ d: OutputDevices.Device, _ list: MixerFavorites.List) {
        guard let uid = d.uid else { return }
        let updated = MixerFavorites.toggled(list == .output ? outputFavorites : inputFavorites, uid: uid)
        if list == .output { outputFavorites = updated } else { inputFavorites = updated }
        MixerFavorites.save(updated, list, to: defaults)
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

    /// Einstellung geändert. Aus: alle Taps sofort zerstört, die Apps spielen wieder direkt.
    func setAppVolumeEnabled(_ on: Bool) {
        guard on != appVolumeEnabled else { return }
        appVolumeEnabled = on
        if !on { releaseAll() }
    }

    /// Alle Regler je App zurück auf 100 % (Beenden, Einstellung aus, Gerätewechsel).
    func releaseAll() {
        engine.releaseAll()
        for i in apps.indices where apps[i].gain != 1 { apps[i].gain = 1 }
        tapFailures = engine.failures
    }

    /// Regler je App (Stufe 2): `percent` 0…200, 100 = kein Tap. Nur mit eingeschalteter Einstellung und für Apps auf genau einem Gerät.
    func setAppGain(_ row: MixerAppRow, percent: Int) {
        guard appVolumeEnabled, row.canTap, let uid = row.deviceUID else { return }
        touch()
        let snapped = MixerRows.snap(percent)   // nahe 100 %: genau 100 %, dann gibt es keinen Tap
        engine.setGain(Float(snapped) / 100, for: .init(appID: row.id, processes: row.processes, deviceUID: uid))
        if let i = apps.firstIndex(where: { $0.id == row.id }) { apps[i].gain = engine.gain(for: row.id) }
        tapFailures = engine.failures
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

    /// Warnton-Lautstärke setzen. Beim Ziehen höchstens ein Aufruf gleichzeitig, immer mit dem neuesten Wert.
    func setAlertVolume(_ percent: Int) {
        let value = SystemAlertVolume.clamp(percent)
        touch()
        alertVolume = value
        pendingAlert = value
        guard !sendingAlert else { return }
        sendingAlert = true
        Task { [weak self] in
            while let self, let next = self.pendingAlert.take() { _ = await self.alertSetter(next) }
            self?.sendingAlert = false
        }
    }
}

private extension Optional {
    /// Liest den Wert und setzt ihn auf nil (für die Warteschlange mit dem neuesten Wert).
    mutating func take() -> Wrapped? {
        defer { self = nil }
        return self
    }
}
