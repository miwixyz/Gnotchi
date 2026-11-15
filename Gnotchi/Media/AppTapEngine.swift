import CoreAudio
import Foundation
import OSLog
import Synchronization

/// Mixer Stufe 2 (SECURE-DESIGN G55, specs/2026-11-15-gnotchi-mixer-stufe2.md): Regler je App über Core-Audio-Prozess-Taps.
/// Ein Tap greift den Ton einer App im Arbeitsspeicher ab, schaltet das Original stumm und gibt ihn mit Verstärkung 0…2 auf
/// demselben Gerät wieder aus. **Der Tap existiert nur, solange der Regler nicht auf 100 % steht**; bei 100 % wird er sofort
/// zerstört und die App spielt wieder direkt. Der Ton wird nie gespeichert, gesendet oder protokolliert (nur Zahl, OSStatus).
/// Benötigt die Freigabe „Audio-Aufnahme“, ab Werk aus (Einstellung), erst beim ersten Ziehen gefragt.

/// Verstärkung für den Echtzeit-Rückruf: nur atomare Zugriffe, keine Sperre, keine Speicherzuweisung.
final class GainCell: @unchecked Sendable {
    private let target = Atomic<UInt32>(Float(1).bitPattern)
    private let last = Atomic<UInt32>(Float(1).bitPattern)
    /// Hat der Rückruf je einen Wert ≠ 0 gesehen? Ein Wahrheitswert, kein Pegel: Ohne Freigabe liefert macOS Nullen statt eines Fehlers.
    private let signal = Atomic<Bool>(false)

    func set(_ g: Float) { target.store(g.bitPattern, ordering: .relaxed) }

    /// Im Rückruf: (Wert vom letzten Puffer, Zielwert) – die Verstärkung gleitet über den Puffer, kein Knacken.
    func ramp() -> (Float, Float) {
        let t = target.load(ordering: .relaxed)
        let l = last.exchange(t, ordering: .relaxed)
        return (Float(bitPattern: l), Float(bitPattern: t))
    }

    func noteSignal() { if !signal.load(ordering: .relaxed) { signal.store(true, ordering: .relaxed) } }
    var sawSignal: Bool { signal.load(ordering: .relaxed) }
}

@MainActor
final class AppTapEngine {

    struct Target: Equatable, Sendable {
        let appID: String
        let processes: [AudioObjectID]
        let deviceUID: String
    }

    enum Failure: Error, Equatable, Sendable {
        /// macOS lieferte nur Stille: Freigabe „Audio-Aufnahme“ fehlt (oder die App spielt gerade nichts).
        case noSignal
        /// Tap oder Gerät ließ sich nicht aufbauen (OSStatus).
        case setup(OSStatus)
        /// Zu viele Regler gleichzeitig.
        case tooMany
        /// Kein Prozess zum Abgreifen (die App gibt keinen Ton mehr aus).
        case noTarget
        /// Gerätewechsel: Regler zurückgesetzt, die App spielt wieder direkt (nie stumm hängen lassen).
        case reset
    }

    static let maxTaps = 6
    /// So lange darf ein neuer Tap ohne Ton bleiben, bevor er als „keine Freigabe“ wieder abgebaut wird.
    static let signalGrace: Duration = .milliseconds(1500)
    /// So lange nach dem Anlegen oder Zerstören eines Taps ignoriert der Motor „Gerät geändert“: Das eigene (private) Aggregat-Gerät
    /// kann selbst eine solche Meldung auslösen, und der Schutz würde sonst den frischen Tap sofort wieder abbauen.
    nonisolated static let ownChangeQuiet: TimeInterval = 1.0

    /// Soll auf eine Geräteänderung reagiert werden? Nicht innerhalb der Karenzzeit nach dem eigenen Anlegen/Zerstören.
    nonisolated static func shouldReact(now: Date, lastOwnChange: Date?) -> Bool {
        guard let lastOwnChange else { return true }
        return now.timeIntervalSince(lastOwnChange) > ownChangeQuiet
    }

