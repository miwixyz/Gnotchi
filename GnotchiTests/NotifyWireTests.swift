import XCTest
@testable import Gnotchi

// SYNTHETISCH – erfundene Mitteilungen, keine echten Inhalte (Datenschutz-Gate, SECURE-DESIGN G16)

/// 0.6.0 Nachrichtenformat zwischen Gnotchi und „Gnotchi Mitteilungen“ (SECURE-DESIGN G29/G30): Schema auf beiden
/// Seiten, Bereinigung, Aktionen.
final class NotifyWireTests: XCTestCase {

    private func payload(_ obj: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    private func noteDict(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var n: [String: Any] = ["id": "79EE4F3C-9E41-43A2-A99E-FBF53F5E4E7B", "kind": "note", "app": "Beispiel-App",
                                "title": "Testtitel", "subtitle": "", "body": "Erfundener Text",
                                "actions": ["Anzeigen", "Schließen"]]
        for (k, v) in overrides { n[k] = v }
        return n
    }

    // MARK: Hilfsprogramm → Gnotchi

    func testValidNoteParses() throws {
        let m = NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["bundle": "com.example.app"])]))
        guard case .note(let n)? = m else { return XCTFail("keine Mitteilung") }
        XCTAssertEqual(n.kind, .note)
        XCTAssertEqual(n.bundle, "com.example.app")
        XCTAssertEqual(n.title, "Testtitel")
        XCTAssertEqual(n.actions, ["Anzeigen", "Schließen"])
    }

    func testRoundTripThroughEncode() {
        let n = NotifyWire.Note(id: "FACETIME_NOTIFICATION", kind: .call, app: "Telefon", bundle: nil, title: "Erika Muster",
                                subtitle: "", body: "", actions: ["Annehmen", "Ablehnen"])
        let data = payload(NotifyWire.encode(.note(n)))
        XCTAssertEqual(NotifyWire.parseHelperMessage(data), .note(n))
        XCTAssertEqual(NotifyWire.parseHelperMessage(payload(NotifyWire.encode(.gone("abc-1")))), .gone("abc-1"))
        XCTAssertEqual(NotifyWire.parseHelperMessage(payload(NotifyWire.encode(.trust(false)))), .trust(false))
    }

    func testUnknownKeysAndWrongTypesAreInvalid() {
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["extra": 1])])), "unbekanntes Feld")
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(), "x": 1])), "Zusatzschlüssel oben")
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": true, "note": noteDict()])), "v als Wahrheitswert")
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 2, "note": noteDict()])), "falsche Version")
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["kind": "alarm"])])), "unbekannte Art")
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["title": 5])])), "Titel keine Zeichenkette")
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "trust": 1])), "trust als Zahl")
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1])), "leer")
    }

    func testIDsAndBundleIDsAreStrict() {
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["id": "../etc"])])))
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["id": String(repeating: "a", count: 65)])])))
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["bundle": "com.example/../x"])])))
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "gone": "a b"])))
        XCTAssertTrue(NotifyWire.isValidID("FACETIME_NOTIFICATION"))
        XCTAssertTrue(NotifyWire.isValidID("E1E7E0D3-4AC9-47A2-A48B-F774E90D0C99"))
    }

    func testTextsAreSanitizedAndTruncated() throws {
        let long = String(repeating: "x", count: 900)
        let m = NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["title": "Böse\u{202E}gnirts", "body": long,
                                                                                 "app": "App\nmit\tUmbruch"])]))
        guard case .note(let n)? = m else { return XCTFail("keine Mitteilung") }
        XCTAssertEqual(n.title, "Bösegnirts", "Richtungszeichen raus")
        XCTAssertEqual(n.app, "App mit Umbruch")
        XCTAssertEqual(n.body.count, NotifyWire.maxBody)
        XCTAssertTrue(n.body.hasSuffix("…"))
    }

    func testTooManyOrTooLongActionsAreInvalid() {
        let seven = (1...7).map { "A\($0)" }
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["actions": seven])])))
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["actions": [String(repeating: "a", count: 41)]])])))
        XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["actions": [""]])])))
    }

    // MARK: Aktionen (G30)

    func testInputAndDetailActionsAreNeverOffered() {
        XCTAssertEqual(NotifyWire.offeredActions(["Details einblenden", "Löschen", "Als gelesen markieren", "Antworten", "Schließen"]),
                       ["Löschen", "Als gelesen markieren", "Schließen"])
        XCTAssertEqual(NotifyWire.offeredActions(["Reply", "Show Details", "Close", "Close"]), ["Close"], "ohne Doppelte")
        // Auch wenn ein (gefälschtes) Hilfsprogramm sie schickt: Gnotchi filtert beim Lesen noch einmal.
        let m = NotifyWire.parseHelperMessage(payload(["v": 1, "note": noteDict(["actions": ["Antworten", "Erledigt"]])]))
        guard case .note(let n)? = m else { return XCTFail("keine Mitteilung") }
        XCTAssertEqual(n.actions, ["Erledigt"])
    }

    func testButtonsWithoutCloseAtMostThree() {
        let n = NotifyWire.Note(id: "x", kind: .note, app: "A", bundle: nil, title: "", subtitle: "", body: "",
                                actions: ["Erledigt", "Morgen erinnern", "Um 15:00 erinnern", "In einer Stunde erinnern", "Schließen"])
        XCTAssertEqual(NotifyWire.buttonActions(n), ["Erledigt", "Morgen erinnern", "Um 15:00 erinnern"])
        XCTAssertEqual(NotifyWire.closeAction(n), "Schließen")
    }

    // MARK: Gnotchi → Hilfsprogramm

    func testCommandsRoundTrip() {
        let all: [NotifyWire.Command] = [.filter(apps: ["com.apple.MobileSMS"], calls: true), .shown("abc"), .release("abc"),
                                         .act(id: "abc", action: "Erledigt"), .act(id: "FACETIME_NOTIFICATION", action: "Annehmen")]
        for c in all { XCTAssertEqual(NotifyWire.parseCommand(payload(NotifyWire.encode(c))), c) }
    }

    func testInvalidCommands() {
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "apps": ["com.ok"], "calls": 1])), "calls als Zahl")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "apps": ["bad id"], "calls": true])), "ungültige Kennung")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "apps": [], "calls": true, "more": 1])), "Zusatzschlüssel")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "act": "abc"])), "Aktion fehlt")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "act": "abc", "action": ""])), "leere Aktion")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "run": "/bin/sh"])), "unbekannter Befehl")
    }

    func testAck() {
        XCTAssertTrue(NotifyWire.isAck(payload(["v": 1, "ok": true])))
        XCTAssertFalse(NotifyWire.isAck(payload(["v": 1, "ok": 1])))
        XCTAssertFalse(NotifyWire.isAck(payload(["v": 1, "ok": false])))
    }
}
