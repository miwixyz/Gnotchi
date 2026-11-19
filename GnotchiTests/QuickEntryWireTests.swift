import XCTest

// SYNTHETISCH – erfundene Einträge, keine echten Kalenderdaten (Datenschutz-Gate, SECURE-DESIGN G16)

/// Schnelleingabe ↔ Kalli (SECURE-DESIGN G61): Nachrichten an Kalli, Kallis Antwort, Weiche im Termin-Socket.
@MainActor
final class QuickEntryWireTests: XCTestCase {

    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let start = Date(timeIntervalSince1970: 1_800_003_600)

    private func entry(_ kind: QuickEntryParser.Kind = .event, title: String = "Zahnarzt", start: Date? = nil,
                       end: Date? = nil, allDay: Bool = false, urgent: Bool = false) -> QuickEntryParser.Entry {
        QuickEntryParser.Entry(kind: kind, title: title, start: start, end: end, allDay: allDay, urgent: urgent,
                               needsCheck: false)
    }

    private func body(_ obj: [String: Any]?) -> [String: Any]? { obj?["create"] as? [String: Any] }

    // MARK: Gnotchi → Kalli

    func testCreateTimedEventMatchesKallisSchema() throws {
        let b = try XCTUnwrap(body(QuickEntryWire.create(entry(start: start, end: start.addingTimeInterval(3600)),
                                                         id: id)))
        XCTAssertEqual(Set(b.keys), ["id", "kind", "title", "start", "end", "allDay", "urgent"], "genau Kallis Felder")
        XCTAssertEqual(b["id"] as? String, id.uuidString)
        XCTAssertEqual(b["kind"] as? String, "event")
        XCTAssertEqual(b["start"] as? Double, 1_800_003_600)
        XCTAssertEqual(b["end"] as? Double, 1_800_007_200)
        XCTAssertEqual(b["allDay"] as? Bool, false)
        XCTAssertEqual(b["urgent"] as? Bool, false, "dringend nur bei Erinnerungen")
    }

    func testCreateAllDayAndReminders() throws {
        let allDay = try XCTUnwrap(body(QuickEntryWire.create(entry(start: start, end: start, allDay: true), id: id)))
        XCTAssertTrue(allDay["end"] is NSNull, "ganztägig ohne Ende")
        let undated = try XCTUnwrap(body(QuickEntryWire.create(entry(.reminder, urgent: true), id: id)))
        XCTAssertTrue(undated["start"] is NSNull)
        XCTAssertEqual(undated["allDay"] as? Bool, false, "ohne Datum nie ganztägig (Kalli lehnt das ab)")
        XCTAssertEqual(undated["urgent"] as? Bool, true)
        let timed = try XCTUnwrap(body(QuickEntryWire.create(entry(.reminder, start: start, end: start), id: id)))
        XCTAssertTrue(timed["end"] is NSNull, "Erinnerung nie mit Ende")
    }

    func testCreateRefusesWhatKalliWouldReject() {
        XCTAssertNil(QuickEntryWire.create(entry(title: "  ", start: start), id: id), "leerer Titel")
        XCTAssertNil(QuickEntryWire.create(entry(start: nil), id: id), "Termin ohne Beginn")
        XCTAssertNil(QuickEntryWire.create(entry(title: String(repeating: "a", count: 201), start: start), id: id))
    }

    func testUndo() {
        XCTAssertEqual((QuickEntryWire.undo(id: id)["undo"] as? [String: String])?["id"], id.uuidString)
    }

    // MARK: Kalli → Gnotchi

    func testParseResult() {
        XCTAssertEqual(QuickEntryWire.parseResult(["v": 2, "result": ["id": id.uuidString, "ok": true]]),
                       .init(id: id, ok: true, error: nil))
        XCTAssertEqual(QuickEntryWire.parseResult(["v": 2, "result": ["id": NSNull(), "ok": false, "error": "Nein"]]),
                       .init(id: nil, ok: false, error: "Nein"))
        XCTAssertEqual(QuickEntryWire.parseResult(["v": 2, "result": ["id": id.uuidString, "ok": false]])?.error,
                       "Kalli hat den Eintrag abgelehnt.", "Ablehnung ohne Text bekommt einen")
    }

