import XCTest
@testable import Gnotchi

// SYNTHETISCH – erfundene Sitzungen, Pfade und Einstellungen (Datenschutz-Gate, SECURE-DESIGN G16)

/// 0.9.0 Code & KI (G34/G35): Hook-Eingabe → Nachricht (datensparsam), Schema, Sitzungen, Einstellungsdatei.
@MainActor
final class ClaudeTests: XCTestCase {

    private let sid = "0a1b2c3d-1111-2222-3333-444455556666"

    private func payload(_ obj: Any) -> Data { (try? JSONSerialization.data(withJSONObject: obj)) ?? Data() }

    // MARK: Hook-Eingabe (G34)

    func testHookInputKeepsOnlyAllowedFields() throws {
        let input: [String: Any] = [
            "hook_event_name": "PermissionRequest", "session_id": sid, "cwd": "/Users/beispiel/Projekte/Mein-Projekt",
            "transcript_path": "/Users/beispiel/.claude/projects/x.jsonl", "permission_mode": "default",
            "tool_name": "Bash", "tool_input": ["command": "git push origin main\n&& echo fertig", "description": "geheim"],
        ]
        let m = try XCTUnwrap(ClaudeWire.message(fromHookInput: input))
        XCTAssertEqual(m.event, .permission)
        XCTAssertEqual(m.project, "Mein-Projekt", "nur der letzte Pfadteil")
        XCTAssertEqual(m.tool, "Bash")
        XCTAssertEqual(m.detail, "git push origin main && echo fertig")
        let wire = String(data: payload(ClaudeWire.encode(m)), encoding: .utf8) ?? ""
        XCTAssertFalse(wire.contains("transcript"), "nie den Verlaufspfad")
        XCTAssertFalse(wire.contains("/Users/"), "nie ganze Pfade")
        XCTAssertFalse(wire.contains("geheim"), "keine weiteren Werkzeugfelder")
    }

    func testFileToolsOnlyFileName() {
        XCTAssertEqual(ClaudeWire.detail(tool: "Write", input: ["file_path": "/Users/beispiel/geheim/notiz.md",
                                                                  "content": "Inhalt"]), "notiz.md")
        XCTAssertEqual(ClaudeWire.detail(tool: "WebFetch", input: ["url": "https://example.com"]), "")
    }

    func testStopTextShortenedWithoutMarkdown() throws {
        let long = "## Ergebnis\n\n- **Punkt eins** erledigt\n" + String(repeating: "x", count: 1000)
        let m = try XCTUnwrap(ClaudeWire.message(fromHookInput: ["hook_event_name": "Stop", "session_id": sid,
                                                                 "cwd": "/tmp/a", "last_assistant_message": long]))
        XCTAssertTrue(m.text.hasPrefix("Ergebnis **Punkt eins** erledigt") || m.text.hasPrefix("Ergebnis Punkt eins"),
                      m.text)
        XCTAssertLessThanOrEqual(m.text.count, ClaudeWire.maxText)
    }

    func testPromptTextNeverSent() throws {
        let m = try XCTUnwrap(ClaudeWire.message(fromHookInput: ["hook_event_name": "UserPromptSubmit", "session_id": sid,
                                                                 "cwd": "/tmp/a", "prompt": "Mein geheimer Auftrag"]))
        XCTAssertEqual(m.text, "")
        XCTAssertNil(ClaudeWire.message(fromHookInput: ["hook_event_name": "PreToolUse", "session_id": sid]),
                     "andere Ereignisse nicht")
        XCTAssertNil(ClaudeWire.message(fromHookInput: ["hook_event_name": "Stop", "session_id": "../etc"]))
    }

    // MARK: Schema (beide Seiten)

