// SYNTHETISCH – erfundene Beispieldaten, keine echten Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
import XCTest
@testable import Gnotchi

/// G3/G9: feste Argumente, Neustart mit wachsender Pause, nach 3 Abbrüchen Schluss.
final class MediaAdapterTests: XCTestCase {

    private let paths = MediaAdapter.Paths(
        script: URL(fileURLWithPath: "/A/Gnotchi.app/Contents/Resources/mediaremote-adapter.pl"),
        framework: URL(fileURLWithPath: "/A/Gnotchi.app/Contents/Frameworks/MediaRemoteAdapter.framework"),
        testClient: URL(fileURLWithPath: "/A/Gnotchi.app/Contents/MacOS/MediaRemoteAdapterTestClient"))

    func testBackoff() {
        XCTAssertEqual(MediaAdapter.restartDelay(afterFailures: 1), 1)
        XCTAssertEqual(MediaAdapter.restartDelay(afterFailures: 2), 5)
        XCTAssertNil(MediaAdapter.restartDelay(afterFailures: 3))
    }

    /// 0.1.1: Ein gescheiterter Selbsttest (19.10., 1,7 Min. nach dem Booten) blieb 20 Std. stehen.
    /// Jetzt neuer Versuch nach 5 s, 30 s, 2 Min., danach alle 5 Min. ohne Ende.
    func testRetestStaffel() {
        XCTAssertEqual(MediaAdapter.retestDelay(afterFailedTests: 1), 5)
        XCTAssertEqual(MediaAdapter.retestDelay(afterFailedTests: 2), 30)
        XCTAssertEqual(MediaAdapter.retestDelay(afterFailedTests: 3), 120)
        XCTAssertEqual(MediaAdapter.retestDelay(afterFailedTests: 4), 300)
        XCTAssertEqual(MediaAdapter.retestDelay(afterFailedTests: 1_000), 300)
    }

    /// Ursache unterscheiden: Zeitlimit, Exit-Code, Signal, Start gescheitert.
    func testTestOutcomeClassification() {
        XCTAssertEqual(MediaAdapter.testOutcome(launched: false, timedOut: false, reason: .exit, status: 0), .launchFailed)
        XCTAssertEqual(MediaAdapter.testOutcome(launched: true, timedOut: true, reason: .uncaughtSignal, status: 15), .timedOut)
        XCTAssertEqual(MediaAdapter.testOutcome(launched: true, timedOut: false, reason: .exit, status: 0), .ok)
        XCTAssertEqual(MediaAdapter.testOutcome(launched: true, timedOut: false, reason: .exit, status: 3), .exitCode(3))
        XCTAssertEqual(MediaAdapter.testOutcome(launched: true, timedOut: false, reason: .uncaughtSignal, status: 9), .signal(9))
    }

    /// Protokolltext nur mit Statuscode – keine Titel, keine App-Namen (Regel der App-Familie).
    func testTestOutcomeLogText() {
        XCTAssertEqual(MediaAdapter.TestOutcome.timedOut.logText, "Zeitlimit 10 s überschritten")
        XCTAssertEqual(MediaAdapter.TestOutcome.exitCode(3).logText, "Exit-Code 3")
        XCTAssertEqual(MediaAdapter.TestOutcome.signal(9).logText, "Signal 9")
        XCTAssertEqual(MediaAdapter.TestOutcome.launchFailed.logText, "Start fehlgeschlagen")
    }

    func testStreamArguments() {
        XCTAssertEqual(MediaAdapter.arguments(paths, .stream),
                       [paths.script.path, paths.framework.path, "stream", "--no-diff", "--micros", "--debounce=100"])
    }

    func testTestArgumentsIncludeClient() {
        XCTAssertEqual(MediaAdapter.arguments(paths, .test),
                       [paths.script.path, paths.framework.path, paths.testClient.path, "test"])
    }

    func testCleanEnvironmentHasNoPerlVariables() {
        // G3 (Review 18.10.): PERL5OPT/PERL5LIB per `launchctl setenv` würden sonst fremden Code laden.
        XCTAssertEqual(MediaAdapter.cleanEnvironment, ["PATH": "/usr/bin:/bin"])
    }

    func testPerlProcessUsesFixedExecutableAndEnvironment() {
        // Jeder Perl-Start läuft über diese Fabrik – sonst vergisst ein Aufrufer die Umgebung.
        let proc = MediaAdapter.perlProcess(["x"])
        XCTAssertEqual(proc.executableURL, URL(fileURLWithPath: "/usr/bin/perl"))
        XCTAssertEqual(proc.arguments, ["x"])
        XCTAssertEqual(proc.environment, ["PATH": "/usr/bin:/bin"])
        XCTAssertTrue((proc.standardOutput as? FileHandle) === FileHandle.nullDevice)
        XCTAssertTrue((proc.standardError as? FileHandle) === FileHandle.nullDevice)
    }

