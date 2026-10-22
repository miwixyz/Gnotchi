import Foundation

/// Mitteilungen und Anrufe (0.6.0, specs/2026-10-22-gnotchi-0.6.0-mitteilungen-anrufe.md, SECURE-DESIGN G28–G30):
/// das Nachrichtenformat zwischen Gnotchi und dem Hilfsprogramm „Gnotchi Mitteilungen“. Reine Teile, in **beiden**
/// Zielen übersetzt (gleiche Datei), damit Senden und Prüfen nie auseinanderlaufen.
///
/// Mitteilungstexte sind privat: nur über den beidseitig geprüften Socket `notify.sock`, nie protokolliert, nie
/// gespeichert. **Schema statt Vertrauen auf beiden Seiten:** unbekannte Schlüssel, falsche Typen oder zu lange
/// Kennungen → ganze Nachricht ungültig (Verbindung zu); Texte werden bereinigt und gekürzt.
enum NotifyWire {

    /// Größte Nachricht (Länge + JSON). Text höchstens 500 Zeichen à ≤ 4 Byte passt bequem.
    nonisolated static let maxFrame = 8192
    nonisolated static let maxID = 64
    nonisolated static let maxApp = 40
    nonisolated static let maxTitle = 120
    nonisolated static let maxBody = 500
    nonisolated static let maxActions = 6
    nonisolated static let maxActionName = 40
    nonisolated static let maxApps = 100
    nonisolated static let maxBundleID = 255
    /// Ungelesen-Zahlen (0.9.0, G33): höchstens so viele Apps, Zahl höchstens 9999.
    nonisolated static let maxBadges = 100
    nonisolated static let maxBadgeCount = 9999

    nonisolated static let helperBundleID = "dev.mwlr.gnotchi.mitteilungen"
    nonisolated static let gnotchiBundleID = "dev.mwlr.gnotchi"
    nonisolated static let socketName = "notify.sock"
    /// Feste Kennung, die macOS 27 einem eingehenden Anruf gibt (gemessen 22.10., iPhone-Anruf über Continuity).
    nonisolated static let callIdentifier = "FACETIME_NOTIFICATION"
    /// Aktion „Mitteilung öffnen“ (= `AXPress` am Banner), kein Name aus dem Banner.
    nonisolated static let openAction = "open"

    enum Kind: String, Sendable { case note, call }

    struct Note: Equatable, Sendable, Identifiable {
        let id: String
        let kind: Kind
        /// Angezeigter App-Name (Mitteilung) bzw. Anrufart („Telefon“, „FaceTime“).
        let app: String
        /// Kennung, falls eindeutig zugeordnet – nur fürs Symbol und den Filter.
        let bundle: String?
        let title: String
        let subtitle: String
        let body: String
        /// Von macOS gemeldete Knöpfe, schon ohne „Details“ und ohne Eingabe-Aktionen (G30).
        let actions: [String]
    }

    /// Ungelesen-Zahl einer App aus dem Dock-Abzeichen (0.9.0, G33) – nur Kennung + Zahl, nie Text.
    struct Badge: Equatable, Sendable {
        let bundle: String
        let count: Int
    }

    enum HelperMessage: Equatable, Sendable {
        case note(Note), gone(String), trust(Bool)
        case badges([Badge])
    }

    enum Command: Equatable, Sendable {
        case filter(apps: [String], calls: Bool, badges: Bool = false)
        case shown(String), release(String)
        /// `stopVoicemail` (0.9.0, G30 erweitert): nur mit „Ablehnen“ am Anruf. Das Hilfsprogramm drückt danach im selben
        /// Banner einmal „Live-Voicemail stoppen“ – Apples Fenster ist weg, der Anrufer landet auf der Mailbox.
        case act(id: String, action: String, stopVoicemail: Bool = false)
    }

    // MARK: Aktionen (G30)

