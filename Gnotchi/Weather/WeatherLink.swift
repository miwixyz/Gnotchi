import AppKit
import OSLog

/// Holt das Wetter (0.7.0, G31), solange „Wetter in der Notch“ an ist und ein Ort gewählt ist: sofort, dann alle
/// 30 Minuten und nach dem Aufwachen; höchstens alle 5 Minuten. Fehler → letzter Stand bis 3 Stunden.
/// Protokoll ohne Ort und Werte.
@MainActor
final class WeatherLink: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "wetter")
    nonisolated static let interval: TimeInterval = 30 * 60
    nonisolated static let minGap: TimeInterval = 5 * 60
    nonisolated static let keepStale: TimeInterval = 3 * 3600

    private let activity: ActivityModel
    private let prefs: Preferences
    private let client = WeatherClient.shared
    private var timer: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var lastAttempt = Date.distantPast
    private var lastKey: String?

    init(activity: ActivityModel, prefs: Preferences) {
        self.activity = activity
        self.prefs = prefs
    }

    func start() {
        guard timer == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: false) }
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh(force: false)
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        lastKey = nil
        activity.setWeather(nil)
    }

    /// Ort oder Einheit geändert → sofort neu (auch innerhalb der 5 Minuten).
    func recheck() {
        guard timer != nil else { return }
        refresh(force: key != lastKey)
    }

    private var key: String? {
        prefs.weatherPlace.map { "\($0.latitude),\($0.longitude),\(prefs.weatherUnit.rawValue)" }
    }

    private func refresh(force: Bool) {
        guard let place = prefs.weatherPlace else { return activity.setWeather(nil) }
        guard force || Date().timeIntervalSince(lastAttempt) >= Self.minGap else { return }
        lastAttempt = Date()
        let unit = prefs.weatherUnit
        let key = key
        if key != lastKey { activity.setWeather(nil) }
        Task { [weak self, client] in
            do {
                var f = try await client.forecast(place, unit: unit)
                f.placeName = place.name
                guard let self, self.timer != nil, self.key == key else { return }
                self.lastKey = key
                self.activity.setWeather(f)
                Self.log.notice("Wetter aktualisiert")
            } catch {
                Self.log.error("Wetter-Fehler (\(String(describing: error), privacy: .public))")
                guard let self, let old = self.activity.weather else { return }
                if Date().timeIntervalSince(old.fetched) > Self.keepStale { self.activity.setWeather(nil) }
            }
        }
    }
}