    private final class Live {
        let tapID: AudioObjectID
        let aggID: AudioObjectID
        let proc: AudioDeviceIOProcID
        let cell: GainCell
        let target: Target
        init(tapID: AudioObjectID, aggID: AudioObjectID, proc: AudioDeviceIOProcID, cell: GainCell, target: Target) {
            self.tapID = tapID; self.aggID = aggID; self.proc = proc; self.cell = cell; self.target = target
        }
    }

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "mixer")
    private var live: [String: Live] = [:]
    private var watchdogs: [String: Task<Void, Never>] = [:]
    private var listeners: [AnyObject] = []
    private var lastOwnChange: Date?
    /// Zustand für die Oberfläche: App → Verstärkung (nur laufende Taps) und letzter Fehler je App.
    private(set) var gains: [String: Float] = [:]
    private(set) var failures: [String: Failure] = [:]
    /// Ist die Prozessliste noch gültig? Austauschbar für Tests.
    var processExists: (AudioObjectID) -> Bool = { AudioRoute.scalar($0, kAudioProcessPropertyPID) as pid_t? != nil }

    var hasTaps: Bool { !live.isEmpty }
    /// Die Prozessliste hat sich geändert, ein Tap lebt noch: Der Mixer prüft, ob die App neue Audio-Prozesse bekommen hat (Browser-Helfer).
    var onProcessListChanged: (() -> Void)?

    func gain(for appID: String) -> Float { gains[appID] ?? 1 }

    /// Regler gesetzt. 100 % = kein Tap (und ein vorhandener wird zerstört).
    func setGain(_ raw: Float, for target: Target) {
        let g = TapMixer.clamp(raw)
        guard TapMixer.needsTap(g) else { release(target.appID); failures[target.appID] = nil; return }
        guard !target.processes.isEmpty else { release(target.appID); failures[target.appID] = .noTarget; return }
        if let l = live[target.appID], l.target == target {
            l.cell.set(g)
            gains[target.appID] = g
            return
        }
        release(target.appID)   // Ziel hat sich geändert (Prozesse, Gerät): neu aufbauen
        guard live.count < Self.maxTaps else { failures[target.appID] = .tooMany; return }
        lastOwnChange = Date()
        switch Self.build(target, gain: g) {
        case .success(let l):
            live[target.appID] = l
            gains[target.appID] = g
            failures[target.appID] = nil
            watch(target.appID, l)
            // Ohne Beobachter für Gerätewechsel gäbe es keinen Schutz vor stumm hängenden Apps: dann lieber gar kein Tap.
            guard startListeners() else {
                release(target.appID)
                failures[target.appID] = .setup(-1)
                return
            }
        case .failure(let f):
            failures[target.appID] = f
        }
    }

    func release(_ appID: String) {
        watchdogs.removeValue(forKey: appID)?.cancel()
        if let l = live.removeValue(forKey: appID) { lastOwnChange = Date(); Self.destroy(l) }
        gains[appID] = nil
        if live.isEmpty { listeners.removeAll() }
    }

    func releaseAll() {
        for id in Array(live.keys) { release(id) }
        listeners.removeAll()
    }

    // MARK: Überwachung

    /// Kommt innerhalb der Frist kein Ton an, ist das fast sicher die fehlende Freigabe (macOS liefert dann Nullen): Tap abbauen,
    /// die App spielt wieder direkt, die Zeile zeigt den Grund. Pausiert die App nur gerade, ist der Abbau ebenfalls harmlos.
    private func watch(_ id: String, _ l: Live) {
        watchdogs[id]?.cancel()
        watchdogs[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.signalGrace)
            guard !Task.isCancelled, let self, let cur = self.live[id], cur === l else { return }
            if !l.cell.sawSignal {
                Self.log.error("Tap ohne Ton abgebaut (keine Freigabe?)")
                self.release(id)
                self.failures[id] = .noSignal
            }
        }
    }

    /// Geräte- oder Prozesswechsel: Tap sofort abbauen, damit keine App stumm hängen bleibt (Entwurf D).
    @discardableResult
    private func startListeners() -> Bool {
        guard listeners.isEmpty else { return true }
        let system = AudioObjectID(kAudioObjectSystemObject)
        let on: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.devicesChanged() } }
        }
        let proc: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.processesChanged() } }
        }
        listeners = [
            Listener(system, kAudioHardwarePropertyDefaultOutputDevice, on),
            Listener(system, kAudioHardwarePropertyDevices, on),
            Listener(system, kAudioHardwarePropertyProcessObjectList, proc),
        ]
        let ok = listeners.allSatisfy { ($0 as? Listener)?.registered == true }
        if !ok { listeners.removeAll() }
        return ok
    }

    func devicesChanged(now: Date = Date()) {
        if live.isEmpty || !Self.shouldReact(now: now, lastOwnChange: lastOwnChange) { return }
        Self.log.notice("Gerätewechsel: alle Regler zurückgesetzt")
        let ids = Array(live.keys)
        releaseAll()
        for id in ids { failures[id] = .reset }   // sichtbar, nicht still: Der Regler springt auf 100 %
    }

    func processesChanged() {
        for (id, l) in live where !l.target.processes.allSatisfy(processExists) { release(id) }
        if !live.isEmpty { onProcessListChanged?() }
    }

    private final class Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
        let registered: Bool
        init(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ block: @escaping AudioObjectPropertyListenerBlock) {
            self.object = object
            self.block = block
            address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
            registered = AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr
        }
        deinit { if registered { AudioObjectRemovePropertyListenerBlock(object, &address, .main, block) } }
    }

    // MARK: Tap bauen und zerstören

    private nonisolated static func build(_ target: Target, gain: Float) -> Result<Live, Failure> {
        let desc = CATapDescription(__processes: target.processes.map { NSNumber(value: $0) }, andDeviceUID: target.deviceUID, withStream: 0)
        desc.name = "Gnotchi Mixer"
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { return .failure(.setup(st)) }

        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Gnotchi Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: target.deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: target.deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        st = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID)
        guard st == noErr else { _ = AudioHardwareDestroyProcessTap(tapID); return .failure(.setup(st)) }

        let cell = GainCell()
        cell.set(gain)
        var proc: AudioDeviceIOProcID?
        let queue = DispatchQueue(label: "dev.mwlr.gnotchi.mixer", qos: .userInteractive)
        st = AudioDeviceCreateIOProcIDWithBlock(&proc, aggID, queue) { _, inData, _, outData, _ in
            // Echtzeit: keine Speicherzuweisung, keine Sperre, kein Protokoll. Nur kopieren und multiplizieren.
            let (g0, g1) = cell.ramp()
            TapMixer.render(input: inData, output: outData, gainStart: g0, gainEnd: g1)
            if !cell.sawSignal, TapMixer.hasSignal(inData) { cell.noteSignal() }
        }
        guard st == noErr, let proc else {
            _ = AudioHardwareDestroyAggregateDevice(aggID); _ = AudioHardwareDestroyProcessTap(tapID)
            return .failure(.setup(st))
        }
        st = AudioDeviceStart(aggID, proc)
        guard st == noErr else {
            _ = AudioDeviceDestroyIOProcID(aggID, proc); _ = AudioHardwareDestroyAggregateDevice(aggID)
            _ = AudioHardwareDestroyProcessTap(tapID)
            return .failure(.setup(st))
        }
        return .success(Live(tapID: tapID, aggID: aggID, proc: proc, cell: cell, target: target))
    }

    private nonisolated static func destroy(_ l: Live) {
        _ = AudioDeviceStop(l.aggID, l.proc)
        _ = AudioDeviceDestroyIOProcID(l.aggID, l.proc)
        _ = AudioHardwareDestroyAggregateDevice(l.aggID)
        _ = AudioHardwareDestroyProcessTap(l.tapID)
    }
}
