import Foundation

/// Schnelleingabe ↔ Kalli (SECURE-DESIGN G61, Erweiterung von G26): Gnotchi erkennt, **Kalli speichert** – Gnotchi
/// hat keinen Zugriff auf Kalender und Erinnerungen. Über dieselbe beidseitig geprüfte Verbindung `kalli.sock`
/// gehen `{"v":2,"create":{…}}` und `{"v":2,"undo":{"id":…}}`, zurück kommt `{"v":2,"result":{…}}`. Kalli prüft
/// jede Anfrage selbst noch einmal (`GnotchiQuickEntry` in Kalli). Rein und getestet. Nie Titel ins Protokoll.
enum QuickEntryWire {

    struct Result: Equatable, Sendable {
        let id: UUID?
        let ok: Bool
        let error: String?
    }

    /// So lange wartet Gnotchi auf Kallis Antwort. Kalli vor der Schnelleingabe antwortet gar nicht. Großzügig
    /// (code-audit 19.11.): Ein zu kurzes Limit meldete einen Fehler, obwohl Kalli gespeichert hatte → doppelter
    /// Eintrag beim zweiten Versuch. Kalli antwortet direkt nach Speichern und Nachlesen.
    nonisolated static let replyTimeout: TimeInterval = 4
    nonisolated static let maxTitle = 200
    nonisolated static let maxError = 200

    /// `nil`, wenn die Eingabe nicht gespeichert werden darf (leerer Titel, Termin ohne Beginn).
    nonisolated static func create(_ e: QuickEntryParser.Entry, id: UUID) -> [String: Any]? {
        let title = e.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title.count <= maxTitle else { return nil }
        if e.kind == .event, e.start == nil { return nil }
        let isEvent = e.kind == .event
        let allDay = e.start != nil && e.allDay
        func seconds(_ d: Date?) -> Any { d.map { $0.timeIntervalSince1970.rounded() } ?? NSNull() }
        return ["v": 2, "create": [
            "id": id.uuidString, "kind": e.kind.rawValue, "title": title, "start": seconds(e.start),
            "end": isEvent && !allDay ? seconds(e.end) : NSNull(), "allDay": allDay,
            "urgent": !isEvent && e.urgent,
        ] as [String: Any]]
    }

    nonisolated static func undo(id: UUID) -> [String: Any] {
        ["v": 2, "undo": ["id": id.uuidString]]
    }

    /// `{"v":2,"result":{"id":"…"|null,"ok":true|false,"error"?:"…"}}`, streng. `nil` = ungültig (Verbindung zu).
    nonisolated static func parseResult(_ obj: [String: Any]) -> Result? {
        guard obj.count == 2, let r = obj["result"] as? [String: Any],
              Set(r.keys).isSubset(of: ["id", "ok", "error"]), r.keys.contains("id"),
              let okValue = r["ok"] as? NSNumber, CFGetTypeID(okValue) == CFBooleanGetTypeID() else { return nil }
        let id: UUID?
        if r["id"] is NSNull {
            id = nil
        } else {
            guard let s = r["id"] as? String, let u = UUID(uuidString: s) else { return nil }
            id = u
        }
        var error: String?
        if let raw = r["error"] {
            guard let s = raw as? String else { return nil }
            let clean = LiveText.sanitize(s)
            error = clean.isEmpty ? "Kalli hat den Eintrag abgelehnt." : String(clean.prefix(maxError))
        }
        let ok = okValue.boolValue
        if ok, error != nil { return nil }   // widersprüchlich
        return Result(id: id, ok: ok, error: ok ? nil : (error ?? "Kalli hat den Eintrag abgelehnt."))
    }
}

/// Warum ein Eintrag nicht gespeichert wurde – Text für die Eingabezeile, die dann offen bleibt.
enum QuickEntryFailure: Error, Equatable, Sendable {
    case kalliNotRunning, noReply, invalid, kalli(String)

    var message: String {
        switch self {
        case .kalliNotRunning: "Kalli läuft nicht. Die Schnelleingabe speichert über Kalli."
        // Ehrlich: Ob gespeichert wurde, weiß Gnotchi ohne Antwort nicht.
        case .noReply: "Kalli antwortet nicht. Bitte in Apple Kalender prüfen, ob der Eintrag da ist, und Kalli aktualisieren."
        case .invalid: "Bitte einen Titel eingeben."
        case .kalli(let text): text
        }
    }
}
