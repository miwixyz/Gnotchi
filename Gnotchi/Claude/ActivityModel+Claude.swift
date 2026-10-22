import Foundation

/// Eine Claude-Code-Sitzung in der Notch (0.9.0 Code & KI, G34). Texte nur bereinigt und gekürzt (ClaudeWire), nie
/// gespeichert oder protokolliert.
struct ClaudeSession: Equatable, Sendable, Identifiable {
    enum State: Equatable, Sendable { case working, waiting, done }

    let id: String
    var project: String
    var state: State
    var tool = ""
    var detail = ""
    var text = ""
    var app: String?
    var pid: Int32?
    var updated: Date

    /// Statuszeile (feste Texte + Werkzeug/Kurzfassung).
    var statusLine: String {
        switch state {
        case .working: "arbeitet …"
        case .waiting: "wartet auf Erlaubnis: " + [tool, detail].filter { !$0.isEmpty }.joined(separator: " – ")
        case .done: "fertig"
        }
    }
}

extension ActivityModel {

    nonisolated static let maxClaudeSessions = 10
    /// Fertige und stumme Sitzungen verschwinden nach 30 Minuten.
    nonisolated static let claudeStale: TimeInterval = 30 * 60

    /// Läuft oder wartet eine Sitzung? Dann ist „Claude“ eine Live-Aktivität (Rotation, Leiste).
    var claudeActive: Bool { claudeSessions.contains { $0.state != .done } }

    /// Für die kleine Insel: wartende vor arbeitenden.
    var claudeHeadline: ClaudeSession? {
        claudeSessions.first { $0.state == .waiting } ?? claudeSessions.first { $0.state == .working }
    }

    /// Für die große Insel: wartende, arbeitende, dann fertige – je die neueste zuerst.
    var claudeOrdered: [ClaudeSession] {
        let rank: (ClaudeSession.State) -> Int = { $0 == .waiting ? 0 : ($0 == .working ? 1 : 2) }
        return claudeSessions.enumerated().sorted { a, b in
            rank(a.element.state) != rank(b.element.state) ? rank(a.element.state) < rank(b.element.state) : a.offset < b.offset
        }.map(\.element)
    }

    func receiveClaude(_ m: ClaudeWire.Message, now: Date = Date()) {
        if m.event == .end {
            claudeSessions.removeAll { $0.id == m.session }
            return
        }
        var s = claudeSessions.first { $0.id == m.session }
            ?? ClaudeSession(id: m.session, project: m.project, state: .working, updated: now)
        let wasDone = s.state == .done && claudeSessions.contains { $0.id == m.session }
        s.project = m.project
        s.updated = now
        if let app = m.app { s.app = app; s.pid = m.pid }
        switch m.event {
        case .prompt:
            s.state = .working
            s.text = ""
        case .permission:
            s.state = .waiting
            s.tool = m.tool
            s.detail = m.detail
        case .tool:
            // Nach einer fertigen Antwort zählt ein verspätetes Werkzeug-Ereignis nicht als „arbeitet“.
            if !wasDone { s.state = .working }
        case .stop:
            s.state = .done
            s.text = m.text
            post(Notice(symbol: "sparkles", title: "Claude fertig · \(s.project)",
                        subtitle: m.text.isEmpty ? "Antwort bereit" : m.text))
        case .end:
            break
        }
        claudeSessions.removeAll { $0.id == m.session }
        claudeSessions.insert(s, at: 0)
        if claudeSessions.count > Self.maxClaudeSessions { claudeSessions.removeLast() }
    }

    /// Alte Sitzungen raus (fertig oder ohne Ereignis seit `claudeStale`).
    func pruneClaude(now: Date = Date()) {
        let kept = claudeSessions.filter { now.timeIntervalSince($0.updated) < Self.claudeStale }
        if kept != claudeSessions { claudeSessions = kept }
    }

    func clearClaude() {
        if !claudeSessions.isEmpty { claudeSessions = [] }
    }
}
