import AppKit
import OSLog
import Security

/// Betreibt den Socket `notify.sock` und das Hilfsprogramm „Gnotchi Mitteilungen“ (0.6.0, G28–G30), solange
/// „Mitteilungen in der Notch“ an ist. Gnotchi selbst bekommt keine Bedienungshilfen (G1) – nur das Hilfsprogramm.
///
/// - Gnotchi prüft das Hilfsprogramm vor dem ersten gelesenen Byte (Audit-Token gegen Developer ID +
///   `dev.mwlr.gnotchi.mitteilungen`); das Hilfsprogramm prüft Gnotchi genauso, bevor es Inhalte schickt.
/// - Inhalte nur im Arbeitsspeicher (ActivityModel), nie protokolliert.
/// - Aus → Socket zu → das Hilfsprogramm holt Apples Banner zurück und beendet sich.
@MainActor
final class NotifyLink: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "mitteilungen")
    nonisolated static let requirement = LiveText.peerRequirement(identifier: NotifyWire.helperBundleID)

    private let activity: ActivityModel
    private let prefs: Preferences
    private var server: PeerSocketServer<NotifyWire.HelperMessage>?
    private var connected = false
    private var lastFilter: NotifyWire.Command?

    init(activity: ActivityModel, prefs: Preferences) {
        self.activity = activity
        self.prefs = prefs
    }

    nonisolated static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems/Gnotchi Mitteilungen.app")
    }

    func start() {
        guard server == nil, let dir = LiveTextLink.directory else { return }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(Self.requirement as CFString, [], &req) == errSecSuccess, let req else {
            return Self.log.error("Mitteilungen: Anforderung ungültig")
        }
        let s = PeerSocketServer<NotifyWire.HelperMessage>(
            directory: dir, fileName: NotifyWire.socketName, label: "Mitteilungen", peer: "Hilfsprogramm",
            requirement: req, maxFrame: NotifyWire.maxFrame, coalesce: false,
            parse: { NotifyWire.parseHelperMessage($0) },
            onValue: { [weak self] message in Task { @MainActor in self?.receive(message) } })
        do {
            try s.start()
        } catch {
            return Self.log.error("Mitteilungen aus: \(String(describing: error), privacy: .public)")
        }
        server = s
        activity.notifyCommand = { [weak s] command in s?.send(NotifyWire.encode(command)) }
        launchHelper()
    }

    func stop() {
        activity.notifyCommand = { _ in }
        server?.stop()
        server = nil
        connected = false
        lastFilter = nil
        activity.clearNotify()
    }

    /// Schalter/App-Liste geändert (oder Einstellungen geöffnet): Filter neu schicken; Hilfsprogramm weg → neu starten.
    func recheck() {
        guard server != nil else { return }
        if connected { sendFilter() } else { launchHelper() }
    }

    func receive(_ message: NotifyWire.HelperMessage?) {
        switch message {
        case nil:
            connected = false
            lastFilter = nil
            activity.clearNotify()
        case .trust(let t)?:
            connected = true
            activity.notifyTrust = t
            sendFilter()
        case .note(let n)?:
            activity.receiveNote(n)
        case .gone(let id)?:
            activity.noteGone(id)
        }
    }

    private func sendFilter() {
        let f = NotifyWire.Command.filter(apps: prefs.notifyApps ?? [], calls: prefs.notifyCalls)
        guard f != lastFilter else { return }
        lastFilter = f
        server?.send(NotifyWire.encode(f))
    }

    /// Nur das eingebettete, signaturgeprüfte Hilfsprogramm starten (wie G24) – nie einen Pfad von außen.
    private func launchHelper() {
        let url = Self.helperURL
        guard Self.isGenuineHelper(url) else {
            return Self.log.error("Mitteilungen: Hilfsprogramm fehlt oder Signatur ungültig – nicht gestartet")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { Self.log.error("Mitteilungen: Start fehlgeschlagen (\(error.localizedDescription, privacy: .public))") }
        }
    }

    nonisolated static func isGenuineHelper(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req) == errSecSuccess
    }
}