    func testParseResultIsStrict() {
        XCTAssertNil(QuickEntryWire.parseResult(["v": 2, "result": ["id": id.uuidString, "ok": 1]]), "Zahl ≠ Bool")
        XCTAssertNil(QuickEntryWire.parseResult(["v": 2, "result": ["ok": true]]), "id fehlt")
        XCTAssertNil(QuickEntryWire.parseResult(["v": 2, "result": ["id": "x", "ok": true]]))
        XCTAssertNil(QuickEntryWire.parseResult(["v": 2, "result": ["id": id.uuidString, "ok": true, "x": 1]]))
        XCTAssertNil(QuickEntryWire.parseResult(["v": 2, "result": ["id": id.uuidString, "ok": true, "error": "?"]]),
                     "ok mit Fehler ist widersprüchlich")
        XCTAssertNil(QuickEntryWire.parseResult(["v": 2, "result": ["id": id.uuidString, "ok": true], "x": 1]))
    }

    func testErrorTextIsSanitizedAndCut() throws {
        let raw = "Zeile\u{0007}eins\n" + String(repeating: "x", count: 500)
        let r = try XCTUnwrap(QuickEntryWire.parseResult(["v": 2, "result": ["id": id.uuidString, "ok": false,
                                                                              "error": raw]]))
        XCTAssertFalse(r.error?.contains("\u{0007}") ?? true)
        XCTAssertLessThanOrEqual(r.error?.count ?? 0, QuickEntryWire.maxError)
    }

    // MARK: Termin-Socket

    private func payload(_ obj: Any) -> Data { (try? JSONSerialization.data(withJSONObject: obj)) ?? Data() }

    func testKalliSocketAcceptsV2ResultsAndStillV1Events() {
        XCTAssertEqual(KalliEvents.parse(payload(["v": 2, "result": ["id": id.uuidString, "ok": true]])),
                       .result(.init(id: id, ok: true, error: nil)))
        XCTAssertNil(KalliEvents.parse(payload(["v": 2, "event": NSNull()])), "v:2 nur als Antwort")
        XCTAssertNil(KalliEvents.parse(payload(["v": 3, "event": NSNull()])))
        XCTAssertEqual(KalliEvents.parse(payload(["v": 1, "event": NSNull()])), KalliEvents.Message.none)
    }

    func testResultDoesNotTouchUpcomingEvent() {
        let model = ActivityModel(media: NowPlayingModel())
        let link = KalliEventLink(activity: model)
        let soon = KalliEvents.Event(title: "Zahnarzt", start: Date().addingTimeInterval(600), color: nil)
        link.receive(.event(soon))
        XCTAssertNotNil(model.upcomingEvent)
        XCTAssertTrue(link.kalliConnected)
        link.receive(.result(.init(id: UUID(), ok: true, error: nil)))
        XCTAssertNotNil(model.upcomingEvent, "Antwort ohne offene Anfrage lässt den Termin stehen")
        link.receive(nil)
        XCTAssertFalse(link.kalliConnected)
        XCTAssertNil(model.upcomingEvent)
    }

    func testEventsHiddenWhenOnlyQuickEntryUsesTheSocket() {
        let model = ActivityModel(media: NowPlayingModel())
        let link = KalliEventLink(activity: model)
        link.showsEvents = false
        link.receive(.event(KalliEvents.Event(title: "Zahnarzt", start: Date().addingTimeInterval(600), color: nil)))
        XCTAssertTrue(link.kalliConnected, "verbunden …")
        XCTAssertNil(model.upcomingEvent, "… aber kein Termin in der Insel")
    }

    func testSubmitWithoutKalliFailsVisibly() async {
        let link = KalliEventLink(activity: ActivityModel(media: NowPlayingModel()))
        let r = await link.submit(entry(start: start, end: start.addingTimeInterval(3600)))
        XCTAssertEqual(r, .failure(.kalliNotRunning))
        let u = await link.undo(id)
        XCTAssertEqual(u, QuickEntryFailure.kalliNotRunning.message)
    }
}