    func testRoundTripAndInvalid() {
        var m = ClaudeWire.Message(session: sid, event: .stop, project: "P", tool: "", detail: "", text: "fertig")
        m.app = "com.example.terminal"
        m.pid = 4242
        XCTAssertEqual(ClaudeWire.parse(payload(ClaudeWire.encode(m))), m)
        let base: [String: Any] = ["session": sid, "event": "stop", "project": "P", "tool": "", "detail": "", "text": ""]
        func with(_ k: String, _ v: Any) -> Data { var c = base; c[k] = v; return payload(["v": 1, "claude": c]) }
        XCTAssertNil(ClaudeWire.parse(with("event", "decide")), "unbekanntes Ereignis")
        XCTAssertNil(ClaudeWire.parse(with("session", "a b")), "Kennung")
        XCTAssertNil(ClaudeWire.parse(with("pid", 1)), "PID 1 nie")
        XCTAssertNil(ClaudeWire.parse(with("pid", true)), "Wahrheitswert")
        XCTAssertNil(ClaudeWire.parse(with("app", "bad id")), "App-Kennung")
        XCTAssertNil(ClaudeWire.parse(with("decision", "allow")), "Zusatzschlüssel")
        XCTAssertNil(ClaudeWire.parse(payload(["v": true, "claude": base])), "v als Bool")
    }

    // MARK: Sitzungen

    private func msg(_ e: ClaudeWire.Event, _ s: String? = nil, text: String = "") -> ClaudeWire.Message {
        ClaudeWire.Message(session: s ?? sid, event: e, project: "Projekt", tool: e == .permission ? "Bash" : "",
                           detail: e == .permission ? "git push" : "", text: text)
    }

    func testSessionStates() {
        let m = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(m.claudeActive)
        m.receiveClaude(msg(.prompt))
        XCTAssertTrue(m.claudeActive)
        XCTAssertTrue(m.chipItems.contains(.claude))
        m.receiveClaude(msg(.permission))
        XCTAssertEqual(m.claudeHeadline?.statusLine, "wartet auf Erlaubnis: Bash – git push")
        m.receiveClaude(msg(.tool))
        XCTAssertEqual(m.claudeSessions.first?.state, .working)
        m.receiveClaude(msg(.stop, text: "Alles erledigt"))
        XCTAssertFalse(m.claudeActive)
        XCTAssertFalse(m.rotationItems.contains(.claude), "kleine Insel: nur laufende")
        XCTAssertTrue(m.chipItems.contains(.claude), "groß: fertige bleiben anklickbar")
        XCTAssertEqual(m.notice?.title, "Claude fertig · Projekt")
        XCTAssertEqual(m.notice?.subtitle, "Alles erledigt")
        m.receiveClaude(msg(.tool))
        XCTAssertEqual(m.claudeSessions.first?.state, .done, "verspätetes Werkzeug-Ereignis weckt nicht auf")
        m.receiveClaude(msg(.end))
        XCTAssertTrue(m.claudeSessions.isEmpty)
    }

    func testOrderingAndPrune() {
        let m = ActivityModel(media: NowPlayingModel())
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        m.receiveClaude(msg(.stop, "s-done"), now: t0)
        m.receiveClaude(msg(.prompt, "s-work"), now: t0)
        m.receiveClaude(msg(.permission, "s-wait"), now: t0)
        XCTAssertEqual(m.claudeOrdered.map(\.id), ["s-wait", "s-work", "s-done"])
        m.pruneClaude(now: t0 + ActivityModel.claudeStale + 1)
        XCTAssertTrue(m.claudeSessions.isEmpty)
        for i in 0...ActivityModel.maxClaudeSessions { m.receiveClaude(msg(.prompt, "s\(i)")) }
        XCTAssertEqual(m.claudeSessions.count, ActivityModel.maxClaudeSessions)
    }

    // MARK: Einstellungsdatei (G35)

    private let hook = "/Applications/Gnotchi.app/Contents/Helpers/Gnotchi Claude.app/Contents/MacOS/Gnotchi Claude"

