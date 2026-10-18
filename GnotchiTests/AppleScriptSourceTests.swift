import CoreServices
import XCTest
@testable import Gnotchi

/// G7: Antworten der Rückfall-Skripte und feste Befehle.
final class AppleScriptSourceTests: XCTestCase {
    private typealias Fields = AppleScriptSource.Fields
    private let now = Date(timeIntervalSince1970: 1000)
    private let spotify = "com.spotify.client"
    private let music = "com.apple.Music"

    // MARK: parse (reine Werte)

    func testSpotifyDurationInMilliseconds() throws {
        let f = Fields(title: "Beispieltitel Eins", artist: "Testband", state: "playing",
                       duration: 206_937, position: 30.5)
        let i = try XCTUnwrap(AppleScriptSource.parse(f, bundleID: spotify, now: now))
        XCTAssertEqual(try XCTUnwrap(i.duration), 206.937, accuracy: 0.001)
        XCTAssertEqual(i.elapsed(at: now), 30.5, accuracy: 0.001)
        XCTAssertTrue(i.isPlaying)
        XCTAssertEqual(i.rate, 1)
        XCTAssertEqual(i.appBundleID, spotify)
        XCTAssertEqual(i.artist, "Testband")
    }

    func testMusicDurationInSecondsAndPaused() throws {
        let f = Fields(title: "Beispieltitel Zwei", artist: "Testmusiker", state: "paused", duration: 245.3, position: 12)
        let i = try XCTUnwrap(AppleScriptSource.parse(f, bundleID: music, now: now))
        XCTAssertEqual(try XCTUnwrap(i.duration), 245.3, accuracy: 0.001)
        XCTAssertFalse(i.isPlaying)
        XCTAssertEqual(i.rate, 0)
    }

    func testOtherStatesAreNotPlaying() throws {
        for state in ["stopped", "fast forwarding", "Playing", nil] as [String?] {
            let f = Fields(title: "T", artist: "I", state: state, duration: 100, position: 1)
            XCTAssertFalse(try XCTUnwrap(AppleScriptSource.parse(f, bundleID: music, now: now)).isPlaying, state ?? "nil")
        }
    }

    func testMissingDurationAndArtist() throws {
        let i = try XCTUnwrap(AppleScriptSource.parse(Fields(title: "Radio", artist: nil, state: "playing", duration: nil, position: nil),
                                                      bundleID: music, now: now))
        XCTAssertNil(i.duration)
        XCTAssertNil(i.artist)
        XCTAssertEqual(i.elapsedAtStamp, 0)
    }

    func testMissingOrEmptyTitleIsNil() {
        XCTAssertNil(AppleScriptSource.parse(Fields(title: nil, artist: "I", state: "playing", duration: 1, position: 0),
                                             bundleID: music, now: now))
        XCTAssertNil(AppleScriptSource.parse(Fields(title: " \n", artist: "I", state: "playing", duration: 1, position: 0),
                                             bundleID: music, now: now))
    }

    /// Antwort kommt aus einer fremden App: unbekannte Absender-ID wird nicht übernommen.
    func testUnsupportedBundleIDIsNil() {
        XCTAssertNil(AppleScriptSource.parse(Fields(title: "T", artist: nil, state: "playing", duration: 1, position: 0),
                                             bundleID: "com.example.evil", now: now))
    }

    /// Wie beim Adapter (G4): Dauer nur endlich, > 0 und höchstens `maxDuration`.
    func testImplausibleDurationIsDropped() throws {
        for bad in [0, -5, .nan, .infinity, NowPlayingInfo.maxDuration + 1] as [Double] {
            let f = Fields(title: "T", artist: "I", state: "playing", duration: bad, position: 1)
            XCTAssertNil(try XCTUnwrap(AppleScriptSource.parse(f, bundleID: music, now: now)).duration, "\(bad)")
        }
    }

    func testNonFinitePositionBecomesZero() throws {
        for bad in [.nan, .infinity, -3] as [Double] {
            let f = Fields(title: "T", artist: "I", state: "paused", duration: 100, position: bad)
            XCTAssertEqual(try XCTUnwrap(AppleScriptSource.parse(f, bundleID: music, now: now)).elapsedAtStamp, 0, "\(bad)")
        }
    }

    /// Steuerzeichen im Titel (auch U+001F, früher Feldtrenner) zerlegen nichts mehr und werden wie überall entfernt.
    func testTextIsSanitized() throws {
        let f = Fields(title: "Ti\u{1F}t\u{202E}el\n", artist: "  ", state: "playing", duration: 100, position: 1)
        let i = try XCTUnwrap(AppleScriptSource.parse(f, bundleID: music, now: now))
        XCTAssertEqual(i.title, "Titel")
        XCTAssertNil(i.artist)
    }