    /// Nie anbieten: öffnen nur die Detailansicht oder ein Eingabefeld (Michael 22.10.: „ohne Antworten“).
    nonisolated static let hiddenActions: Set<String> = [
        "Details einblenden", "Show Details", "Antworten", "Reply", "Mit Nachricht ablehnen", "Decline with Message",
        "Respond with Text", "Live-Voicemail", "Live Voicemail",
    ]
    /// Schließen-Aktion – die Insel zeigt sie als ×, nicht als Knopf mit Text.
    nonisolated static let closeActions: Set<String> = ["Schließen", "Close"]
    nonisolated static let acceptActions: Set<String> = ["Annehmen", "Accept"]
    nonisolated static let declineActions: Set<String> = ["Ablehnen", "Decline"]
    /// Laufendes Gespräch (gemessen 22.10.: nach Annehmen wird dasselbe Banner zur Gesprächsleiste mit „Beenden, Weitere,
    /// Ziffernblock, Stumm, FaceTime-Video“). Angeboten wird nur Beenden.
    nonisolated static let endActions: Set<String> = ["Beenden", "End"]
    /// Nach „Ablehnen“ bei eingeschalteter Live-Voicemail (gemessen 22.10., 14:21/14:26): Das Banner bleibt mit
    /// „Live-Voicemail stoppen“ + „Annehmen“, der Anrufer spricht auf die Mailbox, der Mac liest mit. „Stoppen“ beendet
    /// nur das Mitlesen (Banner weg), der Anrufer bleibt auf der Mailbox. Englisch nicht gemessen.
    nonisolated static let voicemailStopActions: Set<String> = ["Live-Voicemail stoppen", "Stop Live Voicemail"]
    /// Beschriftungen, die ins Protokoll dürfen (feste macOS-Texte). Eigene Aktionen fremder Apps können Inhalte tragen
    /// (z. B. einen Namen) → dort nur „App-Aktion“ (G29, Review 22.10.).
    nonisolated static func logLabel(_ action: String) -> String {
        action == openAction || callActions.contains(action) || closeActions.contains(action) ? action : "App-Aktion"
    }

    /// Alles, was ein Anruf in der Notch auslösen darf (G30).
    nonisolated static let callActions = acceptActions.union(declineActions).union(endActions).union(voicemailStopActions)

    /// Anruf schon angenommen (Gesprächsleiste)?
    nonisolated static func isOngoing(_ call: Note) -> Bool {
        call.actions.contains { endActions.contains($0) }
    }

    /// Anrufer spricht auf die Mailbox, der Mac liest mit (nach „Ablehnen“)?
    nonisolated static func isScreening(_ call: Note) -> Bool {
        call.actions.contains { voicemailStopActions.contains($0) }
    }

    /// Folgeaktion „Live-Voicemail stoppen“ nach eigenem Ablehnen (G30 erweitert): drücken, weiter warten oder verfallen
    /// lassen. Rein, damit die Regel getestet ist – das Hilfsprogramm führt nur aus, was hier `.press` ergibt.
    enum FollowUp: Equatable { case press, wait, expire }

    nonisolated static let followUpWindow: TimeInterval = 2

    /// Darf Apples Banner-Fenster mit diesen Bannern weg (G28, fail-open)? Nur wenn jedes gerade in Gnotchi zu sehen ist.
    /// Ausnahme (0.9.0, Michael 22.10. „B“): Zeigt Gnotchi den Anruf in diesem Fenster, dürfen früher schon gezeigte
    /// Banner mit – nie solche, die Gnotchi nie gezeigt hat (nicht ausgewählt, nicht lesbar).
    nonisolated static func mayHideWindow(ids: [String], shown: Set<String>, everShown: Set<String>) -> Bool {
        let duringCall = shown.contains(callIdentifier) && ids.contains(callIdentifier)
        return !ids.isEmpty && ids.allSatisfy { shown.contains($0) || (duringCall && everShown.contains($0)) }
    }

    /// `pending` = eigenes Ablehnen mit `stopVoicemail` (Kennung, Zeitpunkt). Gedrückt wird nur am **selben** Banner, nur
    /// solange „Ablehnen“ dort verschwunden und „Live-Voicemail stoppen“ erschienen ist, nur innerhalb der Frist.
    nonisolated static func followUp(pending: (id: String, at: Date)?, id: String, actions: [String]?,
                                     now: Date) -> FollowUp? {
        guard let pending, pending.id == id else { return nil }
        guard now.timeIntervalSince(pending.at) <= followUpWindow, now >= pending.at else { return .expire }
        guard let actions else { return .wait }   // Banner gerade leer/weg
        let stop = actions.contains { voicemailStopActions.contains($0) }
        let decline = actions.contains { declineActions.contains($0) }
        return stop && !decline ? .press : .wait
    }

    /// Was das Hilfsprogramm überhaupt meldet: ohne versteckte Aktionen, ohne Doppelte, höchstens `maxActions`.
    nonisolated static func offeredActions(_ names: [String]) -> [String] {
        var out: [String] = []
        for raw in names {
            let name = clean(raw, max: maxActionName)
            guard !name.isEmpty, !hiddenActions.contains(name), !out.contains(name) else { continue }
            out.append(name)
            if out.count == maxActions { break }
        }
        return out
    }

