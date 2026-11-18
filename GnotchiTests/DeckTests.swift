import CoreAudio
import XCTest

/// 0.35.0 Stream Deck (G59): Nachrichtenformat, gemerkte Lautstärken, Reglerschritte, Lauftext.
@MainActor
final class DeckTests: XCTestCase {

    /// Testdaten sind immer gültiges JSON; scheitert es doch, liefern leere Daten einen roten Test statt eines Absturzes.
    private func data(_ obj: Any) -> Data { (try? JSONSerialization.data(withJSONObject: obj)) ?? Data() }

    // MARK: DeckWire.parse – nur die feste Befehlsliste

    func testParsesValidCommands() {
        XCTAssertEqual(DeckWire.parse(data(["v": 1, "hello": "0.35.0"])), .hello(version: "0.35.0"))
        XCTAssertEqual(DeckWire.parse(data(["v": 1, "watch": ["current", "com.spotify.client"]])),
                       .watch(["current", "com.spotify.client"]))
        XCTAssertEqual(DeckWire.parse(data(["v": 1, "cmd": "gain", "app": "net.imput.helium", "delta": -4])),
                       .gain(app: "net.imput.helium", delta: -4))
        XCTAssertEqual(DeckWire.parse(data(["v": 1, "cmd": "mute", "app": "current"])), .mute(app: "current"))
        XCTAssertEqual(DeckWire.parse(data(["v": 1, "cmd": "play", "app": "com.apple.Music", "what": "next"])),
                       .play(app: "com.apple.Music", what: .next))
    }

    func testRejectsEverythingElse() {
        let bad: [Any] = [
            ["v": true, "cmd": "mute", "app": "current"],                       // v als Wahrheitswert
            ["v": 2, "cmd": "mute", "app": "current"],                          // falsche Version
            ["v": 1, "cmd": "gain", "app": "current", "delta": 21],             // über der Grenze
            ["v": 1, "cmd": "gain", "app": "current", "delta": 1.5],            // keine ganze Zahl
            ["v": 1, "cmd": "gain", "app": "current", "delta": true],           // Wahrheitswert statt Zahl
            ["v": 1, "cmd": "play", "app": "current", "what": "seek"],          // kein erlaubter Befehl
            ["v": 1, "cmd": "open", "app": "current"],                          // unbekannt
            ["v": 1, "cmd": "mute", "app": "../../etc"],                        // kein gültiger App-Wert
            ["v": 1, "cmd": "mute", "app": "com.evil\nx"],
            ["v": 1, "cmd": "mute", "app": ""],
            ["v": 1, "watch": Array(repeating: "current", count: 9)],           // zu viele
            ["v": 1, "watch": ["current", 3]],                                  // falscher Typ in der Liste
            ["v": 1, "hello": String(repeating: "x", count: 33)],
            ["cmd": "mute", "app": "current"],                                  // ohne v
        ]
        for b in bad { XCTAssertNil(DeckWire.parse(data(b)), "\(b)") }
        XCTAssertNil(DeckWire.parse(Data("kein json".utf8)))
        // Größer als ein Befehl sein darf → abgelehnt, auch wenn das JSON gültig wäre.
        let big = data(["v": 1, "cmd": "mute", "app": "current", "pad": String(repeating: "a", count: 600)])
        XCTAssertNil(DeckWire.parse(big))
    }

    func testWatchListDropsDuplicates() {
        XCTAssertEqual(DeckWire.parse(data(["v": 1, "watch": ["current", "current", "com.apple.Music"]])),
                       .watch(["current", "com.apple.Music"]))
    }

    func testEncodedCommandsParseBack() {
        let all: [DeckWire.Command] = [.hello(version: "1"), .watch(["current"]), .gain(app: "current", delta: 20),
                                       .mute(app: "com.apple.Music"), .play(app: "current", what: .previous)]
        for c in all { XCTAssertEqual(DeckWire.parse(data(DeckWire.encode(c))), c) }
    }

    // MARK: Rückmeldung

    func testStatusRoundTripAndClamping() throws {
        let s = DeckWire.Status(app: "current", name: "Spotify", title: String(repeating: "T", count: 250), artist: "A\u{202E}B",
                                percent: 64, muted: false, playing: true, canPlay: true, state: .ok)
        let back = try XCTUnwrap(DeckWire.parseStatus(data(DeckWire.encode(s))))
        XCTAssertEqual(back.title?.count, DeckWire.maxTextChars)
        XCTAssertEqual(back.artist, "AB", "Richtungs-Override entfernt")
        XCTAssertEqual(back.percent, 64)
        XCTAssertEqual(back.state, .ok)
        var wild = DeckWire.encode(s)
        wild["percent"] = 999
        XCTAssertEqual(DeckWire.parseStatus(data(wild))?.percent, 200)
        wild["state"] = "hacked"
        XCTAssertNil(DeckWire.parseStatus(data(wild)))
    }

