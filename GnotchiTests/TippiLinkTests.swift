import XCTest

/// 0.2.0 Tippi-Aufnahme in der Insel. Nachrichten kommen über distnoted – jeder lokale Prozess kann senden
/// (SECURE-DESIGN G17): nur das Schema `v`=1, `state` aus der Positivliste, `level` endliche Zahl 0…1.
@MainActor
final class TippiLinkTests: XCTestCase {

    func testParseValid() {
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording", "level": 0.4]), .recording(level: 0.4))
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "transcribing"]), .transcribing)
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "idle"]), .idle)
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording"]), .recording(level: 0), "ohne Pegel: 0")
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording", "level": 0.2, "unbekannt": "x"]),
                       .recording(level: 0.2), "unbekannte Schlüssel ignoriert")
    }

    func testLevelClampedAndChecked() {
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording", "level": 7.0]), .recording(level: 1))
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording", "level": -2]), .recording(level: 0))
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording", "level": Double.nan]), .recording(level: 0))
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording", "level": Double.infinity]), .recording(level: 0))
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording", "level": "0.5"]), .recording(level: 0), "Text ist kein Pegel")
        XCTAssertEqual(TippiLink.parse(["v": 1, "state": "recording", "level": true]), .recording(level: 0), "Bool ist kein Pegel")
    }

    func testParseRejects() {
        XCTAssertNil(TippiLink.parse(nil))
        XCTAssertNil(TippiLink.parse([:]))
        XCTAssertNil(TippiLink.parse(["state": "recording"]), "ohne Version")
        XCTAssertNil(TippiLink.parse(["v": 2, "state": "recording"]), "andere Version")
        XCTAssertNil(TippiLink.parse(["v": true, "state": "recording"]), "Bool ist keine Version")
        XCTAssertNil(TippiLink.parse(["v": 1, "state": "RECORDING"]))
        XCTAssertNil(TippiLink.parse(["v": 1, "state": "<script>"]))
        XCTAssertNil(TippiLink.parse(["v": 1, "state": 3]))
    }

    /// Beginn der Aufnahme bleibt stehen, solange sie läuft (Laufzeit-Anzeige); Umwandeln und Ende wechseln.
    func testRecordingStateFollowsMessages() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let rec = TippiLink.next(nil, .recording(level: 0.3), now: t0)
        XCTAssertEqual(rec, .recording(since: t0))
        XCTAssertEqual(TippiLink.next(rec, .recording(level: 0.9), now: t0.addingTimeInterval(4)), .recording(since: t0))
        XCTAssertEqual(TippiLink.next(rec, .transcribing, now: t0.addingTimeInterval(5)), .transcribing)
        XCTAssertNil(TippiLink.next(.transcribing, .idle, now: t0.addingTimeInterval(6)))
    }

    func testRecordingShowsOverFullscreenAndBlocksNoticeAndExpand() {
        let activity = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(activity.showsOverFullscreen)
        activity.setRecording(.transcribing)
        XCTAssertTrue(activity.isVisible)
        XCTAssertTrue(activity.showsOverFullscreen, "sonst wäre die Aufnahme im Vollbild nirgends zu sehen")
        activity.setRecording(nil)
        XCTAssertFalse(activity.isVisible)

        XCTAssertEqual(IslandController.nextMode(current: .expanded, notice: false, recording: true), .compact)
        XCTAssertEqual(IslandController.nextMode(current: .hidden, notice: true, recording: true), .compact)
        XCTAssertEqual(IslandController.nextMode(current: .notice, notice: true, recording: true), .compact)
    }

    /// Laufzeit wie bei Tippi: m:ss.
    func testElapsedLabel() {
        XCTAssertEqual(TippiLink.elapsedLabel(7.9), "0:07")
        XCTAssertEqual(TippiLink.elapsedLabel(65), "1:05")
        XCTAssertEqual(TippiLink.elapsedLabel(-3), "0:00")
        XCTAssertEqual(TippiLink.elapsedLabel(.nan), "0:00")
    }
}
