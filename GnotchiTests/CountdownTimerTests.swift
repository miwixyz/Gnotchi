import XCTest
@testable import Gnotchi

/// 0.5.0 Eigener Timer: Zeitlogik, Pause/Weiter, Anzeige, Modell.
@MainActor
final class CountdownTimerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemainingCountsDown() {
        let t = CountdownTimer(minutes: 25, now: t0)
        XCTAssertEqual(t.remaining(now: t0), 1500)
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(100)), 1400)
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(2000)), 0, "nie negativ")
    }

    func testPauseFreezesAndResumeContinues() {
        var t = CountdownTimer(minutes: 5, now: t0)
        t.pause(now: t0.addingTimeInterval(60))
        XCTAssertTrue(t.isPaused)
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(500)), 240, "steht während der Pause")
        t.resume(now: t0.addingTimeInterval(500))
        XCTAssertFalse(t.isPaused)
        XCTAssertEqual(t.remaining(now: t0.addingTimeInterval(560)), 180)
    }

    func testClock() {
        XCTAssertEqual(CountdownTimer.clock(1500), "25:00")
        XCTAssertEqual(CountdownTimer.clock(59.2), "1:00", "aufgerundet: 0:00 erst beim Ablauf")
        XCTAssertEqual(CountdownTimer.clock(0), "0:00")
        XCTAssertEqual(CountdownTimer.clock(3723), "1:02:03")
    }

    func testCustomTimeStepsAndBounds() {
        XCTAssertEqual(CountdownTimer.stepCustom(30, up: true), 35)
        XCTAssertEqual(CountdownTimer.stepCustom(10, up: true), 15)
        XCTAssertEqual(CountdownTimer.stepCustom(9, up: true), 10)
        XCTAssertEqual(CountdownTimer.stepCustom(10, up: false), 9)
        XCTAssertEqual(CountdownTimer.stepCustom(15, up: false), 10)
        XCTAssertEqual(CountdownTimer.stepCustom(1, up: false), 1, "nie unter 1")
        XCTAssertEqual(CountdownTimer.stepCustom(180, up: true), 180, "nie über 180")
        XCTAssertEqual(CountdownTimer.parseCustom(" 45 "), 45)
        XCTAssertNil(CountdownTimer.parseCustom("0"))
        XCTAssertNil(CountdownTimer.parseCustom("181"))
        XCTAssertNil(CountdownTimer.parseCustom("zehn"))
        XCTAssertNil(CountdownTimer.parseCustom("1.5"))
    }

    func testSoundOnlyFromFixedList() {
        XCTAssertEqual(CountdownTimer.validSound("Hero"), "Hero")
        XCTAssertEqual(CountdownTimer.validSound(""), "", "kein Ton")
        XCTAssertEqual(CountdownTimer.validSound(nil), "Glass", "Werkseinstellung")
        XCTAssertEqual(CountdownTimer.validSound("/tmp/fremd.aiff"), "Glass", "nie ein Pfad")
        XCTAssertEqual(CountdownTimer.validSound(42), "Glass")
        let prefs = Preferences(defaults: UserDefaults(suiteName: "gnotchi-test-\(UUID().uuidString)")!)
        prefs.timerSound = "../../evil"
        XCTAssertEqual(prefs.timerSound, "Glass", "ungültiger Wert wird nie gespeichert")
    }

    func testShortClockFitsNotchWing() {
        XCTAssertEqual(CountdownTimer.shortClock(1500), "25′")
        XCTAssertEqual(CountdownTimer.shortClock(61), "2′")
        XCTAssertEqual(CountdownTimer.shortClock(44.2), "45s")
        XCTAssertEqual(CountdownTimer.shortClock(0), "0s")
    }

    func testStartShowsTimerAndStopRemovesIt() {
        let model = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(model.isVisible)
        model.showTimerPicker()
        XCTAssertEqual(model.bigContent, .timerPicker)
        model.startTimer(minutes: 10)
        XCTAssertTrue(model.isVisible)
        XCTAssertFalse(model.timerPickerActive, "Auswahl schließt beim Start")
        XCTAssertEqual(model.currentActivity, .timer)
        XCTAssertEqual(model.bigContent, .timer)
        model.pauseTimer()
        XCTAssertEqual(model.timer?.isPaused, true)
        model.resumeTimer()
        XCTAssertEqual(model.timer?.isPaused, false)
        model.stopTimer()
        XCTAssertNil(model.timer)
        XCTAssertFalse(model.isVisible)
    }

    func testTimerSitsAfterEventInRotation() {
        XCTAssertEqual(ActivityModel.rotationItems(event: true, timer: true, media: true, headphones: false, updates: []),
                       [.event, .timer, .media])
    }

    func testCollapseClosesPicker() {
        let model = ActivityModel(media: NowPlayingModel())
        model.showTimerPicker()
        model.endMirror()
        XCTAssertFalse(model.timerPickerActive)
    }
}