    func testAckAndChoices() {
        XCTAssertTrue(DeckWire.isAck(data(["v": 1, "ok": true])))
        XCTAssertFalse(DeckWire.isAck(data(["v": 1, "ok": false])))
        XCTAssertEqual(DeckWire.choices.map(\.name), ["Gerade spielend", "Spotify", "Musik", "Podcasts", "Safari", "Helium", "Edge", "Teams"])
        XCTAssertTrue(DeckWire.choices.allSatisfy { DeckWire.isValidApp($0.id) })
    }

    // MARK: Gemerkte Lautstärken

    func testMemoryValidation() {
        let raw: [String: Any] = ["net.imput.helium": 50, "com.apple.Safari": 100, "bad id": 40, "current": 30,
                                  "com.microsoft.edgemac": 250, "com.x": true, "com.y": 12.5, "com.z": 0]
        XCTAssertEqual(MixerMemory.validated(raw), ["net.imput.helium": 50, "com.z": 0])
        XCTAssertEqual(MixerMemory.validated("kaputt"), [:])
    }

    func testMemoryUpdateAndLimit() {
        var (m, o) = MixerMemory.updated([:], order: [], bundleID: "a.b", percent: 40)
        XCTAssertEqual(m, ["a.b": 40])
        (m, o) = MixerMemory.updated(m, order: o, bundleID: "a.b", percent: 100)
        XCTAssertEqual(m, [:], "100 % wird nicht gemerkt")
        for i in 0..<(MixerMemory.maxEntries + 3) {
            (m, o) = MixerMemory.updated(m, order: o, bundleID: "app.n\(i)", percent: 50)
        }
        XCTAssertEqual(m.count, MixerMemory.maxEntries)
        XCTAssertNil(m["app.n0"], "älteste fallen heraus")
        XCTAssertNotNil(m["app.n\(MixerMemory.maxEntries + 2)"])
    }

    func testMemoryNeverAutoAppliesNearSilence() {
        XCTAssertFalse(MixerMemory.shouldAutoApply(0))
        XCTAssertFalse(MixerMemory.shouldAutoApply(5))
        XCTAssertTrue(MixerMemory.shouldAutoApply(6))
        XCTAssertFalse(MixerMemory.shouldAutoApply(100))
    }

    func testMemoryPersistsInDefaults() throws {
        let suite = "deck-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        defaults.set(["net.imput.helium": 60], forKey: MixerMemory.key)
        let mixer = MixerModel(defaults: defaults)
        XCTAssertEqual(mixer.remembered, ["net.imput.helium": 60])
        mixer.forgetRemembered()
        XCTAssertEqual(mixer.remembered, [:])
        XCTAssertNil(defaults.object(forKey: MixerMemory.key))
    }

    private func row(_ path: String, bundle: String?, tap: Bool = true) -> MixerAppRow {
        var r = MixerAppRow(id: path, name: "x", bundleID: bundle,
                            devices: [OutputDevices.Device(id: 1, name: "L", transport: kAudioDeviceTransportTypeBuiltIn)], volume: nil)
        if tap { r.processes = [7]; r.deviceUID = "uid" }
        return r
    }

    func testRowsToRestoreRules() {
        let rows = [row("/A/Helium.app", bundle: "net.imput.helium"),
                    row("/A/Safari.app", bundle: "com.apple.Safari"),
                    row("/A/Edge.app", bundle: "com.microsoft.edgemac"),
                    row("/A/Spotify.app", bundle: "com.spotify.client"),
                    row("/A/Podcasts.app", bundle: "com.apple.podcasts", tap: false),
                    row("/A/Leise.app", bundle: "app.leise")]
        let memory = ["net.imput.helium": 50, "com.apple.Safari": 70, "com.microsoft.edgemac": 80, "com.spotify.client": 40,
                      "com.apple.podcasts": 60, "app.leise": 3]
        let picked = MixerModel.rowsToRestore(rows, remembered: memory, enabled: true,
                                              liveGain: { $0 == "/A/Safari.app" ? 0.7 : 1 },
                                              failed: { $0 == "/A/Edge.app" })
        XCTAssertEqual(picked.map(\.0.id), ["/A/Helium.app"],
                       "Safari läuft schon, Edge hatte einen Fehler, Spotify regelt AppleScript, Podcasts ohne Tap, 3 % nie automatisch")
        XCTAssertEqual(picked.first?.1, 50)
        XCTAssertTrue(MixerModel.rowsToRestore(rows, remembered: memory, enabled: false, liveGain: { _ in 1 }, failed: { _ in false }).isEmpty)
    }

