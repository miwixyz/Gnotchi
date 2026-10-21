import CoreAudio
import Foundation
import OSLog

/// Kopfhörer-Hinweis (0.2.0, Michael 20.10.): Wechselt der Ton auf Bluetooth-Kopfhörer oder von ihnen
/// zurück, zeigt die Insel 3 s Symbol, Gerätename und Zustand. Beobachtet nur das Standard-Ausgabegerät
/// (Core Audio, öffentlich, keine Bluetooth-Freigabe nötig). Protokoll ohne Gerätenamen.
/// Ab 0.4.0 zusätzlich die Kopfhörer-Aktivität: Solange der Ton über Bluetooth läuft, zeigt die Insel sie
/// dauerhaft. Derselbe, einmal angemeldete Beobachter (G19) – nie im eigenen Rückruf neu anmelden.
@MainActor
final class HeadphoneWatcher: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "ausgang")

    private let activity: ActivityModel
    private var last: OutputDevices.Device?
    private var listener: AudioObjectPropertyListenerBlock?
    /// Schalter „Kopfhörer-Hinweis“ und „Kopfhörer-Aktivität“, bei jedem Wechsel neu gelesen.
    private let noticeOn: @MainActor () -> Bool
    private let activityOn: @MainActor () -> Bool

    init(activity: ActivityModel, noticeOn: @escaping @MainActor () -> Bool = { true },
         activityOn: @escaping @MainActor () -> Bool = { true }) {
        self.activity = activity
        self.noticeOn = noticeOn
        self.activityOn = activityOn
    }

    /// Aktivität zum aktuellen Gerät: nur Bluetooth, nur bei eingeschaltetem Schalter.
    nonisolated static func headphones(_ device: OutputDevices.Device?, enabled: Bool) -> Headphones? {
        guard enabled, let device, device.kind == .bluetooth else { return nil }
        return Headphones(name: device.name, symbol: OutputDevices.Kind.bluetooth.symbol)
    }

    /// Welcher Hinweis zu einem Wechsel gehört. Ohne bekanntes voriges Gerät (gleich nach dem Start) keiner:
    /// Kopfhörer, die schon verbunden sind, sind nichts Neues.
    nonisolated static func notice(old: OutputDevices.Device?, new: OutputDevices.Device?,
                                   setByUs: Bool) -> ActivityModel.Notice? {
        guard let old, let new, old.id != new.id, !setByUs else { return nil }
        if new.kind == .bluetooth {
            return ActivityModel.Notice(symbol: OutputDevices.Kind.bluetooth.symbol, title: new.name, subtitle: "Verbunden")
        }
        if old.kind == .bluetooth {
            return ActivityModel.Notice(symbol: new.kind.symbol, title: new.name, subtitle: "Kopfhörer getrennt")
        }
        return nil
    }

    func start() {
        guard listener == nil else { return }
        last = OutputDevices.current().flatMap(OutputDevices.device)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultChanged() }
        }
        var addr = AudioRoute.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        guard status == noErr else {
            Self.log.error("Kopfhörer-Hinweis: Beobachter nicht angemeldet (OSStatus \(status, privacy: .public))")
            return
        }
        listener = block
        activity.setHeadphones(Self.headphones(last, enabled: activityOn()))
    }

    /// Schalter geändert (AppModel.applyNotchSetting): Aktivität sofort anpassen, ohne neu anzumelden.
    func recheck() {
        guard listener != nil else { return }
        activity.setHeadphones(Self.headphones(last, enabled: activityOn()))
    }

    func stop() {
        if let listener {
            var addr = AudioRoute.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, listener)
        }
        listener = nil
        last = nil
        activity.clearNotice()
        activity.setHeadphones(nil)
    }

    private func defaultChanged() {
        let new = OutputDevices.current().flatMap(OutputDevices.device)
        let byUs = OutputDevices.selectedByUs(new?.id, now: Date(), last: OutputDevices.lastSelection)
        if noticeOn(), let n = Self.notice(old: last, new: new, setByUs: byUs) { activity.post(n) }
        last = new
        activity.setHeadphones(Self.headphones(new, enabled: activityOn()))
    }
}
