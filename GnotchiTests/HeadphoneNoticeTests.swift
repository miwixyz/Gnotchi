import CoreAudio
import XCTest

/// 0.2.0 Kopfhörer-Hinweis: wann die Insel 3 s Gerät + Zustand zeigt (Michael 20.10.: beim Umschalten
/// auf Bluetooth-Kopfhörer und beim Zurückwechseln; nicht, wenn Gnotchi selbst umgeschaltet hat).
@MainActor
final class HeadphoneNoticeTests: XCTestCase {

    private let speaker = OutputDevices.Device(id: 9, name: "Lautsprecher", transport: kAudioDeviceTransportTypeBuiltIn)
    private let buds = OutputDevices.Device(id: 4, name: "Beispiel-Kopfhörer", transport: kAudioDeviceTransportTypeBluetooth)
    private let display = OutputDevices.Device(id: 7, name: "Anzeige", transport: kAudioDeviceTransportTypeHDMI)
    private let otherBuds = OutputDevices.Device(id: 5, name: "Zweite Kopfhörer", transport: kAudioDeviceTransportTypeBluetoothLE)

    func testConnectShowsHeadphones() {
        XCTAssertEqual(HeadphoneWatcher.notice(old: speaker, new: buds, setByUs: false),
                       ActivityModel.Notice(symbol: "headphones", title: "Beispiel-Kopfhörer", subtitle: "Verbunden"))
    }

    func testDisconnectShowsNewDevice() {
        XCTAssertEqual(HeadphoneWatcher.notice(old: buds, new: speaker, setByUs: false),
                       ActivityModel.Notice(symbol: "speaker.wave.2", title: "Lautsprecher", subtitle: "Kopfhörer getrennt"))
    }

    func testBluetoothToBluetoothIsConnect() {
        XCTAssertEqual(HeadphoneWatcher.notice(old: buds, new: otherBuds, setByUs: false)?.subtitle, "Verbunden")
    }

    func testNoNoticeOtherwise() {
        XCTAssertNil(HeadphoneWatcher.notice(old: speaker, new: display, setByUs: false), "kein Kopfhörer beteiligt")
        XCTAssertNil(HeadphoneWatcher.notice(old: speaker, new: buds, setByUs: true), "selbst umgeschaltet")
        XCTAssertNil(HeadphoneWatcher.notice(old: buds, new: buds, setByUs: false), "gleiches Gerät")
        XCTAssertNil(HeadphoneWatcher.notice(old: buds, new: nil, setByUs: false), "kein Gerät")
        // Beim Start kennt Gnotchi das vorige Gerät nicht: Kopfhörer, die schon dran sind, melden nichts.
        XCTAssertNil(HeadphoneWatcher.notice(old: nil, new: buds, setByUs: false))
    }

    /// Gnotchis eigene Auswahl zählt nur für dasselbe Gerät und höchstens 2 s.
    func testSelectedByUsWindow() {
        let t = Date(timeIntervalSince1970: 1_000)
        let last = (id: AudioObjectID(4), at: t)
        XCTAssertTrue(OutputDevices.selectedByUs(4, now: t.addingTimeInterval(1.5), last: last))
        XCTAssertFalse(OutputDevices.selectedByUs(4, now: t.addingTimeInterval(2.5), last: last))
        XCTAssertFalse(OutputDevices.selectedByUs(9, now: t.addingTimeInterval(0.5), last: last))
        XCTAssertFalse(OutputDevices.selectedByUs(4, now: t, last: nil))
    }

    /// Hinweis macht die Insel sichtbar und verschwindet nach seiner Dauer von selbst.
    func testNoticeExpires() async throws {
        let activity = ActivityModel(media: NowPlayingModel(), noticeDuration: .milliseconds(50))
        XCTAssertFalse(activity.isVisible)
        activity.post(ActivityModel.Notice(symbol: "headphones", title: "X", subtitle: "Verbunden"))
        XCTAssertTrue(activity.isVisible)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(activity.notice)
        XCTAssertFalse(activity.isVisible)
    }

    /// Form der Insel: Hinweis verdrängt klein, nicht groß; ohne Hinweis zurück auf klein.
    func testModeWithNotice() {
        XCTAssertEqual(IslandController.nextMode(current: .hidden, notice: true), .notice)
        XCTAssertEqual(IslandController.nextMode(current: .compact, notice: true), .notice)
        XCTAssertEqual(IslandController.nextMode(current: .expanded, notice: true), .expanded)
        XCTAssertEqual(IslandController.nextMode(current: .notice, notice: false), .compact)
        XCTAssertEqual(IslandController.nextMode(current: .hidden, notice: false), .compact)
        XCTAssertEqual(IslandController.nextMode(current: .expanded, notice: false), .expanded)
    }
}
