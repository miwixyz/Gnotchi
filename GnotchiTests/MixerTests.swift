import CoreAudio
import SwiftUI
import XCTest

/// 0.30.0 Mixer (G54): Gruppierung der Apps mit Ton, Prozentrechnung, Ablauf mit Attrappen, Gerätearten.
@MainActor
final class MixerTests: XCTestCase {

    private func proc(_ pid: pid_t, _ path: String?, bundle: String? = nil, out: Bool = true, devices: [UInt32] = [1]) -> MixerAudio.Process {
        MixerAudio.Process(pid: pid, bundleID: bundle, path: path, outputting: out, devices: devices)
    }

    fileprivate let speakers = OutputDevices.Device(id: 1, name: "MacBook Air-Lautsprecher", transport: kAudioDeviceTransportTypeBuiltIn)
    fileprivate let buds = OutputDevices.Device(id: 2, name: "AirPods", transport: kAudioDeviceTransportTypeBluetooth)
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

// Mixer Stufe 2 (G55): Zeilen für den Tap, Einrasten, Einstellung – ohne echten Tap.
extension MixerTests {
    func testRowCanTapOnlyOnExactlyOneKnownDevice() {
        var proc = MixerAudio.Process(object: 77, pid: 10, bundleID: nil, path: "/Applications/Helium.app/Contents/MacOS/Helium",
                                      outputting: true, devices: [1])
        let one = MixerRows.rows([proc], devices: [1: speakers, 2: buds], ownPID: 999,
                                 name: { _ in "Helium" }, bundle: { _ in nil }, uid: { $0 == 1 ? "SPEAKER-UID" : "BUDS-UID" })
        XCTAssertEqual(one.first?.processes, [77])
        XCTAssertEqual(one.first?.deviceUID, "SPEAKER-UID")
        XCTAssertEqual(one.first?.canTap, true)
        proc = MixerAudio.Process(object: 77, pid: 10, bundleID: nil, path: "/Applications/Helium.app/Contents/MacOS/Helium",
                                  outputting: true, devices: [1, 2])
        let two = MixerRows.rows([proc], devices: [1: speakers, 2: buds], ownPID: 999,
                                 name: { _ in "Helium" }, bundle: { _ in nil }, uid: { _ in "X" })
        XCTAssertEqual(two.first?.canTap, false, "zwei Geräte: kein Regler (zu unsicher, wohin der Ton muss)")
    }

    func testSliderSnapsToHundredAndClamps() {
        XCTAssertEqual(MixerRows.snap(98), 100)
        XCTAssertEqual(MixerRows.snap(103), 100)
        XCTAssertEqual(MixerRows.snap(96), 96)
        XCTAssertEqual(MixerRows.snap(250), 200)
        XCTAssertEqual(MixerRows.snap(-5), 0)
    }

    func testAppVolumeIsOffByDefaultAndTapsNeedTheSetting() async {
        let model = MixerModel(interval: .seconds(3600))
        XCTAssertFalse(model.appVolumeEnabled, "ab Werk aus: keine Taps, keine Freigabe-Anfrage")
        let row = MixerAppRow(id: "/Applications/Helium.app", name: "Helium", bundleID: nil, devices: [speakers], volume: nil,
                              processes: [77], deviceUID: "SPEAKER-UID", gain: 1)
        model.setAppGain(row, percent: 50)   // Einstellung aus → nichts passiert
        XCTAssertFalse(model.engine.hasTaps)
    }

    func testDisablingTheSettingReleasesEverything() {
        let model = MixerModel(interval: .seconds(3600))
        model.setAppVolumeEnabled(true)
        model.setAppVolumeEnabled(false)
        XCTAssertFalse(model.engine.hasTaps)
        XCTAssertFalse(model.appVolumeEnabled)
    }

