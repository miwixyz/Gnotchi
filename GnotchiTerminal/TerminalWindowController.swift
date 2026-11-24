import AppKit
import OSLog

/// Ein Terminalfenster mit einer Login-Shell (G65). Schließt sich, wenn die Shell endet; fragt vor dem Schließen, wenn noch
/// ein Programm läuft; beendet die Shell beim Schließen mit SIGHUP (wie Terminal.app), nie mit SIGKILL.
@MainActor
final class TerminalWindowController: NSObject, NSWindowDelegate, LocalProcessTerminalViewDelegate {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi.terminal", category: "window")
    static let fontSizeKey = "terminalFontSize"
    private static var cascadePoint = NSPoint.zero

    let window: NSWindow
    let view: GuardedTerminalView
    var onClose: ((TerminalWindowController) -> Void)?

    private var shellEnded = false
    private var confirmedClose = false

    override init() {
        let size = UserDefaults.standard.object(forKey: Self.fontSizeKey) as? Double
        view = GuardedTerminalView(frame: NSRect(x: 0, y: 0, width: 820, height: 500))
        view.applyFontSize(CGFloat(size ?? Double(TerminalRules.defaultFontSize)))
        view.autoresizingMask = [.width, .height]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 500),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Terminal"
        window.contentView = view
        window.contentMinSize = NSSize(width: 320, height: 160)
        window.isReleasedWhenClosed = false
        window.delegate = self
        view.processDelegate = self
        Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint == .zero ? NSPoint(x: 80, y: 700) : Self.cascadePoint)
    }

    /// Startet die Login-Shell im Home-Ordner. Scheitert der Start, sagt das Fenster es (nie stumm).
    func start() {
        let shell = TerminalRules.systemShell()
        let home = TerminalRules.systemHome()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let env = TerminalRules.environment(inherited: ProcessInfo.processInfo.environment, shell: shell, home: home,
                                            version: version, localeIdentifier: Locale.current.identifier)
        view.startProcess(executable: shell, args: [], environment: env,
                          execName: TerminalRules.loginName(shell), currentDirectory: home)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    // MARK: Läuft noch etwas?

    /// Im Vordergrund des Terminals steht etwas anderes als die Shell (`tcgetpgrp` gegen die Prozessgruppe der Shell).
    var isBusy: Bool {
        guard !shellEnded, view.process.running else { return false }
        return TerminalRules.isBusy(foregroundGroup: tcgetpgrp(view.process.childfd), shellPid: view.process.shellPid)
    }

    func changeFontSize(by delta: CGFloat) { setFontSize(view.currentFontSize + delta) }
    func resetFontSize() { setFontSize(TerminalRules.defaultFontSize) }

    private func setFontSize(_ size: CGFloat) {
        view.applyFontSize(size)
        UserDefaults.standard.set(Double(view.currentFontSize), forKey: Self.fontSizeKey)
    }

    // MARK: Fenster

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isBusy, !confirmedClose else { return true }
        let alert = NSAlert()
        alert.messageText = "In diesem Fenster läuft noch ein Programm."
        alert.informativeText = "Schließen beendet es."
        alert.addButton(withTitle: "Abbrechen")
        alert.addButton(withTitle: "Schließen")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            self.confirmedClose = true
            self.window.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        hangUpShell()
        onClose?(self)
    }

    /// SIGHUP an die Shell (sie gibt ihn an ihre Aufträge weiter). Danach sorgt `terminate()` für das Aufräumen der Sitzung.
    func hangUpShell() {
        guard !shellEnded, view.process.running else { return }
        let pid = view.process.shellPid
        if pid > 0 { kill(pid, SIGHUP) }
        view.terminate()
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        window.title = TerminalRules.sanitizeTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        shellEnded = true
        Self.log.notice("Shell beendet, Code \(exitCode.map(String.init) ?? "Signal", privacy: .public)")
        window.close()
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        shellEnded = true
        Self.log.error("Shell nicht gestartet: \(String(describing: error), privacy: .public)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Die Shell ließ sich nicht starten."
        alert.informativeText = "Das Terminal kann nicht öffnen. Prüfe die Anmelde-Shell des Kontos."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        window.close()
    }
}