    // MARK: Reglerschritte

    func testTapStepsLeaveTheHundredSnap() {
        XCTAssertEqual(DeckController.nextTapPercent(100, delta: 2), 104)
        XCTAssertEqual(DeckController.nextTapPercent(100, delta: -2), 96)
        XCTAssertEqual(DeckController.nextTapPercent(104, delta: -2), 102, "Rückweg rastet im Mixer auf 100 ein")
        XCTAssertEqual(DeckController.nextTapPercent(198, delta: 4), 200)
        XCTAssertEqual(DeckController.nextTapPercent(2, delta: -4), 0)
        XCTAssertEqual(DeckController.nextTapPercent(100, delta: 0), 100)
        XCTAssertEqual(DeckController.percent(0.645), 65)
    }

    // MARK: Lauftext

    func testShortTextStandsStill() {
        var m = Marquee(view: 176, step: 3, holdTicks: 2)
        m.set(key: "Kurz", contentWidth: 120)
        XCTAssertFalse(m.scrolls)
        XCTAssertFalse(m.tick())
        XCTAssertEqual(m.offset, 0)
    }

    func testLongTextHoldsThenScrollsPixelwiseAndLoops() {
        var m = Marquee(view: 100, step: 3, holdTicks: 2, gap: 40)
        m.set(key: "Lang", contentWidth: 200)
        XCTAssertTrue(m.scrolls)
        XCTAssertFalse(m.tick()); XCTAssertFalse(m.tick())   // 2 Takte Halt
        XCTAssertTrue(m.tick())
        XCTAssertEqual(m.offset, 3, "pixelweise, nicht zeichenweise")
        while m.offset != 0 { m.tick() }                     // eine Runde: 240 Pixel
        XCTAssertFalse(m.tick(), "nach einer Runde wieder Halt am Anfang")
        XCTAssertEqual(m.loop, 240)
    }

    func testSameTextDoesNotRestart() {
        var m = Marquee(view: 50, step: 5, holdTicks: 0)
        m.set(key: "A", contentWidth: 300)
        m.tick()
        m.set(key: "A", contentWidth: 300)
        XCTAssertEqual(m.offset, 5)
        m.set(key: "B", contentWidth: 300)
        XCTAssertEqual(m.offset, 0, "neuer Titel beginnt von vorn")
    }

    func testOffsetNeverLeavesTheStrip() {
        var m = Marquee(view: 100, step: 7, holdTicks: 0, gap: 40)
        m.set(key: "x", contentWidth: 150)
        for _ in 0..<1000 {
            m.tick()
            XCTAssertLessThan(m.offset, m.loop)   // Streifen = Text + Lücke + Text ≥ loop + view
        }
    }

    // MARK: Plugin-Version

    func testPluginVersionComparison() {
        XCTAssertFalse(DeckWire.isOutdated(plugin: "0.35.0", current: "0.35.0"))
        XCTAssertTrue(DeckWire.isOutdated(plugin: "0.35.0", current: "0.36.0"))
        XCTAssertFalse(DeckWire.isOutdated(plugin: "0.36.0", current: "0.35.0"), "neueres Plugin ist kein Grund zum Neuinstallieren")
        XCTAssertFalse(DeckWire.isOutdated(plugin: "0.35", current: "0.35.0"), "fehlende Stelle = 0")
        XCTAssertTrue(DeckWire.isOutdated(plugin: "0.9.0", current: "0.10.0"), "zahlenweise, nicht als Text")
        XCTAssertTrue(DeckWire.isOutdated(plugin: "kaputt", current: "0.35.0"))
        XCTAssertTrue(DeckWire.isOutdated(plugin: "", current: "0.35.0"))
    }

    // MARK: Stufe 2 – Lautsprecher je App

