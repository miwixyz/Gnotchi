import Security
import XCTest

// SYNTHETISCH – erfundene Beispielsätze, keine echten Diktate (Datenschutz-Gate, SECURE-DESIGN G16)

/// 0.3.0 Tippis Live-Text (SECURE-DESIGN G21): Rahmen, Schema, Bereinigung, Prüf-Anforderung.
final class LiveTextTests: XCTestCase {

    private func json(_ s: String) -> Data { Data(s.utf8) }

    // MARK: Rahmen

    func testFrameRoundTrip() throws {
        var buf = try XCTUnwrap(LiveText.frame(["v": 1, "text": "Hallo Welt"]))
        guard case .message(let payload) = LiveText.nextFrame(&buf) else { return XCTFail("keine Nachricht") }
        XCTAssertEqual(LiveText.parse(payload), "Hallo Welt")
        XCTAssertTrue(buf.isEmpty)
        XCTAssertEqual(LiveText.nextFrame(&buf), .needMore)
    }

    func testFrameSplitAndConcatenated() throws {
        let one = try XCTUnwrap(LiveText.frame(["v": 1, "text": "eins"]))
        let two = try XCTUnwrap(LiveText.frame(["v": 1, "text": "zwei"]))
        var buf = Data(one.prefix(3))
        XCTAssertEqual(LiveText.nextFrame(&buf), .needMore, "Länge unvollständig")
        buf += one.dropFirst(3).prefix(2)
        XCTAssertEqual(LiveText.nextFrame(&buf), .needMore, "Inhalt unvollständig")
        buf += one.dropFirst(5) + two
        guard case .message(let a) = LiveText.nextFrame(&buf), case .message(let b) = LiveText.nextFrame(&buf) else {
            return XCTFail("zwei Nachrichten erwartet")
        }
        XCTAssertEqual(LiveText.parse(a), "eins")
        XCTAssertEqual(LiveText.parse(b), "zwei")
    }

