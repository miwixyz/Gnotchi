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
    /// Gemerkte Lautstärke je App (G59): Bundle-ID → Prozent, ohne 100. Gilt für Mixer und Stream Deck.
    private(set) var remembered: [String: Int]
    @ObservationIgnored private var rememberedOrder: [String]
    /// Solange gemerkte Werte warten: Prozessliste beobachten, damit eine neu gestartete App ihren Wert bekommt, auch wenn
    /// gerade niemand den Mixer zeigt. Nur bei eingeschalteter „Lautstärke je App“.
    @ObservationIgnored private var memoryListener: AppTapEngine.Listener?
    @ObservationIgnored private var memoryRefresh: Task<Void, Never>?

    init(script: AppleScriptSource = AppleScriptSource(), engine: AppTapEngine = AppTapEngine(),
         interval: Duration = .milliseconds(1500), defaults: UserDefaults = .standard,
         alertSetter: @escaping @Sendable (Int) async -> Bool = { await SystemAlertVolume.set($0) }) {
        self.alertSetter = alertSetter
        self.defaults = defaults
        outputFavorites = MixerFavorites.load(.output, from: defaults)
        inputFavorites = MixerFavorites.load(.input, from: defaults)
        let memory = MixerMemory.load(from: defaults)
        remembered = memory
        rememberedOrder = memory.keys.sorted()
        self.script = script
        self.engine = engine
        self.interval = interval
        engine.onProcessListChanged = { [weak self] in Task { await self?.retargetTaps() } }
    }

    /// Wer den Mixer gerade zeigt (Popover, Insel): Er fragt ab, solange mindestens einer ihn zeigt.
    @ObservationIgnored private var viewers: Set<String> = []
    /// Betrachter, die keinen schnellen Takt brauchen (Stream Deck, G59): Das Plugin ist verbunden, solange Stream Deck läuft,
    /// also fast immer. Zeigt nur es den Mixer, fragt er alle 4 s statt alle 1,5 s ab (Akku; eigene Eingaben wirken sofort).
    @ObservationIgnored private var slowViewers: Set<String> = []
    nonisolated static let slowInterval: Duration = .seconds(4)

    func setVisible(_ owner: String, _ visible: Bool, slow: Bool = false) {
        if visible { viewers.insert(owner) } else { viewers.remove(owner) }
        if visible, slow { slowViewers.insert(owner) } else { slowViewers.remove(owner) }
        // Läuft die Abfrage schon im langsamen Takt und öffnet jemand den Mixer: sofort einmal abfragen, nicht bis zu 4 s warten.
        if visible, !slow, isPolling { Task { await refresh() } }
        if viewers.isEmpty { stop() } else { start() }
    }

    /// Takt der Abfrage: langsam, wenn nur langsame Betrachter zusehen.
    var pollInterval: Duration { viewers.isSubset(of: slowViewers) ? max(interval, Self.slowInterval) : interval }

    /// Fragt der Mixer gerade ab? (Tests)
    var isPolling: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh() async {
        guard Date() >= holdUntil else { return }
        let snapshot = await readSystem()
        guard Date() >= holdUntil else { return }   // inzwischen bedient: nicht mit altem Stand überschreiben
        outputs = OutputDevices.ordered(snapshot.outputs)
        inputs = snapshot.inputs
        output = endpoint(.output)
        input = endpoint(.input)
        systemOutput = MixerAudio.defaultDevice(.systemOutput).flatMap { OutputDevices.device($0) }
        // Nach dem await erneut gegen `holdUntil` prüfen: kein Zurückspringen mitten im Ziehen.
        if let alert = await SystemAlertVolume.read(), Date() >= holdUntil, alert != alertVolume { alertVolume = alert }
        var rows = snapshot.rows
        applyRemembered(rows)
        for i in rows.indices { rows[i].gain = engine.gain(for: rows[i].id) }
        for i in rows.indices {
            rows[i].gain = engine.gain(for: rows[i].id)
            guard let id = rows[i].bundleID, AppleScriptSource.supported.contains(id) else { continue }
            rows[i].volume = await script.volume(.read, bundleID: id)
        }
        // Nach den Abfragen (je App bis 3 s) erneut prüfen: Wurde inzwischen am Regler gezogen, nicht mit altem Stand überschreiben.
        guard Date() >= holdUntil else { return }
        if rows != apps { apps = rows }
        if engine.failures != tapFailures { tapFailures = engine.failures }
    }

    /// Was ein Durchlauf aus Core Audio und dem Dateisystem braucht. Wird **nicht** auf dem Hauptthread gelesen: Gemessen im Deep-Audit
    /// 16.11. (Nachbau): 60–70 ms je Durchlauf, Spitzen über 250 ms bei vielen Audio-Prozessen – das ruckelte Regler und Insel.
    private struct SystemSnapshot: Sendable {
        let outputs: [OutputDevices.Device]
        let inputs: [OutputDevices.Device]
        let rows: [MixerAppRow]
    }

    private nonisolated static func readSystem(ownPID: pid_t) -> SystemSnapshot {
        let outputs = OutputDevices.list()
        let byID = Dictionary(uniqueKeysWithValues: outputs.map { ($0.id, $0) })
        let rows = MixerRows.rows(MixerAudio.audioProcesses(), devices: byID, ownPID: ownPID,
                                  name: { AppIcons.cleanName(FileManager.default.displayName(atPath: $0)) },
                                  bundle: { Bundle(path: $0)?.bundleIdentifier }, uid: { MixerAudio.deviceUID($0) })
        return SystemSnapshot(outputs: outputs, inputs: MixerAudio.inputDevices(), rows: rows)
    }

    private func readSystem() async -> SystemSnapshot {
        let pid = ProcessInfo.processInfo.processIdentifier
        return await Task.detached(priority: .userInitiated) { Self.readSystem(ownPID: pid) }.value
    }

    /// Apps mit Ton jetzt (ohne Player-Lautstärken), mit der laufenden Verstärkung je App.
    private func currentRows() async -> [MixerAppRow] {
        var rows = await readSystem().rows
        for i in rows.indices { rows[i].gain = engine.gain(for: rows[i].id) }
        return rows
    }

    /// Die Prozessliste hat sich geändert, während Regler laufen: Bekommt eine App neue Audio-Prozesse (neuer Browser-Tab), müssen
    /// auch sie unter dem Regler liegen – sonst zeigte der Regler 50 % und die neue Quelle spielte mit 100 %. Tap neu aufbauen.
    func retargetTaps() async {
        guard appVolumeEnabled, engine.hasTaps else { return }
        for row in await currentRows() where row.canTap {
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

    /// Einstellung geändert. Aus: alle Taps sofort zerstört, die Apps spielen wieder direkt (gemerkte Werte bleiben gespeichert,
    /// wirken aber nicht). An: gemerkte Werte gleich anwenden.
    func setAppVolumeEnabled(_ on: Bool) {
        guard on != appVolumeEnabled else { return }
        appVolumeEnabled = on
        if !on { releaseAll() }
        updateMemoryWatch()
        if on, !remembered.isEmpty { Task { await refresh() } }
    }

    // MARK: Gemerkte Lautstärken (G59)

    /// Welche Zeilen bekommen jetzt ihren gemerkten Wert? Nur regelbare Apps ohne laufenden Tap und ohne frischen Fehler
    /// (sonst baute ein abgebauter Tap – keine Freigabe – sich bei jeder Abfrage neu auf), nie Werte ≤ 5 %.
    nonisolated static func rowsToRestore(_ rows: [MixerAppRow], remembered: [String: Int], enabled: Bool,
                                          liveGain: (String) -> Float, failed: (String) -> Bool) -> [(MixerAppRow, Int)] {
        guard enabled else { return [] }
        return rows.compactMap { row in
            guard row.canTap, let id = row.bundleID, !AppleScriptSource.supported.contains(id),
                  let p = remembered[id], MixerMemory.shouldAutoApply(p), liveGain(row.id) == 1, !failed(row.id) else { return nil }
            return (row, p)
        }
    }

    private func applyRemembered(_ rows: [MixerAppRow]) {
        for (row, p) in Self.rowsToRestore(rows, remembered: remembered, enabled: appVolumeEnabled,
                                           // `.reset` (Gerätewechsel) blockiert nicht: gemerkt heißt, auf dem neuen Gerät wieder anwenden.
                                           liveGain: { engine.gain(for: $0) },
                                           failed: { tapFailures[$0] != nil && tapFailures[$0] != .reset }) {
            guard let uid = row.deviceUID else { continue }
            engine.setGain(Float(p) / 100, for: .init(appID: row.id, processes: row.processes, deviceUID: uid))
        }
        tapFailures = engine.failures
    }

    private func remember(_ bundleID: String?, percent: Int) {
        guard let bundleID, DeckWire.isValidApp(bundleID), !AppleScriptSource.supported.contains(bundleID) else { return }
        (remembered, rememberedOrder) = MixerMemory.updated(remembered, order: rememberedOrder, bundleID: bundleID, percent: percent)
        defaults.set(remembered, forKey: MixerMemory.key)
        updateMemoryWatch()
    }

    /// Alle gemerkten Werte vergessen (Taste im Mixer); laufende Regler bleiben, bis man sie bewegt.
    func forgetRemembered() {
        remembered = [:]
        rememberedOrder = []
        defaults.removeObject(forKey: MixerMemory.key)
        updateMemoryWatch()
    }

    /// Prozessliste beobachten, solange etwas zu merken ist; nach einer Änderung zweimal nachsehen (eine neue App gibt oft erst
    /// nach einem Moment Ton aus).
    private func updateMemoryWatch() {
        let wanted = appVolumeEnabled && !remembered.isEmpty
        guard wanted != (memoryListener != nil) else { return }
        guard wanted else { memoryListener = nil; memoryRefresh?.cancel(); memoryRefresh = nil; return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.processListChanged() } }
        }
        let l = AppTapEngine.Listener(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList, block)
        memoryListener = l.registered ? l : nil
    }

    private func processListChanged() {
        memoryRefresh?.cancel()
        memoryRefresh = Task { [weak self] in
            for delay in [1.0, 4.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.applyRemembered(await self.currentRows())
            }
        }
    }

    /// Alle Regler je App zurück auf 100 % (Beenden, Einstellung aus, Gerätewechsel).
    func releaseAll() {
        engine.releaseAll()
        for i in apps.indices where apps[i].gain != 1 { apps[i].gain = 1 }
        tapFailures = engine.failures
    }

    /// Regler je App (Stufe 2): `percent` 0…200, 100 = kein Tap. Nur mit eingeschalteter Einstellung und für Apps auf genau einem Gerät.
    /// `remember: false` für Stummschalten am Stream Deck: Stumm wird nie gemerkt.
    func setAppGain(_ row: MixerAppRow, percent: Int, remember shouldRemember: Bool = true) {
        guard appVolumeEnabled, row.canTap, let uid = row.deviceUID else { return }
        touch()
        let snapped = MixerRows.snap(percent)   // nahe 100 %: genau 100 %, dann gibt es keinen Tap
        engine.setGain(Float(snapped) / 100, for: .init(appID: row.id, processes: row.processes, deviceUID: uid))
        if let i = apps.firstIndex(where: { $0.id == row.id }) { apps[i].gain = engine.gain(for: row.id) }
        tapFailures = engine.failures
        if shouldRemember, engine.failures[row.id] == nil { remember(row.bundleID, percent: snapped) }
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
