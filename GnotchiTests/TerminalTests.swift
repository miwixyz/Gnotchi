import Foundation
import XCTest

/// G65: Regeln des Terminalfensters (Shell, Umgebung, Titel, „läuft noch etwas?“) und der Start des Hilfsprogramms.
final class TerminalTests: XCTestCase {

    // MARK: Shell

    func testParseShellsIgnoresCommentsAndRelativeNames() {
        let text = "# List of acceptable shells\n/bin/bash\n\n  /bin/zsh  \nsh\n#/bin/evil\n"
        XCTAssertEqual(TerminalRules.parseShells(text), ["/bin/bash", "/bin/zsh"])
    }

    func testChooseShellTakesUserShellOnlyWhenListedAndExecutable() {
        let allowed = ["/bin/zsh", "/bin/bash"]
        XCTAssertEqual(TerminalRules.chooseShell(userShell: "/bin/bash", allowed: allowed, isExecutable: { _ in true }), "/bin/bash")
        XCTAssertEqual(TerminalRules.chooseShell(userShell: "/tmp/evil", allowed: allowed, isExecutable: { _ in true }), "/bin/zsh")
        XCTAssertEqual(TerminalRules.chooseShell(userShell: "/bin/bash", allowed: allowed, isExecutable: { _ in false }), "/bin/zsh")
        XCTAssertEqual(TerminalRules.chooseShell(userShell: nil, allowed: allowed, isExecutable: { _ in true }), "/bin/zsh")
        XCTAssertEqual(TerminalRules.chooseShell(userShell: "bash", allowed: ["bash"], isExecutable: { _ in true }), "/bin/zsh")
    }

    func testLoginNameHasLeadingDash() {
        XCTAssertEqual(TerminalRules.loginName("/bin/zsh"), "-zsh")
        XCTAssertEqual(TerminalRules.loginName("/opt/homebrew/bin/fish"), "-fish")
    }

    func testSystemShellIsAnExistingAbsolutePath() {
        let shell = TerminalRules.systemShell()
        XCTAssertTrue(shell.hasPrefix("/"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: shell))
        XCTAssertTrue(TerminalRules.systemHome().hasPrefix("/"))
    }

    // MARK: Umgebung

    func testEnvironmentDropsDebugVariablesAndSetsTerminalFields() {
        let inherited = ["XPC_FLAGS": "0", "DYLD_INSERT_LIBRARIES": "/x.dylib", "__CF_USER_TEXT_ENCODING": "0x1F5:0:0",
                         "MallocStackLogging": "1", "NSZombieEnabled": "YES", "TERM": "dumb", "TERM_PROGRAM": "Other",
                         "SSH_AUTH_SOCK": "/tmp/agent", "TMPDIR": "/var/folders/x/", "USER": "mwlr"]
        let env = TerminalRules.environment(inherited: inherited, shell: "/bin/zsh", home: "/Users/mwlr", version: "0.44.0",
                                            localeIdentifier: "de_DE")
        let dict = Dictionary(uniqueKeysWithValues: env.map { e -> (String, String) in
            let i = e.firstIndex(of: "=")!
            return (String(e[..<i]), String(e[e.index(after: i)...]))
        })
        XCTAssertNil(dict["XPC_FLAGS"]); XCTAssertNil(dict["DYLD_INSERT_LIBRARIES"]); XCTAssertNil(dict["__CF_USER_TEXT_ENCODING"])
        XCTAssertNil(dict["MallocStackLogging"]); XCTAssertNil(dict["NSZombieEnabled"])
        XCTAssertEqual(dict["TERM"], "xterm-256color")
        XCTAssertEqual(dict["TERM_PROGRAM"], "GnotchiTerminal")
        XCTAssertEqual(dict["TERM_PROGRAM_VERSION"], "0.44.0")
        XCTAssertEqual(dict["COLORTERM"], "truecolor")
        XCTAssertEqual(dict["SHELL"], "/bin/zsh")
        XCTAssertEqual(dict["HOME"], "/Users/mwlr")
        XCTAssertEqual(dict["LANG"], "de_DE.UTF-8")
        XCTAssertEqual(dict["SSH_AUTH_SOCK"], "/tmp/agent", "Agent und Temp-Ordner bleiben, sonst gehen git/ssh nicht")
        XCTAssertEqual(dict["TMPDIR"], "/var/folders/x/")
        XCTAssertEqual(dict["USER"], "mwlr")
    }

