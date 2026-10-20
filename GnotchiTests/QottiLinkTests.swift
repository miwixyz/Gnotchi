import XCTest
@testable import Gnotchi

/// 0.3.0 Qotti-Kontingent (SECURE-DESIGN G22): Schema, Warnstufen 80/95 %/Drosselung, Texte.
@MainActor
final class QottiLinkTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Schema

    func testParseValid() throws {
        let s = try XCTUnwrap(QottiLink.parse(["v": 1, "claude5h": 42.4, "claudeReset5h": 1_800_003_600,
                                               "codex5h": 17, "codexState": "stale"], now: now))
        XCTAssertEqual(s.claude, .init(percent: 42, resetAt: Date(timeIntervalSince1970: 1_800_003_600), state: .ok))
        XCTAssertEqual(s.codex, .init(percent: 17, resetAt: nil, state: .stale))
    }

    func testParseClampsAndChecks() throws {
        XCTAssertEqual(QottiLink.parse(["v": 1, "claude5h": 140], now: now)?.claude?.percent, 100)
        XCTAssertEqual(QottiLink.parse(["v": 1, "claude5h": -3], now: now)?.claude?.percent, 0)
        XCTAssertNil(QottiLink.parse(["v": 1, "claude5h": Double.nan], now: now), "nicht endlich")
        XCTAssertNil(QottiLink.parse(["v": 1, "claude5h": true], now: now), "Bool ist keine Zahl")
        XCTAssertNil(QottiLink.parse(["v": 1, "claude5h": "42"], now: now), "Text ist keine Zahl")
        XCTAssertNil(QottiLink.parse(["v": 1, "claude5h": 42, "claudeState": "kaputt"], now: now),
                     "unbekannter Zustand: Anbieter verworfen")
        let farFuture = now.addingTimeInterval(30 * 86_400).timeIntervalSince1970
        XCTAssertNil(QottiLink.parse(["v": 1, "claude5h": 42, "claudeReset5h": farFuture], now: now)?.claude?.resetAt,
                     "unplausibler Zeitpunkt: ohne Zurücksetzung")
    }

    func testParseRejects() {
        XCTAssertNil(QottiLink.parse(nil))
        XCTAssertNil(QottiLink.parse(["claude5h": 42]), "ohne Version")
        XCTAssertNil(QottiLink.parse(["v": 2, "claude5h": 42]))
        XCTAssertNil(QottiLink.parse(["v": true, "claude5h": 42]))
        XCTAssertNil(QottiLink.parse(["v": 1]), "kein Anbieter")
        XCTAssertNil(QottiLink.parse(["v": 1, "email": "x@y.z", "token": "geheim"]), "fremde Felder zählen nicht")
    }

    // MARK: Warnstufen

    private func run(_ values: [(Int, QottiLink.State)]) -> [QottiLink.Level?] {
        var alarm = QottiLink.Alarm()
        return values.map { v in
            let (a, level) = QottiLink.evaluate(alarm, .init(percent: v.0, resetAt: nil, state: v.1))
            alarm = a
            return level
        }
    }

    func testWarnsOnceAt80And95() {
        XCTAssertEqual(run([(50, .ok), (80, .ok), (85, .ok), (95, .ok), (99, .ok)]),
                       [nil, .percent80, nil, .percent95, nil])
    }

    func testJumpStraightTo95GivesOnlyOneWarning() {
        XCTAssertEqual(run([(40, .ok), (96, .ok), (97, .ok)]), [nil, .percent95, nil])
    }

    func testRearmsAfterDroppingBelow() {
        XCTAssertEqual(run([(82, .ok), (10, .ok), (81, .ok)]), [.percent80, nil, .percent80],
                       "nach der Zurücksetzung wieder scharf")
    }

    func testThrottleOnceUntilCleared() {
        XCTAssertEqual(run([(60, .throttled), (60, .throttled), (60, .ok), (60, .throttled)]),
                       [.throttled, nil, nil, .throttled])
    }

    // MARK: Texte

    func testResetLabel() {
        XCTAssertEqual(QottiLink.resetLabel(now.addingTimeInterval(65 * 60), now: now), "zurück in 1 Std. 5 Min.")
        XCTAssertEqual(QottiLink.resetLabel(now.addingTimeInterval(120 * 60), now: now), "zurück in 2 Std.")
        XCTAssertEqual(QottiLink.resetLabel(now.addingTimeInterval(11 * 60 + 5), now: now), "zurück in 12 Min.")
        XCTAssertEqual(QottiLink.resetLabel(now.addingTimeInterval(-5), now: now), "wird gleich zurückgesetzt")
        XCTAssertEqual(QottiLink.resetLabel(nil, now: now), "5-Stunden-Limit")
    }

    func testLine() {
        XCTAssertEqual(QottiLink.line(.init(claude: .init(percent: 42, resetAt: nil, state: .ok),
                                            codex: .init(percent: 17, resetAt: nil, state: .ok))),
                       "Claude 42 % · GPT 17 %")
        XCTAssertEqual(QottiLink.line(.init(claude: .init(percent: 100, resetAt: nil, state: .throttled), codex: nil)),
                       "Claude gedrosselt")
        XCTAssertNil(QottiLink.line(nil))
        XCTAssertNil(QottiLink.line(.init()))
    }

    func testNotice() {
        let p = QottiLink.Provider(percent: 82, resetAt: now.addingTimeInterval(65 * 60), state: .ok)
        let n = QottiLink.notice(name: "Claude", p, .percent80, now: now)
        XCTAssertEqual(n.title, "Claude 82 %")
        XCTAssertEqual(n.subtitle, "zurück in 1 Std. 5 Min.")
        XCTAssertEqual(QottiLink.notice(name: "GPT", p, .throttled, now: now).title, "GPT gedrosselt")
    }

    func testPanelFrameGrowsPerLine() throws {
        let m = IslandGeometry.ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32,
                                             auxLeftWidth: 662, auxRightWidth: 662)
        let layout = IslandGeometry.layout(for: m)
        let base = try XCTUnwrap(IslandController.panelFrame(mode: .expanded, layout: layout)).height
        let one = try XCTUnwrap(IslandController.panelFrame(mode: .expanded, layout: layout, quota: true)).height
        let two = try XCTUnwrap(IslandController.panelFrame(mode: .expanded, layout: layout, privacy: true, quota: true)).height
        XCTAssertEqual(one - base, IslandGeometry.privacyLineHeight)
        XCTAssertEqual(two - base, 2 * IslandGeometry.privacyLineHeight)
    }
}