    func testPreferenceAppVolumeOffByDefaultAndPersisted() {
        let defaults = UserDefaults(suiteName: "dev.mwlr.gnotchi.tests.appvol")!
        defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.appvol")
        defer { defaults.removePersistentDomain(forName: "dev.mwlr.gnotchi.tests.appvol") }
        let p = Preferences(defaults: defaults)
        XCTAssertFalse(p.appVolume)
        p.appVolume = true
        XCTAssertTrue(Preferences(defaults: defaults).appVolume)
    }

    // MARK: Tap-Motor-Zustand (ohne Core Audio)

    func testEngineHundredPercentNeverBuildsATap() {
        let engine = AppTapEngine()
        engine.setGain(1.0, for: .init(appID: "a", processes: [1], deviceUID: "UID"))
        engine.setGain(1.004, for: .init(appID: "a", processes: [1], deviceUID: "UID"))
        XCTAssertFalse(engine.hasTaps, "100 % bedeutet: kein Tap, die App spielt direkt")
        XCTAssertEqual(engine.gain(for: "a"), 1)
    }

    func testEngineBogusTargetFailsCleanlyAndLeavesAppAlone() {
        let engine = AppTapEngine()
        engine.setGain(0.5, for: .init(appID: "a", processes: [999_999], deviceUID: "gibt-es-nicht"))
        XCTAssertFalse(engine.hasTaps, "kein Tap angelegt")
        if case .setup = engine.failures["a"] { } else { XCTFail("Fehler muss sichtbar sein, nicht still") }
        XCTAssertEqual(engine.gain(for: "a"), 1)
        engine.setGain(1.0, for: .init(appID: "a", processes: [999_999], deviceUID: "gibt-es-nicht"))
        XCTAssertNil(engine.failures["a"], "zurück auf 100 % löscht den Fehler")
    }

    func testDeviceChangeWithoutTapsDoesNothing() {
        let engine = AppTapEngine()
        engine.devicesChanged()
        engine.processesChanged()
        XCTAssertFalse(engine.hasTaps)
    }

    func testGainCellRampsFromLastToTarget() {
        let cell = GainCell()
        XCTAssertEqual(cell.ramp().0, 1)
        cell.set(0.25)
        let (a, b) = cell.ramp()
        XCTAssertEqual(a, 1)
        XCTAssertEqual(b, 0.25)
        XCTAssertEqual(cell.ramp().0, 0.25, "nächster Puffer startet beim letzten Ziel")
        XCTAssertFalse(cell.sawSignal)
        cell.noteSignal()
        XCTAssertTrue(cell.sawSignal)
    }
}

extension MixerTests {
    func testOwnDeviceChangeWithinQuietTimeIsIgnored() {
        let now = Date()
        XCTAssertTrue(AppTapEngine.shouldReact(now: now, lastOwnChange: nil), "ohne eigene Änderung: reagieren")
        XCTAssertFalse(AppTapEngine.shouldReact(now: now, lastOwnChange: now.addingTimeInterval(-0.3)), "eigenes Aggregat meldet sich selbst")
        XCTAssertTrue(AppTapEngine.shouldReact(now: now, lastOwnChange: now.addingTimeInterval(-2)), "später: echter Gerätewechsel")
    }
}

// Mixer in der Insel (0.30.0): Ring-Taste, große Ansicht, gemeinsame Abfrage mit dem Popover.
extension MixerTests {
    func testMixerRingButtonIsOnTheRightAlwaysAvailableAndOnByDefault() {
        XCTAssertEqual(RingButton.mixer.side, .right)
        XCTAssertTrue(RingButton.mixer.onByDefault)
        let activity = ActivityModel(media: NowPlayingModel())
        XCTAssertTrue(activity.ringAvailable.contains(.mixer))
        XCTAssertTrue(activity.ringButtons.contains(.mixer), "ab Werk im Ring")
    }

