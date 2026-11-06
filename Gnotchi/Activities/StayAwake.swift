import Foundation
import IOKit.pwr_mgt
import Observation
import OSLog

/// Wach bleiben (0.21.0, specs/2026-11-06-gnotchi-0.21.0-wachbleiben-timer.md, G47).
///
/// Aktiv, wenn von Hand an (für eine Dauer oder „bis aus“) **oder** Zeitplan an und jetzt im Zeitfenster. Dann hält
/// eine Energie-Zusicherung den Mac wach (`PreventUserIdleSystemSleep`, ohne Freigabe). Mit „Status in Teams/Slack
/// aktiv halten“ bittet Gnotchi das Hilfsprogramm jede Minute um eine winzige Mausbewegung (`nudge`); ob es sich
/// bewegt (≥ 4 Min. Leerlauf), entscheidet das Hilfsprogramm. Einstellungen in UserDefaults, nur lokal.
@MainActor
@Observable
final class StayAwake: NotchPart {
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "wach")
    nonisolated static let durations: [(label: String, hours: Int?)] = [("1 Std.", 1), ("2 Std.", 2), ("4 Std.", 4), ("Bis aus", nil)]
    /// Wochentage wie `Calendar` (1 = So … 7 = Sa). Ab Werk Mo–Fr.
    nonisolated static let defaultDays: Set<Int> = [2, 3, 4, 5, 6]
    nonisolated static let defaultFrom = 9 * 60
    nonisolated static let defaultTo = 18 * 60
    nonisolated static let step = 15

    enum Key {
        static let schedule = "awakeSchedule", days = "awakeDays", from = "awakeFrom", to = "awakeTo", nudge = "awakeNudge"
    }

    @ObservationIgnored private let defaults: UserDefaults
    var schedule: Bool { didSet { defaults.set(schedule, forKey: Key.schedule); update() } }
    var days: Set<Int> { didSet { defaults.set(days.sorted(), forKey: Key.days); update() } }
    /// Minuten seit Mitternacht, 15-Min.-Schritte, `from < to` (kein Fenster über Mitternacht).
    var from: Int { didSet { defaults.set(from, forKey: Key.from); update() } }
    var to: Int { didSet { defaults.set(to, forKey: Key.to); update() } }
    var nudge: Bool { didSet { defaults.set(nudge, forKey: Key.nudge); onNudgeChange(); update() } }

    /// Von Hand an bis zu diesem Zeitpunkt (`.distantFuture` = bis aus). Nicht gespeichert: nach Neustart aus.
    private(set) var manualUntil: Date?
    /// Von Hand aus im Zeitfenster: Zeitplan schweigt bis hierhin (Ende des heutigen Fensters).
    private(set) var suppressedUntil: Date?
    private(set) var isActive = false

    /// Hilfsprogramm starten/stoppen (AppModel → applyNotchSetting).
    @ObservationIgnored var onNudgeChange: () -> Void = {}
    /// Befehl ans Hilfsprogramm (ActivityModel.notifyCommand).
    @ObservationIgnored var send: (NotifyWire.Command) -> Void = { _ in }
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastNudge: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        schedule = defaults.object(forKey: Key.schedule) as? Bool ?? false
        nudge = defaults.object(forKey: Key.nudge) as? Bool ?? false
        let (f, t) = Self.validWindow(from: defaults.object(forKey: Key.from), to: defaults.object(forKey: Key.to))
        from = f
        to = t
        days = Self.validDays(defaults.object(forKey: Key.days))
    }

    // MARK: Bedienung

    /// Von Hand an für `hours` Stunden, `nil` = bis aus.
    func turnOn(hours: Int?, now: Date = Date()) {
        manualUntil = hours.map { now.addingTimeInterval(TimeInterval($0) * 3600) } ?? .distantFuture
        suppressedUntil = nil
        update(now: now)
    }

    /// Von Hand aus. Im Zeitfenster schweigt der Zeitplan bis zu dessen Ende heute.
    func turnOff(now: Date = Date()) {
        manualUntil = nil
        if schedule, Self.inWindow(now, days: days, from: from, to: to) {
            suppressedUntil = Self.windowEnd(now, to: to)
        }
        update(now: now)
    }

    /// Bis wann wach – für Menü und Ansicht. nil = aus, `.distantFuture` = bis aus.
    var activeUntil: Date? {
        guard isActive else { return nil }
        let now = Date()
        if let m = manualUntil, m > now { return m }
        return Self.windowEnd(now, to: to)
    }

    // MARK: NotchPart

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        update()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        setAssertion(false)
        isActive = false
    }

    // MARK: Regeln (getestet)

    nonisolated static func inWindow(_ now: Date, days: Set<Int>, from: Int, to: Int, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let wd = c.weekday, days.contains(wd), from < to else { return false }
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return minute >= from && minute < to
    }

    nonisolated static func windowEnd(_ now: Date, to: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: to / 60, minute: to % 60, second: 0, of: now) ?? now
    }

    nonisolated static func isActive(now: Date, manualUntil: Date?, schedule: Bool, inWindow: Bool, suppressedUntil: Date?) -> Bool {
        if let manualUntil, manualUntil > now { return true }
        if let suppressedUntil, suppressedUntil > now { return false }
        return schedule && inWindow
    }

    nonisolated static func validDays(_ raw: Any?) -> Set<Int> {
        guard let list = raw as? [Int] else { return defaultDays }
        return Set(list.filter { (1...7).contains($0) })
    }

    /// Auf 15 Min. gerundet, 0…24 h, `from < to`; sonst ab Werk 9–18.
    nonisolated static func validWindow(from rawFrom: Any?, to rawTo: Any?) -> (Int, Int) {
        guard let f = rawFrom as? Int, let t = rawTo as? Int, (0...1440).contains(f), (0...1440).contains(t),
              f % step == 0, t % step == 0, f < t else { return (defaultFrom, defaultTo) }
        return (f, t)
    }

    nonisolated static func timeText(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: Intern

    private func update(now: Date = Date()) {
        if let m = manualUntil, m <= now { manualUntil = nil }
        if let s = suppressedUntil, s <= now { suppressedUntil = nil }
        let active = Self.isActive(now: now, manualUntil: manualUntil, schedule: schedule,
                                   inWindow: Self.inWindow(now, days: days, from: from, to: to),
                                   suppressedUntil: suppressedUntil)
        if active != isActive {
            isActive = active
            Self.log.notice("Wach bleiben \(active ? "an" : "aus", privacy: .public)")
        }
        setAssertion(active && timer != nil)
        guard active, nudge, timer != nil else { return }
        // Jede Minute höchstens einmal fragen; das Hilfsprogramm prüft Leerlauf und Abstand selbst (G47).
        if let lastNudge, now.timeIntervalSince(lastNudge) < 55 { return }
        lastNudge = now
        send(.nudge)
    }

    private func setAssertion(_ on: Bool) {
        if on, assertion == 0 {
            let r = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Gnotchi: Wach bleiben" as CFString, &assertion)
            if r != kIOReturnSuccess {
                assertion = 0
                Self.log.error("Wach bleiben: Zusicherung abgelehnt (\(r, privacy: .public))")
            }
        } else if !on, assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
}
