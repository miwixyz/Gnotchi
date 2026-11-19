import XCTest

// SYNTHETISCH – erfundene Einträge, keine echten Kalenderdaten (Datenschutz-Gate, SECURE-DESIGN G16)

/// Eingabezeile der Schnelleingabe (G61): Ablauf ohne Fenster und ohne Kalli.
@MainActor
final class QuickEntryStateTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 2
        return c
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 14, minute: 30))! }

    private final class Fake {
        var submitted: [QuickEntryParser.Entry] = []
        var undone: [UUID] = []
        var submitResult: Result<UUID, QuickEntryFailure> = .success(UUID())
        var undoMessage: String?
        var closed = 0
    }

    private func state(_ fake: Fake) -> QuickEntryState {
        QuickEntryState(submit: { fake.submitted.append($0); return fake.submitResult },
                        undo: { fake.undone.append($0); return fake.undoMessage },
                        close: { fake.closed += 1 }, now: { [now] in now }, calendar: calendar)
    }

    func testTypingUpdatesPreviewAndSaveSendsEntry() async {
        let fake = Fake()
        let s = state(fake)
        s.text = "Zahnarzt morgen 15 Uhr"
        XCTAssertEqual(s.entry.kind, .event)
        XCTAssertEqual(s.entry.title, "Zahnarzt")
        await s.save()
        XCTAssertEqual(fake.submitted.map(\.title), ["Zahnarzt"])
        guard case .saved = s.phase else { return XCTFail("gespeichert") }
        XCTAssertFalse(s.isEditable, "nach dem Speichern nichts mehr tippen")
    }

    func testEmptyTitleIsNotSent() async {
        let fake = Fake()
        let s = state(fake)
        s.text = "morgen 15 Uhr"
        XCTAssertFalse(s.canSave)
        await s.save()
        XCTAssertTrue(fake.submitted.isEmpty)
        XCTAssertEqual(s.phase, .failed(QuickEntryFailure.invalid.message))
        s.text = "Zahnarzt morgen 15 Uhr"
        XCTAssertEqual(s.phase, .editing, "Weitertippen nimmt den Hinweis weg")
    }

    func testFailureStaysOpenWithMessage() async {
        let fake = Fake()
        fake.submitResult = .failure(.kalliNotRunning)
        let s = state(fake)
        s.text = "Zahnarzt morgen 15 Uhr"
        await s.save()
        XCTAssertEqual(s.phase, .failed(QuickEntryFailure.kalliNotRunning.message))
        XCTAssertTrue(s.isEditable, "Fehler: Zeile bleibt offen und bearbeitbar")
        XCTAssertEqual(fake.closed, 0)
    }

    func testTabTogglesKind() {
        let s = state(Fake())
        s.text = "Zahnarzt morgen 15 Uhr"
        XCTAssertTrue(s.handle(keyCode: 48, command: false, characters: "\t"))
        XCTAssertEqual(s.entry.kind, .reminder)
        s.text = "Zahnarzt morgen 16 Uhr"
        XCTAssertEqual(s.entry.kind, .reminder, "Umschalten gilt weiter beim Tippen")
        _ = s.handle(keyCode: 48, command: false, characters: "\t")
        XCTAssertEqual(s.entry.kind, .event)
    }

    func testUndoOnlyRightAfterSaving() async {
        let fake = Fake()
        let id = UUID()
        fake.submitResult = .success(id)
        let s = state(fake)
        XCTAssertFalse(s.handle(keyCode: 6, command: true, characters: "z"), "⌘Z beim Tippen bleibt beim Textfeld")
        s.text = "Zahnarzt morgen 15 Uhr"
        await s.save()
        await s.undoLast()
        XCTAssertEqual(fake.undone, [id])
        XCTAssertEqual(s.phase, .undone)
        await s.undoLast()
        XCTAssertEqual(fake.undone.count, 1, "nur einmal")
    }

    func testFailedUndoStaysOpen() async {
        let fake = Fake()
        fake.undoMessage = "Eintrag nicht gefunden."
        let s = state(fake)
        s.text = "Zahnarzt morgen 15 Uhr"
        await s.save()
        await s.undoLast()
        XCTAssertEqual(s.phase, .failed("Eintrag nicht gefunden."))
    }

    func testSavedClosesByItself() async throws {
        let fake = Fake()
        let s = state(fake)
        s.text = "Zahnarzt morgen 15 Uhr"
        await s.save()
        try await Task.sleep(for: .seconds(QuickEntryState.savedLinger + 0.5))
        XCTAssertEqual(fake.closed, 1, "schließt sich nach ~1,5 s selbst")
    }

    func testUndoneClosesByItself() async throws {
        let fake = Fake()
        let s = state(fake)
        s.text = "Zahnarzt morgen 15 Uhr"
        await s.save()
        await s.undoLast()
        XCTAssertEqual(s.phase, .undone)
        try await Task.sleep(for: .seconds(1.6))
        XCTAssertEqual(fake.closed, 1, "nach dem Zurücknehmen schließt die Zeile nach ~1 s selbst")
    }

    func testInputIsCapped() {
        let s = state(Fake())
        s.text = String(repeating: "a", count: 1000)
        XCTAssertEqual(s.text.count, QuickEntryState.maxInput)
    }

    // MARK: Vorschau

    private func entry(_ text: String) -> QuickEntryParser.Entry {
        QuickEntryParser.parse(text, now: now, calendar: calendar)
    }

    func testPreviewText() {
        XCTAssertEqual(QuickEntryPreview.when(entry("Zahnarzt morgen 15 Uhr"), now: now, calendar: calendar),
                       "Fr 20.11. · 15:00–16:00")
        XCTAssertEqual(QuickEntryPreview.when(entry("Rechnung zahlen bis 30.11."), now: now, calendar: calendar),
                       "Mo 30.11. · ganztägig")
        XCTAssertEqual(QuickEntryPreview.when(entry("Geburtstag Mama 12.01.2027"), now: now, calendar: calendar),
                       "Di 12.01.2027 · ganztägig")
        XCTAssertEqual(QuickEntryPreview.when(entry("Paket abholen"), now: now, calendar: calendar), "ohne Datum")
        XCTAssertEqual(QuickEntryPreview.when(entry("erinnere mich in 2 Stunden Tom anzurufen"), now: now,
                                              calendar: calendar), "Do 19.11. · 16:30")
        XCTAssertEqual(QuickEntryPreview.kindLabel(entry("Paket abholen")), "Erinnerung")
    }
}
