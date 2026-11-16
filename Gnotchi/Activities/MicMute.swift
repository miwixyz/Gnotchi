import CoreAudio
import Foundation

/// Mikrofon stumm (0.28.0, SECURE-DESIGN G52): schaltet das Standard-Eingabegerät per Core Audio stumm, ohne Freigabe.
/// Geht „Stumm“ nicht (manche Bluetooth-Headsets, iPhone-Mikrofon), dient die Eingangslautstärke 0 als Ersatz; geht auch
/// das nicht, ist die Taste nicht nutzbar. Der Zustand kommt aus dem Gerät (Property-Listener), nicht aus einer eigenen
/// Merkvariable. **Beim Beenden wird entstummt**, wenn Gnotchi stummgeschaltet hat (eigene Apps scheitern nie stumm).
enum MicMuteMethod: Equatable, Sendable {
    case mute, volume, none

    nonisolated static func choose(muteSettable: Bool, volumeSettable: Bool) -> MicMuteMethod {
        muteSettable ? .mute : (volumeSettable ? .volume : .none)
    }
}

/// Zugriff auf das Gerät – austauschbar, damit der Ablauf ohne echtes Mikrofon getestet werden kann.
protocol MicBackend: AnyObject {
    func defaultInput() -> UInt32?
    func canSetMute(_ device: UInt32) -> Bool
    func canSetVolume(_ device: UInt32) -> Bool
    func isMuted(_ device: UInt32) -> Bool?
    func setMuted(_ device: UInt32, _ on: Bool) -> Bool
    func volume(_ device: UInt32) -> Float?
    func setVolume(_ device: UInt32, _ value: Float) -> Bool
    /// Meldet Änderungen am Standardgerät und an dessen Stumm/Lautstärke. Rückgabe hält die Anmeldung am Leben.
    func observe(device: UInt32?, _ handler: @escaping @MainActor () -> Void) -> AnyObject?
}

@MainActor
@Observable
final class MicMute {
    enum State: Equatable { case unsupported, unmuted, muted }

    private(set) var state: State = .unsupported
    var isMuted: Bool { state == .muted }
    var isSupported: Bool { state != .unsupported }

    @ObservationIgnored private let backend: MicBackend
    @ObservationIgnored private var device: UInt32?
    @ObservationIgnored private var method: MicMuteMethod = .none
    @ObservationIgnored private var mutedByUs = false
    @ObservationIgnored private var savedVolume: Float?
    @ObservationIgnored private var tokens: [AnyObject] = []
    @ObservationIgnored private var active = false
    /// Gerät, an dem gerade beobachtet wird: Beobachter nur beim Gerätewechsel umhängen (nicht bei jeder Änderung).
    @ObservationIgnored private var observed: UInt32?

    init(backend: MicBackend = CoreAudioMic()) { self.backend = backend }

    /// Läuft nur, solange die Taste überhaupt gebraucht wird: dann Zustand lesen und Änderungen beobachten.
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            refresh()
        } else {
            restoreIfMutedByUs()
            tokens.removeAll()
            observed = nil
            state = .unsupported
        }
    }

    /// Beenden: Nur wenn Gnotchi stummgeschaltet hat, wieder laut stellen.
    func restoreIfMutedByUs() {
        guard mutedByUs, state == .muted else { mutedByUs = false; return }
        _ = apply(muted: false)
        mutedByUs = false
    }

    func toggle() {
        guard isSupported else { return }
        let target = !isMuted
        if apply(muted: target) { mutedByUs = target }
        refresh()
    }

    private func apply(muted: Bool) -> Bool {
        guard let device else { return false }
        switch method {
        case .mute:
            return backend.setMuted(device, muted)
        case .volume:
            if muted {
                if let v = backend.volume(device), v > 0.001 { savedVolume = v }
                return backend.setVolume(device, 0)
            }
            return backend.setVolume(device, savedVolume ?? 0.5)
        case .none:
            return false
        }
    }

    /// Standardgerät, Fähigkeiten und Zustand neu lesen und die Beobachter auf das aktuelle Gerät umhängen.
    func refresh() {
        guard active else { return }
        let d = backend.defaultInput()
        if d != device { mutedByUs = false; savedVolume = nil }
        device = d
        guard let d else {
            method = .none
            state = .unsupported
            // Kein Eingabegerät: nur den Wechsel des Standardgeräts weiter beobachten, sonst käme ein später
            // angeschlossenes Mikrofon nie an.
            tokens = backend.observe(device: nil) { [weak self] in self?.refresh() }.map { [$0] } ?? []
            observed = nil
            return
        }
        method = MicMuteMethod.choose(muteSettable: backend.canSetMute(d), volumeSettable: backend.canSetVolume(d))
        switch method {
        case .mute: state = backend.isMuted(d) == true ? .muted : .unmuted
        case .volume: state = (backend.volume(d) ?? 1) <= 0.001 ? .muted : .unmuted
        case .none: state = .unsupported
        }
        if tokens.isEmpty || observed != d {
            tokens = backend.observe(device: d) { [weak self] in self?.refresh() }.map { [$0] } ?? []
            observed = d
        }
    }
}

