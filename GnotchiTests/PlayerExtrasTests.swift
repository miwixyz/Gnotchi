import AppKit
import XCTest

// SYNTHETISCH – keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16).

/// 0.17.0 Shuffle: Skripte nur für Spotify/Musik mit festen Kennungen, Lesen ändert nichts, Antwort sicher gelesen.
@MainActor
final class PlayerExtrasTests: XCTestCase {

    func testScriptsOnlyForSpotifyAndMusicWithFixedIDs() {
        XCTAssertEqual(AppleScriptSource.extraScript(.toggleShuffle, bundleID: "com.example.evil\"; do shell script \"x"), "")
        XCTAssertEqual(AppleScriptSource.extraScript(.read, bundleID: "com.google.Chrome"), "")
        let spotify = AppleScriptSource.extraScript(.toggleShuffle, bundleID: AppleScriptSource.spotify)
        XCTAssertTrue(spotify.contains("set shuffling to not shuffling"))
        XCTAssertTrue(spotify.contains("application id \"com.spotify.client\""))
        XCTAssertTrue(spotify.contains("with timeout of 3 seconds"))
        let music = AppleScriptSource.extraScript(.toggleShuffle, bundleID: AppleScriptSource.music)
        XCTAssertTrue(music.contains("set shuffle enabled to not shuffle enabled"))
    }

    func testReadChangesNothing() {
        for id in [AppleScriptSource.spotify, AppleScriptSource.music] {
            let read = AppleScriptSource.extraScript(.read, bundleID: id)
            XCTAssertFalse(read.contains("set "), "Lesen ändert nichts")
            XCTAssertFalse(read.contains("favorited") || read.contains("starred"), "Favorit verworfen (0.17.0)")
        }
    }

    func testStateParsing() {
        let on = NSAppleEventDescriptor.list()
        on.insert(NSAppleEventDescriptor(boolean: true), at: 1)
        XCTAssertEqual(AppleScriptSource.extraState(from: on), .init(shuffle: true))
        let text = NSAppleEventDescriptor.list()
        text.insert(NSAppleEventDescriptor(string: "true"), at: 1)
        XCTAssertNil(AppleScriptSource.extraState(from: text), "Text ist kein Wahrheitswert")
        XCTAssertNil(AppleScriptSource.extraState(from: NSAppleEventDescriptor(string: "x")))
    }
}
