import XCTest

/// Dünner Fortschrittsbalken (Michael, 18.10.): Mausposition → Sekunden, Füllstand.
final class ProgressRowScrubTests: XCTestCase {

    // MARK: seconds(atX:width:upper:)

    func testMapsLinearly() {
        XCTAssertEqual(ProgressRow.seconds(atX: 50, width: 200, upper: 225), 56.25)
        XCTAssertEqual(ProgressRow.seconds(atX: 0, width: 200, upper: 225), 0)
        XCTAssertEqual(ProgressRow.seconds(atX: 200, width: 200, upper: 225), 225)
    }

    /// Ziehen über den Rand hinaus: festhalten am Anfang bzw. Ende, nie darüber.
    func testClampsOutsideTrack() {
        XCTAssertEqual(ProgressRow.seconds(atX: -30, width: 200, upper: 225), 0)
        XCTAssertEqual(ProgressRow.seconds(atX: 260, width: 200, upper: 225), 225)
    }

    /// Unbrauchbare Werte (Balken noch ohne Breite, NaN) ergeben 0 statt eines Absturzes oder NaN.
    func testDegenerateInputsGiveZero() {
        XCTAssertEqual(ProgressRow.seconds(atX: 10, width: 0, upper: 225), 0)
        XCTAssertEqual(ProgressRow.seconds(atX: .nan, width: 200, upper: 225), 0)
        XCTAssertEqual(ProgressRow.seconds(atX: 10, width: .infinity, upper: 225), 0)
        XCTAssertEqual(ProgressRow.seconds(atX: 10, width: 200, upper: .infinity), 0)
        XCTAssertEqual(ProgressRow.seconds(atX: 10, width: 200, upper: -5), 0)
    }

    // MARK: Display.fraction

    func testFractionWithDuration() {
        XCTAssertEqual(ProgressRow.display(elapsed: 90, duration: 180).fraction, 0.5)
    }

    /// Livestream ohne Dauer: leerer Balken (vorher stand der gesperrte Regler nach 1 s am Ende).
    func testFractionWithoutDurationIsEmpty() {
        XCTAssertEqual(ProgressRow.display(elapsed: 125, duration: nil).fraction, 0)
    }

    func testFractionClamped() {
        XCTAssertEqual(ProgressRow.display(elapsed: 300, duration: 180).fraction, 1)
        XCTAssertEqual(ProgressRow.display(elapsed: -4, duration: 180).fraction, 0)
    }
}