/// Echtes Gerät über Core Audio. Nur Standard-Eingabe, Hauptkanal; keine Freigabe nötig (gemessen 15.11.: eingebautes
/// Mikrofon hat „Stumm“ und Lautstärke setzbar, das iPhone-Mikrofon beides nicht).
final class CoreAudioMic: MicBackend {

    private func address(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeInput)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func defaultInput() -> UInt32? {
        var a = address(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal)
        var d = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &d) == noErr,
              d != kAudioObjectUnknown else { return nil }
        return d
    }

    private func settable(_ d: UInt32, _ s: AudioObjectPropertySelector) -> Bool {
        var a = address(s)
        var ok: DarwinBoolean = false
        return AudioObjectHasProperty(d, &a) && AudioObjectIsPropertySettable(d, &a, &ok) == noErr && ok.boolValue
    }

    func canSetMute(_ device: UInt32) -> Bool { settable(device, kAudioDevicePropertyMute) }
    func canSetVolume(_ device: UInt32) -> Bool { settable(device, kAudioDevicePropertyVolumeScalar) }

    func isMuted(_ device: UInt32) -> Bool? {
        var a = address(kAudioDevicePropertyMute), v: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v != 0 : nil
    }

    func setMuted(_ device: UInt32, _ on: Bool) -> Bool {
        var a = address(kAudioDevicePropertyMute), v: UInt32 = on ? 1 : 0
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    func volume(_ device: UInt32) -> Float? {
        var a = address(kAudioDevicePropertyVolumeScalar), v: Float = 0, size = UInt32(MemoryLayout<Float>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    func setVolume(_ device: UInt32, _ value: Float) -> Bool {
        var a = address(kAudioDevicePropertyVolumeScalar), v = min(1, max(0, value))
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float>.size), &v) == noErr
    }

    /// Anmeldung am Standard-Eingang des Systems und am Gerät; beim Freigeben des Tokens werden beide abgemeldet.
    func observe(device: UInt32?, _ handler: @escaping @MainActor () -> Void) -> AnyObject? {
        let token = Listeners()
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { handler() } }
        }
        var targets: [(AudioObjectID, AudioObjectPropertyAddress)] = [
            (AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal)),
        ]
        if let device {
            targets.append((device, address(kAudioDevicePropertyMute)))
            targets.append((device, address(kAudioDevicePropertyVolumeScalar)))
        }
        for (obj, addr) in targets {
            var a = addr
            if AudioObjectAddPropertyListenerBlock(obj, &a, .main, block) == noErr {
                token.entries.append((obj, addr, block))
            }
        }
        return token
    }

    private final class Listeners {
        // swiftlint:disable:next large_tuple
        var entries: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
        deinit {
            for (obj, addr, block) in entries {
                var a = addr
                AudioObjectRemovePropertyListenerBlock(obj, &a, .main, block)
            }
        }
    }
}
