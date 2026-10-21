import AppKit
import Foundation
import OSLog
import Security

/// Nächster Termin aus Kalli (0.5.0, specs/2026-10-21-gnotchi-0.5.0-termine.md, SECURE-DESIGN G26): reine Teile.
/// Termin-Titel sind privat. Sie kommen nur über den lokalen Socket `kalli.sock`, dessen Gegenseite per
/// Audit-Token gegen Kallis Developer-ID-Anforderung geprüft ist, nie über distnoted, und werden nie
/// protokolliert oder gespeichert.
enum KalliEvents {

    nonisolated static let requirement = LiveText.peerRequirement(identifier: "com.kalli.app")
    /// So lange vor Beginn erscheint der Termin in der Insel (Michael 21.10.: 15 Minuten).
    nonisolated static let lead: TimeInterval = 15 * 60
    nonisolated static let maxTitle = 120

    struct RGB: Equatable, Sendable {
        let r, g, b: Double
    }

    struct Event: Equatable, Sendable {
        let title: String
        let start: Date
        let color: RGB?
    }

    enum Message: Equatable, Sendable {
        case event(Event), none
    }

    // MARK: Schema

    /// `{"v":1,"event":{"title":"…","start":<Unix-Sekunden>,"color":"#RRGGBB"}}` oder `{"v":1,"event":null}`.
    /// `nil` = ungültig (Verbindung zu). Beginn außerhalb von jetzt − 1 Tag … jetzt + 400 Tage → `.none`.
    nonisolated static func parse(_ payload: Data, now: Date = Date()) -> Message? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              isNumber(obj["v"], equalTo: 1) else { return nil }
        guard let raw = obj["event"], !(raw is NSNull) else { return Message.none }
        guard let e = raw as? [String: Any], let title = e["title"] as? String,
              let s = e["start"] as? NSNumber, CFGetTypeID(s) != CFBooleanGetTypeID() else { return nil }
        let t = s.doubleValue
        guard t.isFinite else { return nil }
        var color: RGB?
        if let c = e["color"] {
            guard let str = c as? String, let rgb = hexColor(str) else { return nil }
            color = rgb
        }
        let start = Date(timeIntervalSince1970: t)
        guard start >= now.addingTimeInterval(-86_400), start <= now.addingTimeInterval(400 * 86_400) else {
            return Message.none
        }
        return .event(Event(title: cleanTitle(title), start: start, color: color))
    }

    nonisolated static func isNumber(_ value: Any?, equalTo n: Int) -> Bool {
        guard let v = value as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID() else { return false }
        return v.intValue == n && v.doubleValue == Double(n)
    }

    /// `#` + genau 6 Hexziffern.
    nonisolated static func hexColor(_ s: String) -> RGB? {
        let scalars = Array(s.unicodeScalars)
        guard scalars.count == 7, scalars[0] == "#",
              scalars.dropFirst().allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) || ("A"..."F").contains($0) }),
              let value = UInt32(String(s.dropFirst()), radix: 16) else { return nil }
        return RGB(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255,
                   b: Double(value & 0xFF) / 255)
    }

    /// Bereinigt wie Live-Text (G21), höchstens `maxTitle` Zeichen, leer → „Termin“.
    nonisolated static func cleanTitle(_ s: String) -> String {
        let clean = LiveText.sanitize(s)
        guard !clean.isEmpty else { return "Termin" }
        guard clean.count > maxTitle else { return clean }
        return String(clean.prefix(maxTitle - 1)) + "…"
    }

    // MARK: Anzeige

    /// Sichtbar ab `lead` vor Beginn bis Beginn.
    nonisolated static func isShowing(_ e: Event, now: Date) -> Bool {
        now >= e.start.addingTimeInterval(-lead) && now < e.start
    }

    /// Nächster Zeitpunkt, an dem sich die Sichtbarkeit ändert; nil = nichts mehr zu tun (begonnen).
    nonisolated static func nextChange(_ e: Event, now: Date) -> Date? {
        let showAt = e.start.addingTimeInterval(-lead)
        if now < showAt { return showAt }
        if now < e.start { return e.start }
        return nil
    }

    /// „12 Min“ – aufgerundet, mindestens 1.
    nonisolated static func minutesLeft(_ e: Event, now: Date) -> Int {
        max(1, Int((e.start.timeIntervalSince(now) / 60).rounded(.up)))
    }

    nonisolated static func timeText(_ e: Event) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f.string(from: e.start)
    }
}

/// Betreibt den Socket `kalli.sock` (G26), solange „Termine aus Kalli anzeigen“ an ist, und setzt den Termin in
/// der Insel ab 15 Minuten vor Beginn bis zum Beginn. Der Termin lebt nur im Arbeitsspeicher.
@MainActor
final class KalliEventLink: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "termine")

    private let activity: ActivityModel
    private var server: PeerSocketServer<KalliEvents.Message>?
    private var latest: KalliEvents.Event?
    private var timer: Task<Void, Never>?

    init(activity: ActivityModel) {
        self.activity = activity
    }

    func start() {
        guard server == nil, let dir = LiveTextLink.directory else { return }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(KalliEvents.requirement as CFString, [], &req) == errSecSuccess,
              let req else { return Self.log.error("Termine: Anforderung ungültig") }
        let s = PeerSocketServer<KalliEvents.Message>(
            directory: dir, fileName: "kalli.sock", label: "Termine", peer: "Kalli", requirement: req,
            parse: { KalliEvents.parse($0) },
            onValue: { [weak self] message in Task { @MainActor in self?.receive(message) } })
        do {
            try s.start()
            server = s
        } catch {
            Self.log.error("Termine aus: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        receive(nil)
    }

    /// Klick auf den Termin: Apple Kalender öffnen (Michael 21.10. – Kallis SwiftUI-Popover lässt sich von außen
    /// nicht öffnen, `performClick` und nachgestellte Mausereignisse gemessen ohne Wirkung).
    nonisolated static func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// `nil` = getrennt/aus → Termin sofort verwerfen.
    func receive(_ message: KalliEvents.Message?) {
        if case .event(let e)? = message { latest = e } else { latest = nil }
        schedule()
    }

    private func schedule(now: Date = Date()) {
        timer?.cancel()
        timer = nil
        guard let e = latest else { return activity.setUpcomingEvent(nil) }
        activity.setUpcomingEvent(KalliEvents.isShowing(e, now: now) ? e : nil)
        guard let next = KalliEvents.nextChange(e, now: now) else {
            latest = nil
            return
        }
        // ContinuousClock läuft im Ruhezustand weiter: Nach dem Aufwachen stimmt der Zeitpunkt.
        let wait = max(1, next.timeIntervalSince(now))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.schedule()
        }
    }
}
