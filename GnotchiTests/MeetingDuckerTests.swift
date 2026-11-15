import XCTest

/// 0.29.0 Meeting-Leiser (G53): Rechnungen, Ablauf mit Attrappen-Player, Wiederherstellung.
@MainActor
final class MeetingDuckerTests: XCTestCase {

    private let spotify = AppleScriptSource.spotify
    private let music = AppleScriptSource.music

    /// Player ohne AppleScript: Lautstärken im Speicher, „läuft nicht“ = nil.
    private final class FakePlayer: PlayerVolume {
        var volumes: [String: Int]
        var running: Set<String>
        init(_ volumes: [String: Int]) { self.volumes = volumes; running = Set(volumes.keys) }
        var players: [String] { [AppleScriptSource.spotify, AppleScriptSource.music] }
        func volume(_ action: AppleScriptSource.VolumeAction, bundleID: String) async -> Int? { apply(action, bundleID) }
        nonisolated func volumeSync(_ action: AppleScriptSource.VolumeAction, bundleID: String) -> Int? {
            MainActor.assumeIsolated { apply(action, bundleID) }
        }
        private func apply(_ action: AppleScriptSource.VolumeAction, _ id: String) -> Int? {
            guard running.contains(id), volumes[id] != nil else { return nil }
            if case .set(let v) = action { volumes[id] = min(100, max(0, v)) }
            return volumes[id]
        }
    }

    private var store: UserDefaults!
    private let suite = "dev.mwlr.gnotchi.tests.duck"