    /// Knöpfe mit Text in der Insel: ohne Schließen (das ×), höchstens drei.
    nonisolated static func buttonActions(_ note: Note) -> [String] {
        Array(note.actions.filter { !closeActions.contains($0) }.prefix(3))
    }

    nonisolated static func closeAction(_ note: Note) -> String? {
        note.actions.first { closeActions.contains($0) }
    }

    // MARK: Rahmen wie Live-Text (4 Byte Länge + JSON), nur größer

    nonisolated static func nextFrame(_ buffer: inout Data) -> LiveText.Frame {
        LiveText.nextFrame(&buffer, max: maxFrame)
    }

    nonisolated static func frame(_ object: [String: Any]) -> Data? {
        LiveText.frame(object, max: maxFrame)
    }

    // MARK: Hilfsprogramm → Gnotchi

    nonisolated static func encode(_ m: HelperMessage) -> [String: Any] {
        switch m {
        case .note(let n):
            var note: [String: Any] = ["id": n.id, "kind": n.kind.rawValue, "app": n.app, "title": n.title,
                                       "subtitle": n.subtitle, "body": n.body, "actions": n.actions]
            if let b = n.bundle { note["bundle"] = b }
            return ["v": 1, "note": note]
        case .gone(let id): return ["v": 1, "gone": id]
        case .trust(let t): return ["v": 1, "trust": t]
        case .badges(let list): return ["v": 1, "badges": list.map { ["bundle": $0.bundle, "count": $0.count] }]
        }
    }

    /// `nil` = ungültig. Texte werden hier (Empfänger) noch einmal bereinigt und gekürzt.
    nonisolated static func parseHelperMessage(_ payload: Data) -> HelperMessage? {
        guard let obj = object(payload) else { return nil }
        if let raw = obj["note"] {
            guard obj.count == 2, let n = raw as? [String: Any] else { return nil }
            return parseNote(n).map(HelperMessage.note)
        }
        if let raw = obj["gone"] {
            guard obj.count == 2, let id = raw as? String, isValidID(id) else { return nil }
            return .gone(id)
        }
        if let raw = obj["trust"] {
            guard obj.count == 2, let t = bool(raw) else { return nil }
            return .trust(t)
        }
        if let raw = obj["badges"] {
            guard obj.count == 2 else { return nil }
            return parseBadges(raw).map(HelperMessage.badges)
        }
        return nil
    }

    /// Liste aus Kennung + ganzer Zahl 1…9999, keine Doppelten, keine weiteren Felder (G33).
    nonisolated static func parseBadges(_ raw: Any) -> [Badge]? {
        guard let list = raw as? [[String: Any]], list.count <= maxBadges else { return nil }
        var out: [Badge] = []
        for entry in list {
            guard entry.count == 2, let b = entry["bundle"] as? String, isValidBundleID(b),
                  let n = entry["count"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue == Double(n.intValue), (1...maxBadgeCount).contains(n.intValue),
                  !out.contains(where: { $0.bundle == b }) else { return nil }
            out.append(Badge(bundle: b, count: n.intValue))
        }
        return out
    }

    /// Dock-Abzeichen → Zahl (G33). Apps setzen ihren Abzeichen-Text selbst (`NSDockTile.badgeLabel`, beliebig) →
    /// unvertraut: nur reine Ziffern zählen (gekürzt auf `maxBadgeCount`), jedes andere nicht leere Abzeichen
    /// („•“, „!“, Text) = 1. Leer → nil (nichts ungelesen).
    nonisolated static func badgeCount(_ label: String) -> Int? {
        let t = label.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        guard t.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return 1 }
        let digits = t.drop { $0 == "0" }
        guard !digits.isEmpty else { return nil }   // „0“
        return digits.count > 4 ? maxBadgeCount : min(Int(digits) ?? maxBadgeCount, maxBadgeCount)
    }

    nonisolated private static let noteKeys: Set<String> = ["id", "kind", "app", "bundle", "title", "subtitle", "body",
                                                            "actions"]

