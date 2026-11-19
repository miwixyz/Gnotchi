import Foundation
import Observation
import OSLog

/// Zustand der Eingabezeile (specs/2026-11-19-gnotchi-schnelleingabe.md, Fragen 2–6): Text → Vorschau beim Tippen,
/// Tab wechselt die Art, ↵ speichert über Kalli, danach ~1,5 s „Gespeichert · Rückgängig (⌘Z)“, dann zu. Fehler:
/// die Zeile bleibt offen und sagt, was los ist. Ohne Fenster und ohne Kalli testbar (Closures).
@MainActor
@Observable
final class QuickEntryState {

    enum Phase: Equatable {
        case editing, saving
        case saved(UUID)
        case undone
        case failed(String)
    }

    /// Längere Eingaben schneidet die Zeile ab (Kalli nimmt ohnehin höchstens 200 Zeichen Titel).
    nonisolated static let maxInput = 300
    /// So lange steht „Gespeichert“ mit ⌘Z, bevor die Zeile von selbst schließt (Michael, Frage 6 und Regel ~1,5 s).
    nonisolated static let savedLinger: TimeInterval = 1.5

    var text = "" {
        didSet {
            if text.count > Self.maxInput { text = String(text.prefix(Self.maxInput)) }
            if case .failed = phase { phase = .editing }
            reparse()
        }
    }
    private(set) var entry: QuickEntryParser.Entry
    private(set) var phase: Phase = .editing
    private(set) var kindToggled = false

    private let submit: (QuickEntryParser.Entry) async -> Result<UUID, QuickEntryFailure>
    private let undo: (UUID) async -> String?
    private let close: () -> Void
    private let now: () -> Date
    private let calendar: Calendar
    private var closeTask: Task<Void, Never>?

    init(submit: @escaping (QuickEntryParser.Entry) async -> Result<UUID, QuickEntryFailure>,
         undo: @escaping (UUID) async -> String?, close: @escaping () -> Void,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.submit = submit
        self.undo = undo
        self.close = close
        self.now = now
        self.calendar = calendar
        entry = QuickEntryParser.parse("", now: now(), calendar: calendar)
    }

    var isEditable: Bool {
        switch phase {
        case .editing, .failed: true
        case .saving, .saved, .undone: false
        }
    }

    /// Return nur mit Titel (sonst Hinweis in der Vorschau, nichts geht raus).
    var canSave: Bool { isEditable && !entry.title.isEmpty }

    func toggleKind() {
        guard isEditable else { return }
        kindToggled.toggle()
        reparse()
    }

    func save() async {
        // Nur Längen und Art, nie Inhalt (Sichttest 19.11.: ↵ ohne Anfrage).
        Logger(subsystem: "dev.mwlr.gnotchi", category: "schnelleingabe").notice(
            "↵: Text \(self.text.count, privacy: .public) Zeichen, Titel \(self.entry.title.count, privacy: .public), Art \(self.entry.kind.rawValue, privacy: .public), bearbeitbar \(self.isEditable, privacy: .public)")
        guard isEditable else { return }
        guard canSave else { return phase = .failed(QuickEntryFailure.invalid.message) }
        phase = .saving
        switch await submit(entry) {
        case .failure(let failure):
            phase = .failed(failure.message)
        case .success(let id):
            phase = .saved(id)
            closeLater(after: Self.savedLinger)
        }
    }

    /// ⌘Z nur, solange „Gespeichert“ steht.
    func undoLast() async {
        guard case .saved(let id) = phase else { return }
        closeTask?.cancel()
        phase = .saving
        if let message = await undo(id) {
            phase = .failed(message)   // bleibt offen: Michael sieht, dass der Eintrag noch da sein kann
        } else {
            phase = .undone
            closeLater(after: 1)
        }
    }

    /// Tasten aus dem Fenster-Monitor (vor dem Textfeld, sonst springt Tab aus dem Feld). `true` = verbraucht.
    func handle(keyCode: UInt16, command: Bool, characters: String?) -> Bool {
        switch keyCode {
        case 48:   // Tab
            toggleKind()
            return true
        case 36, 76:   // Return, Enter
            Task { await save() }
            return true
        default:
            guard command, characters?.lowercased() == "z", case .saved = phase else { return false }
            Task { await undoLast() }
            return true
        }
    }

    func cancelPendingClose() { closeTask?.cancel() }

    private func reparse() {
        let parsed = QuickEntryParser.parse(text, now: now(), calendar: calendar)
        entry = kindToggled ? QuickEntryParser.toggled(parsed, now: now(), calendar: calendar) : parsed
    }

    private func closeLater(after seconds: TimeInterval) {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}

/// Text der Vorschauzeile – rein, getestet. „Fr 20.11. · 15:00–16:00“, „Mo 30.11. · ganztägig“, „ohne Datum“.
enum QuickEntryPreview {

    nonisolated static func when(_ e: QuickEntryParser.Entry, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let start = e.start else { return String(localized: "ohne Datum") }
        let otherYear = calendar.component(.year, from: start) != calendar.component(.year, from: now)
        let day = dayText(start, calendar) + (otherYear ? String(calendar.component(.year, from: start)) : "")
        if e.allDay { return day + " · " + String(localized: "ganztägig") }
        let from = clock(start, calendar)
        guard e.kind == .event, let end = e.end else { return day + " · " + from }
        let to = calendar.isDate(start, inSameDayAs: end) ? clock(end, calendar) : dayText(end, calendar) + " " + clock(end, calendar)
        return day + " · " + from + "–" + to
    }

    nonisolated static func kindLabel(_ e: QuickEntryParser.Entry) -> String {
        e.kind == .event ? String(localized: "Termin") : String(localized: "Erinnerung")
    }

    nonisolated static func symbol(_ e: QuickEntryParser.Entry) -> String {
        e.kind == .event ? "calendar" : "checkmark.circle"
    }

    private nonisolated static let weekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    /// „Fr 20.11.“ – Kurzform ohne Punkt wie in der Spezifikation, unabhängig von der Systemsprache.
    private nonisolated static func dayText(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.weekday, .day, .month], from: d)
        return String(format: "%@ %02d.%02d.", weekdays[((c.weekday ?? 1) - 1) % 7], c.day ?? 0, c.month ?? 0)
    }

    private nonisolated static func clock(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
