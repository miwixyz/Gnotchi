import Foundation

/// Code & KI (0.9.0, specs/2026-10-22-gnotchi-0.9.0-code-ki.md, SECURE-DESIGN G34): Nachrichtenformat zwischen dem
/// Hook-Programm „Gnotchi Claude“ und Gnotchi. Reine Teile, in **beiden** Zielen übersetzt (gleiche Datei).
///
/// Datensparsam: aus der Hook-Eingabe von Claude Code bleiben nur Sitzungs-Kennung, Ereignis, Projektname, App,
/// Werkzeug, Kurzfassung und gekürzte Antwort. Nie Prompt-Text, `transcript_path`, Dateiinhalte. Nie protokolliert.
enum ClaudeWire {

    nonisolated static let socketName = "claude.sock"
    nonisolated static let hookBundleID = "dev.mwlr.gnotchi.claude"
    /// Erkennungszeichen der eigenen Hook-Einträge in `~/.claude/settings.json` (G35).
    nonisolated static let hookMarker = "Gnotchi Claude.app"
    nonisolated static let maxFrame = 4096
    nonisolated static let maxSession = 64
    nonisolated static let maxProject = 60
    nonisolated static let maxTool = 60
    nonisolated static let maxDetail = 120
    nonisolated static let maxText = 300
    /// Größte Hook-Eingabe, die das Hook-Programm liest (Write-Werkzeug bringt ganze Dateien mit).
    nonisolated static let maxInput = 4 * 1024 * 1024

    enum Event: String, Sendable, CaseIterable {
        case prompt, permission, tool, stop, end
    }

    struct Message: Equatable, Sendable {
        let session: String
        let event: Event
        let project: String
        /// Kennung + PID des Programms, in dem die Sitzung läuft (Klick holt es nach vorn).
        var app: String?
        var pid: Int32?
        var tool: String = ""
        var detail: String = ""
        var text: String = ""
    }

    // MARK: Hook-Eingabe → Nachricht (im Hook-Programm, getestet)

    /// Claude-Code-Ereignisname → eigenes Ereignis. Andere Ereignisse → nil (nichts senden).
    nonisolated static func event(forHook name: String) -> Event? {
        switch name {
        case "UserPromptSubmit": .prompt
        case "PermissionRequest": .permission
        case "PostToolUse": .tool
        case "Stop": .stop
        case "SessionEnd": .end
        default: nil
        }
    }

    /// Nur die erlaubten Felder, gekürzt und bereinigt. `nil` = nicht senden.
    nonisolated static func message(fromHookInput obj: [String: Any]) -> Message? {
        guard let name = obj["hook_event_name"] as? String, let event = event(forHook: name),
              let session = obj["session_id"] as? String, isValidSession(session) else { return nil }
        let cwd = obj["cwd"] as? String ?? ""
        var m = Message(session: session, event: event, project: projectName(cwd))
        switch event {
        case .permission:
            let tool = obj["tool_name"] as? String ?? ""
            m.tool = LiveText.sanitize(String(tool.prefix(maxTool)))
            m.detail = detail(tool: tool, input: obj["tool_input"] as? [String: Any] ?? [:])
        case .stop:
            m.text = shortText(obj["last_assistant_message"] as? String ?? "")
        case .prompt, .tool, .end:
            break
        }
        return m
    }

    /// Letzter Pfadteil (Projektordner), nie der ganze Pfad.
    nonisolated static func projectName(_ cwd: String) -> String {
        let last = (cwd as NSString).lastPathComponent
        return clean(last.isEmpty || last == "/" ? "Claude" : last, max: maxProject)
    }

    /// Kurzfassung je Werkzeug: Bash → Befehl (gekürzt); Datei-Werkzeuge → nur Dateiname; sonst nichts.
    nonisolated static func detail(tool: String, input: [String: Any]) -> String {
        if tool == "Bash", let cmd = input["command"] as? String {
            return clean(cmd.replacingOccurrences(of: "\n", with: " "), max: maxDetail)
        }
        for key in ["file_path", "notebook_path", "path"] {
            if let p = input[key] as? String, !p.isEmpty { return clean((p as NSString).lastPathComponent, max: maxDetail) }
        }
        return ""
    }

    /// Erste Zeilen der Antwort ohne Markdown-Zeichen am Zeilenanfang, höchstens `maxText` Zeichen.
    nonisolated static func shortText(_ s: String) -> String {
        let lines = s.prefix(maxText * 4).split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.drop { "#*>-`|".contains($0) || $0 == " " } }
            .map(String.init)
            .filter { !$0.isEmpty }
        return clean(lines.prefix(3).joined(separator: " "), max: maxText)
    }

    // MARK: Rahmen + Schema (beide Seiten)

    nonisolated static func encode(_ m: Message) -> [String: Any] {
        var c: [String: Any] = ["session": m.session, "event": m.event.rawValue, "project": m.project,
                                "tool": m.tool, "detail": m.detail, "text": m.text]
        if let a = m.app { c["app"] = a }
        if let p = m.pid { c["pid"] = Int(p) }
        return ["v": 1, "claude": c]
    }

    nonisolated private static let keys: Set<String> = ["session", "event", "project", "app", "pid", "tool", "detail", "text"]

    /// `nil` = ungültig (Verbindung zu). Texte werden hier noch einmal bereinigt und gekürzt.
    nonisolated static func parse(_ payload: Data) -> Message? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], obj.count == 2,
              let v = obj["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(), v.intValue == 1, v.doubleValue == 1,
              let c = obj["claude"] as? [String: Any], Set(c.keys).isSubset(of: keys),
              let session = c["session"] as? String, isValidSession(session),
              let ev = c["event"] as? String, let event = Event(rawValue: ev),
              let project = c["project"] as? String, let tool = c["tool"] as? String,
              let detail = c["detail"] as? String, let text = c["text"] as? String else { return nil }
        var m = Message(session: session, event: event, project: clean(project, max: maxProject),
                        tool: clean(tool, max: maxTool), detail: clean(detail, max: maxDetail), text: clean(text, max: maxText))
        if let a = c["app"] {
            guard let s = a as? String, NotifyWire.isValidBundleID(s) else { return nil }
            m.app = s
        }
        if let p = c["pid"] {
            guard let n = p as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == Double(n.int32Value),
                  n.int32Value > 1 else { return nil }
            m.pid = n.int32Value
        }
        return m
    }

    /// UUID-Zeichen: Buchstaben, Ziffern, `-`, höchstens 64.
    nonisolated static func isValidSession(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= maxSession && s.utf8.allSatisfy { c in
            (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2D
        }
    }

    nonisolated static func clean(_ s: String, max: Int) -> String { NotifyWire.clean(s, max: max) }
}