    nonisolated static func parseNote(_ n: [String: Any]) -> Note? {
        guard Set(n.keys).isSubset(of: noteKeys),
              let id = n["id"] as? String, isValidID(id),
              let kindRaw = n["kind"] as? String, let kind = Kind(rawValue: kindRaw),
              let app = n["app"] as? String, let title = n["title"] as? String,
              let subtitle = n["subtitle"] as? String, let body = n["body"] as? String,
              let actions = n["actions"] as? [String], actions.count <= maxActions else { return nil }
        var bundle: String?
        if let b = n["bundle"] {
            guard let s = b as? String, isValidBundleID(s) else { return nil }
            bundle = s
        }
        guard actions.allSatisfy({ !$0.isEmpty && $0.count <= maxActionName }) else { return nil }
        return Note(id: id, kind: kind, app: clean(app, max: maxApp), bundle: bundle, title: clean(title, max: maxTitle),
                    subtitle: clean(subtitle, max: maxTitle), body: clean(body, max: maxBody),
                    actions: offeredActions(actions))
    }

    // MARK: Gnotchi → Hilfsprogramm

    nonisolated static func encode(_ c: Command) -> [String: Any] {
        switch c {
        case .filter(let apps, let calls, let badges): ["v": 1, "apps": apps, "calls": calls, "badges": badges]
        case .shown(let id): ["v": 1, "shown": id]
        case .release(let id): ["v": 1, "release": id]
        case .act(let id, let action, let stop):
            stop ? ["v": 1, "act": id, "action": action, "then": "stopVoicemail"] : ["v": 1, "act": id, "action": action]
        }
    }

    nonisolated static func parseCommand(_ payload: Data) -> Command? {
        guard let obj = object(payload) else { return nil }
        if let raw = obj["apps"] {
            guard obj.count == 4, let apps = raw as? [String], apps.count <= maxApps, apps.allSatisfy(isValidBundleID),
                  let calls = obj["calls"].flatMap(bool), let badges = obj["badges"].flatMap(bool) else { return nil }
            return .filter(apps: apps, calls: calls, badges: badges)
        }
        if let raw = obj["shown"] {
            guard obj.count == 2, let id = raw as? String, isValidID(id) else { return nil }
            return .shown(id)
        }
        if let raw = obj["release"] {
            guard obj.count == 2, let id = raw as? String, isValidID(id) else { return nil }
            return .release(id)
        }
        if obj["act"] != nil { return parseAct(obj) }
        return nil
    }

    nonisolated private static func parseAct(_ obj: [String: Any]) -> Command? {
        guard let id = obj["act"] as? String, isValidID(id),
              let action = obj["action"] as? String, !action.isEmpty, action.count <= maxActionName else { return nil }
        if obj.count == 3 { return .act(id: id, action: action) }
        // Folgeaktion nur als einziger Zusatz, nur genau dieser Wert, nur mit Ablehnen am Anruf (G30 erweitert).
        guard obj.count == 4, obj["then"] as? String == "stopVoicemail", id == callIdentifier,
              declineActions.contains(action) else { return nil }
        return .act(id: id, action: action, stopVoicemail: true)
    }

    nonisolated static func isAck(_ payload: Data) -> Bool {
        guard let obj = object(payload), obj.count == 2 else { return false }
        return obj["ok"].flatMap(bool) == true
    }

    // MARK: Prüfungen (getestet)

    /// UUID von macOS oder `FACETIME_NOTIFICATION`: nur ASCII-Buchstaben, Ziffern, `-`, `_`.
    nonisolated static func isValidID(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= maxID && s.utf8.allSatisfy { c in
            (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2D || c == 0x5F
        }
    }

    nonisolated static func isValidBundleID(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= maxBundleID && s.utf8.allSatisfy { c in
            (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2D || c == 0x2E
        }
    }

    /// Bereinigt wie Live-Text (G21: Steuer-/Format-/Richtungszeichen raus) und auf `max` Zeichen gekürzt.
    nonisolated static func clean(_ s: String, max: Int) -> String {
        // Erst grob kürzen (Review 22.10.): sonst liefe die Bereinigung über einen beliebig langen Banner-Text.
        let c = LiveText.sanitize(String(s.prefix(max * 4)))
        guard c.count > max else { return c }
        return String(c.prefix(max - 1)) + "…"
    }

    /// JSON-Objekt mit `v` = Zahl 1 (kein Wahrheitswert), sonst nil.
    nonisolated private static func object(_ payload: Data) -> [String: Any]? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let v = obj["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(),
              v.intValue == 1, v.doubleValue == 1 else { return nil }
        return obj
    }

    /// Echter Wahrheitswert (keine Zahl 0/1).
    nonisolated private static func bool(_ value: Any) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }
}
