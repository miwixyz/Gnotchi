import CoreAudio
import XCTest

/// Wo die Musik spielt (Michael, 18.10.: Spotify Connect auf externe Lautsprecher soll sichtbar sein).
/// Gemessen 18.10.: Spielt Spotify über Connect, meldet MediaRemote playing = true, Core Audio für
/// Spotifys Prozess aber IsRunningOutput = 0. Edge/Helium spielen in `….helper`-Prozessen,
/// Safari im geteilten `com.apple.WebKit.GPU`.
final class AudioRouteTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1000)
    private func p(_ pid: pid_t, _ id: String?, _ out: Bool) -> AudioRoute.AudioProcess {
        AudioRoute.AudioProcess(pid: pid, bundleID: id, isRunningOutput: out)
    }

    // MARK: outputting – gibt der Prozess der Quell-App Ton aus?

    func testSpotifyConnectMeasuredNotOutputting() {
        let list = [p(79759, "com.spotify.client", false), p(79690, "com.apple.Music", false)]
        XCTAssertEqual(AudioRoute.outputting(pid: 79759, bundleID: "com.spotify.client", processes: list), false)
    }

    func testOutputtingByPID() {
        XCTAssertEqual(AudioRoute.outputting(pid: 5, bundleID: nil, processes: [p(5, nil, true)]), true)
    }

    /// Edge: Hauptprozess still, Ton im Hilfsprozess → zählt als „gibt aus“.
    func testHelperProcessOfSameAppCounts() {
        let list = [p(1, "com.microsoft.edgemac", false), p(2, "com.microsoft.edgemac.helper", true)]
        XCTAssertEqual(AudioRoute.outputting(pid: 1, bundleID: "com.microsoft.edgemac", processes: list), true)
    }

    /// Nur echte Unter-IDs: „com.spotify.clientX“ gehört nicht zu Spotify.
    func testPrefixWithoutDotDoesNotCount() {
        let list = [p(1, "com.spotify.client", false), p(2, "com.spotify.clientX", true)]
        XCTAssertEqual(AudioRoute.outputting(pid: 1, bundleID: "com.spotify.client", processes: list), false)
    }

    /// Kein Core-Audio-Objekt für die App → unbekannt, nie „anderes Gerät“.
    func testUnknownWithoutProcessObject() {
        XCTAssertNil(AudioRoute.outputting(pid: 9, bundleID: "com.example.player", processes: [p(1, "x.y", true)]))
        XCTAssertNil(AudioRoute.outputting(pid: nil, bundleID: nil, processes: []))
    }

    /// Safari spielt im geteilten WebKit-GPU-Prozess, der keiner App zuzuordnen ist: Läuft der, ist
    /// „App still“ kein Beweis für ein anderes Gerät → unbekannt.
    func testWebKitGPUOutputMakesSilenceUnknown() {
        let list = [p(1, "com.apple.Safari", false), p(2, AudioRoute.webKitGPU, true)]
        XCTAssertNil(AudioRoute.outputting(pid: 1, bundleID: "com.apple.Safari", processes: list))
    }

    // MARK: identities – PID und Bundle-ID je Core-Audio-Objekt nur einmal lesen (Review M6)

    func testKnownObjectsAreNotReadAgain() {
        let known: [AudioObjectID: AudioRoute.Identity] = [10: .init(pid: 1, bundleID: "a")]
        var read: [AudioObjectID] = []
        let result = AudioRoute.identities(for: [10, 11], known: known) { id in
            read.append(id)
            return .init(pid: 2, bundleID: "b")
        }
        XCTAssertEqual(read, [11])
        XCTAssertEqual(result, [10: .init(pid: 1, bundleID: "a"), 11: .init(pid: 2, bundleID: "b")])
    }

    /// Verschwundene Objekte fliegen raus (Zwischenspeicher wächst nicht); unlesbare werden nicht gemerkt.
    func testVanishedAndUnreadableDropped() {
        let known: [AudioObjectID: AudioRoute.Identity] = [10: .init(pid: 1, bundleID: "a")]
        let result = AudioRoute.identities(for: [12], known: known) { _ in nil }
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: liveCachedPID – Quell-App neu gestartet (Spotify-Neustart während der Wiedergabe)

    func testCachedPIDKeptWhileAlive() {
        XCTAssertEqual(AudioRoute.liveCachedPID(79759) { _ in true }, 79759)
    }

    func testCachedPIDDroppedWhenProcessGone() {
        XCTAssertNil(AudioRoute.liveCachedPID(79759) { _ in false })
        XCTAssertNil(AudioRoute.liveCachedPID(nil) { _ in true })
    }

    // MARK: nextSilentSince – Entprellen

    func testSilenceStartsClock() {
        XCTAssertEqual(AudioRoute.nextSilentSince(isPlaying: true, outputting: false, current: nil, now: t0), t0)
    }

    func testSilenceKeepsClock() {
        let earlier = t0.addingTimeInterval(-3)
        XCTAssertEqual(AudioRoute.nextSilentSince(isPlaying: true, outputting: false, current: earlier, now: t0), earlier)
    }

    func testOutputOrPauseOrUnknownResetsClock() {
        let earlier = t0.addingTimeInterval(-3)
        XCTAssertNil(AudioRoute.nextSilentSince(isPlaying: true, outputting: true, current: earlier, now: t0))
        XCTAssertNil(AudioRoute.nextSilentSince(isPlaying: false, outputting: false, current: earlier, now: t0))
        XCTAssertNil(AudioRoute.nextSilentSince(isPlaying: true, outputting: nil, current: earlier, now: t0))
    }

    // MARK: decide

    private func decide(playing: Bool = true, outputting: Bool? = true, silentFor: TimeInterval? = nil,
                        transport: UInt32? = kAudioDeviceTransportTypeBuiltIn, name: String? = "MacBook Air-Lautsprecher")
        -> PlaybackRoute {
        AudioRoute.decide(isPlaying: playing, outputting: outputting, silentFor: silentFor,
                          transport: transport, outputName: name)
    }

    func testLocalBuiltIn() {
        XCTAssertEqual(decide(), .local)
    }

    func testRemoteAfterDebounce() {
        XCTAssertEqual(decide(outputting: false, silentFor: 2.1), .remote)
    }

    /// Titelanfang: kurz still ist kein anderes Gerät (kein Flackern).
    func testShortSilenceStaysLocal() {
        XCTAssertEqual(decide(outputting: false, silentFor: 1.5), .local)
        XCTAssertEqual(decide(outputting: false, silentFor: 2.0), .local)
    }

    func testPausedIsNeverRemote() {
        XCTAssertEqual(decide(playing: false, outputting: false, silentFor: 10), .local)
    }

    func testUnknownProcessIsNeverRemote() {
        XCTAssertEqual(decide(outputting: nil, silentFor: 10), .local)
    }

    func testAirPlayOutputDevice() {
        XCTAssertEqual(decide(transport: kAudioDeviceTransportTypeAirPlay, name: "Wohnzimmer"),
                       .device(name: "Wohnzimmer", kind: .airPlay))
    }

    func testBluetoothOutputDevice() {
        XCTAssertEqual(decide(transport: kAudioDeviceTransportTypeBluetooth, name: "AirPods Pro"),
                       .device(name: "AirPods Pro", kind: .bluetooth))
        XCTAssertEqual(decide(transport: kAudioDeviceTransportTypeBluetoothLE, name: "Kopfhörer"),
                       .device(name: "Kopfhörer", kind: .bluetooth))
    }

    /// Spielt die App gar nicht lokal, ist das Ausgabegerät des Mac egal.
    func testRemoteWinsOverDevice() {
        XCTAssertEqual(decide(outputting: false, silentFor: 5, transport: kAudioDeviceTransportTypeAirPlay, name: "Küche"),
                       .remote)
    }

    /// Gerätenamen sind frei vergeben: bereinigt, gekürzt; ohne Namen ein Ersatz.
    func testDeviceNameSanitizedAndFallback() {
        XCTAssertEqual(decide(transport: kAudioDeviceTransportTypeAirPlay, name: "Wohn\u{202E}zimmer"),
                       .device(name: "Wohnzimmer", kind: .airPlay))
        XCTAssertEqual(decide(transport: kAudioDeviceTransportTypeAirPlay, name: nil),
                       .device(name: "AirPlay", kind: .airPlay))
        XCTAssertEqual(decide(transport: kAudioDeviceTransportTypeBluetooth, name: "  "),
                       .device(name: "Bluetooth", kind: .bluetooth))
        let long = String(repeating: "x", count: 200)
        guard case .device(let n, _) = decide(transport: kAudioDeviceTransportTypeAirPlay, name: long) else {
            return XCTFail("kein Gerät")
        }
        XCTAssertEqual(n.count, AudioRoute.maxNameLength)
    }

    // MARK: Darstellung

    func testPresentation() {
        XCTAssertNil(PlaybackRoute.local.symbol)
        XCTAssertNil(PlaybackRoute.local.label)
        XCTAssertEqual(PlaybackRoute.remote.symbol, "hifispeaker.fill")
        XCTAssertEqual(PlaybackRoute.remote.label, "Auf anderem Gerät")
        XCTAssertEqual(PlaybackRoute.device(name: "Wohnzimmer", kind: .airPlay).symbol, "airplayaudio")
        XCTAssertEqual(PlaybackRoute.device(name: "Wohnzimmer", kind: .airPlay).label, "Wohnzimmer")
        XCTAssertEqual(PlaybackRoute.device(name: "AirPods", kind: .bluetooth).symbol, "headphones")
    }

    /// Pegel heißt „Ton kommt hier raus“ – bei anderem Gerät oder AirPlay steht dort ein Lautsprecher.
    func testLevelBarsReplaced() {
        XCTAssertFalse(PlaybackRoute.local.replacesLevelBars)
        XCTAssertTrue(PlaybackRoute.remote.replacesLevelBars)
        XCTAssertTrue(PlaybackRoute.device(name: "W", kind: .airPlay).replacesLevelBars)
        XCTAssertFalse(PlaybackRoute.device(name: "AirPods", kind: .bluetooth).replacesLevelBars)
    }
}
