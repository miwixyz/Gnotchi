import XCTest

/// Zeitanzeige der großen Insel. `Int(...)` würde bei NaN/∞/riesigen Werten abstürzen –
/// NowPlayingInfo garantiert endlich und ≤ 48 h, die Anzeige sichert trotzdem selbst ab.
final class ProgressRowClockTests: XCTestCase {

    func testZero() { XCTAssertEqual(ProgressRow.clock(0), "0:00") }

    func testRoundsDown() { XCTAssertEqual(ProgressRow.clock(59.9), "0:59") }

    func testMinutes() { XCTAssertEqual(ProgressRow.clock(61), "1:01") }

    func testHours() { XCTAssertEqual(ProgressRow.clock(3600), "1:00:00") }

    func testMaxDuration() { XCTAssertEqual(ProgressRow.clock(NowPlayingInfo.maxDuration), "48:00:00") }

    func testNegativeClampsToZero() { XCTAssertEqual(ProgressRow.clock(-5), "0:00") }

    func testNonFiniteShowsPlaceholder() {
        XCTAssertEqual(ProgressRow.clock(.infinity), ProgressRow.placeholder)
        XCTAssertEqual(ProgressRow.clock(-.infinity), ProgressRow.placeholder)
        XCTAssertEqual(ProgressRow.clock(.nan), ProgressRow.placeholder)
        XCTAssertEqual(ProgressRow.placeholder, "–:––")
    }

    func testAbsurdlyLargeShowsPlaceholder() {
        // Endlich, aber jenseits von Int: ohne Grenze stürzte Int(...) ab.
        XCTAssertEqual(ProgressRow.clock(1e300), ProgressRow.placeholder)
        XCTAssertEqual(ProgressRow.clock(NowPlayingInfo.maxDuration + 1), ProgressRow.placeholder)
    }
}
