import XCTest
@testable import Gnotchi

/// Security-Review 18.10. (B3/B4): höchstens ein Befehl bzw. ein Cover-Dekodieren gleichzeitig.
final class SingleFlightTests: XCTestCase {

    // MARK: OneAtATime – Adapter-Befehle: weitere Klicks verwerfen, solange einer läuft

    func testSecondCommandDroppedWhileFirstRuns() {
        var gate = OneAtATime()
        XCTAssertTrue(gate.tryStart())
        XCTAssertFalse(gate.tryStart())
        XCTAssertFalse(gate.tryStart())
        gate.finish()
        XCTAssertTrue(gate.tryStart())
    }

    // MARK: LatestWins – Cover: eins in Arbeit, nur das neueste wartet

    func testFirstStartsImmediately() {
        var f = LatestWins<String>()
        XCTAssertEqual(f.submit("A"), "A")
        XCTAssertTrue(f.running)
    }

    func testNewestWaitingReplacesOlder() {
        var f = LatestWins<String>()
        _ = f.submit("A")
        XCTAssertNil(f.submit("B"))
        XCTAssertNil(f.submit("C"))
        XCTAssertEqual(f.finish(), "C")     // B verworfen, C startet
        XCTAssertTrue(f.running)
        XCTAssertNil(f.finish())             // nichts wartet → frei
        XCTAssertFalse(f.running)
        XCTAssertEqual(f.submit("D"), "D")
    }
}
