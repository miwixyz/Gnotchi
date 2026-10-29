import CoreAudio
import XCTest

/// Regression 21.10. (Ressourcenfund): Jede Geräteänderung meldete „Geräteliste geändert“ viermal so
/// oft wie die vorige, weil `devicesChanged` die System-Beobachter im eigenen Rückruf ab- und neu
/// anmeldete. Core Audio rief die alten weiter auf (Abmelden meldete trotzdem `noErr`).
/// Echte Geräteänderung: ein öffentliches Aggregat-Gerät kurz anlegen und wieder entfernen.
@MainActor
final class PrivacyMonitorListenerTests: XCTestCase {

    private func toggleAggregateDevice() async throws {
        let desc: [String: Any] = [kAudioAggregateDeviceUIDKey: "dev.mwlr.gnotchi.test.\(UUID().uuidString)",
                                   kAudioAggregateDeviceNameKey: "Gnotchi-Test (wird entfernt)",
                                   kAudioAggregateDeviceIsPrivateKey: 0]
        var device: AudioObjectID = 0
        guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &device) == noErr else {
            throw XCTSkip("Aggregat-Gerät lässt sich hier nicht anlegen")
        }
        try await Task.sleep(for: .milliseconds(400))
        AudioHardwareDestroyAggregateDevice(device)
        try await Task.sleep(for: .milliseconds(400))
    }

    func testDeviceChangesDoNotMultiplyNotifications() async throws {
        let monitor = PrivacyMonitor(activity: ActivityModel(media: NowPlayingModel()))
        monitor.start()
        defer { monitor.stop() }
        for _ in 0..<5 { try await toggleAggregateDevice() }
        // Gemessen 21.10. mit Fehler: 3 + 12 + 48 + 192 + 768. Ohne: etwa 2–3 je Änderung.
        XCTAssertLessThanOrEqual(monitor.devicesChangedCount, 30,
                                 "„Geräteliste geändert“ \(monitor.devicesChangedCount)-mal nach 5 Geräteänderungen")
    }
}
