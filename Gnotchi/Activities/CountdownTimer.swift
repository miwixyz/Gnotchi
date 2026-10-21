import AppKit
import Foundation
import OSLog

/// Eigener Timer (0.5.0, Fahrplan „Timer + Kalender“, Michael 21.10.). Nur lokal: keine Berechtigung, kein Netz,
/// keine Verbindung nach außen. Ein Timer zur Zeit.
struct CountdownTimer: Equatable, Sendable {

    /// Auswahl im Menü und in der großen Insel (Minuten).
    nonisolated static let choices = [5, 10, 15, 25]

    let duration: TimeInterval
    /// Läuft: Ende. Pausiert: nil.
    private(set) var endsAt: Date?
    /// Pausiert: verbleibende Zeit. Läuft: nil.
    private(set) var pausedRemaining: TimeInterval?

    init(minutes: Int, now: Date) {
        duration = TimeInterval(minutes * 60)
        endsAt = now.addingTimeInterval(duration)
    }

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, (endsAt ?? now).timeIntervalSince(now))
    }

    mutating func pause(now: Date) {
        guard !isPaused else { return }
        pausedRemaining = remaining(now: now)
        endsAt = nil
    }

    mutating func resume(now: Date) {
        guard let left = pausedRemaining else { return }
        endsAt = now.addingTimeInterval(left)
        pausedRemaining = nil
    }

    /// Kurzform für den 40-pt-Flügel neben der Notch (Testbild 21.10.: „25:00“ lief unter die Notch):
    /// „25′“, in der letzten Minute „45s“.
    nonisolated static func shortClock(_ t: TimeInterval) -> String {
        t >= 60 ? "\(Int((t / 60).rounded(.up)))′" : "\(max(0, Int(t.rounded(.up))))s"
    }

    /// „12:34“ bzw. „1:02:03“ – aufgerundet auf volle Sekunden, damit „0:00“ erst beim Ablauf steht.
    nonisolated static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

extension ActivityModel {

    private static var timerLog: Logger { Logger(subsystem: "dev.mwlr.gnotchi", category: "timer") }

    /// Startet einen Timer (ersetzt einen laufenden) und zeigt ihn groß, falls die Insel offen ist.
    func startTimer(minutes: Int) {
        timer = CountdownTimer(minutes: minutes, now: Date())
        timerPickerActive = false
        mirrorActive = false
        rotationCursor = .timer
        Self.timerLog.notice("Timer \(minutes, privacy: .public) Min gestartet")
        scheduleTimerEnd()
    }

    func pauseTimer() {
        timer?.pause(now: Date())
        scheduleTimerEnd()
    }

    func resumeTimer() {
        timer?.resume(now: Date())
        scheduleTimerEnd()
    }

    func stopTimer() {
        timer = nil
        timerTask?.cancel()
        timerTask = nil
    }

    /// Klick auf das Timer-Symbol in der Leiste, solange keiner läuft: Auswahl groß zeigen.
    func showTimerPicker() {
        timerPickerActive = true
        mirrorActive = false
    }

    private func scheduleTimerEnd() {
        timerTask?.cancel()
        timerTask = nil
        guard let t = timer, !t.isPaused else { return }
        let wait = t.remaining(now: Date())
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.timerFinished()
        }
    }

    private func timerFinished() {
        guard let t = timer else { return }
        timer = nil
        timerTask = nil
        Self.timerLog.notice("Timer abgelaufen")
        post(Notice(symbol: "timer", title: "Timer abgelaufen",
                    subtitle: "\(Int(t.duration / 60)) Minuten sind um"))
        NSSound(named: "Glass")?.play()
    }
}
