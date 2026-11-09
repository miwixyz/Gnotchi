import XCTest
@testable import Gnotchi

/// Signal von außen → geordnetes Beenden (perl-Adapter darf nicht verwaisen, Task 22.10./Fix 09.11.).
/// Der echte SIGTERM-Fall ist nur am Prozess prüfbar (Schleife im Sichttest-Profil); hier der Mechanismus,
/// mit SIGUSR2, damit ein Fehler den Testprozess nicht beendet.
@MainActor
final class TerminationSignalsTests: XCTestCase {

    func testHandlesExternalQuitSignals() {
        XCTAssertEqual(Set(TerminationSignals.handled), [SIGTERM, SIGINT, SIGHUP])
    }

    func testSignalReachesHandlerInsteadOfKillingProcess() {
        let got = expectation(description: "Signal angekommen")
        var received: Int32?
        let sources = TerminationSignals.install([SIGUSR2]) { sig in
            received = sig
            got.fulfill()
        }
        defer { sources.forEach { $0.cancel() } }
        // An den Prozess wie `kill` von außen – `raise` zielt nur auf den eigenen Thread, das sieht die Quelle nicht.
        kill(getpid(), SIGUSR2)
        wait(for: [got], timeout: 2)
        XCTAssertEqual(received, SIGUSR2)
    }
}
