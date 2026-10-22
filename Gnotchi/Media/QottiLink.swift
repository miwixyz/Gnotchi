import Foundation
import OSLog

/// Qotti-Kontingent in der Insel (0.3.0, specs/2026-10-20-gnotchi-0.3.0-qotti.md, SECURE-DESIGN G22).
/// Qotti meldet über distnoted `app.qotti.local.kontingent` nur Zahlen und eine feste Aufzählung – jeder
/// lokale Prozess kann senden und mitlesen (wie G17): Schema statt Vertrauen, feste Texte, keine Befehle.
@MainActor
final class QottiLink: NotchPart {

    enum State: String, Sendable { case ok, stale, throttled }

    struct Provider: Equatable, Sendable {
        let percent: Int
        let resetAt: Date?
        let state: State
    }

    struct Snapshot: Equatable, Sendable {
        var claude: Provider?
        var codex: Provider?
        var isEmpty: Bool { claude == nil && codex == nil }
    }

    /// Je Anbieter: welche Warnstufe noch auslösen darf (Michael 20.10.: 80 % und 95 %, dazu Drosselung).
    struct Alarm: Equatable, Sendable {
        var armed80 = true
        var armed95 = true
        var armedThrottle = true
    }

    enum Level: Equatable, Sendable { case percent80, percent95, throttled }