    func testSelectingMixerShowsItBigAndOtherViewsClearIt() {
        let activity = ActivityModel(media: NowPlayingModel())
        activity.ringTap(.mixer)
        XCTAssertEqual(activity.bigContent, .mixer)
        XCTAssertTrue(activity.ringSelected(.mixer))
        activity.selectSpeedtest()
        XCTAssertFalse(activity.mixerActive, "Geschwindigkeitstest ersetzt den Mixer")
        activity.ringTap(.mixer)
        activity.select(.media)
        XCTAssertFalse(activity.mixerActive, "andere Ansicht → Mixer zu")
        XCTAssertNotEqual(activity.bigContent, .mixer)
    }

    func testIslandAndPopoverShareOnePollingLoop() {
        let model = MixerModel(interval: .seconds(3600))
        model.setVisible("popover", true)
        model.setVisible("insel", true)
        XCTAssertTrue(model.isPolling)
        model.setVisible("popover", false)
        XCTAssertTrue(model.isPolling, "die Insel zeigt ihn noch")
        model.setVisible("insel", false)
        XCTAssertFalse(model.isPolling, "niemand zeigt ihn: keine Abfrage")
    }

    func testMixerBigViewGetsItsOwnHeight() {
        XCTAssertEqual(IslandController.tallHeight(.mixer), IslandGeometry.mixerHeight)
        XCTAssertGreaterThan(IslandGeometry.mixerHeight, IslandGeometry.clipboardHeight)
    }

    func testRenderMixerInIslandPicture() throws {
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let speakers = OutputDevices.Device(id: 1, name: "MacBook Air-Lautsprecher", transport: kAudioDeviceTransportTypeBuiltIn)
        let buds = OutputDevices.Device(id: 2, name: "Michaels AirPods", transport: kAudioDeviceTransportTypeBluetooth)
        let mic = OutputDevices.Device(id: 4, name: "MacBook Air-Mikrofon", transport: kAudioDeviceTransportTypeBuiltIn)
        let model = MixerModel(interval: .seconds(3600))
        model.setPreview(
            output: .init(device: speakers, volume: 0.56, muted: false, canSetVolume: true, canMute: true), systemOutput: speakers,
            input: .init(device: mic, volume: 0.5, muted: false, canSetVolume: true, canMute: true),
            outputs: [speakers, buds], inputs: [mic],
            apps: [MixerAppRow(id: "/Applications/Spotify.app", name: "Spotify", bundleID: "com.spotify.client", devices: [buds], volume: 70),
                   MixerAppRow(id: "/Applications/Helium.app", name: "Helium", bundleID: nil, devices: [speakers], volume: nil,
                               processes: [9], deviceUID: "UID", gain: 0.5)])
        model.setAppVolumeEnabled(true)
        let view = MixerView(model: model, wide: true).padding(12).frame(width: 600, height: IslandGeometry.mixerHeight)
            .background(Color(white: 0.18)).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: IslandGeometry.mixerHeight)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("gnotchi-mixer-insel.png"), options: .atomic)
        model.setAppVolumeEnabled(false)
    }

    func testEngineRefusesAnEmptyTarget() {
        let engine = AppTapEngine()
        engine.setGain(0.5, for: .init(appID: "a", processes: [], deviceUID: "UID"))
        XCTAssertEqual(engine.failures["a"], .noTarget)
        XCTAssertFalse(engine.hasTaps)
    }
}

// Zwischenspeicher der Automation-Erlaubnis (Fund 15.11.): nie blockierend auf dem Hauptthread.
extension MixerTests {
    func testAutomationStatusNeverBlocksTheCaller() {
        // Die Systemabfrage blockierte im Test länger als 2 s und am 15.11. zweimal dauerhaft: Der Aufrufer darf nie darauf warten.
        let start = Date()
        for _ in 0..<50 { _ = AutomationStatus.shared.isAllowed(AppleScriptSource.spotify) }
        AutomationStatus.shared.refresh()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, "isAllowed/refresh kehren sofort zurück")
    }

    func testUnknownAppIsNeverAllowed() {
        XCTAssertFalse(AutomationStatus.shared.isAllowed("evil.app"))
    }
}
