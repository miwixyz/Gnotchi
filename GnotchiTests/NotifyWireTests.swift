import XCTest

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
                                         .filter(apps: [], calls: false, badges: true),
                                         .act(id: "abc", action: "Erledigt"), .act(id: "FACETIME_NOTIFICATION", action: "Annehmen"),
                                         .act(id: "FACETIME_NOTIFICATION", action: "Ablehnen", stopVoicemail: true)]
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

    // MARK: 0.12.0 – Einfügen (G42): nur „einfügen“, kein Inhalt, keine Taste

    func testPasteRoundTrip() {
        XCTAssertEqual(NotifyWire.parseCommand(payload(NotifyWire.encode(.paste))), .paste)
        XCTAssertEqual(NotifyWire.encode(.paste).count, 2, "nur v + paste")
    }

    func testPasteRejectsAnythingElse() {
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "paste": false])), "false")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "paste": 1])), "Zahl statt Wahrheitswert")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "paste": "rm -rf ~"])), "Text")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "paste": true, "text": "x"])), "Zusatz: Text")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "paste": true, "key": 36])), "Zusatz: Taste")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 2, "paste": true])), "falsche Version")
    }

    func testAck() {
        XCTAssertTrue(NotifyWire.isAck(payload(["v": 1, "ok": true])))
        XCTAssertFalse(NotifyWire.isAck(payload(["v": 1, "ok": 1])))
        XCTAssertFalse(NotifyWire.isAck(payload(["v": 1, "ok": false])))
    }

    // MARK: 0.9.0 – Folgeaktion „Live-Voicemail stoppen“ (G30 erweitert)

    func testStopVoicemailOnlyWithDeclineOnCall() {
        let call = NotifyWire.callIdentifier
        XCTAssertEqual(NotifyWire.parseCommand(payload(["v": 1, "act": call, "action": "Ablehnen", "then": "stopVoicemail"])),
                       .act(id: call, action: "Ablehnen", stopVoicemail: true))
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "act": call, "action": "Annehmen", "then": "stopVoicemail"])),
                     "nie nach Annehmen")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "act": "abc", "action": "Ablehnen", "then": "stopVoicemail"])),
                     "nur am Anruf")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "act": call, "action": "Ablehnen", "then": "keep"])),
                     "unbekannter Wert")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "act": call, "action": "Ablehnen", "then": true])), "Typ")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "act": call, "action": "Ablehnen", "more": 1])),
                     "anderer Zusatzschlüssel")
        XCTAssertNil(NotifyWire.parseCommand(payload(["v": 1, "apps": [], "calls": true])), "Filter ohne badges")
    }

    /// Gemessen 22.10.: Klingeln → Ablehnen → „Live-Voicemail stoppen“ + „Annehmen“ → leer.
    func testFollowUpGate() {
        let id = NotifyWire.callIdentifier
        let t0 = Date(timeIntervalSince1970: 1_000)
        let p = (id: id, at: t0)
        let ringing = ["Annehmen", "Ablehnen"]
        let screening = ["Annehmen", "Live-Voicemail stoppen"]
        XCTAssertNil(NotifyWire.followUp(pending: nil, id: id, actions: screening, now: t0), "ohne eigenes Ablehnen nie")
        XCTAssertNil(NotifyWire.followUp(pending: (id: "anderes", at: t0), id: id, actions: screening, now: t0),
                     "nur dasselbe Banner")
        XCTAssertEqual(NotifyWire.followUp(pending: p, id: id, actions: ringing, now: t0 + 0.1), .wait,
                       "Ablehnen noch da → warten")
        XCTAssertEqual(NotifyWire.followUp(pending: p, id: id, actions: nil, now: t0 + 0.1), .wait, "Banner gerade leer")
        XCTAssertEqual(NotifyWire.followUp(pending: p, id: id, actions: screening, now: t0 + 0.2), .press)
        XCTAssertEqual(NotifyWire.followUp(pending: p, id: id, actions: screening + ["Ablehnen"], now: t0 + 0.2), .wait,
                       "neuer Anruf klingelt schon wieder → nicht drücken")
        XCTAssertEqual(NotifyWire.followUp(pending: p, id: id, actions: screening, now: t0 + 2.5), .expire, "Frist")
        XCTAssertEqual(NotifyWire.followUp(pending: p, id: id, actions: screening, now: t0 - 1), .expire, "Uhr zurück")
        XCTAssertEqual(NotifyWire.followUp(pending: p, id: id, actions: ["Stop Live Voicemail", "Accept"], now: t0 + 1),
                       .press, "englisch")
    }

    func testScreeningAndCallActions() {
        let screening = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                        title: "Erika Muster", subtitle: "", body: "",
                                        actions: ["Annehmen", "Live-Voicemail stoppen"])
        XCTAssertTrue(NotifyWire.isScreening(screening))
        XCTAssertFalse(NotifyWire.isOngoing(screening))
        XCTAssertTrue(NotifyWire.callActions.contains("Live-Voicemail stoppen"))
        XCTAssertFalse(NotifyWire.callActions.contains("Live-Voicemail"), "Apples eigener Mailbox-Knopf bleibt weg")
        XCTAssertFalse(NotifyWire.callActions.contains("Mit Nachricht ablehnen"))
    }

    /// Gemessen 22.10., 15:27: Eine stehengebliebene Kalender-Erinnerung hielt Apples Fenster samt Anruf sichtbar.
    func testMayHideWindowDuringCall() {
        let call = NotifyWire.callIdentifier
        XCTAssertTrue(NotifyWire.mayHideWindow(ids: ["a"], shown: ["a"], everShown: ["a"]))
        XCTAssertFalse(NotifyWire.mayHideWindow(ids: ["a", "b"], shown: ["a"], everShown: ["a", "b"]),
                       "ohne Anruf nur, was gerade gezeigt wird")
        XCTAssertTrue(NotifyWire.mayHideWindow(ids: [call, "erinnerung"], shown: [call], everShown: [call, "erinnerung"]),
                      "Anruf: früher gezeigter Hinweis darf mit")
        XCTAssertFalse(NotifyWire.mayHideWindow(ids: [call, "fremd"], shown: [call], everShown: [call]),
                       "nie gezeigter (nicht ausgewählter) Hinweis hält das Fenster")
        XCTAssertFalse(NotifyWire.mayHideWindow(ids: [call, "erinnerung"], shown: [], everShown: [call, "erinnerung"]),
                       "Anruf nicht (mehr) in Gnotchi → alles zurück")
        XCTAssertFalse(NotifyWire.mayHideWindow(ids: [], shown: [call], everShown: []))
    }

    // MARK: 0.9.0 – Ungelesen-Zahlen (G33)

    func testBadgeCountTreatsLabelAsUntrusted() {
        XCTAssertEqual(NotifyWire.badgeCount("5"), 5)
        XCTAssertEqual(NotifyWire.badgeCount(" 12 "), 12)
        XCTAssertEqual(NotifyWire.badgeCount("9999"), 9999)
        XCTAssertEqual(NotifyWire.badgeCount("123456789012345678901234567890"), NotifyWire.maxBadgeCount, "kein Überlauf")
        XCTAssertEqual(NotifyWire.badgeCount("•"), 1, "Punkt = 1")
        XCTAssertEqual(NotifyWire.badgeCount("Neu: Erika"), 1, "Text nie übernehmen")
        XCTAssertEqual(NotifyWire.badgeCount("٣"), 1, "nur ASCII-Ziffern")
        XCTAssertEqual(NotifyWire.badgeCount("-3"), 1)
        XCTAssertNil(NotifyWire.badgeCount(""))
        XCTAssertNil(NotifyWire.badgeCount("0"))
        XCTAssertNil(NotifyWire.badgeCount("000"))
    }

    func testBadgesRoundTripAndSchema() {
        let list = [NotifyWire.Badge(bundle: "com.apple.mail", count: 5), NotifyWire.Badge(bundle: "net.whatsapp.WhatsApp", count: 1)]
        XCTAssertEqual(NotifyWire.parseHelperMessage(payload(NotifyWire.encode(.badges(list)))), .badges(list))
        XCTAssertEqual(NotifyWire.parseHelperMessage(payload(["v": 1, "badges": []])), .badges([]))
        let bad: [(Any, String)] = [
            ([["bundle": "com.a", "count": 0]], "0"),
            ([["bundle": "com.a", "count": 10_000]], "zu groß"),
            ([["bundle": "com.a", "count": 1.5]], "keine ganze Zahl"),
            ([["bundle": "com.a", "count": true]], "Wahrheitswert"),
            ([["bundle": "com.a", "count": "3"]], "Text"),
            ([["bundle": "bad id", "count": 3]], "Kennung"),
            ([["bundle": "com.a", "count": 3, "text": "Erika"]], "Zusatzschlüssel"),
            ([["bundle": "com.a", "count": 3], ["bundle": "com.a", "count": 4]], "doppelt"),
            (Array(repeating: ["bundle": "com.a", "count": 1], count: NotifyWire.maxBadges + 1), "zu viele"),
            ("com.a", "kein Feld"),
        ]
        for (value, why) in bad {
            XCTAssertNil(NotifyWire.parseHelperMessage(payload(["v": 1, "badges": value])), why)
        }
    }
}
