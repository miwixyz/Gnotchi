import CoreAudio
import Foundation

/// Wo die Musik gerade herauskommt. Nur Anzeige, keine Steuerung.
enum PlaybackRoute: Equatable, Sendable {
    /// Lautsprecher oder Kopfhörer am Kabel des Mac – nichts anzeigen.
    case local
    /// Die Quell-App spielt, gibt auf diesem Mac aber keinen Ton aus (Spotify Connect u. ä.).
    case remote
    /// Ausgabegerät des Mac ist AirPlay oder Bluetooth.
    case device(name: String, kind: DeviceKind)

    enum DeviceKind: Equatable, Sendable { case airPlay, bluetooth }

    var symbol: String? {
        switch self {
        case .local: nil
        case .remote: "hifispeaker.fill"
        case .device(_, .airPlay): "airplayaudio"
        case .device(_, .bluetooth): "headphones"
        }
    }

    var label: String? {
        switch self {
        case .local: nil
        case .remote: "Auf anderem Gerät"
        case .device(let name, _): name
        }
    }

    /// Der Pegel behauptet „Ton kommt hier raus“. Bei anderem Gerät oder AirPlay-Lautsprecher stimmt das
    /// nicht → kleiner Lautsprecher statt Pegel. Bluetooth-Kopfhörer sind „hier“ genug.
    var replacesLevelBars: Bool {
        switch self {
        case .remote, .device(_, .airPlay): true
        case .local, .device(_, .bluetooth): false
        }
    }
}

/// Liest Core Audio (öffentliche API, keine Freigabe nötig, gemessen 18.10.): je Prozess nur PID,
/// Bundle-ID und „gibt Ton aus“; vom Standard-Ausgabegerät nur Art (Transport) und Namen.
/// Kein Ton wird aufgenommen oder abgegriffen (SECURE-DESIGN G15). Entscheidung als reine Funktion.
enum AudioRoute {

    struct AudioProcess: Equatable, Sendable {
        let pid: pid_t
        let bundleID: String?
        let isRunningOutput: Bool
    }

    /// PID und Bundle-ID eines Core-Audio-Prozessobjekts – ändern sich nicht, solange das Objekt lebt.
    struct Identity: Equatable, Sendable {
        let pid: pid_t
        let bundleID: String?
    }

    struct Snapshot: Sendable {
        let processes: [AudioProcess]
        /// Für die nächste Abfrage mitgeben (`snapshot(known:)`): nur neue Objekte werden gelesen.
        let identities: [AudioObjectID: Identity]
        let outputTransport: UInt32?
        let outputName: String?
    }

    /// Erst nach so langer Stille gilt die Wiedergabe als „auf anderem Gerät“ (Titelanfang, Puffern).
    static let remoteAfter: TimeInterval = 2
    /// Abfragetakt – nur solange die Insel sichtbar ist und Musik läuft (NowPlayingModel).
    static let pollInterval: Duration = .seconds(2)
    static let maxNameLength = 40
    /// Safari & Co. spielen in diesem geteilten Prozess; er gehört keiner App erkennbar.
    static let webKitGPU = "com.apple.WebKit.GPU"

    // MARK: Reine Entscheidung (getestet)

    /// Gemerkte PID der Quell-App nur, solange der Prozess noch lebt (Spotify-Neustart während der Wiedergabe:
    /// neue PID, die alte gehört niemandem mehr oder bald einem anderen Prozess).
    static func liveCachedPID(_ pid: pid_t?, isAlive: (pid_t) -> Bool) -> pid_t? {
        guard let pid, isAlive(pid) else { return nil }
        return pid
    }

    /// Bekannte Objekte aus dem Zwischenspeicher, nur neue lesen; verschwundene und unlesbare fallen weg.
    static func identities(for ids: [AudioObjectID], known: [AudioObjectID: Identity],
                           read: (AudioObjectID) -> Identity?) -> [AudioObjectID: Identity] {
        var result: [AudioObjectID: Identity] = [:]
        for id in ids {
            if let hit = known[id] ?? read(id) { result[id] = hit }
        }
        return result
    }

