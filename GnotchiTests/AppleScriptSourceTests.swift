import XCTest
@testable import Gnotchi

/// G7: Antworten der Rückfall-Skripte und feste Befehle.
final class AppleScriptSourceTests: XCTestCase {
    private let sep = "\u{1F}"
    private let now = Date(timeIntervalSince1970: 1000)
    private let spotify = "com.spotify.client"
    private let music = "com.apple.Music"

    private func raw(_ fields: String...) -> String { fields.joined(separator: sep) }

    // MARK: parse

    func testSpotifyDurationInMilliseconds() throws {
        let i = try XCTUnwrap(AppleScriptSource.parse(raw("Beispieltitel Eins", "Testband", "206937", "30.5", "playing"),
                                                      bundleID: spotify, now: now))
        XCTAssertEqual(try XCTUnwrap(i.duration), 206.937, accuracy: 0.001)
        XCTAssertEqual(i.elapsed(at: now), 30.5, accuracy: 0.001)
        XCTAssertTrue(i.isPlaying)
        XCTAssertEqual(i.appBundleID, spotify)
        XCTAssertEqual(i.artist, "Testband")
    }

    func testMusicDurationInSecondsAndPaused() throws {
        let i = try XCTUnwrap(AppleScriptSource.parse(raw("Beispieltitel Zwei", "Beispielkünstler", "245.3", "12", "paused"),
                                                      bundleID: music, now: now))
        XCTAssertEqual(try XCTUnwrap(i.duration), 245.3, accuracy: 0.001)
        XCTAssertFalse(i.isPlaying)
        XCTAssertEqual(i.rate, 0)
    }

    /// AppleScript wandelt Zahlen je nach Systemsprache mit Komma und große Werte in E-Schreibweise.
    func testGermanDecimalCommaAndExponent() throws {
        let i = try XCTUnwrap(AppleScriptSource.parse(raw("Hörspiel", "Erzähler", "1,08E+4", "12,5", "playing"),
                                                      bundleID: music, now: now))
        XCTAssertEqual(try XCTUnwrap(i.duration), 10_800, accuracy: 0.001)
        XCTAssertEqual(i.elapsed(at: now), 12.5, accuracy: 0.001)
    }

    func testStoppedOrGarbageIsNil() {
        XCTAssertNil(AppleScriptSource.parse("", bundleID: music, now: now))
        XCTAssertNil(AppleScriptSource.parse("nur ein feld", bundleID: music, now: now))
        XCTAssertNil(AppleScriptSource.parse(raw("", "Interpret", "100", "1", "playing"), bundleID: music, now: now))
    }

    /// Antwort kommt aus einer fremden App: unbekannte Absender-ID wird nicht übernommen.
    func testUnsupportedBundleIDIsNil() {
        XCTAssertNil(AppleScriptSource.parse(raw("Titel", "I", "100", "1", "playing"), bundleID: "com.example.evil", now: now))
    }

    /// Wie beim Adapter (G4): Dauer nur endlich, > 0 und höchstens `maxDuration`.
    func testImplausibleDurationIsDropped() throws {
        for bad in ["0", "-5", "nan", "inf", "x", String(NowPlayingInfo.maxDuration + 1)] {
            let i = try XCTUnwrap(AppleScriptSource.parse(raw("T", "I", bad, "1", "playing"), bundleID: music, now: now))
            XCTAssertNil(i.duration, bad)
        }
    }

    func testNonFinitePositionBecomesZero() throws {
        for bad in ["nan", "inf", "-3", "x"] {
            let i = try XCTUnwrap(AppleScriptSource.parse(raw("T", "I", "100", bad, "paused"), bundleID: music, now: now))
            XCTAssertEqual(i.elapsedAtStamp, 0, bad)
        }
    }

    func testTextIsSanitized() throws {
        let i = try XCTUnwrap(AppleScriptSource.parse(raw("Ti\u{202E}tel\n", "  ", "100", "1", "playing"), bundleID: music, now: now))
        XCTAssertEqual(i.title, "Titel")
        XCTAssertNil(i.artist)
    }

    // MARK: script

    func testSeekScriptIsNumberOnly() {
        XCTAssertTrue(AppleScriptSource.script(.seek(61.5), bundleID: music).contains("set player position to 61.500"))
        XCTAssertTrue(AppleScriptSource.script(.seek(-4), bundleID: music).contains("set player position to 0.000"))
        XCTAssertTrue(AppleScriptSource.script(.seek(.nan), bundleID: music).contains("set player position to 0.000"))
        XCTAssertTrue(AppleScriptSource.script(.seek(.infinity), bundleID: music).contains("set player position to 0.000"))
        XCTAssertTrue(AppleScriptSource.script(.send(.next), bundleID: spotify).contains("next track"))
    }

    /// G7: Nur die beiden festen Ziel-Apps; alles andere ergibt kein Skript – auch keine
    /// Einschleusung über eine präparierte „Bundle-ID“.
    func testUnsupportedBundleIDGivesNoScript() {
        let evil = "com.spotify.client\"\ndo shell script \"touch /tmp/x\"\ntell application \"Finder"
        for id in [evil, "com.apple.Finder", "", "com.spotify.client "] {
            XCTAssertEqual(AppleScriptSource.script(.send(.toggle), bundleID: id), "", id)
            XCTAssertEqual(AppleScriptSource.script(.stream, bundleID: id), "", id)
            XCTAssertEqual(AppleScriptSource.script(.seek(1), bundleID: id), "", id)
        }
    }

    /// Außer der Spulposition steckt nichts Variables im Skript: jedes Skript ist für eine
    /// feste Ziel-App bis auf die formatierte Zahl identisch mit seiner Vorlage.
    func testScriptsAreConstantsExceptSeekNumber() {
        let calls: [MediaAdapter.Call] = [.stream, .test, .send(.play), .send(.pause), .send(.toggle),
                                          .send(.next), .send(.previous)]
        for id in AppleScriptSource.supported {
            for call in calls {
                let s = AppleScriptSource.script(call, bundleID: id)
                XCTAssertTrue(s.hasPrefix("tell application id \"\(id)\"\n"), "\(id) \(call)")
                XCTAssertTrue(s.hasSuffix("\nend tell"), "\(id) \(call)")
            }
            let a = AppleScriptSource.script(.seek(12.25), bundleID: id)
            let b = AppleScriptSource.script(.seek(99_999.5), bundleID: id)
            XCTAssertEqual(a.replacingOccurrences(of: "12.250", with: "N"), b.replacingOccurrences(of: "99999.500", with: "N"))
            XCTAssertFalse(a.contains("12,250"), "Spulzahl immer mit Punkt (en_US_POSIX)")
        }
    }

    /// Der Spotify-Rückfall darf Musik nie mitsteuern und umgekehrt.
    func testTargetIsTheGivenApp() {
        XCTAssertTrue(AppleScriptSource.script(.send(.toggle), bundleID: spotify).contains("\"com.spotify.client\""))
        XCTAssertFalse(AppleScriptSource.script(.send(.toggle), bundleID: spotify).contains("com.apple.Music"))
    }
}
