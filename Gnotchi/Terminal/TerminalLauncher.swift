import AppKit
import OSLog

/// Terminalfenster (0.44.0, G65): startet das eingebettete Hilfsprogramm „Gnotchi Terminal“. Gnotchi redet danach nie wieder mit
/// ihm (kein Socket, keine Nachricht). Gestartet wird nur der Pfad im eigenen Bundle und nur nach Signaturprüfung.
enum TerminalLauncher {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "terminal")
    nonisolated static let bundleID = "dev.mwlr.gnotchi.terminal"
    nonisolated static let requirement = LiveText.peerRequirement(identifier: bundleID)

    nonisolated static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Gnotchi Terminal.app")
    }

    /// Fremder oder fehlender Helfer → `false`. Dieselbe Prüfung wie bei „Gnotchi Mitteilungen“.
    nonisolated static func isGenuineHelper(_ url: URL, requirement: String = requirement) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req) == errSecSuccess
    }

    /// Öffnet das Terminal. Scheitert das, sagt Gnotchi es (nie stumm).
    @MainActor static func open() {
        let url = helperURL
        guard isGenuineHelper(url) else {
            log.error("Terminal: Hilfsprogramm fehlt oder Signatur ungültig – nicht gestartet")
            return fail("Das Terminal-Hilfsprogramm fehlt oder seine Signatur ist ungültig. Installiere Gnotchi neu.")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            guard let error else { return }
            log.error("Terminal: Start fehlgeschlagen (\(error.localizedDescription, privacy: .public))")
            Task { @MainActor in fail("Das Terminal ließ sich nicht starten: \(error.localizedDescription)") }
        }
    }

    @MainActor private static func fail(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Terminal"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
