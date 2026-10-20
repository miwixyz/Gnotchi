import CoreAudio
import Foundation
import OSLog

/// Ausgabegeräte von macOS auflisten und das Standard-Ausgabegerät setzen – nur auf Klick des Nutzers
/// (SECURE-DESIGN G20). Öffentliche Core-Audio-Schnittstelle, keine Freigabe nötig (gemessen 20.10.).
/// Lesen ist billig (wenige Eigenschaften je Gerät) und läuft beim Öffnen des Menüs.
enum OutputDevices {

    struct Device: Equatable, Sendable, Identifiable {
        let id: AudioObjectID
        let name: String
        let transport: UInt32
        var kind: Kind { OutputDevices.kind(transport: transport) }
    }

    enum Kind: Equatable, Sendable {
        case builtIn, bluetooth, airPlay, display, usb, virtual, other

        var symbol: String {
            switch self {
            case .builtIn, .other: "speaker.wave.2"
            case .bluetooth: "headphones"
            case .airPlay: "airplayaudio"
            case .display: "tv"
            case .usb: "hifispeaker"
            case .virtual: "waveform"
            }
        }
    }

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "ausgang")

    // MARK: Reine Teile (getestet)

    nonisolated static func kind(transport: UInt32) -> Kind {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: .display
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate: .virtual
        default: .other
        }
    }

    /// Menü-Reihenfolge: eingebaute Lautsprecher zuerst, dann alphabetisch.
    nonisolated static func ordered(_ devices: [Device]) -> [Device] {
        devices.sorted { a, b in
            let ab = a.kind == .builtIn, bb = b.kind == .builtIn
            if ab != bb { return ab }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Nur ein Gerät, das gerade (noch) in der Liste steht – zwischen Menü-Öffnen und Klick kann es verschwinden.
    nonisolated static func canSelect(_ id: AudioObjectID, in devices: [Device]) -> Bool {
        id != kAudioObjectUnknown && devices.contains { $0.id == id }
    }

    /// Gerätenamen vergibt der Nutzer frei → bereinigt und gekürzt wie beim Wiedergabeweg.
    nonisolated static func cleanName(_ s: String?) -> String? {
        AudioRoute.cleanName(s)
    }

    // MARK: Core Audio

    /// Geräte mit mindestens einem Ausgang, ohne versteckte. Ohne Namen kein Eintrag.
    static func list() -> [Device] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        return AudioRoute.objectList(system, kAudioHardwarePropertyDevices).compactMap { id in
            guard outputStreamCount(id) > 0 else { return nil }
            let hidden: UInt32 = AudioRoute.scalar(id, kAudioDevicePropertyIsHidden) ?? 0
            guard hidden == 0, let name = cleanName(AudioRoute.string(id, kAudioObjectPropertyName)) else { return nil }
            return Device(id: id, name: name, transport: AudioRoute.scalar(id, kAudioDevicePropertyTransportType) ?? 0)
        }
    }

    /// Aktuelles Standard-Ausgabegerät; nil, wenn macOS keins meldet.
    static func current() -> AudioObjectID? {
        let id: AudioObjectID? = AudioRoute.scalar(AudioObjectID(kAudioObjectSystemObject),
                                                   kAudioHardwarePropertyDefaultOutputDevice)
        return id.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    /// Setzt das Standard-Ausgabegerät. Prüft vorher gegen die frische Liste. Protokoll nur mit
    /// Übertragungsart und Statuscode, nie mit Gerätenamen (Protokollregel der App-Familie).
    @discardableResult
    static func select(_ id: AudioObjectID) -> Bool {
        let devices = list()
        guard canSelect(id, in: devices) else {
            log.error("Ausgabegerät nicht mehr vorhanden, nichts gesetzt")
            return false
        }
        var addr = AudioRoute.address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &value)
        guard status == noErr else {
            log.error("Ausgabegerät setzen gescheitert (OSStatus \(status, privacy: .public))")
            return false
        }
        let transport = devices.first { $0.id == id }?.transport ?? 0
        log.notice("Ausgabegerät gesetzt (Art \(transport, privacy: .public))")
        return true
    }

    private static func outputStreamCount(_ id: AudioObjectID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioObjectPropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }
}