    override func setUp() {
        super.setUp()
        store = UserDefaults(suiteName: suite)
        store.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func ducker(_ fake: FakePlayer, enabled: Bool = true, percent: Int = 30) -> MeetingDucker {
        let d = MeetingDucker(player: fake, store: store, fadeStep: .zero, watchInterval: .seconds(3600))
        d.configure(enabled: enabled, percent: percent, apps: ["Microsoft Teams", "zoom.us"])
        return d
    }

    // MARK: Rechnungen

    func testTargetIsShareOfOriginalNeverHigher() {
        XCTAssertEqual(DuckLogic.target(original: 80, percent: 30), 24)
        XCTAssertEqual(DuckLogic.target(original: 100, percent: 50), 50)
        XCTAssertEqual(DuckLogic.target(original: 0, percent: 30), 0)
        XCTAssertEqual(DuckLogic.target(original: 2, percent: 20), 1, "nie auf 0 = stumm")
        XCTAssertLessThanOrEqual(DuckLogic.target(original: 7, percent: 50), 7)
    }

    func testRestoreOnlyNearDuckedValue() {
        XCTAssertTrue(DuckLogic.shouldRestore(current: 24, ducked: 24))
        XCTAssertTrue(DuckLogic.shouldRestore(current: 26, ducked: 24), "Rundung/Spotify-Schritte")
        XCTAssertFalse(DuckLogic.shouldRestore(current: 60, ducked: 24), "selbst geändert")
    }

    func testMeetingDetectionIsExactAndCaseInsensitive() {
        let apps: Set<String> = ["Microsoft Teams", "zoom.us"]
        XCTAssertTrue(DuckLogic.isMeeting(micApps: ["Spotify", "microsoft teams"], meetingApps: apps))
        XCTAssertFalse(DuckLogic.isMeeting(micApps: ["Tippi"], meetingApps: apps), "Diktat zählt nicht")
        XCTAssertFalse(DuckLogic.isMeeting(micApps: ["Microsoft Teams Helper"], meetingApps: apps), "kein Teilstring")
        XCTAssertFalse(DuckLogic.isMeeting(micApps: [], meetingApps: apps))
    }

    func testValidAppsFiltersJunk() {
        let long = String(repeating: "x", count: 65)
        let v = DuckLogic.validApps(["Teams", " Teams ", "", "a\u{0007}b", long, 3, "Zoom"] as [Any])
        XCTAssertEqual(v, ["Teams", "Zoom"])
        XCTAssertNil(DuckLogic.validApps("Teams"))
        XCTAssertEqual(DuckLogic.validApps((0..<50).map { "App\($0)" })?.count, DuckLogic.maxApps)
    }

    func testDecodeSavedKeepsOnlySanePlayerEntries() {
        let players = [spotify, music]
        let stored: [String: [Int]] = [spotify: [80, 24], music: [50, 90], "evil.app": [80, 24], "x": [1]]
        XCTAssertEqual(DuckLogic.decodeSaved(stored, players: players), [spotify: .init(original: 80, ducked: 24)],
                       "Fremde Kennung, Länge falsch und gesenkt > vorher fallen weg")
        XCTAssertEqual(DuckLogic.decodeSaved("kein Dictionary", players: players), [:])
        XCTAssertEqual(DuckLogic.decodeSaved([spotify: [150, 10]], players: players), [:], "über 100")
    }

    func testPercentChoicesValidated() {
        XCTAssertEqual(DuckLogic.validPercent(50), 50)
        XCTAssertEqual(DuckLogic.validPercent(33), 30)
        XCTAssertEqual(DuckLogic.validPercent("viel"), 30)
    }

    func testScriptUsesFixedIDsAndClampsVolume() {
        XCTAssertEqual(AppleScriptSource.volumeScript(.read, bundleID: "evil.app"), "")
        let s = AppleScriptSource.volumeScript(.set(500), bundleID: spotify)
        XCTAssertTrue(s.contains("set sound volume to 100"))
        XCTAssertTrue(s.contains("application id \"com.spotify.client\""))
        XCTAssertTrue(AppleScriptSource.volumeScript(.set(-9), bundleID: music).contains("set sound volume to 0"))
        XCTAssertTrue(AppleScriptSource.volumeScript(.read, bundleID: music).contains("is running"), "startet die App nie")
    }

    // MARK: Ablauf

    func testDucksWhenMeetingAppUsesMicAndRestoresAfterwards() async {
        let fake = FakePlayer([spotify: 80])
        let d = ducker(fake)
        d.micAppsChanged(["Microsoft Teams"])
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 24)
        XCTAssertEqual(store.object(forKey: MeetingDucker.savedKey) as? [String: [Int]], [spotify: [80, 24]], "erst gemerkt, persistiert")
        d.micAppsChanged([])
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 80)
        XCTAssertNil(store.object(forKey: MeetingDucker.savedKey), "nach dem Zurückstellen nichts mehr gemerkt")
    }

    func testOtherMicAppDoesNotDuck() async {
        let fake = FakePlayer([spotify: 80])
        let d = ducker(fake)
        d.micAppsChanged(["Tippi"])
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 80)
    }

    func testDisabledNeverTouchesVolume() async {
        let fake = FakePlayer([spotify: 80])
        let d = ducker(fake, enabled: false)
        d.micAppsChanged(["Microsoft Teams"])
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 80)
    }

    func testBothPlayersAreDucked() async {
        let fake = FakePlayer([spotify: 80, music: 60])
        let d = ducker(fake)
        d.micAppsChanged(["zoom.us"])
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 24)
        XCTAssertEqual(fake.volumes[music], 18)
    }

    func testUserChangeDuringMeetingIsKept() async {
        let fake = FakePlayer([spotify: 80])
        let d = ducker(fake)
        d.micAppsChanged(["Microsoft Teams"])
        await d.settle()
        fake.volumes[spotify] = 60   // Michael dreht selbst lauter
        d.micAppsChanged([])
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 60, "Michaels Wert bleibt, nicht zurück auf 80")
        XCTAssertTrue(d.saved.isEmpty)
    }

    func testAppNotRunningKeepsMemoryUntilItReturns() async {
        let fake = FakePlayer([spotify: 80])
        let d = ducker(fake)
        d.micAppsChanged(["Microsoft Teams"])
        await d.settle()
        fake.running.remove(spotify)   // Spotify wird im Meeting beendet, seine Lautstärke bleibt bei 24
        d.micAppsChanged([])
        await d.settle()
        XCTAssertEqual(d.saved[spotify]?.original, 80, "gemerkt, solange Spotify nicht läuft")
        fake.running.insert(spotify)
        d.configure(enabled: true, percent: 30, apps: ["Microsoft Teams"])   // nächster Durchgang (Start/Wächter)
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 80)
        XCTAssertTrue(d.saved.isEmpty)
    }

    func testStartupRecoversVolumeLeftDuckedByCrash() async {
        store.set([spotify: [80, 24]], forKey: MeetingDucker.savedKey)
        let fake = FakePlayer([spotify: 24])   // Gnotchi stürzte im Meeting ab, Spotify blieb leise
        let d = ducker(fake)
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 80, "nächster Start stellt wieder her")
    }

    func testShutdownRestoresSynchronously() async {
        let fake = FakePlayer([spotify: 80])
        let d = ducker(fake)
        d.micAppsChanged(["Microsoft Teams"])
        await d.settle()
        d.shutdown()
        XCTAssertEqual(fake.volumes[spotify], 80)
        XCTAssertTrue(d.saved.isEmpty)
    }

    func testSilentOrAlreadyLowPlayerIsLeftAlone() async {
        let fake = FakePlayer([spotify: 0, music: 1])
        let d = ducker(fake)
        d.micAppsChanged(["Microsoft Teams"])
        await d.settle()
        XCTAssertEqual(fake.volumes[spotify], 0)
        XCTAssertEqual(fake.volumes[music], 1, "schon bei 1: nichts zu senken")
    }

    func testPreferencesPersistMeetingSettings() {
        let defaults = UserDefaults(suiteName: "dev.mwlr.gnotchi.tests.duck2")!
        defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.duck2")
        defer { defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.duck2") }
        let p = Preferences(defaults: defaults)
        XCTAssertFalse(p.meetingDuck, "ab Werk aus")
        XCTAssertEqual(p.meetingDuckPercent, 30)
        XCTAssertEqual(p.meetingApps, DuckLogic.defaultMeetingApps)
        p.meetingDuck = true
        p.setMeetingApp("Helium", on: true)
        p.setMeetingApp("Slack", on: false)
        let q = Preferences(defaults: defaults)
        XCTAssertTrue(q.meetingDuck)
        XCTAssertTrue(q.meetingApps.contains("Helium"))
        XCTAssertFalse(q.meetingApps.contains("Slack"))
    }
}