    func testRouteCommand() {
        XCTAssertEqual(DeckWire.parse(data(["v": 1, "cmd": "route", "app": "net.imput.helium", "device": "BuiltInSpeakerDevice"])),
                       .route(app: "net.imput.helium", device: "BuiltInSpeakerDevice"))
        XCTAssertEqual(DeckWire.parse(data(["v": 1, "cmd": "route", "app": "current", "device": NSNull()])),
                       .route(app: "current", device: nil))
        XCTAssertNil(DeckWire.parse(data(["v": 1, "cmd": "route", "app": "current"])), "ohne device kein Befehl")
        XCTAssertNil(DeckWire.parse(data(["v": 1, "cmd": "route", "app": "current", "device": "a\nb"])))
        XCTAssertNil(DeckWire.parse(data(["v": 1, "cmd": "route", "app": "current", "device": ""])))
        XCTAssertNil(DeckWire.parse(data(["v": 1, "cmd": "route", "app": "current", "device": String(repeating: "x", count: 201)])))
        let c = DeckWire.Command.route(app: "current", device: nil)
        XCTAssertEqual(DeckWire.parse(data(DeckWire.encode(c))), c)
    }

    func testStatusCarriesOutputsAndOldFieldsStillParse() throws {
        var s = DeckWire.Status(app: "current", name: "Helium", title: nil, artist: nil, percent: 100, muted: false,
                                playing: true, canPlay: true, state: .ok)
        s.outputs = [.init(uid: "A", name: "Kopfhörer"), .init(uid: "B", name: "Mac mini-Lautsprecher")]
        s.output = "B"
        s.canRoute = true
        let back = try XCTUnwrap(DeckWire.parseStatus(data(DeckWire.encode(s))))
        XCTAssertEqual(back.outputs, s.outputs)
        XCTAssertEqual(back.output, "B")
        XCTAssertTrue(back.canRoute)
        // Rückmeldung eines Gnotchi 0.35 (ohne die neuen Felder) bleibt lesbar.
        var old = DeckWire.encode(s)
        old["outputs"] = nil; old["output"] = nil; old["canRoute"] = nil
        let o = try XCTUnwrap(DeckWire.parseStatus(data(old)))
        XCTAssertTrue(o.outputs.isEmpty)
        XCTAssertFalse(o.canRoute)
    }

    // MARK: 0.38 Tasten „Ausgabe“ und „Mikrofon“

    func testSystemIDsPassTheWireAndAreNoApp() {
        for id in [DeckWire.systemOutput, DeckWire.systemInput] {
            XCTAssertTrue(DeckWire.isValidApp(id))
            XCTAssertTrue(DeckWire.isSystem(id))
            let c = DeckWire.Command.route(app: id, device: "AirPods-UID")
            XCTAssertEqual(DeckWire.parse(data(DeckWire.encode(c))), c)
        }
        XCTAssertEqual(DeckWire.parse(data(DeckWire.encode(.watch([DeckWire.systemOutput, "current"])))),
                       .watch([DeckWire.systemOutput, "current"]))
        XCTAssertFalse(DeckWire.isSystem("current"))
        XCTAssertFalse(DeckWire.isSystem("com.spotify.client"))
    }

    private func dev(_ id: AudioObjectID, _ name: String, uid: String?) -> OutputDevices.Device {
        OutputDevices.Device(id: id, name: name, transport: kAudioDeviceTransportTypeBuiltIn, uid: uid)
    }

    func testSystemStatusListsFavoritesFirstAndAlwaysTheCurrentDevice() throws {
        let suite = "DeckTests.system.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let mixer = MixerModel(interval: .seconds(3600), defaults: defaults)
        let outs = (1...10).map { dev(AudioObjectID($0), "Gerät \($0)", uid: "u\($0)") } + [dev(99, "Ohne UID", uid: nil)]
        let mic = dev(50, "AirPods", uid: "pods-in")
        mixer.setPreview(output: .init(device: outs[9]), systemOutput: nil, input: .init(device: mic), outputs: outs,
                         inputs: [dev(51, "Mac-Mikrofon", uid: "mac-in"), mic], apps: [])
        mixer.toggleFavorite(outs[4], .output)
        let deck = DeckController(mixer: mixer, media: NowPlayingModel())

        let out = deck.status(DeckWire.systemOutput)
        XCTAssertEqual(out.name, "Ausgabe")
        XCTAssertEqual(out.state, .ok)
        XCTAssertTrue(out.canRoute)
        XCTAssertEqual(out.outputs.count, DeckWire.maxOutputs)
        XCTAssertEqual(out.output, "u10")
        XCTAssertEqual(out.outputs.first?.uid, "u10", "eingestelltes Gerät hinter Platz 8 wird vorn eingefügt")
        XCTAssertEqual(out.outputs[1].uid, "u5", "Favorit vor den übrigen")
        XCTAssertFalse(out.outputs.contains { $0.name == "Ohne UID" })

        let input = deck.status(DeckWire.systemInput)
        XCTAssertEqual(input.name, "Mikrofon")
        XCTAssertEqual(input.outputs.map(\.uid), ["mac-in", "pods-in"], "beim Mikrofon die Eingänge")
        XCTAssertEqual(input.output, "pods-in")
        // Über das Netz und zurück: dieselben Felder wie bei „App-Lautsprecher“.
        XCTAssertEqual(DeckWire.parseStatus(data(DeckWire.encode(input))), input)
    }

