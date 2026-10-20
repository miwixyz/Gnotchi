import CoreAudio
import CoreMediaIO
import Darwin
import Foundation
import OSLog

/// Mikrofon/Kamera aktiv (0.2.0, Michael 20.10.): Punkt an der Insel, beim Darüberfahren welche App das
/// Mikrofon nutzt. Nur lesend über öffentliche Schnittstellen – Core Audio (Prozess „nimmt auf“) und
/// CoreMediaIO (Kamera „läuft irgendwo“). Gemessen 20.10.: Kamera ohne TCC-Anfrage, Mikrofon nur
/// TCC-Vorabprüfung, kein Dialog (SECURE-DESIGN G18). Kein Ton wird gelesen. App-Namen nie ins Protokoll.
@MainActor
final class PrivacyMonitor: NotchPart {

    /// Ein Prozess, der gerade aufnimmt: Bundle-ID (Core Audio) und Programmpfad (proc_pidpath).
    struct MicEntry: Equatable, Sendable {
        let bundleID: String?
        let path: String?
    }

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "datenschutz")
    /// Solange das Mikrofon an ist, Namen so oft neu lesen (eine zweite App kommt ohne Gerätewechsel dazu).
    private static let pollInterval: Duration = .seconds(2)
    /// Meldungen kommen in Salven (Prozessliste) – sammeln.
    private static let debounce: Duration = .milliseconds(200)

    private let activity: ActivityModel
    private var running = false
    /// Angemeldete Beobachter – zum Abmelden braucht Core Audio dasselbe Objekt, dieselbe Adresse, denselben Block.
    private struct AudioListener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private struct CameraListener {
        let object: CMIOObjectID
        let address: CMIOObjectPropertyAddress
        let block: CMIOObjectPropertyListenerBlock
    }
    private var audioListeners: [AudioListener] = []
    private var cameraListeners: [CameraListener] = []
    private var pending: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var generation = 0

    init(activity: ActivityModel) {
        self.activity = activity
    }

    // MARK: Reine Teile (getestet)

    /// Äußerste `.app` im Pfad: Browser nehmen über Hilfs-Apps im eigenen Bundle auf.
    nonisolated static func outermostApp(path: String?) -> String? {
        guard let path else { return nil }
        if let r = path.range(of: ".app/") { return String(path[..<r.lowerBound]) + ".app" }
        return path.hasSuffix(".app") ? path : nil
    }

    /// Namen je aufnehmendem Prozess, doppelte zusammengefasst, Reihenfolge der Prozessliste.
    /// Safari & Co. nehmen im geteilten WebKit-Prozess auf – welche App, sagt macOS nicht → „Webseite“.
    nonisolated static func micNames(_ entries: [MicEntry], displayName: (String) -> String?) -> [String] {
        var seen = Set<String>()
        return entries.compactMap { e in
            let name: String
            if e.bundleID == AudioRoute.webKitGPU {
                name = "Webseite"
            } else if let app = outermostApp(path: e.path), let n = displayName(app) {
                name = n
            } else {
                name = "Unbekannte App"
            }
            return seen.insert(name).inserted ? name : nil
        }
    }

    // MARK: Betrieb

    func start() {
        guard !running else { return }
        running = true
        generation += 1
        registerListeners()
        scheduleRead()
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        removeListeners()
        pending?.cancel()
        poll?.cancel()
        pending = nil
        poll = nil
        activity.setPrivacy(.none)
    }

    /// Geräteliste geändert: Beobachter je Gerät neu anmelden.
    private func devicesChanged() {
        guard running else { return }
        removeListeners()
        registerListeners()
        scheduleRead()
    }

    private func scheduleRead() {
        pending?.cancel()
        let gen = generation
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let ownPID = getpid()
            let state = await Task.detached(priority: .utility) { Self.read(ownPID: ownPID) }.value
            guard let self, self.running, gen == self.generation, !Task.isCancelled else { return }
            self.activity.setPrivacy(state)
            self.updatePolling(micOn: state.mic)
        }
    }

    private func updatePolling(micOn: Bool) {
        guard micOn else { poll?.cancel(); poll = nil; return }
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self, self.running else { return }
                self.scheduleRead()
                if !self.activity.privacy.mic { self.poll = nil; return }
            }
        }
    }

    // MARK: Lesen (außerhalb des Hauptthreads)

    private nonisolated static func read(ownPID: pid_t) -> ActivityModel.Privacy {
        let entries = micEntries(ownPID: ownPID)
        let names = micNames(entries) { AppIcons.cleanName(FileManager.default.displayName(atPath: $0)) }
        return ActivityModel.Privacy(micApps: names, camera: cameraActive())
    }

    /// Prozesse mit „nimmt auf“ (Core Audio), ohne Gnotchi selbst.
    private nonisolated static func micEntries(ownPID: pid_t) -> [MicEntry] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        return AudioRoute.objectList(system, kAudioHardwarePropertyProcessObjectList).compactMap { id in
            let input: UInt32 = AudioRoute.scalar(id, kAudioProcessPropertyIsRunningInput) ?? 0
            guard input != 0, let pid: pid_t = AudioRoute.scalar(id, kAudioProcessPropertyPID), pid != ownPID else { return nil }
            return MicEntry(bundleID: AudioRoute.string(id, kAudioProcessPropertyBundleID), path: executablePath(pid))
        }
    }

    private nonisolated static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    private nonisolated static func cameraActive() -> Bool {
        cameraDevices().contains { cam in
            var addr = cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            var value: UInt32 = 0
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(cam, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
            return status == noErr && value != 0
        }
    }

    private nonisolated static func cameraDevices() -> [CMIOObjectID] {
        var addr = cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private nonisolated static func cmioAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector,
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    // MARK: Beobachter

    private func registerListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        addAudio(system, kAudioHardwarePropertyDevices) { $0.devicesChanged() }
        addAudio(system, kAudioHardwarePropertyProcessObjectList) { $0.scheduleRead() }
        for device in AudioRoute.objectList(system, kAudioHardwarePropertyDevices) where Self.hasInput(device) {
            addAudio(device, kAudioDevicePropertyDeviceIsRunningSomewhere) { $0.scheduleRead() }
        }
        addCamera(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)) {
            $0.devicesChanged()
        }
        for cam in Self.cameraDevices() {
            addCamera(cam, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)) { $0.scheduleRead() }
        }
    }

    private func addAudio(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          _ action: @escaping @MainActor (PrivacyMonitor) -> Void) {
        var addr = AudioRoute.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &addr, .main, block)
        guard status == noErr else {
            return Self.log.error("Beobachter Core Audio nicht angemeldet (OSStatus \(status, privacy: .public))")
        }
        audioListeners.append(AudioListener(object: object, address: addr, block: block))
    }

    private func addCamera(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector,
                           _ action: @escaping @MainActor (PrivacyMonitor) -> Void) {
        var addr = Self.cmioAddress(selector)
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        let status = CMIOObjectAddPropertyListenerBlock(object, &addr, .main, block)
        guard status == noErr else {
            return Self.log.error("Beobachter Kamera nicht angemeldet (OSStatus \(status, privacy: .public))")
        }
        cameraListeners.append(CameraListener(object: object, address: addr, block: block))
    }

    private func removeListeners() {
        for l in audioListeners {
            var a = l.address
            AudioObjectRemovePropertyListenerBlock(l.object, &a, .main, l.block)
        }
        for l in cameraListeners {
            var a = l.address
            CMIOObjectRemovePropertyListenerBlock(l.object, &a, .main, l.block)
        }
        audioListeners.removeAll()
        cameraListeners.removeAll()
    }

    private nonisolated static func hasInput(_ device: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioObjectPropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }
}
