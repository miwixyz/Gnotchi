import XCTest
@testable import Gnotchi

/// G4/G5 + Mitschnitt 18.10.: Was aus dem Strom wird.
final class NowPlayingInfoTests: XCTestCase {

    // Adapter-Zeilen im Aufbau des Mitschnitts vom 18.10. (Titel/Interpreten erfunden, G8/G14), am Stück
    // lassen (nicht umbrechen) – Zeilenlänge hier bewusst erlaubt.
    // swiftlint:disable line_length
    private let spotify = #"{"type":"data","diff":false,"payload":{"playbackRate":1,"album":"Beispielalbum!","bundleIdentifier":"com.spotify.client","title":"Beispieltitel Eins","artist":"Testband","durationMicros":206937000,"elapsedTimeMicros":30004000,"timestampEpochMicros":1792312654000000,"contentItemIdentifier":"8A34","playing":true}}"#
    private let safari = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","title":"DEMO PARTY MIX","artist":"TEST PERSON official","durationMicros":3600000000,"elapsedTimeMicros":0,"timestampEpochMicros":1792312654000000,"playing":true,"playbackRate":1}}"#
    private let heliumFirst = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"net.imput.helium","title":"DEMO PARTY MIX","artist":"","playing":true}}"#
    // swiftlint:enable line_length
    private let empty = #"{"type":"data","diff":false,"payload":{}}"#

    private func parse(_ s: String) -> NowPlayingInfo? {
        NowPlayingInfo.parse(line: Data(s.utf8))
    }

    func testSpotify() throws {
        let i = try XCTUnwrap(parse(spotify))
        XCTAssertEqual(i.title, "Beispieltitel Eins")
        XCTAssertEqual(i.artist, "Testband")
        XCTAssertEqual(i.appBundleID, "com.spotify.client")
        XCTAssertTrue(i.isPlaying)
        XCTAssertEqual(try XCTUnwrap(i.duration), 206.937, accuracy: 0.001)
        XCTAssertFalse(i.isIncomplete)
    }

    func testSafariUsesParentApp() throws {
        XCTAssertEqual(try XCTUnwrap(parse(safari)).appBundleID, "com.apple.Safari")
    }

    func testBrowserFirstEventIsIncomplete() throws {
        let i = try XCTUnwrap(parse(heliumFirst))
        XCTAssertNil(i.artist)
        XCTAssertTrue(i.isIncomplete)
    }

    func testEmptyPayloadMeansNothingPlays() {
        XCTAssertNil(parse(empty))
    }

    func testGarbageIsNil() {
        XCTAssertNil(parse("kein json"))
        XCTAssertNil(parse(#"{"type":"data","payload":"x"}"#))
    }

    func testSanitizeRemovesControlAndBidiAndTruncates() {
        XCTAssertEqual(NowPlayingInfo.sanitize("A\u{202E}B\u{0007}C\u{2066}"), "ABC")
        XCTAssertEqual(NowPlayingInfo.sanitize(String(repeating: "x", count: 400))?.count, 300)
        XCTAssertNil(NowPlayingInfo.sanitize("  \u{202E} "))
    }

    func testElapsedRunsOnWhilePlaying() throws {
        let i = try XCTUnwrap(parse(spotify))
        let t0 = Date(timeIntervalSince1970: 1_792_312_654)
        XCTAssertEqual(i.elapsed(at: t0.addingTimeInterval(10)), 40.004, accuracy: 0.001)
        XCTAssertEqual(i.elapsed(at: t0.addingTimeInterval(10_000)), 206.937, accuracy: 0.001)  // nie über Dauer
    }

    func testElapsedStandsWhenPaused() throws {
        let paused = spotify.replacingOccurrences(of: #""playbackRate":1"#, with: #""playbackRate":0"#)
            .replacingOccurrences(of: #""playing":true"#, with: #""playing":false"#)
        let i = try XCTUnwrap(parse(paused))
        XCTAssertEqual(i.elapsed(at: Date(timeIntervalSince1970: 1_792_312_754)), 30.004, accuracy: 0.001)
    }

    // MARK: - sanitize: Zalgo, Zeilentrenner, unsichtbare Zeichen

    func testZalgoIsBoundedInBytesAndMarksPerBase() throws {
        let zalgo = "a" + String(repeating: "\u{0301}", count: 2_000_000)
        let out = try XCTUnwrap(NowPlayingInfo.sanitize(zalgo))
        XCTAssertLessThanOrEqual(out.utf8.count, 1200)
        XCTAssertLessThanOrEqual(out.unicodeScalars.count, 5)
    }

    func testManyZalgoCharactersStayUnderByteCap() throws {
        let unit = "a" + String(repeating: "\u{0301}", count: 10)
        let out = try XCTUnwrap(NowPlayingInfo.sanitize(String(repeating: unit, count: 250)))
        XCTAssertLessThanOrEqual(out.utf8.count, 1200)
        for ch in out { XCTAssertLessThanOrEqual(ch.unicodeScalars.count, 5) }
    }

    func testLineSeparatorsAreRemoved() {
        XCTAssertEqual(NowPlayingInfo.sanitize("A\u{2028}B\u{2029}C"), "ABC")
    }

    func testInvisibleFormatCharactersAreRemoved() {
        // LRM, RLM, ALM, ZWSP, BOM/ZWNBSP
        XCTAssertEqual(NowPlayingInfo.sanitize("A\u{200E}B\u{200F}C\u{061C}D\u{200B}E\u{FEFF}F"), "ABCDEF")
    }

    func testTruncationCountsCharactersWithNonAscii() {
        XCTAssertEqual(NowPlayingInfo.sanitize(String(repeating: "ä", count: 400))?.count, 300)
    }

    // MARK: - Zahlen: nichts Unendliches oder Absurdes in die Oberfläche

    private func payload(_ replacing: [String: String]) -> String {
        var line = spotify
        for (k, v) in replacing { line = line.replacingOccurrences(of: k, with: v) }
        return line
    }

    func testHugeRateWithoutDurationStaysBounded() throws {
        let line = payload([#""playbackRate":1"#: #""playbackRate":1e308"#,
                            #""durationMicros":206937000,"#: ""])
        let i = try XCTUnwrap(parse(line))
        XCTAssertNil(i.duration)
        let e = i.elapsed(at: Date(timeIntervalSince1970: 1_792_312_664))
        XCTAssertTrue(e.isFinite)
        XCTAssertLessThanOrEqual(e, NowPlayingInfo.maxDuration)
    }

    func testHugeDurationIsRejected() throws {
        let i = try XCTUnwrap(parse(payload([#""durationMicros":206937000"#: #""durationMicros":1e308"#])))
        XCTAssertNil(i.duration)
    }

    func testDurationOverLimitIsRejected() throws {
        let micros = Int(NowPlayingInfo.maxDuration + 1) * 1_000_000
        let i = try XCTUnwrap(parse(payload([#""durationMicros":206937000"#: #""durationMicros":\#(micros)"#])))
        XCTAssertNil(i.duration)
    }

    func testFutureStampDoesNotRunBackwards() throws {
        let i = try XCTUnwrap(parse(payload([#""timestampEpochMicros":1792312654000000"#:
                                                #""timestampEpochMicros":9000000000000000000"#])))
        XCTAssertEqual(i.elapsed(at: Date(timeIntervalSince1970: 1_792_312_700)), 30.004, accuracy: 0.001)
    }

    func testMemberwiseInitWithNonFiniteValuesStaysFinite() {
        let t = Date(timeIntervalSince1970: 1_792_312_654)
        let now = t.addingTimeInterval(10)
        func make(duration: TimeInterval?, elapsed: TimeInterval, rate: Double) -> NowPlayingInfo {
            NowPlayingInfo(title: "T", artist: nil, album: nil, appBundleID: nil, isPlaying: true,
                           duration: duration, elapsedAtStamp: elapsed, stamp: t, rate: rate,
                           contentID: nil, artworkBase64: nil)
        }
        for info in [make(duration: .infinity, elapsed: 5, rate: 1),
                     make(duration: nil, elapsed: .nan, rate: 1),
                     make(duration: nil, elapsed: 5, rate: .nan),
                     make(duration: .nan, elapsed: 5, rate: .infinity),
                     make(duration: -5, elapsed: 5, rate: 1)] {
            let e = info.elapsed(at: now)
            XCTAssertTrue(e.isFinite)
            XCTAssertGreaterThanOrEqual(e, 0)
        }
    }

    func testPlayingWithRateZeroStandsStill() throws {
        let i = try XCTUnwrap(parse(payload([#""playbackRate":1"#: #""playbackRate":0"#])))
        XCTAssertTrue(i.isPlaying)
        XCTAssertEqual(i.elapsed(at: Date(timeIntervalSince1970: 1_792_312_754)), 30.004, accuracy: 0.001)
    }

    func testInvalidParentBundleIDFallsBackToOwnBundleID() throws {
        let line = safari.replacingOccurrences(of: "com.apple.Safari", with: "x y")
        XCTAssertEqual(try XCTUnwrap(parse(line)).appBundleID, "com.apple.WebKit.GPU")
    }

    // MARK: - Cover-Größe

    func testOversizedArtworkIsDropped() throws {
        let big = String(repeating: "A", count: NowPlayingInfo.maxArtworkBase64Bytes + 1)
        let small = String(repeating: "A", count: 1024)
        func withArt(_ a: String) -> String {
            spotify.replacingOccurrences(of: #""playing":true"#, with: #""playing":true,"artworkData":"\#(a)""#)
        }
        XCTAssertNil(try XCTUnwrap(parse(withArt(big))).artworkBase64)
        XCTAssertEqual(try XCTUnwrap(parse(withArt(small))).artworkBase64, small)
    }

    // MARK: - sanitize: ZWJ/ZWNJ nur zwischen echten Zeichen, legitimer Text bleibt

    func testEmojiJoinerSequencesSurvive() {
        for text in ["\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}",
                     "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
                     "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"] {
            XCTAssertEqual(NowPlayingInfo.sanitize(text), text)
        }
    }

    func testPersianZeroWidthNonJoinerSurvives() {
        let text = "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}"
        XCTAssertEqual(NowPlayingInfo.sanitize(text), text)
    }

    func testOrphanAndDoubledJoinersAreDropped() {
        XCTAssertEqual(NowPlayingInfo.sanitize("\u{200D}a"), "a")
        XCTAssertEqual(NowPlayingInfo.sanitize("a\u{200D}"), "a")
        XCTAssertEqual(NowPlayingInfo.sanitize("a\u{200D}\u{200D}b"), "ab")
        XCTAssertEqual(NowPlayingInfo.sanitize("a\u{200B}\u{200D}b"), "ab")
        XCTAssertEqual(NowPlayingInfo.sanitize("a\u{200D}\u{200E}b"), "ab")
    }

    func testJoinersAreCappedPerField() throws {
        let out = try XCTUnwrap(NowPlayingInfo.sanitize("a" + String(repeating: "\u{200D}b", count: 100)))
        XCTAssertEqual(out.unicodeScalars.filter { $0.value == 0x200D }.count, 8)
    }

    func testLegitimateCombiningTextSurvives() {
        for text in ["Vi\u{1EC7}t Nam",                  // NFC
                     "Vie\u{0323}\u{0302}t Nam",         // NFD
                     "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}",  // Hindi
                     "Z\u{0337}\u{0321}\u{031B}a\u{0336}l\u{0338}g\u{0335}o"] {
            XCTAssertEqual(NowPlayingInfo.sanitize(text), text)
        }
    }
}