    func testFailuresResetAfterLongRun() {
        // Review 18.10.: Der Strom meldet sofort `payload:{}` – ein Rücksetzen bei jeder Zeile
        // ergäbe eine endlose Neustartschleife. Nur ein Lauf ≥ 30 s setzt den Zähler zurück.
        XCTAssertEqual(MediaAdapter.failuresAfterExit(previous: 0, ranFor: 2), 1)
        XCTAssertEqual(MediaAdapter.failuresAfterExit(previous: 2, ranFor: 2), 3)
        XCTAssertEqual(MediaAdapter.failuresAfterExit(previous: 2, ranFor: 40), 1)
        XCTAssertEqual(MediaAdapter.failuresAfterExit(previous: 2, ranFor: 30), 1)
    }

    func testEreEscape() {
        XCTAssertEqual(MediaAdapter.ereEscape("/A/Gnotchi (2).app/x.pl"), #"/A/Gnotchi \(2\)\.app/x\.pl"#)
        XCTAssertEqual(MediaAdapter.ereEscape(#".[]()*+?{}|^$\"#), #"\.\[\]\(\)\*\+\?\{\}\|\^\$\\"#)
    }

    func testOrphanSearchOnlyLaunchdChildrenAnchored() {
        // G9: nur Waisen (Eltern = launchd), Muster verankert – trifft kein `less …/adapter.pl`.
        XCTAssertEqual(MediaAdapter.pgrepArguments(scriptPath: "/A/Gnotchi (2).app/a.pl"),
                       ["-P", "1", "-f", #"^/usr/bin/perl /A/Gnotchi \(2\)\.app/a\.pl "#])
    }

    func testCommandAndSeekArguments() {
        XCTAssertEqual(MediaAdapter.arguments(paths, .send(.toggle)).suffix(2), ["send", "2"])
        // Perl-Skript erwartet Mikrosekunden (gemessen 18.10.), begrenzt auf ≥ 0.
        XCTAssertEqual(MediaAdapter.arguments(paths, .seek(61.5)).suffix(2), ["seek", "61500000"])
        XCTAssertEqual(MediaAdapter.arguments(paths, .seek(-3)).suffix(2), ["seek", "0"])
        // Unendlich würde beim Int64-Umwandeln abstürzen.
        XCTAssertEqual(MediaAdapter.arguments(paths, .seek(.infinity)).suffix(2), ["seek", "0"])
        XCTAssertEqual(MediaAdapter.arguments(paths, .seek(.nan)).suffix(2), ["seek", "0"])
    }

    // MARK: latestEvent – je Paket nur die letzte brauchbare Zeile (Security-Review B3)

    private func line(_ s: String) -> Data { Data(s.utf8) }
    private let infoA = #"{"type":"data","payload":{"title":"Beispieltitel Eins","bundleIdentifier":"com.spotify.client","playing":true}}"#
    private let infoB = #"{"type":"data","payload":{"title":"Beispieltitel Zwei","bundleIdentifier":"com.apple.Music","playing":true}}"#
    private let empty = #"{"type":"data","diff":false,"payload":{}}"#

    func testLastLineWins() {
        let r = MediaAdapter.latestEvent(in: [line(infoA), line(infoB)])
        guard case .info(let i)? = r.event else { return XCTFail("keine Meldung") }
        XCTAssertEqual(i.title, "Beispieltitel Zwei")
        XCTAssertEqual(r.badLines, 0)
    }

    /// Leeres payload als letzte Zeile heißt weiterhin „nichts läuft“.
    func testEmptyPayloadLastClears() {
        XCTAssertEqual(MediaAdapter.latestEvent(in: [line(infoA), line(empty)]).event, .clear)
    }

    /// Die Hinweiszeile aus spike/ (G16) hat kein payload: keine Meldung, leert nicht, wird als unbrauchbar gezählt.
    func testSyntheticMarkerLineIsSkipped() {
        let marker = #"{"_hinweis":"SYNTHETISCH – erfundene Beispieldaten, keine echten Hördaten"}"#
        XCTAssertNil(NowPlayingInfo.parse(line: line(marker)))
        let r = MediaAdapter.latestEvent(in: [line(infoA), line(marker)])
        guard case .info(let i)? = r.event else { return XCTFail("keine Meldung") }
        XCTAssertEqual(i.title, "Beispieltitel Eins")
        XCTAssertEqual(r.badLines, 1)
    }

    /// Unlesbare letzte Zeile leert nicht – die letzte brauchbare davor zählt, die kaputte wird gezählt.
    func testBadLastLineFallsBackAndCounts() {
        let r = MediaAdapter.latestEvent(in: [line(infoA), line("{kaputt"), line("Müll")])
        guard case .info(let i)? = r.event else { return XCTFail("keine Meldung") }
        XCTAssertEqual(i.title, "Beispieltitel Eins")
        XCTAssertEqual(r.badLines, 2)
    }

    func testOnlyBadLines() {
        let r = MediaAdapter.latestEvent(in: [line("{kaputt"), line("x")])
        XCTAssertNil(r.event)
        XCTAssertEqual(r.badLines, 2)
        XCTAssertNil(MediaAdapter.latestEvent(in: []).event)
    }

    /// Dekodiert nur bis zur ersten brauchbaren Zeile von hinten – frühere bleiben ungelesen.
    func testEarlierLinesNotDecoded() {
        let r = MediaAdapter.latestEvent(in: [line("{kaputt"), line(infoB)])
        XCTAssertEqual(r.badLines, 0)
    }
}