    func testSystemStatusWithoutDevicesCannotRoute() throws {
        let suite = "DeckTests.empty.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let deck = DeckController(mixer: MixerModel(interval: .seconds(3600), defaults: defaults), media: NowPlayingModel())
        let s = deck.status(DeckWire.systemOutput)
        XCTAssertTrue(s.outputs.isEmpty)
        XCTAssertFalse(s.canRoute)
    }

    func testFixedDeviceFromSettings() {
        XCTAssertTrue(DeviceKey.fixed([:]) == (nil, nil))
        XCTAssertTrue(DeviceKey.fixed(["device": ""]) == (nil, nil), "leer = reihum")
        XCTAssertTrue(DeviceKey.fixed(["device": "a\nb", "deviceName": "X"]) == (nil, nil))
        XCTAssertTrue(DeviceKey.fixed(["device": 5]) == (nil, nil))
        let f = DeviceKey.fixed(["device": "pods", "deviceName": String(repeating: "A", count: 80)])
        XCTAssertEqual(f.uid, "pods")
        XCTAssertEqual(f.name?.count, 60)
        XCTAssertNil(DeviceKey.fixed(["device": "pods", "deviceName": ""]).name)
    }

    func testDeviceKeyLook() {
        var s = DeckWire.Status(app: DeckWire.systemOutput, name: "Ausgabe", title: nil, artist: nil, percent: nil,
                                muted: false, playing: false, canPlay: false, state: .ok)
        s.outputs = [.init(uid: "spk", name: "Lautsprecher"), .init(uid: "pods", name: "AirPods")]
        s.output = "spk"
        s.canRoute = true
        // Festes Gerät: leuchtet nur, wenn eingestellt.
        XCTAssertTrue(DeviceKey.look(s, input: false, fixed: "pods", fixedName: "AirPods", connected: true) == ("key-sysout-off", "AirPods"))
        s.output = "pods"
        XCTAssertTrue(DeviceKey.look(s, input: false, fixed: "pods", fixedName: nil, connected: true) == ("key-sysout", "AirPods"))
        // Nicht angeschlossen → gemerkter Name und Hinweis.
        XCTAssertTrue(DeviceKey.look(s, input: true, fixed: "gone", fixedName: "Jabra", connected: true) == ("key-sysin-off", "Jabra\nnicht da"))
        // Reihum: zeigt das eingestellte Gerät.
        XCTAssertTrue(DeviceKey.look(s, input: false, fixed: nil, fixedName: nil, connected: true) == ("key-sysout", "AirPods"))
        // Ohne Verbindung oder ohne Liste: gedimmt, nie leer.
        XCTAssertTrue(DeviceKey.look(s, input: false, fixed: "pods", fixedName: "AirPods", connected: false) == ("key-sysout-off", "Gnotchi aus"))
        XCTAssertTrue(DeviceKey.look(nil, input: false, fixed: "pods", fixedName: "AirPods", connected: true) == ("key-sysout-off", "AirPods"))
        XCTAssertTrue(DeviceKey.look(nil, input: false, fixed: nil, fixedName: nil, connected: true) == ("key-sysout-off", "…"))
    }

    func testTargetIsRoutedOnlyWithOtherDevice() {
        XCTAssertFalse(AppTapEngine.Target(appID: "a", processes: [1], deviceUID: "X").isRouted)
        XCTAssertFalse(AppTapEngine.Target(appID: "a", processes: [1], deviceUID: "X", outputUID: "X").isRouted)
        XCTAssertTrue(AppTapEngine.Target(appID: "a", processes: [1], deviceUID: "X", outputUID: "Y").isRouted)
    }
}
