import Foundation
import IOKit.pwr_mgt
import Observation
import OSLog

/// Wach bleiben (0.21.0, specs/2026-11-06-gnotchi-0.21.0-wachbleiben-timer.md, G47).
///
/// Aktiv, wenn von Hand an (für eine Dauer oder „bis aus“) **oder** Zeitplan an und jetzt im Zeitfenster **oder**
/// Zeitplan an mit „Außerhalb wach bleiben“. Dann hält eine Energie-Zusicherung den Mac wach
/// (`PreventUserIdleSystemSleep`, ohne Freigabe – der Bildschirm darf dabei schlafen). Mausbewegung (`.mouse`) nur im
/// Zeitfenster und von Hand mit „mit Maus“ (Michael 09.11.): dann bittet Gnotchi das Hilfsprogramm jede Minute um eine
/// winzige Bewegung (`nudge`); ob es sich bewegt (≥ 4 Min. Leerlauf), entscheidet das Hilfsprogramm. Erst die Bewegung
/// hält auch den Bildschirm an. Einstellungen in UserDefaults, nur lokal.
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
        static let outside = "awakeOutside"
    }

    /// aus · wach ohne Maus (Bildschirm darf schlafen) · wach mit Mausbewegung.
    enum Mode: Equatable { case off, quiet, mouse }

    @ObservationIgnored private let defaults: UserDefaults
    var schedule: Bool { didSet { defaults.set(schedule, forKey: Key.schedule); onNudgeChange(); update() } }
    /// Mit Zeitplan: außerhalb des Fensters wach bleiben, ohne Maus. Ab Werk aus.
    var outside: Bool { didSet { defaults.set(outside, forKey: Key.outside); update() } }
    var days: Set<Int> { didSet { defaults.set(days.sorted(), forKey: Key.days); update() } }
    /// Minuten seit Mitternacht, 15-Min.-Schritte, `from < to` (kein Fenster über Mitternacht).
    var from: Int { didSet { defaults.set(from, forKey: Key.from); update() } }
    var to: Int { didSet { defaults.set(to, forKey: Key.to); update() } }
    /// Von Hand eingeschaltet mit Mausbewegung (Schlüssel aus 0.21.0, damals für alles). Der Zeitplan bewegt immer.
    var nudge: Bool { didSet { defaults.set(nudge, forKey: Key.nudge); onNudgeChange(); update() } }

    /// Hilfsprogramm nötig, sobald sich die Maus bewegen kann.
    var needsHelper: Bool { nudge || schedule }

    /// Von Hand an bis zu diesem Zeitpunkt (`.distantFuture` = bis aus). Nicht gespeichert: nach Neustart aus.
    private(set) var manualUntil: Date?
    /// Von Hand aus im Zeitfenster: Zeitplan schweigt bis hierhin (Ende des heutigen Fensters).
    private(set) var suppressedUntil: Date?
    private(set) var mode = Mode.off
    var isActive: Bool { mode != .off }

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
        outside = defaults.object(forKey: Key.outside) as? Bool ?? false
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

    /// Von Hand aus. Der Zeitplan schweigt bis zum nächsten Wechsel (Fensterende bzw. nächster Fensterbeginn).
    func turnOff(now: Date = Date()) {
        manualUntil = nil
        if let s = plan.suppressAfterOff(now) { suppressedUntil = s }
        update(now: now)
    }

    /// Bis wann wach – für Menü und Ansicht. nil = aus, `.distantFuture` = bis aus.
    var activeUntil: Date? {
        guard isActive else { return nil }
        let now = Date()
        if let m = manualUntil, m > now { return m }
        if plan.inWindow(now) { return Self.windowEnd(now, to: to) }
        return plan.nextStart(after: now) ?? .distantFuture
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
        mode = .off
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

    /// Zeitplan-Einstellungen als Wert, damit die Regeln ohne Instanz testbar sind.
    struct Plan {
        var on: Bool, outside: Bool, days: Set<Int>, from: Int, to: Int

        func inWindow(_ now: Date, calendar: Calendar = .current) -> Bool {
            StayAwake.inWindow(now, days: days, from: from, to: to, calendar: calendar)
        }

        /// Von Hand schlägt alles (mit/ohne Maus nach Wahl), dann „von Hand aus“, dann Zeitplan: im Fenster mit Maus,
        /// außerhalb mit „Außerhalb wach bleiben“ ohne Maus.
        func mode(now: Date, manualUntil: Date?, manualNudge: Bool, suppressedUntil: Date?,
                  calendar: Calendar = .current) -> Mode {
            if let manualUntil, manualUntil > now { return manualNudge ? .mouse : .quiet }
            if let suppressedUntil, suppressedUntil > now { return .off }
            guard on else { return .off }
            if inWindow(now, calendar: calendar) { return .mouse }
            return outside ? .quiet : .off
        }

        /// Nächster Fensterbeginn NACH `now` (heute oder an einem der nächsten 7 Tage). nil = keine Tage gewählt.
        func nextStart(after now: Date, calendar: Calendar = .current) -> Date? {
            let today = calendar.startOfDay(for: now)
            for offset in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      days.contains(calendar.component(.weekday, from: day)),
                      let start = calendar.date(bySettingHour: from / 60, minute: from % 60, second: 0, of: day),
                      start > now else { continue }
                return start
            }
            return nil
        }

        /// Wie lange „von Hand aus“ den Zeitplan stumm schaltet. nil = es läuft gerade nichts vom Zeitplan.
        func suppressAfterOff(_ now: Date, calendar: Calendar = .current) -> Date? {
            guard on else { return nil }
            if inWindow(now, calendar: calendar) { return StayAwake.windowEnd(now, to: to, calendar: calendar) }
            guard outside else { return nil }
            return nextStart(after: now, calendar: calendar) ?? .distantFuture
        }
    }

    var plan: Plan { Plan(on: schedule, outside: outside, days: days, from: from, to: to) }

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
        let next = plan.mode(now: now, manualUntil: manualUntil, manualNudge: nudge, suppressedUntil: suppressedUntil)
        if next != mode {
            mode = next
            let text = next == .off ? "aus" : next == .quiet ? "an, ohne Maus" : "an, mit Maus"
            Self.log.notice("Wach bleiben \(text, privacy: .public)")
        }
        setAssertion(isActive && timer != nil)
        guard mode == .mouse, timer != nil else { return }
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
