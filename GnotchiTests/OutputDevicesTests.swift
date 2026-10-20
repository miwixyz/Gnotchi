import CoreAudio
import XCTest
@testable import Gnotchi

/// 0.2.0 Audio-Ausgang wählen: Art und Symbol je Übertragungsart, Reihenfolge im Menü,
/// nur Geräte aus der aktuellen Liste dürfen gesetzt werden (SECURE-DESIGN G20).
final class OutputDevicesTests: XCTestCase {

    private func device(_ id: AudioObjectID, _ name: String, _ transport: UInt32) -> OutputDevices.Device {
        OutputDevices.Device(id: id, name: name, transport: transport)
    }

    func testKindFromTransport() {
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeBuiltIn), .builtIn)
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeBluetooth), .bluetooth)
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeBluetoothLE), .bluetooth)
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeAirPlay), .airPlay)
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeHDMI), .display)
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeDisplayPort), .display)
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeUSB), .usb)
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeVirtual), .virtual)
        XCTAssertEqual(OutputDevices.kind(transport: kAudioDeviceTransportTypeAggregate), .virtual)
        XCTAssertEqual(OutputDevices.kind(transport: 0), .other)
    }

    func testSymbols() {
        XCTAssertEqual(OutputDevices.Kind.bluetooth.symbol, "headphones")
        XCTAssertEqual(OutputDevices.Kind.airPlay.symbol, "airplayaudio")
        XCTAssertEqual(OutputDevices.Kind.display.symbol, "tv")
        XCTAssertEqual(OutputDevices.Kind.builtIn.symbol, "speaker.wave.2")
    }

    /// Eingebaut zuerst, dann alphabetisch (ohne Groß-/Kleinschreibung) – stabil, egal wie Core Audio sortiert.
    func testMenuOrder() {
        let list = [device(5, "Zimmer", kAudioDeviceTransportTypeAirPlay),
                    device(2, "beispiel-kopfhörer", kAudioDeviceTransportTypeBluetooth),
                    device(9, "Mac mini-Lautsprecher", kAudioDeviceTransportTypeBuiltIn),
                    device(3, "Anzeige", kAudioDeviceTransportTypeHDMI)]
        XCTAssertEqual(OutputDevices.ordered(list).map(\.id), [9, 3, 2, 5])
    }

    func testOnlyListedDevicesCanBeSelected() {
        let list = [device(9, "Lautsprecher", kAudioDeviceTransportTypeBuiltIn)]
        XCTAssertTrue(OutputDevices.canSelect(9, in: list))
        XCTAssertFalse(OutputDevices.canSelect(4, in: list), "Gerät inzwischen weg")
        XCTAssertFalse(OutputDevices.canSelect(kAudioObjectUnknown, in: list))
    }

    /// Gerätenamen vergibt der Nutzer frei: bereinigt und gekürzt wie beim Wiedergabeweg.
    func testNamesAreCleaned() {
        XCTAssertEqual(OutputDevices.cleanName("  Wohnzimmer  "), "Wohnzimmer")
        XCTAssertEqual(OutputDevices.cleanName(String(repeating: "x", count: 100))?.count, AudioRoute.maxNameLength)
        XCTAssertNil(OutputDevices.cleanName(""))
        XCTAssertNil(OutputDevices.cleanName(nil))
    }
}