    // MARK: fields(from:) – Apple-Event-Liste lesen

    private func list(_ items: NSAppleEventDescriptor...) -> NSAppleEventDescriptor {
        let l = NSAppleEventDescriptor.list()
        for item in items { l.insert(item, at: 0) }
        return l
    }

    /// `missing value` = Typcode 'msng' (cMissingValue, in Swift nicht importiert).
    private let missing = NSAppleEventDescriptor(typeCode: 0x6D73_6E67)

    func testFieldsFromListWithLongAndDouble() throws {
        let d = list(.init(string: "A\u{1F}B"), .init(string: "Interpret"), .init(int32: 206_937), .init(double: 30.5), .init(string: "playing"))
        let f = try XCTUnwrap(AppleScriptSource.fields(from: d))
        XCTAssertEqual(f, Fields(title: "A\u{1F}B", artist: "Interpret", state: "playing", duration: 206_937, position: 30.5))
    }

    func testFieldsMissingValueBecomesNil() throws {
        let d = list(.init(string: "Radio"), missing, missing, .init(double: 3), .init(string: "playing"))
        let f = try XCTUnwrap(AppleScriptSource.fields(from: d))
        XCTAssertNil(f.artist)
        XCTAssertNil(f.duration)
        XCTAssertEqual(f.position, 3)
    }

    /// `doubleValue` gäbe für Text 0,0 – Zahlen nur per Umwandlung, Text an Zahlenstelle ergibt nil.
    func testTextInNumberSlotIsNotZero() throws {
        let d = list(.init(string: "T"), .init(string: "I"), .init(string: "abc"), .init(string: "xyz"), .init(string: "paused"))
        let f = try XCTUnwrap(AppleScriptSource.fields(from: d))
        XCTAssertNil(f.duration)
        XCTAssertNil(f.position)
    }

    func testFieldsWrongShapeIsNil() {
        XCTAssertNil(AppleScriptSource.fields(from: NSAppleEventDescriptor.list()))      // gestoppt: {}
        XCTAssertNil(AppleScriptSource.fields(from: NSAppleEventDescriptor.null()))      // App lief nicht mehr
        XCTAssertNil(AppleScriptSource.fields(from: NSAppleEventDescriptor(string: "x")))
        XCTAssertNil(AppleScriptSource.fields(from: list(.init(string: "a"), .init(string: "b"))))
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

    /// Außer der Spulposition steckt nichts Variables im Skript. Jedes Skript prüft IM Skript,
    /// ob die App läuft (sonst startet `tell application` eine gerade beendete App neu);
    /// Befehle haben eine Zeitgrenze, die Abfrage nicht (sie wartet beim ersten Mal auf den Dialog).
    func testScriptsAreConstantsExceptSeekNumber() {
        let commands: [MediaAdapter.Call] = [.send(.play), .send(.pause), .send(.toggle), .send(.next), .send(.previous), .seek(1)]
        for id in AppleScriptSource.supported {
            for call in commands + [.stream, .test] {
                let s = AppleScriptSource.script(call, bundleID: id)
                XCTAssertTrue(s.hasPrefix("if application id \"\(id)\" is running then\ntell application id \"\(id)\"\n"), "\(id) \(call)")
                XCTAssertTrue(s.hasSuffix("\nend tell\nend if"), "\(id) \(call)")
            }
            for call in commands {
                XCTAssertTrue(AppleScriptSource.script(call, bundleID: id).contains("with timeout of 3 seconds\n"), "\(id) \(call)")
            }
            XCTAssertFalse(AppleScriptSource.script(.stream, bundleID: id).contains("timeout"))
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

    // MARK: blocked – wann der Hinweis „Automation nicht erlaubt“ gilt

    func testBlockedOnlyWhenNoUsableSourceRemains() {
        // Spotify verweigert, Musik läuft und ist erlaubt → kein Hinweis.
        XCTAssertEqual(AppleScriptSource.blocked(running: [spotify, music], denied: [spotify]), [])
        // Spotify verweigert, Musik läuft nicht → Hinweis nennt Spotify.
        XCTAssertEqual(AppleScriptSource.blocked(running: [spotify], denied: [spotify]), [spotify])
        // Beide verweigert → beide, feste Reihenfolge.
        XCTAssertEqual(AppleScriptSource.blocked(running: [music, spotify], denied: [music, spotify]), [spotify, music])
        // Nichts verweigert → nie ein Hinweis.
        XCTAssertEqual(AppleScriptSource.blocked(running: [], denied: []), [])
        // Fremde IDs zählen nicht.
        XCTAssertEqual(AppleScriptSource.blocked(running: ["com.example"], denied: ["com.example"]), [])
    }
}
