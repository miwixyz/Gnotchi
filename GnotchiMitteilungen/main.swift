import AppKit
import ApplicationServices
import OSLog

/// „Gnotchi Mitteilungen“ (0.6.0, SECURE-DESIGN G28): eigenes Programm mit eigener Bedienungshilfen-Freigabe, damit
/// Gnotchi selbst (und sein Perl-Kindprozess) ohne bleibt (G1). Gnotchi startet es nur bei eingeschaltetem Schalter;
/// es beendet sich, sobald Gnotchi die Verbindung trennt oder 10 s lang nicht erreichbar ist.
@MainActor
final class HelperApp {

    private static let log = Logger(subsystem: NotifyWire.helperBundleID, category: "app")
    private static let connectTimeout: TimeInterval = 10

    private static let gnotchiRequirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier ""# + NotifyWire.gnotchiBundleID
        + #"" and certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

    private let watcher = NotificationWatcher()
    private let dock = DockBadgeReader()
    /// Zuletzt geschickter Filter-Teil „Ungelesen-Zahlen“ – gelesen wird erst mit Freigabe.
    private var badgeApps: Set<String>?
    private var trusted = false
    private var connection: GnotchiConnection?
    private var trustTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    func start() {
        installSignalHandlers()
        guard let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Gnotchi/\(NotifyWire.socketName)").path else { return quit("kein Pfad") }
        let c = GnotchiConnection(path: path, requirement: Self.gnotchiRequirement)
        c.onCommand = { [weak self] in self?.handle($0) }
        c.onClose = { [weak self] in self?.quit("Gnotchi getrennt") }
        connection = c
        watcher.onNote = { [weak self] in self?.connection?.send(.note($0)) }
        watcher.onGone = { [weak self] in self?.connection?.send(.gone($0)) }
        dock.onChange = { [weak self] in self?.connection?.send(.badges($0)) }
        connectWithRetry(started: Date())
    }

    private func connectWithRetry(started: Date) {
        guard let connection else { return }
        if connection.connect() { return afterConnect() }
        guard Date().timeIntervalSince(started) < Self.connectTimeout else { return quit("Gnotchi nicht erreichbar") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { [weak self] in self?.connectWithRetry(started: started) }
        }
    }

    /// Freigabe fragen (einmal mit Systemdialog), Gnotchi den Stand melden, dann alle 2 s nachsehen, bis sie da ist.
    private func afterConnect() {
        // Schlüssel als Text: die globale Konstante ist unter Swift 6 nicht nebenläufigkeitssicher.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        connection?.send(.trust(trusted))
        if trusted { return becameTrusted() }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, AXIsProcessTrusted() else { return }
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.connection?.send(.trust(true))
                self.becameTrusted()
            }
        }
    }

    private func becameTrusted() {
        trusted = true
        watcher.start()
        updateDock()
    }

    private func handle(_ command: NotifyWire.Command) {
        switch command {
        case .filter(let apps, let calls, let badges):
            watcher.filter = .init(apps: Set(apps), calls: calls)
            badgeApps = badges ? Set(apps) : nil
            updateDock()
        case .shown(let id): watcher.markShown(id)
        case .release(let id): watcher.release(id)
        case .act(let id, let action, let stop): watcher.perform(id: id, action: action, stopVoicemail: stop)
        }
    }

    /// Dock nur lesen, wenn eingeschaltet **und** freigegeben (G28 erweitert).
    private func updateDock() {
        guard trusted, let apps = badgeApps else { return dock.stop() }
        dock.apps = apps
        dock.start()
    }

    /// Versteckte Banner immer zurück, bevor das Programm endet – sonst bliebe Apples Mitteilungsfenster weg.
    func quit(_ reason: String) {
        watcher.stop()
        dock.stop()
        Self.log.notice("Ende: \(reason, privacy: .public)")
        exit(0)
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { MainActor.assumeIsolated { [weak self] in self?.quit("Signal \(sig)") } }
            src.resume()
            signalSources.append(src)
        }
    }
}

let helper = HelperApp()
helper.start()
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
