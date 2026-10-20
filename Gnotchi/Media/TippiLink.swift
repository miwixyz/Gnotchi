import Foundation
import OSLog

/// Tippi-Aufnahme in der Insel (0.2.0, Michael 20.10.): Tippi meldet seinen Diktat-Zustand über
/// `DistributedNotificationCenter`; läuft Gnotchi mit diesem Schalter, blendet Tippi seine eigene Pille aus
/// (Tippi prüft dafür Gnotchis Signatur und liest den Schalter `tippiRecording`).
/// Jeder lokale Prozess kann diese Meldung senden (SECURE-DESIGN G17): Gnotchi zeigt nur feste Texte,
/// nimmt aus der Nachricht nur Zustand (Positivliste) und Pegel (begrenzt), und ohne Meldung seit 3 s
/// gilt die Aufnahme als beendet – die Insel bleibt nicht hängen, wenn Tippi abstürzt.
@MainActor
final class TippiLink: NotchPart {

    enum Message: Equatable, Sendable {
        case recording(level: Double), transcribing, idle
    }

    nonisolated static let notificationName = Notification.Name("com.tippi.app.aufnahme")
    /// Tippi sendet beim Aufnehmen 10×/s, beim Umwandeln 1×/s – länger still heißt: vorbei.
    static let staleAfter: Duration = .seconds(3)
    /// Pegel höchstens so oft an die Ansicht geben (Schutz gegen eine Nachrichtenflut).
    nonisolated static let minLevelInterval: TimeInterval = 1.0 / 30

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "tippi")

    private let activity: ActivityModel
    private var observer: NSObjectProtocol?
    private var stale: Task<Void, Never>?
    private var lastLevelAt = Date.distantPast

    init(activity: ActivityModel) {
        self.activity = activity
    }

    // MARK: Reine Teile (getestet)

    /// Schema: `v` = 1, `state` ∈ {recording, transcribing, idle}, `level` endliche Zahl (kein Bool), auf 0…1
    /// begrenzt. Unbekannte Schlüssel werden ignoriert, alles andere verworfen.
    nonisolated static func parse(_ info: [AnyHashable: Any]?) -> Message? {
        guard let info, let v = number(info["v"]), v.intValue == 1, v.doubleValue == 1,
              let state = info["state"] as? String else { return nil }
        switch state {
        case "recording":
            let raw = number(info["level"])?.doubleValue ?? 0
            return .recording(level: raw.isFinite ? min(max(raw, 0), 1) : 0)
        case "transcribing": return .transcribing
        case "idle": return .idle
        default: return nil
        }
    }

    /// Zahl, aber kein Wahrheitswert (NSNumber trägt beides).
    private nonisolated static func number(_ any: Any?) -> NSNumber? {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n
    }

    nonisolated static func next(_ current: ActivityModel.Recording?, _ m: Message, now: Date) -> ActivityModel.Recording? {
        switch m {
        case .recording:
            if case .recording? = current { return current }
            return .recording(since: now)
        case .transcribing: return .transcribing
        case .idle: return nil
        }
    }

    /// Laufzeit wie in Tippis Pille: m:ss.
    nonisolated static func elapsedLabel(_ seconds: TimeInterval) -> String {
        let t = seconds.isFinite ? Int(max(0, seconds)) : 0
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: Betrieb

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { [weak self] note in
            let message = Self.parse(note.userInfo)
            MainActor.assumeIsolated { self?.receive(message) }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        stale?.cancel()
        stale = nil
        activity.setRecording(nil)
    }

    private func receive(_ message: Message?) {
        guard let message else { return }
        let now = Date()
        let new = Self.next(activity.recording, message, now: now)
        if (activity.recording == nil) != (new == nil) {
            Self.log.notice("Tippi-Aufnahme \(new == nil ? "beendet" : "angezeigt", privacy: .public)")
        }
        activity.setRecording(new)
        if case .recording(let level) = message, now.timeIntervalSince(lastLevelAt) >= Self.minLevelInterval {
            activity.setRecordingLevel(level)
            lastLevelAt = now
        }
        stale?.cancel()
        guard new != nil else { stale = nil; return }
        stale = Task { [weak self] in
            try? await Task.sleep(for: Self.staleAfter)
            guard !Task.isCancelled, let self else { return }
            Self.log.notice("Tippi-Aufnahme: keine Meldung seit 3 s, ausgeblendet")
            self.activity.setRecording(nil)
        }
    }
}
