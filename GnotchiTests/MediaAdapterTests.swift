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
}