    nonisolated static let notificationName = Notification.Name("app.qotti.local.kontingent")
    /// Qotti sendet bei Änderung und alle 60 s – länger still heißt: Qotti ist weg, Werte verwerfen.
    static let staleAfter: Duration = .seconds(300)
    /// Höchstens so oft auswerten (letzter Stand gewinnt).
    nonisolated static let minInterval: TimeInterval = 1

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "qotti")

    private let activity: ActivityModel
    private var observer: NSObjectProtocol?
    private var stale: Task<Void, Never>?
    private var flush: Task<Void, Never>?
    private var pending: Snapshot?
    private var lastApplied = Date.distantPast
    private var alarms: [String: Alarm] = [:]

    init(activity: ActivityModel) {
        self.activity = activity
    }

    // MARK: Reine Teile (getestet)

    /// Schema: `v` = 1; je Anbieter `<name>5h` Zahl (kein Bool, endlich) → auf 0…100 gerundet und begrenzt,
    /// `<name>Reset5h` Unix-Sekunden (nur plausibel: höchstens 1 Tag zurück, 8 Tage voraus), `<name>State` aus
    /// der Positivliste (fehlt = ok, unbekannt = Anbieter verworfen). Kein Anbieter → nil.
    nonisolated static func parse(_ info: [AnyHashable: Any]?, now: Date = Date()) -> Snapshot? {
        guard let info, let v = number(info["v"]), v.intValue == 1, v.doubleValue == 1 else { return nil }
        let s = Snapshot(claude: provider("claude", info, now: now), codex: provider("codex", info, now: now))
        return s.isEmpty ? nil : s
    }

    private nonisolated static func provider(_ name: String, _ info: [AnyHashable: Any], now: Date) -> Provider? {
        guard let raw = number(info["\(name)5h"])?.doubleValue, raw.isFinite else { return nil }
        let state: State
        if let s = info["\(name)State"] {
            guard let str = s as? String, let parsed = State(rawValue: str) else { return nil }
            state = parsed
        } else {
            state = .ok
        }
        var reset: Date?
        if let secs = number(info["\(name)Reset5h"])?.doubleValue, secs.isFinite {
            let d = Date(timeIntervalSince1970: secs)
            if d > now.addingTimeInterval(-86_400), d < now.addingTimeInterval(8 * 86_400) { reset = d }
        }
        return Provider(percent: Int(min(max(raw, 0), 100).rounded()), resetAt: reset, state: state)
    }

    /// Zahl, aber kein Wahrheitswert (NSNumber trägt beides).
    private nonisolated static func number(_ any: Any?) -> NSNumber? {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n
    }

    /// Nächste Warnung je Anbieter. Drosselung vor 95 % vor 80 %; springt der Wert direkt über 95 %,
    /// kommt nur die 95-%-Warnung. Eine Stufe wird erst wieder scharf, wenn der Wert darunter fällt.
    nonisolated static func evaluate(_ alarm: Alarm, _ p: Provider?) -> (Alarm, Level?) {
        guard let p else { return (alarm, nil) }
        var a = alarm
        if p.state != .throttled { a.armedThrottle = true }
        if p.percent < 80 { a.armed80 = true }
        if p.percent < 95 { a.armed95 = true }
        if p.state == .throttled, a.armedThrottle {
            a.armedThrottle = false
            return (a, .throttled)
        }
        if p.percent >= 95, a.armed95 {
            a.armed95 = false
            a.armed80 = false
            return (a, .percent95)
        }
        if p.percent >= 80, a.armed80 {
            a.armed80 = false
            return (a, .percent80)
        }
        return (a, nil)
    }

    /// „zurück in 1 Std. 5 Min.“ – wie Qotti, ohne Sekunden.
    nonisolated static func resetLabel(_ reset: Date?, now: Date = Date()) -> String {
        guard let reset else { return "5-Stunden-Limit" }
        let minutes = Int((reset.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "wird gleich zurückgesetzt" }
        if minutes < 60 { return "zurück in \(minutes) Min." }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "zurück in \(h) Std." : "zurück in \(h) Std. \(m) Min."
    }

    nonisolated static func notice(name: String, _ p: Provider, _ level: Level, now: Date = Date()) -> ActivityModel.Notice {
        switch level {
        case .throttled:
            ActivityModel.Notice(symbol: "exclamationmark.triangle.fill", title: "\(name) gedrosselt",
                                 subtitle: resetLabel(p.resetAt, now: now))
        case .percent95:
            ActivityModel.Notice(symbol: "gauge.with.dots.needle.100percent", title: "\(name) \(p.percent) %",
                                 subtitle: resetLabel(p.resetAt, now: now))
        case .percent80:
            ActivityModel.Notice(symbol: "gauge.with.dots.needle.67percent", title: "\(name) \(p.percent) %",
                                 subtitle: resetLabel(p.resetAt, now: now))
        }
    }

    /// Zeile der großen Insel: „Claude 42 % · Codex 17 %“ (nur 5 h, wie Qottis Menüleiste; „Codex“ wie Qotti seit 21.10.).
    nonisolated static func line(_ s: Snapshot?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        func part(_ name: String, _ p: Provider?) -> String? {
            guard let p else { return nil }
            return p.state == .throttled ? "\(name) gedrosselt" : "\(name) \(p.percent) %"
        }
        return [part("Claude", s.claude), part("Codex", s.codex)].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Betrieb

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { [weak self] note in
            let snapshot = Self.parse(note.userInfo)
            Task { @MainActor in self?.receive(snapshot) }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        stale?.cancel()
        flush?.cancel()
        stale = nil
        flush = nil
        pending = nil
        alarms = [:]
        activity.setQuota(nil)
    }

    private func receive(_ snapshot: Snapshot?) {
        guard let snapshot else { return }
        let wait = Self.minInterval - Date().timeIntervalSince(lastApplied)
        guard wait > 0 else { return apply(snapshot) }
        pending = snapshot
        guard flush == nil else { return }
        flush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            flush = nil
            if let p = pending { pending = nil; apply(p) }
        }
    }

    private func apply(_ s: Snapshot) {
        lastApplied = Date()
        if activity.quota == nil { Self.log.notice("Qotti-Kontingent empfangen") }
        activity.setQuota(s)
        for (key, name, p) in [("claude", "Claude", s.claude), ("codex", "Codex", s.codex)] {
            let (a, level) = Self.evaluate(alarms[key] ?? Alarm(), p)
            alarms[key] = a
            if let level, let p { activity.post(Self.notice(name: name, p, level)) }
        }
        stale?.cancel()
        stale = Task { [weak self] in
            try? await Task.sleep(for: Self.staleAfter)
            guard !Task.isCancelled, let self else { return }
            Self.log.notice("Qotti-Kontingent: keine Meldung seit 5 Min., verworfen")
            activity.setQuota(nil)
        }
    }
}
