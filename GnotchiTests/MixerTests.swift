import CoreAudio
import SwiftUI
import XCTest

/// 0.30.0 Mixer (G54): Gruppierung der Apps mit Ton, Prozentrechnung, Ablauf mit Attrappen, Gerätearten.
@MainActor
final class MixerTests: XCTestCase {

    private func proc(_ pid: pid_t, _ path: String?, bundle: String? = nil, out: Bool = true, devices: [UInt32] = [1]) -> MixerAudio.Process {
        MixerAudio.Process(pid: pid, bundleID: bundle, path: path, outputting: out, devices: devices)
    }

    private let speakers = OutputDevices.Device(id: 1, name: "MacBook Air-Lautsprecher", transport: kAudioDeviceTransportTypeBuiltIn)
    private let buds = OutputDevices.Device(id: 2, name: "AirPods", transport: kAudioDeviceTransportTypeBluetooth)
    private let tv = OutputDevices.Device(id: 3, name: "Wohnzimmer", transport: kAudioDeviceTransportTypeAirPlay)

    private func rows(_ p: [MixerAudio.Process], own: pid_t = 999) -> [MixerAppRow] {
        MixerRows.rows(p, devices: [1: speakers, 2: buds, 3: tv], ownPID: own,
                       name: { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") },
                       bundle: { "id." + (($0 as NSString).lastPathComponent) })
    }

    func testOneRowPerAppNotPerProcess() {
        let r = rows([proc(10, "/Applications/Helium.app/Contents/Frameworks/X.framework/Helium Helper.app/Contents/MacOS/Helium Helper"),
                      proc(11, "/Applications/Helium.app/Contents/MacOS/Helium")])
        XCTAssertEqual(r.map(\.name), ["Helium"], "zwei Prozesse, eine Zeile")
    }

    func testOnlyOutputtingProcessesInsideAnApp() {
        let r = rows([proc(10, "/Applications/Spotify.app/Contents/MacOS/Spotify", out: false),
                      proc(11, "/usr/libexec/audiomxd"),                      // Systemdienst, keine App
                      proc(12, "/Applications/Musik.app/Contents/MacOS/Musik")])
        XCTAssertEqual(r.map(\.name), ["Musik"])
    }

    func testOwnProcessIsLeftOut() {
        XCTAssertTrue(rows([proc(999, "/Applications/Gnotchi.app/Contents/MacOS/Gnotchi")]).isEmpty)
    }

    func testDevicesAreJoinedAndNamedWithKind() {
        let r = rows([proc(10, "/Applications/A.app/Contents/MacOS/A", devices: [1]),
                      proc(11, "/Applications/A.app/Contents/MacOS/A", devices: [1, 2])])
        XCTAssertEqual(r.first?.devices.map(\.name), ["MacBook Air-Lautsprecher", "AirPods"], "vereinigt, ohne Doppelte")
        XCTAssertEqual(r.first?.devices.map(\.kind), [.builtIn, .bluetooth])
    }

    func testUnknownDeviceIsSkippedNotCrashed() {
        let r = rows([proc(10, "/Applications/A.app/Contents/MacOS/A", devices: [77])])
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r[0].devices.isEmpty)
    }

    func testRowsAreSortedByNameAndCapped() {
        let many = (0..<20).map { proc(pid_t(100 + $0), "/Applications/App\(String(format: "%02d", 19 - $0)).app/Contents/MacOS/x") }
        let r = rows(many)
        XCTAssertEqual(r.count, MixerRows.maxRows)
        XCTAssertEqual(r.first?.name, "App00")
    }

    func testPercent() {
        XCTAssertEqual(MixerRows.percent(0.4375), 44)
        XCTAssertEqual(MixerRows.percent(1.7), 100)
        XCTAssertEqual(MixerRows.percent(-1), 0)
        XCTAssertNil(MixerRows.percent(nil))
    }