    func testFrameRejectsZeroAndOversize() {
        var zero = Data([0, 0, 0, 0])
        XCTAssertEqual(LiveText.nextFrame(&zero), .invalid)
        var huge = Data([0, 0, 0x10, 0x00])   // 4096 + 4 > maxFrame
        XCTAssertEqual(LiveText.nextFrame(&huge), .invalid)
        var giant = Data([0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(LiveText.nextFrame(&giant), .invalid)
        XCTAssertNil(LiveText.frame(["v": 1, "text": String(repeating: "a", count: 5000)]), "Sender begrenzt auch")
    }

    // MARK: Schema

    func testParseRejects() {
        XCTAssertNil(LiveText.parse(json(#"{"text":"x"}"#)), "ohne Version")
        XCTAssertNil(LiveText.parse(json(#"{"v":2,"text":"x"}"#)), "andere Version")
        XCTAssertNil(LiveText.parse(json(#"{"v":1.5,"text":"x"}"#)), "keine ganze Zahl")
        XCTAssertNil(LiveText.parse(json(#"{"v":true,"text":"x"}"#)), "Bool ist keine Version")
        XCTAssertNil(LiveText.parse(json(#"{"v":1,"text":7}"#)), "Text muss String sein")
        XCTAssertNil(LiveText.parse(json(#"{"v":1}"#)))
        XCTAssertNil(LiveText.parse(json(#"[1,2]"#)))
        XCTAssertNil(LiveText.parse(json("kein json")))
        XCTAssertNil(LiveText.parse(Data([0xFF, 0xFE, 0x00])), "kaputtes UTF-8")
        XCTAssertEqual(LiveText.parse(json(#"{"v":1,"text":"ok","x":"egal"}"#)), "ok", "unbekannte Schlüssel ignoriert")
    }

    // MARK: Bereinigung

    func testSanitizeRemovesControlAndBidi() {
        XCTAssertEqual(LiveText.sanitize("a\u{202E}b\u{2066}c\u{200B}d\u{0007}e"), "abcd e",
                       "Richtungs-Override, Isolat, Nullbreite entfernt, Steuerzeichen BEL → Leerzeichen")
        XCTAssertEqual(LiveText.sanitize("Zeile eins\nZeile\tzwei\r\n"), "Zeile eins Zeile zwei")
        XCTAssertEqual(LiveText.sanitize("  viel    Raum  "), "viel Raum")
        XCTAssertEqual(LiveText.sanitize("👨\u{200D}💻 bleibt"), "👨\u{200D}💻 bleibt", "Emoji-Verbinder bleibt")
        XCTAssertEqual(LiveText.sanitize(""), "")
    }

    func testTailKeepsNewestWordsAtWordBoundary() {
        let words = (1...200).map { "wort\($0)" }.joined(separator: " ")
        let t = LiveText.tail(words)
        XCTAssertTrue(t.hasPrefix("…"))
        XCTAssertTrue(t.hasSuffix("wort200"))
        XCTAssertLessThanOrEqual(t.count, LiveText.maxChars + 1)
        XCTAssertTrue(t.dropFirst().first?.isLetter == true, "beginnt mit ganzem Wort, nicht mitten drin")
        XCTAssertEqual(LiveText.tail("kurz"), "kurz")
    }

    // MARK: Prüf-Anforderung

    func testRequirementCompilesAndRejectsThisTestRunner() throws {
        var req: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(LiveText.tippiRequirement as CFString, [], &req), errSecSuccess)
        let requirement = try XCTUnwrap(req)
        var me: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &me), errSecSuccess)
        // Der Testlauf ist kein Developer-ID-signiertes Tippi → muss durchfallen.
        XCTAssertNotEqual(SecCodeCheckValidity(try XCTUnwrap(me), [], requirement), errSecSuccess)
    }

    func testRequirementDemandsDeveloperIDAndTeam() {
        let r = LiveText.peerRequirement(identifier: "com.tippi.app")
        XCTAssertTrue(r.contains("1.2.840.113635.100.6.2.6"), "Developer-ID-Zwischenzertifikat")
        XCTAssertTrue(r.contains(#"identifier "com.tippi.app""#))
        XCTAssertTrue(r.contains(#"leaf[subject.OU] = "LTKJ6Z2VYB""#))
    }
}

/// 0.3.0: Insel-Form und Modell für den Live-Text.
@MainActor
final class LiveTextModeTests: XCTestCase {

    func testModeWithLiveText() {
        XCTAssertEqual(IslandController.nextMode(current: .compact, notice: false, recording: true, liveText: true), .live)
        XCTAssertEqual(IslandController.nextMode(current: .expanded, notice: true, recording: true, liveText: true), .live,
                       "verdrängt groß und Hinweis wie die Aufnahme")
        XCTAssertEqual(IslandController.nextMode(current: .live, notice: false, recording: true, liveText: false), .compact,
                       "Text weg, Aufnahme läuft: klein")
        XCTAssertEqual(IslandController.nextMode(current: .live, notice: false, recording: false), .compact,
                       "Aufnahme vorbei, Musik läuft: klein, nicht live")
        XCTAssertEqual(IslandController.nextMode(current: .live, notice: true, recording: false), .notice)
    }

    func testPanelFrameLive() throws {
        let m = IslandGeometry.ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32,
                                             auxLeftWidth: 662, auxRightWidth: 662)
        let layout = IslandGeometry.layout(for: m)
        let f = try XCTUnwrap(IslandController.panelFrame(mode: .live, layout: layout))
        XCTAssertEqual(f.width, IslandGeometry.liveSize.width)
        XCTAssertEqual(f.height, IslandGeometry.liveSize.height + 32, "mit Notch um deren Höhe länger")
        XCTAssertEqual(f.maxY, 982, "oben bündig")
    }

    func testModelDropsTextWithoutRecordingAndClearsOnEnd() {
        let a = ActivityModel(media: NowPlayingModel())
        a.setLiveText("vor der Aufnahme")
        XCTAssertNil(a.liveText, "ohne laufende Aufnahme verworfen")
        XCTAssertFalse(a.showsLiveText)
        a.setRecording(.recording(since: Date()))
        a.setLiveText("jetzt")
        XCTAssertEqual(a.liveText, "jetzt")
        XCTAssertTrue(a.showsLiveText)
        a.setLiveText("")
        XCTAssertNil(a.liveText, "leer = nichts")
        a.setLiveText("weiter")
        a.setRecording(.transcribing)
        XCTAssertEqual(a.liveText, "weiter", "beim Umwandeln bleibt der letzte Stand")
        a.setRecording(nil)
        XCTAssertNil(a.liveText, "Aufnahme vorbei: Text weg")
        XCTAssertFalse(a.hasLiveText)
    }
}
