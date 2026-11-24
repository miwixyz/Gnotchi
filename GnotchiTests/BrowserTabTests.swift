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

    private func tab(_ i: Int, playing: Bool) -> BrowserTab.Tab {
        BrowserTab.Tab(window: 1, index: i, paused: !playing, title: "T\(i)", artist: nil)
    }

    /// Messung 17.11. mit zwei Tabs: Video 2 lief, Druck pausierte es, nächster Druck startete Video 1. Jetzt: Video 2.
    func testPlayResumesLastActiveTabNotTheFirst() {
        let one = tab(1, playing: false), two = tab(2, playing: true)
        let active = BrowserTab.active([one, two], previous: nil)
        XCTAssertEqual(active, BrowserTab.TabID(two))
        let paused = [one, tab(2, playing: false)]
        let still = BrowserTab.active(paused, previous: active)
        XCTAssertEqual(still, BrowserTab.TabID(two), "nichts spielt → der zuletzt aktive bleibt")
        let plan = BrowserTab.plan(paused, active: still)
        XCTAssertEqual(plan?.action, .play)
        XCTAssertEqual(plan?.tabs, [tab(2, playing: false)])
        XCTAssertEqual(BrowserTab.displayed(paused, active: still)?.index, 2)
    }

    func testPausePausesEveryPlayingTab() {
        let tabs = [tab(1, playing: true), tab(2, playing: true), tab(3, playing: false)]
        let plan = BrowserTab.plan(tabs, active: BrowserTab.TabID(tabs[1]))
        XCTAssertEqual(plan?.action, .pause)
        XCTAssertEqual(plan?.tabs.map(\.index), [1, 2])
    }

    func testActiveFollowsPlayingAndFallsBack() {
        let one = tab(1, playing: false), two = tab(2, playing: false)
        XCTAssertEqual(BrowserTab.active([one, two], previous: nil), BrowserTab.TabID(one), "ohne Vorgeschichte: der erste")
        XCTAssertEqual(BrowserTab.active([tab(1, playing: true), tab(2, playing: true)], previous: BrowserTab.TabID(two)),
                       BrowserTab.TabID(two), "spielen mehrere, bleibt der aktive")
        XCTAssertEqual(BrowserTab.active([one], previous: BrowserTab.TabID(two)), BrowserTab.TabID(one), "aktiver Tab geschlossen")
        XCTAssertNil(BrowserTab.active([], previous: BrowserTab.TabID(two)))
        XCTAssertNil(BrowserTab.plan([], active: nil))
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
        let s = try XCTUnwrap(BrowserTab.tabScript(.helium, window: 2, index: 7, action: .pause))
        XCTAssertTrue(s.contains("execute tab id 7 of window id 2 javascript"))
        XCTAssertTrue(s.contains("net.imput.helium"))
        for b in DeckBrowser.all {
            XCTAssertNil(BrowserTab.tabScript(b, window: 0, index: 1, action: .read), b.name)
            XCTAssertNil(BrowserTab.tabScript(b, window: 1, index: 99_999_999_999, action: .read), b.name)
            XCTAssertNil(BrowserTab.tabScript(b, window: -1, index: 1, action: .read), b.name)
        }
    }

    // MARK: Mehrere Browser (G59 Punkt 10, 0.45)

    func testBrowserTableHasOnlyMeasuredScriptableBrowsers() {
        XCTAssertEqual(DeckBrowser.all.map(\.id),
                       ["com.google.Chrome", "com.microsoft.edgemac", "net.imput.helium", "com.apple.Safari"])
        // Search (nur lesendes sdef) und Firefox (keine Skriptschnittstelle) dürfen nie in die Tabelle.
        XCTAssertNil(DeckBrowser.with(id: "com.officecommun.search"))
        XCTAssertNil(DeckBrowser.with(id: "org.mozilla.firefox"))
        XCTAssertEqual(Set(DeckBrowser.all.map(\.id)).count, DeckBrowser.all.count)
        for b in DeckBrowser.all {
            XCTAssertTrue(DeckWire.isValidApp(b.id), b.name)
            XCTAssertTrue(DeckWire.choices.contains { $0.id == b.id }, "\(b.name) wählbar im Plugin")
        }
    }

    func testChromiumDialectUsesTabAndWindowIDs() throws {
        for b in [DeckBrowser.chrome, .edge, .helium] {
            let s = try XCTUnwrap(BrowserTab.tabScript(b, window: 3, index: 9, action: .read))
            XCTAssertTrue(s.contains("tell application id \"\(b.id)\" to return execute tab id 9 of window id 3 javascript"), b.name)
            XCTAssertTrue(BrowserTab.listScript(b).contains("(id of w) & tb & (id of t) & tb & (URL of t)"), b.name)
        }
    }

    func testSafariDialectUsesDoJavaScriptInTabPosition() throws {
        let s = try XCTUnwrap(BrowserTab.tabScript(.safari, window: 3, index: 2, action: .pause))
        XCTAssertTrue(s.contains("tell application id \"com.apple.Safari\" to return do JavaScript \""))
        XCTAssertTrue(s.contains("\" in tab 2 of window id 3"))
        XCTAssertFalse(s.contains("execute tab id"))
        let list = BrowserTab.listScript(.safari)
        XCTAssertTrue(list.contains("set i to 0"))
        XCTAssertFalse(list.contains("id of t"), "Safari kennt keine Tab-IDs")
        XCTAssertFalse(list.contains("javascript") || list.contains("JavaScript"))
    }

    /// Jedes Skript ist an seinen Browser gebunden und nie eine fremde Kennung.
    func testScriptsNameOnlyTheirOwnBrowser() throws {
        for b in DeckBrowser.all {
            let list = BrowserTab.listScript(b)
            XCTAssertEqual(list.components(separatedBy: "application id \"").count - 1, 2, "Laufprüfung + tell")
            XCTAssertTrue(list.contains("application id \"\(b.id)\" is not running then return"), b.name)
            let tab = try XCTUnwrap(BrowserTab.tabScript(b, window: 1, index: 1, action: .read))
            XCTAssertEqual(tab.components(separatedBy: "application id \"").count - 1, 1)
            XCTAssertTrue(tab.contains("application id \"\(b.id)\""), b.name)
        }
    }

    /// Gemessen 17.11.: Im tell-Block von Helium ist „tab“ eine Klasse, kein Tabulator – die Liste kam als „1tab1tab…“ zurück.
    func testListScriptTakesTabCharacterBeforeTellBlock() throws {
        for b in DeckBrowser.all {
            let s = BrowserTab.listScript(b)
            XCTAssertFalse(s.contains("& tab &"), b.name)
            let tb = try XCTUnwrap(s.range(of: "set tb to ASCII character 9"))
            let tell = try XCTUnwrap(s.range(of: "tell application id"))
            XCTAssertLessThan(tb.lowerBound, tell.lowerBound, b.name)
        }
    }

    func testListScriptNeverStartsTheBrowserAndRunsNoJavascript() {
        for b in DeckBrowser.all {
            XCTAssertTrue(BrowserTab.listScript(b).contains("is not running then return"), b.name)
            XCTAssertFalse(BrowserTab.listScript(b).lowercased().contains("javascript"), b.name)
        }
    }

    /// Gemessen 24.11. mit osascript: Safari meldet Fehler 8, Edge (Chromium) 12, wenn „JavaScript von Apple Events“ aus ist.
    func testJavascriptOffErrorCodesPerDialect() {
        XCTAssertEqual(BrowserTab.failure(12, .edge), .javascriptOff)
        XCTAssertEqual(BrowserTab.failure(12, .helium), .javascriptOff)
        XCTAssertEqual(BrowserTab.failure(8, .safari), .javascriptOff)
        XCTAssertEqual(BrowserTab.failure(12, .safari), .other, "Chromium-Nummer gilt nicht für Safari")
        XCTAssertEqual(BrowserTab.failure(8, .chrome), .other, "Safari-Nummer gilt nicht für Chromium")
        XCTAssertEqual(BrowserTab.failure(AppleScriptSource.deniedError, .safari), .denied)
        XCTAssertEqual(BrowserTab.failure(-1712, .edge), .other)
    }

    func testHintsNameTheRealMenuPaths() {
        XCTAssertEqual(DeckBrowser.helium.javascriptSettingPath, "Darstellung → Entwickler")
        XCTAssertEqual(DeckBrowser.chrome.javascriptSettingPath, "Ansicht → Entwickler")
        XCTAssertEqual(DeckBrowser.edge.javascriptSettingPath, "Ansicht → Entwickler")
        XCTAssertTrue(DeckBrowser.safari.javascriptSettingPath.hasPrefix("Einstellungen → Entwickler"))
    }

    // MARK: Wire

    func testNeedsBrowserRoundTripsAndIsOptional() throws {
        var s = DeckWire.Status(app: DeckBrowser.helium.id, name: "Helium", title: nil, artist: nil, percent: nil, muted: false,
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