    func testEnvironmentKeepsExistingLang() {
        let env = TerminalRules.environment(inherited: ["LANG": "fr_FR.UTF-8"], shell: "/bin/zsh", home: "/h", version: "1",
                                            localeIdentifier: "de_DE")
        XCTAssertTrue(env.contains("LANG=fr_FR.UTF-8"))
    }

    func testLangValueAcceptsOnlyKnownShape() {
        XCTAssertEqual(TerminalRules.langValue(localeIdentifier: "de_DE"), "de_DE.UTF-8")
        XCTAssertEqual(TerminalRules.langValue(localeIdentifier: "en_US@calendar=gregorian"), "en_US.UTF-8")
        XCTAssertEqual(TerminalRules.langValue(localeIdentifier: "de"), "en_US.UTF-8")
        XCTAssertEqual(TerminalRules.langValue(localeIdentifier: "x;rm -rf_/"), "en_US.UTF-8")
        XCTAssertEqual(TerminalRules.langValue(localeIdentifier: "DE_de"), "en_US.UTF-8")
    }

    // MARK: Titel, Schrift, Beschäftigt

    func testSanitizeTitleStripsControlCharactersAndShortens() {
        XCTAssertEqual(TerminalRules.sanitizeTitle("vim\u{1B}[31m x\u{7}"), "vim[31m x")
        XCTAssertEqual(TerminalRules.sanitizeTitle("  \u{7}  "), "Terminal")
        XCTAssertEqual(TerminalRules.sanitizeTitle(String(repeating: "a", count: 500)).count, 121)
        XCTAssertEqual(TerminalRules.sanitizeTitle("Zeile1\nZeile2"), "Zeile1Zeile2")
    }

    func testIsBusyOnlyWhenForegroundDiffersFromShell() {
        XCTAssertFalse(TerminalRules.isBusy(foregroundGroup: 100, shellPid: 100))
        XCTAssertTrue(TerminalRules.isBusy(foregroundGroup: 200, shellPid: 100))
        XCTAssertFalse(TerminalRules.isBusy(foregroundGroup: -1, shellPid: 100), "Messfehler blockiert das Schließen nie")
        XCTAssertFalse(TerminalRules.isBusy(foregroundGroup: 0, shellPid: 100))
        XCTAssertFalse(TerminalRules.isBusy(foregroundGroup: 200, shellPid: 0))
    }

    func testFontSizeIsClamped() {
        XCTAssertEqual(TerminalRules.clampedFontSize(2), 9)
        XCTAssertEqual(TerminalRules.clampedFontSize(99), 36)
        XCTAssertEqual(TerminalRules.clampedFontSize(.nan), 13)
        XCTAssertEqual(TerminalRules.clampedFontSize(14), 14)
    }

    // MARK: Start aus Gnotchi

    func testHelperIsInsideOwnBundleHelpersFolder() {
        XCTAssertTrue(TerminalLauncher.helperURL.path.hasSuffix("/Contents/Helpers/Gnotchi Terminal.app"))
        XCTAssertEqual(TerminalLauncher.bundleID, "dev.mwlr.gnotchi.terminal")
    }

    func testForeignOrMissingHelperIsRejected() {
        XCTAssertFalse(TerminalLauncher.isGenuineHelper(URL(fileURLWithPath: "/nonexistent/Gnotchi Terminal.app")))
        // Apples Terminal ist gültig signiert, aber nicht von uns: Anforderung (Team, Kennung) muss ihn ablehnen.
        XCTAssertFalse(TerminalLauncher.isGenuineHelper(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")))
    }

    @MainActor func testTerminalSwitchIsOffByDefault() {
        let suite = "dev.mwlr.gnotchi.tests.terminal"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(Preferences(defaults: d).terminal)
    }
}