    /// Aufbau wie eine echte Datei (Reihenfolge von Hand, Umlaute, Escapes, Zahlen, leere Felder) – erfunden.
    private let sample = """
    {
      "permissions": {
        "allow": [
          "Bash(git status:*)",
          "Read(/Users/beispiel/**)"
        ],
        "deny": []
      },
      "model": "beispiel",
      "hooks": {
        "Stop": [
          {
            "matcher": "",
            "hooks": [
              {
                "type": "command",
                "command": "echo \\"fertig\\" | tee -a ~/log.txt\\n",
                "timeout": 30
              }
            ]
          }
        ],
        "SessionStart": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "bash ~/Skripte/Übersicht.sh \\\\ \\u0001"
              }
            ]
          }
        ]
      },
      "zahl": 1.50,
      "leer": {},
      "theme": null,
      "an": true
    }

    """

    func testRoundTripIsByteIdentical() throws {
        XCTAssertEqual(try ClaudeSettings.updated(sample, hookPath: nil), sample)
    }

    func testAddKeepsOthersAndRemoveRestoresOriginal() throws {
        let added = try ClaudeSettings.updated(sample, hookPath: hook)
        XCTAssertTrue(ClaudeSettings.isInstalled(added, hookPath: hook))
        XCTAssertTrue(added.contains("Übersicht.sh"), "fremde Hooks bleiben")
        XCTAssertTrue(added.contains("\"async\": true"))
        XCTAssertEqual(try ClaudeSettings.updated(added, hookPath: hook), added, "zweimal = einmal")
        XCTAssertEqual(try ClaudeSettings.updated(added, hookPath: nil), sample, "aus = byte-gleich wie vorher")
        let moved = try ClaudeSettings.updated(added, hookPath: "/tmp/x/Gnotchi.app/Contents/Helpers/Gnotchi Claude.app/a")
        XCTAssertFalse(moved.contains("/Applications/Gnotchi.app"), "alter Pfad ersetzt")
        XCTAssertEqual(try ClaudeSettings.updated(moved, hookPath: nil), sample)
    }

    func testRefusesUnfamiliarFormat() {
        XCTAssertThrowsError(try ClaudeSettings.updated("{\"a\":1}", hookPath: hook)) {
            XCTAssertEqual($0 as? ClaudeSettings.Failure, .notIdentical, "anderes Format → nichts schreiben")
        }
        XCTAssertThrowsError(try ClaudeSettings.updated("{\n  \"a\": \"\\/\"\n}", hookPath: hook), "\\/ käme anders zurück")
        XCTAssertThrowsError(try ClaudeSettings.updated("[]", hookPath: hook))
        XCTAssertThrowsError(try ClaudeSettings.updated("{ kaputt", hookPath: hook))
    }

    func testCommandRejectsQuoteAndForeignPath() {
        XCTAssertNil(ClaudeSettings.command(hookPath: "/tmp/it's/Gnotchi Claude.app/x"))
        XCTAssertNil(ClaudeSettings.command(hookPath: "/usr/local/bin/anderes"))
        XCTAssertEqual(ClaudeSettings.command(hookPath: hook), "test -x '\(hook)' && '\(hook)' || true")
    }

    func testApplyWritesBackupAndKeepsPermissions() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        try sample.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try ClaudeSettings.apply(fileURL: file, hookPath: hook)
        XCTAssertTrue(ClaudeSettings.isInstalled(try String(contentsOf: file, encoding: .utf8), hookPath: hook))
        let backup = dir.appendingPathComponent("settings.json.gnotchi-backup")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), sample)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int, 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".") }
        XCTAssertTrue(leftovers.isEmpty, "keine temporären Dateien")
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        try ClaudeSettings.apply(fileURL: file, hookPath: nil)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), sample)
        // Link → verweigert
        let link = dir.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try ClaudeSettings.apply(fileURL: link, hookPath: hook))
    }
}