    func testAirPlayAndBluetoothHaveOwnSymbols() {
        XCTAssertEqual(airplay.kind.symbol, "airplayaudio")
        XCTAssertEqual(buds.kind.symbol, "headphones")
        XCTAssertEqual(speakers.kind, .builtIn)
    }

    private var airplay: OutputDevices.Device { tv }

    func testReadingRealSystemDoesNotCrash() async {
        // Am echten System: Standardgeräte und Prozessliste lesen (nur lesend). Ergebnis hängt vom Mac ab.
        let model = MixerModel(interval: .seconds(3600))
        await model.refresh()
        XCTAssertFalse(model.outputs.isEmpty, "jeder Mac hat mindestens ein Ausgabegerät")
        if let v = model.output.volume { XCTAssertTrue((0...1).contains(v)) }
    }

    func testStartStopIsIdempotent() {
        let model = MixerModel(interval: .seconds(3600))
        model.start()
        model.start()
        model.stop()
        model.stop()
    }
}

// Bild des Mixers (nur mit GNOTCHI_RENDER_DIR): NSHostingView statt ImageRenderer, damit Regler und Menüs (AppKit) mitgezeichnet werden.
extension MixerTests {
    func testRenderMixerPicture() throws {
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let speakers = OutputDevices.Device(id: 1, name: "MacBook Air-Lautsprecher", transport: kAudioDeviceTransportTypeBuiltIn)
        let buds = OutputDevices.Device(id: 2, name: "Michaels AirPods", transport: kAudioDeviceTransportTypeBluetooth)
        let tv = OutputDevices.Device(id: 3, name: "Wohnzimmer", transport: kAudioDeviceTransportTypeAirPlay)
        let mic = OutputDevices.Device(id: 4, name: "MacBook Air-Mikrofon", transport: kAudioDeviceTransportTypeBuiltIn)
        let model = MixerModel(interval: .seconds(3600))
        model.setPreview(
            output: .init(device: speakers, volume: 0.56, muted: false, canSetVolume: true, canMute: true),
            systemOutput: speakers,
            input: .init(device: mic, volume: 0.5, muted: false, canSetVolume: true, canMute: true),
            outputs: [speakers, buds, tv], inputs: [mic],
            apps: [MixerAppRow(id: "/Applications/Spotify.app", name: "Spotify", bundleID: "com.spotify.client", devices: [buds], volume: 70),
                   MixerAppRow(id: "/Applications/Helium.app", name: "Helium", bundleID: nil, devices: [speakers], volume: nil),
                   MixerAppRow(id: "/Applications/Musik.app", name: "Musik", bundleID: "com.apple.Music", devices: [tv], volume: 40)])
        let host = NSHostingView(rootView: MixerView(model: model).padding(14).frame(width: 360).background(Color(white: 0.95)))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("gnotchi-mixer.png"), options: .atomic)
    }
}

// Bild des Popovers (nur mit GNOTCHI_RENDER_DIR): beide Reiter, echtes AppModel ohne Start; der Mixer liest den echten Mac.
extension MixerTests {
    func testRenderPopoverPictures() async throws {
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        for tab in ["mixer", "functions"] {
            UserDefaults.standard.set(tab, forKey: "popoverTab")
            let model = AppModel(prefs: Preferences(defaults: UserDefaults(suiteName: "dev.mwlr.gnotchi.tests.popover")!), allowStart: false)
            let mixer = MixerModel(interval: .seconds(3600))
            await mixer.refresh()
            let host = NSHostingView(rootView: PopoverContent(mixer: mixer).environment(model).background(Color(white: 0.95)))
            host.frame = NSRect(x: 0, y: 0, width: 360, height: 700)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            for _ in 0..<6 {   // Messung der Inhaltshöhe und Neuaufbau abwarten
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
            }
            let size = host.fittingSize
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("gnotchi-popover-\(tab).png"), options: .atomic)
        }
        UserDefaults.standard.removeObject(forKey: "popoverTab")
    }
}
