import XCTest
@testable import Gnotchi

/// Warnton-Lautstärke (0.33.0, G57): feste Skripte, begrenzter Wert, Vorrang des letzten Werts.
@MainActor
final class SystemAlertVolumeTests: XCTestCase {
    func testClampKeepsValueInZeroToHundred() {
        XCTAssertEqual(SystemAlertVolume.clamp(-5), 0)
        XCTAssertEqual(SystemAlertVolume.clamp(0), 0)
        XCTAssertEqual(SystemAlertVolume.clamp(57), 57)
        XCTAssertEqual(SystemAlertVolume.clamp(100), 100)
        XCTAssertEqual(SystemAlertVolume.clamp(9_999), 100)
        XCTAssertEqual(SystemAlertVolume.clamp(Int.max), 100)
        XCTAssertEqual(SystemAlertVolume.clamp(Int.min), 0)
    }

    func testSetScriptContainsOnlyTheClampedNumber() {
        let s = SystemAlertVolume.setScript(250)
        XCTAssertTrue(s.contains("set volume alert volume 100"))
        XCTAssertFalse(s.contains("250"))
        XCTAssertTrue(s.contains("with timeout of 3 seconds"))
        XCTAssertTrue(SystemAlertVolume.setScript(-3).contains("alert volume 0\n"))
    }

    func testScriptsTargetNoApplication() {
        // Kein „tell application“: Es gibt keinen Automation-Dialog und kein Zielprogramm.
        XCTAssertFalse(SystemAlertVolume.readScript.contains("tell application"))
        XCTAssertFalse(SystemAlertVolume.setScript(40).contains("tell application"))
        XCTAssertFalse(SystemAlertVolume.setScript(40).contains("do shell script"))
    }

    func testReadingRealSystemGivesPercent() async throws {
        // Nur lesend. Am echten System: macOS meldet eine Zahl von 0 bis 100.
        let value = await SystemAlertVolume.read()
        let v = try XCTUnwrap(value, "macOS meldet keine Warnton-Lautstärke")
        XCTAssertTrue((0...100).contains(v))
    }

    /// Sammelt, was das Modell setzen wollte – ohne die echte Warnton-Lautstärke des Macs anzufassen.
    private actor Recorder {
        private(set) var values: [Int] = []
        func add(_ v: Int) { values.append(v) }
    }

    private func model(_ recorder: Recorder) -> MixerModel {
        MixerModel(interval: .seconds(3600), defaults: throwawayDefaults("gnotchi-alerttest"),
                   alertSetter: { await recorder.add($0); return true })
    }

    func testModelClampsAndKeepsLatestValue() {
        let model = model(Recorder())
        XCTAssertNil(model.alertVolume)
        model.setAlertVolume(500)
        XCTAssertEqual(model.alertVolume, 100)
        model.setAlertVolume(-1)
        XCTAssertEqual(model.alertVolume, 0)
    }

    func testDraggingSendsOnlyClampedValuesAndEndsOnLatest() async throws {
        let recorder = Recorder()
        let model = model(recorder)
        for v in [10, 20, 30, 400, -7, 55] { model.setAlertVolume(v) }
        try await Task.sleep(for: .milliseconds(300))
        let sent = await recorder.values
        XCTAssertEqual(sent.last, 55, "der letzte Wert gewinnt")
        XCTAssertTrue(sent.allSatisfy { (0...100).contains($0) })
        XCTAssertLessThanOrEqual(sent.count, 6)
        XCTAssertEqual(model.alertVolume, 55)
    }
}
