import AppKit
import Foundation
import OSLog

/// Eigener Timer (0.5.0, Fahrplan „Timer + Kalender“, Michael 21.10.). Nur lokal: keine Berechtigung, kein Netz,
/// keine Verbindung nach außen. Ein Timer zur Zeit.
struct CountdownTimer: Equatable, Sendable {

    /// Auswahl im Menü und in der großen Insel (Minuten).
    nonisolated static let choices = [5, 10, 15, 25]
    /// Eigene Zeit (Michael 21.10.): 1 bis 180 Minuten, zuletzt gewählte bleibt (UserDefaults).
    nonisolated static let customRange = 1...180
    nonisolated static let customKey = "timerCustomMinutes"

    nonisolated static func clampCustom(_ m: Int) -> Int {
        min(max(m, customRange.lowerBound), customRange.upperBound)
    }

    /// − / +: unter 10 Minuten in 1er-, darüber in 5er-Schritten.
    nonisolated static func stepCustom(_ m: Int, up: Bool) -> Int {
        let step = (up ? m >= 10 : m > 10) ? 5 : 1
        return clampCustom(up ? m + step : m - step)
    }

    /// Töne bei Ablauf (Michael 21.10.: Tonauswahl): die Systemtöne aus /System/Library/Sounds, gemessen 21.10.
    /// unter macOS 27. Gespielt wird nur ein Name aus dieser Liste, nie ein Pfad aus den Einstellungen.
    nonisolated static let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop",
                                     "Purr", "Sosumi", "Submarine", "Tink"]
    nonisolated static let defaultSound = "Glass"
    /// Leerer Name = kein Ton.
    nonisolated static let silent = ""

    /// Gespeicherter Wert → gültiger Ton (unbekannt → Werkseinstellung).
    nonisolated static func validSound(_ value: Any?) -> String {
        guard let s = value as? String else { return defaultSound }
        return s == silent || sounds.contains(s) ? s : defaultSound
    }

    @MainActor static func play(_ sound: String) {
        guard sounds.contains(sound) else { return }
        NSSound(named: NSSound.Name(sound))?.play()
    }

    /// Eingabe aus dem Menü-Fenster: nur ganze Minuten im Bereich, sonst nil.
    nonisolated static func parseCustom(_ text: String) -> Int? {
        guard let m = Int(text.trimmingCharacters(in: .whitespaces)), customRange.contains(m) else { return nil }
        return m
    }

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
        CountdownTimer.play(CountdownTimer.validSound(UserDefaults.standard.object(forKey: Preferences.Key.timerSound)))
    }
}
