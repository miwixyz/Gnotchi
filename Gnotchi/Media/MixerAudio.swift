import CoreAudio
import Foundation

/// Core-Audio-Zugriffe des Mixers (0.30.0, G54): Lautstärke, Stumm und Standardgeräte für Ausgabe, Systemtöne und
/// Eingabe. Öffentliche Eigenschaften der Geräte, **keine Freigabe** (gemessen 15.11.: MacBook-Lautsprecher Lautstärke und
/// Stumm setzbar am Hauptkanal). Geräte ohne Hauptkanal (manche HDMI/USB/AirPlay) haben Lautstärke je Kanal: dann Mittel
/// aus Kanal 1 und 2 lesen, beide setzen.
enum MixerAudio {

    enum Selector {
        case output, systemOutput, input
        var property: AudioObjectPropertySelector {
            switch self {
            case .output: kAudioHardwarePropertyDefaultOutputDevice
            case .systemOutput: kAudioHardwarePropertyDefaultSystemOutputDevice
            case .input: kAudioHardwarePropertyDefaultInputDevice
            }
        }
        var scope: AudioObjectPropertyScope { self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput }
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                                _ element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: element)
    }

    // MARK: Standardgeräte

    static func defaultDevice(_ which: Selector) -> AudioObjectID? {
        let id: AudioObjectID? = AudioRoute.scalar(system, which.property)
        return id.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    /// Standardgerät setzen – nur auf Klick, nur gegen die frische Liste (wie `OutputDevices.select`).
    @discardableResult
    static func setDefault(_ which: Selector, _ id: AudioObjectID) -> Bool {
        let known = which == .input ? inputDevices() : OutputDevices.list()
        guard known.contains(where: { $0.id == id }) else { return false }
        var a = AudioRoute.address(which.property)
        var value = id
        return AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }

    /// Geräte mit mindestens einem Eingang, ohne versteckte, mit Namen.
    static func inputDevices() -> [OutputDevices.Device] {
        AudioRoute.objectList(system, kAudioHardwarePropertyDevices).compactMap { id in
            var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return nil }
            let hidden: UInt32 = AudioRoute.scalar(id, kAudioDevicePropertyIsHidden) ?? 0
            guard hidden == 0, let d = OutputDevices.device(id) else { return nil }
            return d
        }
    }

    // MARK: Lautstärke und Stumm

    /// Lautstärke 0…1: Hauptkanal, sonst Mittel aus Kanal 1 und 2; nil, wenn das Gerät keine meldet.
    static func volume(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Float? {
        if let v = read(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain) { return v }
        let channels = [UInt32(1), 2].compactMap { read(device, kAudioDevicePropertyVolumeScalar, scope, $0) }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Float(channels.count)
    }

    static func canSetVolume(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        settable(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain)
            || [UInt32(1), 2].contains { settable(device, kAudioDevicePropertyVolumeScalar, scope, $0) }
    }

    @discardableResult
    static func setVolume(_ device: AudioObjectID, scope: AudioObjectPropertyScope, _ value: Float) -> Bool {
        let v = min(1, max(0, value))
        if settable(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain) {
            return write(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain, v)
        }
        let results = [UInt32(1), 2].filter { settable(device, kAudioDevicePropertyVolumeScalar, scope, $0) }
            .map { write(device, kAudioDevicePropertyVolumeScalar, scope, $0, v) }
        return !results.isEmpty && !results.contains(false)
    }

    static func isMuted(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool? {
        var a = address(kAudioDevicePropertyMute, scope)
        guard AudioObjectHasProperty(device, &a) else { return nil }
        var v: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v != 0 : nil
    }

    static func canSetMute(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        settable(device, kAudioDevicePropertyMute, scope, kAudioObjectPropertyElementMain)
    }

    @discardableResult
    static func setMuted(_ device: AudioObjectID, scope: AudioObjectPropertyScope, _ on: Bool) -> Bool {
        var a = address(kAudioDevicePropertyMute, scope)
        var v: UInt32 = on ? 1 : 0
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    private static func read(_ d: AudioObjectID, _ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                             _ element: UInt32) -> Float? {
        var a = address(s, scope, element)
        guard AudioObjectHasProperty(d, &a) else { return nil }
        var v: Float = 0, size = UInt32(MemoryLayout<Float>.size)
        return AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func write(_ d: AudioObjectID, _ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                              _ element: UInt32, _ value: Float) -> Bool {
        var a = address(s, scope, element)
        var v = value
        return AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<Float>.size), &v) == noErr
    }

    private static func settable(_ d: AudioObjectID, _ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                                 _ element: UInt32) -> Bool {
        var a = address(s, scope, element)
        var ok: DarwinBoolean = false
        return AudioObjectHasProperty(d, &a) && AudioObjectIsPropertySettable(d, &a, &ok) == noErr && ok.boolValue
    }

    // MARK: Apps mit Ton

    /// Ein Audio-Prozess für die App-Zeilen: nur gelesene Eigenschaften (gemessen 15.11.: auch das Gerät je Prozess,
    /// `kAudioProcessPropertyDevices`, ohne Freigabe und ohne Tap).
    struct Process: Equatable, Sendable {
        let pid: pid_t
        let bundleID: String?
        let path: String?
        let outputting: Bool
        let devices: [AudioObjectID]
    }

    static func audioProcesses() -> [Process] {
        AudioRoute.objectList(system, kAudioHardwarePropertyProcessObjectList).compactMap { id in
            guard let pid: pid_t = AudioRoute.scalar(id, kAudioProcessPropertyPID) else { return nil }
            let running: UInt32 = AudioRoute.scalar(id, kAudioProcessPropertyIsRunningOutput) ?? 0
            var a = address(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput)
            var size: UInt32 = 0
            var devices: [AudioObjectID] = []
            if running != 0, AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 {
                devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
                if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &devices) != noErr { devices = [] }
            }
            return Process(pid: pid, bundleID: AudioRoute.string(id, kAudioProcessPropertyBundleID),
                           path: executablePath(pid), outputting: running != 0, devices: devices)
        }
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }
}
