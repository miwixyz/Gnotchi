import SwiftUI
import XCTest

/// Absturz 22.10., 13:14 (`Normalizing.init` → precondition): Der VoiceOver-Regler im Fortschrittsbalken bekam bei
/// Wiedergabe ohne Dauer den Bereich 0…1 mit Schritt 10. Gemessen: Schritt größer als Bereich bricht ab.
/// Dieser Test baut genau diese Regler – vor dem Fix beendete er den Testlauf mit SIGTRAP.
@MainActor
final class ProgressRowSliderTests: XCTestCase {

    func testStepNeverExceedsRange() {
        for duration in [nil, 0.5, 1, 5, 9.9, 10, 724, .infinity, -3] as [TimeInterval?] {
            let d = ProgressRow.display(elapsed: 0, duration: duration)
            let step = ProgressRow.accessibilityStep(upper: d.sliderUpper)
            XCTAssertGreaterThan(step, 0)
            XCTAssertLessThanOrEqual(step, d.sliderUpper, "Dauer \(String(describing: duration))")
            _ = Slider(value: .constant(d.sliderValue), in: 0...d.sliderUpper, step: step)   // stürzte vorher ab
        }
        XCTAssertEqual(ProgressRow.accessibilityStep(upper: 724), ProgressRow.accessibilityStep, "lange Titel wie bisher 10 s")
    }
}
