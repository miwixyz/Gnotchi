import XCTest

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

    private func waitArmed(_ m: ActivityModel) {
        let armed = expectation(description: "scharf")
        Task { @MainActor in
            while !m.callArmed { try? await Task.sleep(for: .milliseconds(5)) }
            armed.fulfill()
        }
        wait(for: [armed], timeout: 2)
    }

    /// 0.9.0 Rot: Ablehnen mit Folgeaktion, Anruf sofort weg, weitere Meldungen desselben Banners bis `gone` ignoriert.
    func testDeclineStopsVoicemailAndDismisses() {
        let (m, sent) = model()
        m.receiveNote(call)
        m.declineCall()
        XCTAssertTrue(sent.list.isEmpty, "noch nicht scharf")
        waitArmed(m)
        m.declineCall()
        XCTAssertEqual(sent.list, [.act(id: NotifyWire.callIdentifier, action: "Ablehnen", stopVoicemail: true)])
        XCTAssertNil(m.call)
        m.receiveNote(NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                      title: "Erika Muster", subtitle: "", body: "",
                                      actions: ["Annehmen", "Live-Voicemail stoppen"]))
        XCTAssertNil(m.call, "Mailbox-Zustand nach Rot nicht zeigen")
        m.noteGone(NotifyWire.callIdentifier)
        m.receiveNote(call)
        XCTAssertNotNil(m.call, "nächster Anruf erscheint wieder")
    }

    /// 0.9.0 Mitlesen: Ablehnen ohne Folgeaktion, danach Mailbox mit „Mitlesen beenden“ + Annehmen.
    func testScreenKeepsCallAndOffersStop() {
        let (m, sent) = model()
        m.receiveNote(call)
        waitArmed(m)
        m.screenCall()
        XCTAssertEqual(sent.list, [.act(id: NotifyWire.callIdentifier, action: "Ablehnen")])
        let screening = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                        title: "Erika Muster", subtitle: "", body: "",
                                        actions: ["Annehmen", "Live-Voicemail stoppen"])
        m.receiveNote(screening)
        XCTAssertEqual(m.call, screening)
        waitArmed(m)
        m.declineCall()
        XCTAssertEqual(sent.list.count, 1, "im Mailbox-Zustand gibt es kein Ablehnen mehr")
        m.answerCall("Live-Voicemail stoppen")
        XCTAssertEqual(sent.list.last, .act(id: NotifyWire.callIdentifier, action: "Live-Voicemail stoppen"))
    }

    /// Apples Anruf-Banner weg, sobald eine Insel den Anruf zeigt – einmal; nicht im Gespräch, nicht bei leerer Liste.
    func testCallDisplayedSendsShownOnce() {
        let (m, sent) = model()
        m.callDisplayed()
        XCTAssertTrue(sent.list.isEmpty)
        m.receiveNote(call)
        m.callDisplayed()
        m.callDisplayed()
        XCTAssertEqual(sent.list, [.shown(NotifyWire.callIdentifier)])
        m.noteGone(NotifyWire.callIdentifier)
        m.receiveNote(NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                      title: "", subtitle: "", body: "", actions: ["Beenden"]))
        m.callDisplayed()
        XCTAssertEqual(sent.list.count, 1, "Gespräch: Apples Leiste bleibt")
        m.noteGone(NotifyWire.callIdentifier)
        m.receiveNote(NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                      title: "", subtitle: "", body: "", actions: []))
        m.callDisplayed()
        XCTAssertEqual(sent.list.count, 1, "unbekannter Zustand: Apples Banner bleibt")
        m.noteGone(NotifyWire.callIdentifier)
        m.receiveNote(NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                      title: "", subtitle: "", body: "", actions: ["Annehmen", "Live-Voicemail stoppen"]))
        m.callDisplayed()
        XCTAssertEqual(sent.list.count, 1, "Mitlesen: Abschrift steht nur in Apples Fenster")
    }

    /// Schalter „Zähler auch in der kleinen Insel“ aus: Zahlen bleiben (Band/groß), halten die kleine Insel aber nicht offen.
    func testCompactUnreadSwitch() {
        let (m, _) = model()
        m.receiveBadges([NotifyWire.Badge(bundle: "com.apple.mail", count: 5)])
        XCTAssertEqual(m.compactUnreadTotal, 5)
        XCTAssertTrue(m.isVisible)
        m.compactUnread = false
        XCTAssertEqual(m.compactUnreadTotal, 0)
        XCTAssertEqual(m.unread.count, 1, "Band und große Insel zeigen weiter")
        XCTAssertFalse(m.isVisible, "nichts anderes da → Insel weg")
    }

    func testBadgesFilteredToSelectedApps() {
        let (m, _) = model()
        m.receiveBadges([NotifyWire.Badge(bundle: "com.apple.mail", count: 5),
                         NotifyWire.Badge(bundle: "com.evil.app", count: 3)], allowed: ["com.apple.mail"])
        XCTAssertEqual(m.unread, [NotifyWire.Badge(bundle: "com.apple.mail", count: 5)])
    }

    func testCallButtonsPerState() {
        let ringing = CallIsland.buttons(call).map(\.label)
        XCTAssertEqual(ringing, ["Ablehnen", "Mitlesen (Mailbox)", "Annehmen"])
        let screening = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                        title: "", subtitle: "", body: "", actions: ["Annehmen", "Live-Voicemail stoppen"])
        XCTAssertEqual(CallIsland.buttons(screening).map(\.label), ["Mitlesen beenden", "Annehmen"])
        XCTAssertEqual(CallIsland.status(screening), "Mailbox · Mitlesen")
        let ongoing = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                      title: "", subtitle: "", body: "", actions: ["Beenden"])
        XCTAssertEqual(CallIsland.buttons(ongoing).map(\.label), ["Beenden"])
        let unknown = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                      title: "", subtitle: "", body: "", actions: [])
        XCTAssertTrue(CallIsland.buttons(unknown).isEmpty)
        XCTAssertEqual(CallIsland.status(unknown), "Telefon · in macOS beantworten")
    }

    func testBadgesKeepIdleIslandAndSum() {
        let (m, _) = model()
        XCTAssertFalse(m.isVisible)
        m.receiveBadges([NotifyWire.Badge(bundle: "com.apple.mail", count: 5),
                         NotifyWire.Badge(bundle: "com.example.app", count: 9999)])
        XCTAssertTrue(m.isVisible)
        XCTAssertEqual(m.unreadTotal, NotifyWire.maxBadgeCount, "Summe gedeckelt")
        m.receiveBadges([])
        XCTAssertFalse(m.isVisible)
        m.receiveBadges([NotifyWire.Badge(bundle: "com.apple.mail", count: 2)])
        m.clearNotify()
        XCTAssertTrue(m.unread.isEmpty)
        XCTAssertEqual(UnreadMini.short(1000), "999+")
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
