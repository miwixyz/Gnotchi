import AppKit
import OSLog

/// Messpunkt 0.16.0 (Michael 27.10.: „Eindruck, dass der Fokus genommen wird, kann mich aber täuschen“): meldet ins
/// Protokoll, wenn während einer sichtbaren Mitteilung oder eines Anrufs die vorderste App wechselt – und ob das Gnotchi
/// oder sein Hilfsprogramm war. Nur ja/nein, nie App-Namen (Protokoll-Regel).
/// Lesen: `log show --last 1h --info --predicate 'subsystem == "dev.mwlr.gnotchi" AND category == "fokus"'`.
@MainActor
final class FocusProbe {
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "fokus")
    private var observer: NSObjectProtocol?
    private let showing: @MainActor () -> Bool

    init(showing: @escaping @MainActor () -> Bool) {
        self.showing = showing
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let own = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            let helper = app?.bundleIdentifier == NotifyWire.helperBundleID
            MainActor.assumeIsolated { self?.report(own: own, helper: helper) }
        }
    }

    private func report(own: Bool, helper: Bool) {
        guard showing() else { return }
        Self.log.notice("""
            Vordere App gewechselt, während eine Mitteilung zu sehen ist (Gnotchi: \(own ? "ja" : "nein", privacy: .public), \
            Hilfsprogramm: \(helper ? "ja" : "nein", privacy: .public))
            """)
    }
}
