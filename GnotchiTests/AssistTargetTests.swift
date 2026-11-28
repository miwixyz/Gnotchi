import XCTest

/// Ersatzquelle für Spotify/Musik (NowPlayingModel+Assist).
@MainActor
final class AssistTargetTests: XCTestCase {
    private let spotify = AppleScriptSource.spotify
    private let music = AppleScriptSource.music

    func testAdapterSpieltKeinErsatz() {
        XCTAssertNil(NowPlayingModel.assistTarget(adapterPlaying: true, audible: [spotify], allowed: { _ in true }))
    }
    func testHoerbarUndErlaubtGibtZiel() {
        XCTAssertEqual(NowPlayingModel.assistTarget(adapterPlaying: false, audible: [spotify], allowed: { _ in true }), spotify)
    }
    func testNichtErlaubtKeinZiel() {
        XCTAssertNil(NowPlayingModel.assistTarget(adapterPlaying: false, audible: [spotify], allowed: { _ in false }))
    }
    func testNichtHoerbarKeinZiel() {
        XCTAssertNil(NowPlayingModel.assistTarget(adapterPlaying: false, audible: [], allowed: { _ in true }))
    }
    func testErlaubteAppWirdGewaehlt() {
        let t = NowPlayingModel.assistTarget(adapterPlaying: false, audible: [spotify, music], allowed: { $0 == AppleScriptSource.music })
        XCTAssertEqual(t, music)
    }
    func testHilfsprozessZaehlt() {
        let p = [MixerAudio.AudioApp(pid: 1, bundleID: "com.spotify.client.helper", path: nil, outputting: true, devices: []),
                 MixerAudio.AudioApp(pid: 2, bundleID: "com.spotify.clientX", path: nil, outputting: true, devices: []),
                 MixerAudio.AudioApp(pid: 3, bundleID: "com.apple.Music", path: nil, outputting: false, devices: [])]
        XCTAssertEqual(NowPlayingModel.audibleSupported(p), [spotify])
    }

    private func info(_ title: String, _ id: String, playing: Bool) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: "A", album: nil, appBundleID: id, isPlaying: playing,
                       duration: 100, elapsedAtStamp: 0, stamp: Date(), rate: playing ? 1 : 0,
                       contentID: nil, artworkBase64: nil)
    }

    func testErsatzAnzeigeUndRueckkehrZumAdapter() {
        let m = NowPlayingModel()
        m.receiveFromAdapter(info("Helium", "net.imput.helium", playing: false))
        m.assistActive = true
        m.receiveFromFallback(info("Song", spotify, playing: true))
        XCTAssertEqual(m.info?.title, "Song")
        // Adapter meldet weiter Pause: Ersatzanzeige bleibt.
        m.receiveFromAdapter(info("Helium", "net.imput.helium", playing: false))
        XCTAssertEqual(m.info?.title, "Song")
        // Pause: Ersatz bleibt zunächst und zeigt die Pause.
        m.receiveFromFallback(info("Song", spotify, playing: false))
        XCTAssertTrue(m.assistActive)
        XCTAssertEqual(m.info?.title, "Song")
        // Nach der Haltezeit: zurück zur Adapter-Meldung.
        m.assistPausedSince = Date().addingTimeInterval(-NowPlayingModel.assistPauseHold - 1)
        m.receiveFromFallback(info("Song", spotify, playing: false))
        XCTAssertFalse(m.assistActive)
        XCTAssertEqual(m.info?.title, "Helium")
    }

    func testAppBeendetEndetErsatz() {
        let m = NowPlayingModel()
        m.receiveFromAdapter(info("Helium", "net.imput.helium", playing: false))
        m.assistActive = true
        m.receiveFromFallback(nil)
        XCTAssertFalse(m.assistActive)
        XCTAssertEqual(m.info?.title, "Helium")
    }

    func testAdapterSpieltBeendetErsatz() {
        let m = NowPlayingModel()
        m.assistActive = true
        m.receiveFromAdapter(info("Neu", "com.apple.Music", playing: true))
        XCTAssertFalse(m.assistActive)
        XCTAssertEqual(m.info?.title, "Neu")
    }

    func testFallbackOhneErsatzWirdIgnoriert() {
        let m = NowPlayingModel()
        m.receiveFromFallback(info("Song", spotify, playing: true))
        XCTAssertNil(m.info)
    }

    func testMerkerUndVergessen() {
        let id = AppleScriptSource.spotify
        let before = AutomationStatus.granted(id)
        defer { AutomationStatus.remember(id, before) }
        AutomationStatus.remember(id, true)
        XCTAssertTrue(AutomationStatus.granted(id))
        AutomationStatus.shared.forget(id)
        XCTAssertFalse(AutomationStatus.granted(id))
        XCTAssertFalse(AutomationStatus.shared.isAllowed(id))
    }

    func testVerweigertEndetErsatzUndVergisstZustimmung() {
        let id = AppleScriptSource.spotify
        let before = AutomationStatus.granted(id)
        defer { AutomationStatus.remember(id, before) }
        AutomationStatus.remember(id, true)
        let m = NowPlayingModel()
        m.assistActive = true
        m.fallback.onDenied?([id])
        XCTAssertFalse(m.assistActive)
        XCTAssertFalse(AutomationStatus.granted(id))
    }
}
