import XCTest

/// Stream Deck, Browser-Weg (G59 Punkt 10): Positivliste, Auswahl des Tabs, fremde Daten, feste Skripte.
@MainActor
final class BrowserTabTests: XCTestCase {

    // MARK: Positivliste

    func testAllowsOnlyExactYouTubeHosts() {
        XCTAssertTrue(BrowserTab.isAllowedURL("https://www.youtube.com/watch?v=abc"))
        XCTAssertTrue(BrowserTab.isAllowedURL("https://music.youtube.com/"))
        XCTAssertTrue(BrowserTab.isAllowedURL("HTTPS://WWW.YOUTUBE.COM/watch"))
    }

    func testRejectsLookalikesAndOtherSchemes() {
        let bad = [
            "https://www.youtube.com.evil.example/watch",      // Host nur als Anfang
            "https://evil.example/www.youtube.com",            // nur im Pfad
            "https://evil.example/?u=https://www.youtube.com", // nur im Suchteil
            "https://www.youtube.com@evil.example/",           // Benutzerteil
            "https://user:pw@www.youtube.com/",                // Zugangsdaten
            "http://www.youtube.com/watch",                    // kein https
            "javascript://www.youtube.com/%0aalert(1)",
            "https://youtube.com/watch",                       // anderer Host, nicht auf der Liste
            "https://mail.google.com/mail/u/0/",
            "", "kein url",
            "https://www.youtube.com/" + String(repeating: "a", count: 2100),
        ]
        for b in bad { XCTAssertFalse(BrowserTab.isAllowedURL(b), b) }
    }

    // MARK: Listenskript → Kandidaten

    func testCandidatesKeepOnlyAllowedTabsAndDropGarbage() {
        let listing = """
            1869061220\t1869061001\thttps://mail.google.com/mail/u/0/
            1869061220\t1869061599\thttps://www.youtube.com/watch?v=x
            1869061300\t42\thttps://music.youtube.com/
            x\t3\thttps://www.youtube.com/
            1\t0\thttps://www.youtube.com/
            1\t-5\thttps://www.youtube.com/
            1\t99999999999\thttps://www.youtube.com/
            1\t4
            \u{0}\t\t
            """
        let c = BrowserTab.candidates(from: listing)
        XCTAssertEqual(c.map { "\($0.window).\($0.index)" }, ["1869061220.1869061599", "1869061300.42"])
    }

    func testCandidatesAreCapped() {
        let listing = (1...20).map { "1\t\($0)\thttps://www.youtube.com/watch?v=\($0)" }.joined(separator: "\n")
        XCTAssertEqual(BrowserTab.candidates(from: listing).count, BrowserTab.maxCandidates)
    }

    // MARK: Auswahl

    func testTogglePrefersPlayingTab() {
        let a = BrowserTab.Tab(window: 1, index: 1, paused: true, title: "A", artist: nil)
        let b = BrowserTab.Tab(window: 1, index: 5, paused: false, title: "B", artist: nil)
        XCTAssertEqual(BrowserTab.toggleTarget([a, b]), b)
        XCTAssertEqual(BrowserTab.toggleTarget([a]), a)
        XCTAssertNil(BrowserTab.toggleTarget([]))
    }

    // MARK: Fremde Daten

    func testParseStateCleansAndLimitsText() {
        let long = String(repeating: "x", count: 500)
        let json = #"{"p":false,"t":"\#(long)","a":"Kanal\u0007‮"}"#
        let tab = BrowserTab.parseState(json, window: 1, index: 2)
        XCTAssertEqual(tab?.paused, false)
        XCTAssertEqual(tab?.title?.count, DeckWire.maxTextChars)
        XCTAssertEqual(tab?.artist, "Kanal")
    }

    func testParseStateRejectsWrongShape() {
        for bad in ["", "kein json", "[]", #"{"t":"x"}"#, #"{"p":"ja"}"#, #"{"p":1}"#, String(repeating: "a", count: 3000)] {
            XCTAssertNil(BrowserTab.parseState(bad, window: 1, index: 1), bad)
        }
        // Leere Texte werden zu nil, nicht zu leeren Zeilen.
        let t = BrowserTab.parseState(#"{"p":true,"t":"","a":""}"#, window: 1, index: 1)
        XCTAssertNotNil(t)
        XCTAssertNil(t?.title)
        XCTAssertNil(t?.artist)
    }

    // MARK: Feste Skripte

    func testJavascriptIsConstantAndGuardsHost() {
        for a in [BrowserTab.Action.read, .play, .pause] {
            let js = BrowserTab.javascript(a)
            XCTAssertTrue(js.contains("location.hostname"), "Host im Tab selbst geprüft")
            XCTAssertFalse(js.contains("\""), "keine Anführungszeichen, die das Skript aufbrechen könnten")
            XCTAssertFalse(js.contains("\\"))
            XCTAssertFalse(js.contains("fetch") || js.contains("XMLHttpRequest") || js.contains("document.cookie"))
        }
        XCTAssertFalse(BrowserTab.javascript(.read).contains("play()") || BrowserTab.javascript(.read).contains("pause()"))
        XCTAssertTrue(BrowserTab.javascript(.pause).contains("v.pause();"))
        XCTAssertTrue(BrowserTab.javascript(.play).contains("v.play();"))
    }

    func testTabScriptOnlyTakesBoundedIntegers() throws {
        let s = try XCTUnwrap(BrowserTab.tabScript(window: 2, index: 7, action: .pause))
        XCTAssertTrue(s.contains("execute tab id 7 of window id 2 javascript"))
        XCTAssertTrue(s.contains("net.imput.helium"))
        XCTAssertNil(BrowserTab.tabScript(window: 0, index: 1, action: .read))
        XCTAssertNil(BrowserTab.tabScript(window: 1, index: 99_999_999_999, action: .read))
        XCTAssertNil(BrowserTab.tabScript(window: -1, index: 1, action: .read))
    }

    /// Gemessen 17.11.: Im tell-Block von Helium ist „tab“ eine Klasse, kein Tabulator – die Liste kam als „1tab1tab…“ zurück.
    func testListScriptTakesTabCharacterBeforeTellBlock() throws {
        let s = BrowserTab.listScript
        XCTAssertFalse(s.contains("& tab &"))
        let tb = try XCTUnwrap(s.range(of: "set tb to ASCII character 9"))
        let tell = try XCTUnwrap(s.range(of: "tell application id"))
        XCTAssertLessThan(tb.lowerBound, tell.lowerBound)
    }

    func testListScriptNeverStartsHeliumAndRunsNoJavascript() {
        XCTAssertTrue(BrowserTab.listScript.contains("is not running then return"))
        XCTAssertFalse(BrowserTab.listScript.contains("javascript"))
    }

    // MARK: Wire

    func testNeedsBrowserRoundTripsAndIsOptional() throws {
        var s = DeckWire.Status(app: BrowserTab.bundleID, name: "Helium", title: nil, artist: nil, percent: nil, muted: false,
                                playing: false, canPlay: false, state: .silent)
        XCTAssertNil(DeckWire.encode(s)["needsBrowser"])
        s.needsBrowser = true
        let data = try JSONSerialization.data(withJSONObject: DeckWire.encode(s))
        XCTAssertEqual(DeckWire.parseStatus(data)?.needsBrowser, true)
    }

    func testBrowserSettingIsOffByDefault() {
        let defaults = UserDefaults(suiteName: "BrowserTabTests-\(UUID().uuidString)") ?? .standard
        XCTAssertFalse(Preferences(defaults: defaults).deckBrowserTab)
    }
}