    /// Gibt die Quell-App Ton aus? Zählt der Prozess mit `pid` und jeder mit gleicher Bundle-ID oder
    /// Unter-ID (`<id>.helper`: Edge, Helium, gemessen 18.10.). nil = unbekannt: kein Core-Audio-Objekt
    /// für die App, oder sie ist still, während der geteilte WebKit-Prozess spielt (könnte ihr Ton sein).
    static func outputting(pid: pid_t?, bundleID: String?, processes: [AudioProcess]) -> Bool? {
        let mine = processes.filter { p in
            if let pid, p.pid == pid { return true }
            guard let id = bundleID, let other = p.bundleID else { return false }
            return other == id || other.hasPrefix(id + ".")
        }
        if mine.contains(where: \.isRunningOutput) { return true }
        if mine.isEmpty { return nil }
        // Diese Regel kann eine Anzeige „Auf anderem Gerät“ nur VERHINDERN (Ergebnis unbekannt → lokal),
        // nie erzeugen: Sie greift nur, wenn die App selbst schon still ist.
        if processes.contains(where: { $0.bundleID == webKitGPU && $0.isRunningOutput }) { return nil }
        return false
    }

    /// Seit wann die spielende App still ist; jede Ausgabe, Pause oder Unklarheit setzt die Uhr zurück.
    static func nextSilentSince(isPlaying: Bool, outputting: Bool?, current: Date?, now: Date) -> Date? {
        guard isPlaying, outputting == false else { return nil }
        return current ?? now
    }

    /// `silentFor`: wie lange die App schon still ist (aus `nextSilentSince`), nil = nicht still.
    static func decide(isPlaying: Bool, outputting: Bool?, silentFor: TimeInterval?,
                       transport: UInt32?, outputName: String?) -> PlaybackRoute {
        if isPlaying, outputting == false, let silentFor, silentFor > remoteAfter {
            return .remote
        }
        switch transport {
        case kAudioDeviceTransportTypeAirPlay:
            return .device(name: cleanName(outputName) ?? "AirPlay", kind: .airPlay)
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .device(name: cleanName(outputName) ?? "Bluetooth", kind: .bluetooth)
        default:
            return .local
        }
    }

    /// Gerätenamen vergibt der Nutzer frei (AirPlay-Lautsprecher) – bereinigt wie Strom-Texte, gekürzt.
    private static func cleanName(_ s: String?) -> String? {
        NowPlayingInfo.sanitize(s).map { String($0.prefix(maxNameLength)) }
    }

    // MARK: Core Audio lesen (nur lesen; außerhalb des Hauptthreads aufrufen)

    /// Je Abfrage: Objektliste und „gibt Ton aus“ je Objekt; PID/Bundle-ID nur für neue Objekte (`known`).
    static func snapshot(known: [AudioObjectID: Identity]) -> Snapshot {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let ids = objectList(system, kAudioHardwarePropertyProcessObjectList)
        let identities = identities(for: ids, known: known) { id in
            guard let pid: pid_t = scalar(id, kAudioProcessPropertyPID) else { return nil }
            return Identity(pid: pid, bundleID: string(id, kAudioProcessPropertyBundleID))
        }
        let processes = ids.compactMap { id -> AudioProcess? in
            guard let who = identities[id] else { return nil }
            let running: UInt32 = scalar(id, kAudioProcessPropertyIsRunningOutput) ?? 0
            return AudioProcess(pid: who.pid, bundleID: who.bundleID, isRunningOutput: running != 0)
        }
        let device: AudioObjectID? = scalar(system, kAudioHardwarePropertyDefaultOutputDevice)
        let output = device.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
        return Snapshot(processes: processes, identities: identities,
                        outputTransport: output.flatMap { scalar($0, kAudioDevicePropertyTransportType) },
                        outputName: output.flatMap { string($0, kAudioObjectPropertyName) })
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func scalar<T: BitwiseCopyable>(_ object: AudioObjectID,
                                                   _ selector: AudioObjectPropertySelector) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size,
                                                      alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, pointer) == noErr,
              size == MemoryLayout<T>.size else { return nil }
        return pointer.load(as: T.self)
    }

    /// CFString-Eigenschaften gibt Core Audio mit +1 zurück (Aufrufer gibt frei) → takeRetainedValue.
    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0) }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}
