import XCTest

/// 0.28.0 Aktions-Tasten: Mikrofon stumm (G52) und Geschwindigkeitstest (G51), ohne echtes Gerät bzw. Netz.
@MainActor
final class RingActionsTests: XCTestCase {

    // MARK: Mikrofon stumm

    private final class FakeMic: MicBackend {
        var device: UInt32? = 7
        var canMute = true, canVolume = true
        var muted = false
        var vol: Float = 0.6
        func defaultInput() -> UInt32? { device }
        func canSetMute(_ d: UInt32) -> Bool { canMute }
        func canSetVolume(_ d: UInt32) -> Bool { canVolume }
        func isMuted(_ d: UInt32) -> Bool? { muted }
        func setMuted(_ d: UInt32, _ on: Bool) -> Bool { muted = on; return true }
        func volume(_ d: UInt32) -> Float? { vol }
        func setVolume(_ d: UInt32, _ v: Float) -> Bool { vol = v; return true }
        func observe(device: UInt32?, _ handler: @escaping @MainActor () -> Void) -> AnyObject? { nil }
    }

    func testMethodPrefersMuteThenVolume() {
        XCTAssertEqual(MicMuteMethod.choose(muteSettable: true, volumeSettable: true), .mute)
        XCTAssertEqual(MicMuteMethod.choose(muteSettable: false, volumeSettable: true), .volume)
        XCTAssertEqual(MicMuteMethod.choose(muteSettable: false, volumeSettable: false), .none)
    }

    func testToggleMutesAndUnmutes() {
        let fake = FakeMic()
        let mic = MicMute(backend: fake)
        mic.setActive(true)
        XCTAssertEqual(mic.state, .unmuted)
        mic.toggle()
        XCTAssertTrue(fake.muted)
        XCTAssertEqual(mic.state, .muted)
        mic.toggle()
        XCTAssertFalse(fake.muted)
        XCTAssertEqual(mic.state, .unmuted)
    }

    func testVolumeFallbackRestoresPreviousVolume() {
        let fake = FakeMic()
        fake.canMute = false
        let mic = MicMute(backend: fake)
        mic.setActive(true)
        mic.toggle()
        XCTAssertEqual(fake.vol, 0, "stumm = Eingangslautstärke 0")
        XCTAssertEqual(mic.state, .muted)
        mic.toggle()
        XCTAssertEqual(fake.vol, 0.6, accuracy: 0.001, "die vorige Lautstärke kommt zurück")
    }

    func testUnsupportedDeviceDisablesButton() {
        let fake = FakeMic()
        fake.canMute = false
        fake.canVolume = false
        let mic = MicMute(backend: fake)
        mic.setActive(true)
        XCTAssertEqual(mic.state, .unsupported)
        mic.toggle()
        XCTAssertFalse(fake.muted, "ohne Fähigkeit passiert nichts")
    }

    func testNoInputDeviceIsUnsupported() {
        let fake = FakeMic()
        fake.device = nil
        let mic = MicMute(backend: fake)
        mic.setActive(true)
        XCTAssertFalse(mic.isSupported)
    }

    func testQuittingUnmutesOnlyWhatWeMuted() {
        let fake = FakeMic()
        let mic = MicMute(backend: fake)
        mic.setActive(true)
        mic.toggle()
        mic.setActive(false)   // Beenden bzw. Taste aus
        XCTAssertFalse(fake.muted, "von Gnotchi stummgeschaltet → wieder laut")
    }

    func testQuittingLeavesForeignMuteAlone() {
        let fake = FakeMic()
        fake.muted = true   // von außen (Systemeinstellungen) stumm
        let mic = MicMute(backend: fake)
        mic.setActive(true)
        XCTAssertEqual(mic.state, .muted)
        mic.setActive(false)
        XCTAssertTrue(fake.muted, "fremde Stummschaltung bleibt")
    }

