import XCTest
@testable import Gnotchi

// SYNTHETISCH – erfundene Mitteilungen und Anrufer (Datenschutz-Gate, SECURE-DESIGN G16)

/// 0.6.0 Mitteilungen und Anrufe in der Insel: Warteschlange, „erst zeigen, dann verstecken“, Zeit, Klicks (G29/G30),
/// Vorrang der Formen.
@MainActor
final class NotifyActivityTests: XCTestCase {

    private func note(_ id: String, actions: [String] = ["Erledigt", "Schließen"]) -> NotifyWire.Note {
        NotifyWire.Note(id: id, kind: .note, app: "Beispiel", bundle: "com.example.app", title: "T \(id)", subtitle: "",
                        body: "", actions: actions)
    }

    private let call = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                       title: "Erika Muster", subtitle: "", body: "", actions: ["Annehmen", "Ablehnen"])

    private func model(noteDuration: Duration = .seconds(6), arm: Duration = .milliseconds(1)) -> (ActivityModel, Sent) {
        let m = ActivityModel(media: NowPlayingModel(), noteDuration: noteDuration, callArmDelay: arm)
        let sent = Sent()
        m.notifyCommand = { sent.list.append($0) }
        return (m, sent)
    }

    final class Sent { var list: [NotifyWire.Command] = [] }

    func testQueueShowsFirstAndCountsRest() {
        let (m, _) = model()
        XCTAssertFalse(m.isVisible)
        m.receiveNote(note("a"))
        m.receiveNote(note("b"))
        m.receiveNote(note("a"))   // doppelt
        XCTAssertTrue(m.isVisible)
        XCTAssertEqual(m.currentNote?.id, "a")
        XCTAssertEqual(m.queuedNotes, 1)
    }

    func testShownOnlyOnceWhenDisplayed() {
        let (m, sent) = model()
        m.receiveNote(note("a"))
        XCTAssertTrue(sent.list.isEmpty, "nicht angezeigt → Apples Banner bleibt")
        m.noteDisplayed()
        m.noteDisplayed()
        XCTAssertEqual(sent.list, [.shown("a")])
    }

    func testReleasedAfterDurationThenNext() {
        let (m, sent) = model(noteDuration: .milliseconds(50))
        m.receiveNote(note("a"))
        m.receiveNote(note("b"))
        m.noteDisplayed()
        let done = expectation(description: "weiter")
        Task { @MainActor in
            while m.currentNote?.id == "a" { try? await Task.sleep(for: .milliseconds(10)) }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(sent.list, [.shown("a"), .release("a")])
        XCTAssertEqual(m.currentNote?.id, "b")
    }

    func testTimeStandsWhileHovered() {
        let (m, sent) = model(noteDuration: .milliseconds(30))
        m.receiveNote(note("a"))
        m.setRotationPaused(true)
        m.noteDisplayed()
        let waited = expectation(description: "gewartet")
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); waited.fulfill() }
        wait(for: [waited], timeout: 2)
        XCTAssertEqual(m.currentNote?.id, "a", "Maus darüber: bleibt")
        XCTAssertEqual(sent.list, [.shown("a")])
    }

    func testClicksSendOnlyListedActions() {
        let (m, sent) = model()
        m.receiveNote(note("a"))
        m.receiveNote(note("b"))
        m.performNoteAction("Antworten")   // nicht gemeldet → nichts
        XCTAssertTrue(sent.list.isEmpty)
        m.performNoteAction("Erledigt")
        XCTAssertEqual(sent.list, [.act(id: "a", action: "Erledigt")])
        m.openNote()
        XCTAssertEqual(sent.list.last, .act(id: "b", action: NotifyWire.openAction))
        XCTAssertNil(m.currentNote)
    }

    func testGoneRemovesFrontOrWaiting() {
        let (m, _) = model()
        m.receiveNote(note("a"))
        m.receiveNote(note("b"))
        m.receiveNote(note("c"))
        m.noteGone("b")
        XCTAssertEqual(m.notes.map(\.id), ["a", "c"])
        m.noteGone("a")
        XCTAssertEqual(m.currentNote?.id, "c")
    }

    func testFloodDropsOldestWaitingNeverShown() {
        let (m, _) = model()
        for i in 0...ActivityModel.maxQueuedNotes { m.receiveNote(note("n\(i)")) }
        XCTAssertEqual(m.notes.count, ActivityModel.maxQueuedNotes)
        XCTAssertEqual(m.currentNote?.id, "n0", "die angezeigte bleibt")
        XCTAssertFalse(m.notes.contains { $0.id == "n1" }, "älteste wartende fliegt")
    }

    func testCallArmsBeforeAnswering() {
        let (m, sent) = model(arm: .milliseconds(80))
        m.receiveNote(call)
        XCTAssertTrue(m.isVisible)
        XCTAssertTrue(m.showsOverFullscreen, "Anruf auch über Vollbild")
        m.answerCall("Annehmen")
        XCTAssertTrue(sent.list.isEmpty, "noch nicht scharf")
        let armed = expectation(description: "scharf")
        Task { @MainActor in
            while !m.callArmed { try? await Task.sleep(for: .milliseconds(10)) }
            armed.fulfill()
        }
        wait(for: [armed], timeout: 2)
        m.answerCall("Live-Voicemail")
        XCTAssertTrue(sent.list.isEmpty, "nur gemeldete Aktion")
        m.answerCall("Annehmen")
        m.answerCall("Annehmen")
        XCTAssertEqual(sent.list, [.act(id: NotifyWire.callIdentifier, action: "Annehmen")], "nur einmal")
        m.noteGone(NotifyWire.callIdentifier)
        XCTAssertNil(m.call)
        XCTAssertFalse(m.isVisible)
    }

    /// Gemessen 22.10.: Nach Annehmen kommt derselbe Anruf mit „Beenden“ – Knöpfe wieder scharf, Auflegen geht.
    func testOngoingCallRearmsWithEnd() {
        let (m, sent) = model(arm: .milliseconds(1))
        m.receiveNote(call)
        let armed = expectation(description: "scharf")
        Task { @MainActor in
            while !m.callArmed { try? await Task.sleep(for: .milliseconds(5)) }
            armed.fulfill()
        }
        wait(for: [armed], timeout: 2)
        m.answerCall("Annehmen")
        XCTAssertFalse(m.callArmed)
        let ongoing = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                      title: "Erika Muster", subtitle: "", body: "", actions: ["Beenden"])
        XCTAssertTrue(NotifyWire.isOngoing(ongoing))
        XCTAssertFalse(NotifyWire.isOngoing(call))
        m.receiveNote(ongoing)
        let rearmed = expectation(description: "wieder scharf")
        Task { @MainActor in
            while !m.callArmed { try? await Task.sleep(for: .milliseconds(5)) }
            rearmed.fulfill()
        }
        wait(for: [rearmed], timeout: 2)
        m.answerCall("Beenden")
        XCTAssertEqual(sent.list.last, .act(id: NotifyWire.callIdentifier, action: "Beenden"))
    }

    func testClearDropsEverything() {
        let (m, _) = model()
        m.receiveNote(note("a"))
        m.receiveNote(call)
        m.notifyTrust = true
        m.clearNotify()
        XCTAssertTrue(m.notes.isEmpty)
        XCTAssertNil(m.call)
        XCTAssertNil(m.notifyTrust)
    }

    // MARK: Formen

    func testCallBeatsEverything() {
        XCTAssertEqual(IslandController.nextMode(current: .expanded, notice: true, recording: true, call: true), .call)
        XCTAssertEqual(IslandController.nextMode(current: .call, notice: false), .compact, "Anruf vorbei")
        XCTAssertEqual(IslandController.nextMode(current: .call, notice: false, message: true), .message)
    }

    func testMessageLikeNoticeButKeepsBigAndRecording() {
        XCTAssertEqual(IslandController.nextMode(current: .compact, notice: false, message: true), .message)
        XCTAssertEqual(IslandController.nextMode(current: .notice, notice: true, message: true), .message)
        XCTAssertEqual(IslandController.nextMode(current: .expanded, notice: false, message: true), .expanded)
        XCTAssertEqual(IslandController.nextMode(current: .band, notice: false, message: true), .band)
        XCTAssertEqual(IslandController.nextMode(current: .compact, notice: false, recording: true, message: true), .compact,
                       "Aufnahme geht vor – Mitteilung wartet")
        XCTAssertEqual(IslandController.nextMode(current: .message, notice: false), .compact)
    }

    func testFramesForNewForms() throws {
        let m = IslandGeometry.ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32,
                                             auxLeftWidth: 666, auxRightWidth: 666)
        let layout = IslandGeometry.layout(for: m)
        let message = try XCTUnwrap(IslandController.panelFrame(mode: .message, layout: layout))
        XCTAssertEqual(message.width, IslandGeometry.messageSize.width)
        XCTAssertEqual(message.height, IslandGeometry.messageSize.height + 32, "mit Notch um deren Höhe länger")
        XCTAssertEqual(message.maxY, 982, "oben bündig")
        let call = try XCTUnwrap(IslandController.panelFrame(mode: .call, layout: layout))
        XCTAssertEqual(call.width, IslandGeometry.callSize.width)
        XCTAssertEqual(call.midX, message.midX, accuracy: 0.5)
    }
}
