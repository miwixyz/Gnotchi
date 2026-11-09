import Foundation

/// Beenden von außen (SIGTERM/SIGINT/SIGHUP: `kill`, control-C, Abmelden) → geordnet über `NSApp.terminate`, damit
/// `willTerminateNotification` kommt und `stopNotch()` den perl-Adapter mitbeendet. Mit der Standardaktion starb
/// der Prozess sofort, der Adapter lief verwaist weiter (09.11. gemessen: 10 von 10 Läufen).
/// Vorbild: `GnotchiMitteilungen/main.swift` (`installSignalHandlers`).
enum TerminationSignals {
    static let handled: [Int32] = [SIGTERM, SIGINT, SIGHUP]

    /// Die Quellen muss der Aufrufer halten, sonst sind sie sofort wieder weg.
    @MainActor
    static func install(_ signals: [Int32] = handled,
                        onSignal: @escaping @MainActor (Int32) -> Void) -> [DispatchSourceSignal] {
        signals.map { sig in
            signal(sig, SIG_IGN)   // Standardaktion aus, sonst beendet das Signal den Prozess vor der Quelle
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { MainActor.assumeIsolated { onSignal(sig) } }
            src.resume()
            return src
        }
    }
}