    func testChangeOfDefaultDeviceForgetsOurMute() {
        let fake = FakeMic()
        let mic = MicMute(backend: fake)
        mic.setActive(true)
        mic.toggle()
        fake.device = 9   // anderes Mikrofon wird Standard
        fake.muted = true
        mic.refresh()
        mic.setActive(false)
        XCTAssertTrue(fake.muted, "das neue Gerät hat nicht Gnotchi stummgeschaltet")
    }

    // MARK: Geschwindigkeitstest

    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testParseRealisticOutput() throws {
        let r = try XCTUnwrap(SpeedTest.parse(json(#"{"dl_throughput":187076416,"ul_throughput":34453692,"base_rtt":29.47,"responsiveness":40.0017,"interface_name":"en0"}"#)))
        XCTAssertEqual(r.downMbps, 187.076416, accuracy: 0.0001)
        XCTAssertEqual(r.upMbps, 34.453692, accuracy: 0.0001)
        XCTAssertEqual(r.latencyMs ?? 0, 29.47, accuracy: 0.001)
        XCTAssertEqual(r.responsiveness, 40)
    }

    func testParseWithoutOptionalFields() throws {
        let r = try XCTUnwrap(SpeedTest.parse(json(#"{"dl_throughput":1000000,"ul_throughput":2000000}"#)))
        XCTAssertNil(r.latencyMs)
        XCTAssertNil(r.responsiveness)
    }

    func testParseRejectsNonsense() {
        XCTAssertNil(SpeedTest.parse(json("kein json")))
        XCTAssertNil(SpeedTest.parse(json(#"{"dl_throughput":1}"#)), "Upload fehlt")
        XCTAssertNil(SpeedTest.parse(json(#"{"dl_throughput":-5,"ul_throughput":1}"#)), "negativ")
        XCTAssertNil(SpeedTest.parse(json(#"{"dl_throughput":"schnell","ul_throughput":1}"#)), "kein Zahlenwert")
        XCTAssertNil(SpeedTest.parse(json(#"{"dl_throughput":1e30,"ul_throughput":1}"#)), "über der Obergrenze")
    }

    func testParseRejectsOversizedOutput() {
        let big = #"{"dl_throughput":1,"ul_throughput":1,"x":""# + String(repeating: "a", count: SpeedTest.maxOutput) + #""}"#
        XCTAssertNil(SpeedTest.parse(json(big)))
    }

    func testMbpsText() {
        XCTAssertEqual(SpeedTest.mbpsText(187.07), "187")
        XCTAssertEqual(SpeedTest.mbpsText(4.56), "4,6")
        XCTAssertEqual(SpeedTest.mbpsText(0), "0,0")
    }

    func testProcessIsFixedAndShellFree() {
        XCTAssertEqual(SpeedTest.path, "/usr/bin/networkQuality", "fester Pfad")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: SpeedTest.path))
        XCTAssertEqual(SpeedTest.arguments, ["-c", "-M", "20"], "feste Argumente, höchstens 20 s")
    }

    func testSecondStartWhileRunningIsIgnored() {
        let t = SpeedTest()
        t.start()
        XCTAssertEqual(t.state, .running)
        t.start()   // ein Lauf gleichzeitig
        XCTAssertEqual(t.state, .running)
    }

    // MARK: Batterie in der Ruhe-Insel

    private func power(_ extra: [String: Any] = [:]) -> [String: Any] {
        var d: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 84, "Max Capacity": 100,
                                "Is Charging": false, "Power Source State": "Battery Power"]
        d.merge(extra) { $1 }
        return d
    }

    func testBatteryParse() throws {
        let b = try XCTUnwrap(BatteryStatus.parse(power()))
        XCTAssertEqual(b.percent, 84)
        XCTAssertFalse(b.charging)
        XCTAssertFalse(b.pluggedIn)
        XCTAssertEqual(b.text, "84 %")
    }

    func testBatteryParseChargingOnAC() throws {
        let b = try XCTUnwrap(BatteryStatus.parse(power(["Is Charging": true, "Power Source State": "AC Power"])))
        XCTAssertTrue(b.charging)
        XCTAssertTrue(b.pluggedIn)
        XCTAssertTrue(b.symbol.hasSuffix(".bolt"))
    }

    func testBatteryParseIgnoresOtherSourcesAndNonsense() {
        XCTAssertNil(BatteryStatus.parse(power(["Type": "UPS"])), "nur die eingebaute Batterie")
        XCTAssertNil(BatteryStatus.parse(power(["Max Capacity": 0])), "keine Division durch null")
        XCTAssertNil(BatteryStatus.parse(power(["Current Capacity": -4])))
        XCTAssertNil(BatteryStatus.parse([:]))
    }

    func testBatteryPercentIsCapped() throws {
        XCTAssertEqual(try XCTUnwrap(BatteryStatus.parse(power(["Current Capacity": 120]))).percent, 100)
    }

    func testBatterySymbolFollowsLevel() {
        XCTAssertEqual(BatteryStatus(percent: 100, charging: false, pluggedIn: false).symbol, "battery.100percent")
        XCTAssertEqual(BatteryStatus(percent: 70, charging: false, pluggedIn: false).symbol, "battery.75percent")
        XCTAssertEqual(BatteryStatus(percent: 50, charging: false, pluggedIn: false).symbol, "battery.50percent")
        XCTAssertEqual(BatteryStatus(percent: 20, charging: false, pluggedIn: false).symbol, "battery.25percent")
        XCTAssertEqual(BatteryStatus(percent: 5, charging: false, pluggedIn: false).symbol, "battery.0percent")
    }

    /// Am echten System: Ist eine Batterie da, stimmt der Wert; ein Mac mini liefert nil. Beides ist richtig.
    func testReadingRealSystemIsPlausible() {
        if let b = BatteryStatus.read() { XCTAssertTrue((0...100).contains(b.percent)) }
    }

    func testBatteryOnlyHoldsIdleIslandWhenSwitchedOnAndPresent() {
        let activity = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(activity.hasIdleContent)
        activity.batteryIdle = true
        XCTAssertFalse(activity.hasIdleContent, "Schalter an, aber noch keine Batterie gelesen (oder Mac mini)")
    }

    // MARK: Ring-Verfügbarkeit

    func testMicButtonOnlyInMeetingUnlessAlways() {
        let fake = FakeMic()
        let activity = ActivityModel(media: NowPlayingModel())
        activity.mic = MicMute(backend: fake)
        activity.mic.setActive(true)
        XCTAssertFalse(activity.ringAvailable.contains(.mic), "kein Meeting, nicht stumm → keine Taste")
        activity.ringMicAlways = true
        XCTAssertTrue(activity.ringAvailable.contains(.mic))
        activity.ringMicAlways = false
        activity.mic.toggle()
        XCTAssertTrue(activity.ringAvailable.contains(.mic), "stumm → die Taste bleibt, sonst käme man nicht mehr heran")
    }

    func testAwakeButtonOnlyWithFeature() {
        let activity = ActivityModel(media: NowPlayingModel())
        XCTAssertFalse(activity.ringAvailable.contains(.awake), "ohne „Wach bleiben“ keine Taste, die nichts tut")
        activity.awake = StayAwake()
        XCTAssertTrue(activity.ringAvailable.contains(.awake))
    }

    func testActionButtonsAreAvailableButOffByDefault() {
        let activity = ActivityModel(media: NowPlayingModel())
        XCTAssertTrue(activity.ringAvailable.isSuperset(of: [.screenshot, .speedtest]))
        XCTAssertFalse(activity.ringButtons.contains(.screenshot), "ab Werk aus")
        activity.ringOn.insert(.screenshot)
        XCTAssertTrue(activity.ringButtons.contains(.screenshot))
    }

    func testSpeedtestExclusiveWithOtherBigViews() {
        let activity = ActivityModel(media: NowPlayingModel())
        activity.selectSpeedtest()
        XCTAssertEqual(activity.bigContent, .speedtest)
        activity.selectMirror()   // ohne eingeschalteten Spiegel: setzt nur zurück
        activity.select(.media)
        XCTAssertFalse(activity.speedtestActive, "andere Ansicht → Test nicht mehr groß")
    }
}
