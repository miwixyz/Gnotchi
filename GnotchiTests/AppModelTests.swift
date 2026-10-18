import XCTest
@testable import Gnotchi

/// Lebenszyklus „Musik in der Notch“ gegen Attrappen: Reihenfolge, keine doppelten Starts/Stopps,
/// und im Testlauf (ohne Freigabe) startet nichts – sonst liefe perl bzw. AppleScript im Test-Host.
@MainActor
final class AppModelTests: XCTestCase {

    private let suite = "dev.mwlr.gnotchi.tests.appmodel"
    private var prefs: Preferences!
    private var calls: CallLog!
    private var islandsMade = 0

    override func setUp() async throws {
        try await super.setUp()
        // Eigene Suite: nie Michaels echte Einstellung im Test-Host überschreiben.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        prefs = Preferences(defaults: defaults)
        calls = CallLog()
        islandsMade = 0
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func makeModel(allowStart: Bool) -> AppModel {
        let log = calls!
        return AppModel(prefs: prefs, allowStart: allowStart,
                        source: FakePart(name: "source", log: log),
                        makeIsland: { [unowned self] in
                            islandsMade += 1
                            return FakePart(name: "island", log: log)
                        })
    }

    func testOnOffSequence() {
        let model = makeModel(allowStart: true)

        prefs.notchMedia = true
        model.applyNotchSetting()
        XCTAssertEqual(calls.entries, ["source.start", "island.start"])
        XCTAssertTrue(model.notchRunning)

        model.applyNotchSetting()
        XCTAssertEqual(calls.entries, ["source.start", "island.start"], "kein doppelter Start")

        prefs.notchMedia = false
        model.applyNotchSetting()
        XCTAssertEqual(calls.entries.suffix(2), ["island.stop", "source.stop"], "Insel vor der Quelle")
        XCTAssertFalse(model.notchRunning)

        model.applyNotchSetting()
        XCTAssertEqual(calls.entries.count, 4, "kein doppelter Stopp")

        prefs.notchMedia = true
        model.applyNotchSetting()
        XCTAssertEqual(calls.entries, ["source.start", "island.start", "island.stop", "source.stop",
                                       "source.start", "island.start"])
        XCTAssertEqual(islandsMade, 1, "eine Insel für alle Läufe")
    }

    /// Schalter aus von Anfang an: keine Insel anlegen, nichts stoppen.
    func testOffFromStartCreatesNothing() {
        let model = makeModel(allowStart: true)
        prefs.notchMedia = false
        model.applyNotchSetting()
        XCTAssertEqual(calls.entries, [])
        XCTAssertEqual(islandsMade, 0)
    }

    func testNothingStartsInTestRunByDefault() {
        XCTAssertTrue(AppModel.isRunningTests)
        prefs.notchMedia = true
        let model = AppModel(prefs: prefs,
                             source: FakePart(name: "source", log: calls),
                             makeIsland: { FakePart(name: "island", log: self.calls) })
        model.applyNotchSetting()
        XCTAssertEqual(calls.entries, [])
        XCTAssertFalse(model.notchRunning)
    }

    /// Ohne Attrappen: das echte Modell bleibt im Testlauf unberührt.
    func testRealPipelineDoesNotStartInTestRun() {
        prefs.notchMedia = true
        let model = AppModel(prefs: prefs)
        model.applyNotchSetting()
        XCTAssertFalse(model.notchRunning)
        XCTAssertNil(model.nowPlaying.unavailableReason)
    }
}

@MainActor
private final class CallLog {
    var entries: [String] = []
}

@MainActor
private final class FakePart: NotchPart {
    let name: String
    let log: CallLog
    init(name: String, log: CallLog) {
        self.name = name
        self.log = log
    }
    func start() { log.entries.append("\(name).start") }
    func stop() { log.entries.append("\(name).stop") }
}
