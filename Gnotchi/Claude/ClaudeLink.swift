import AppKit
import OSLog
import Security

/// Code & KI (0.9.0, G34/G35): Socket `claude.sock` für das Hook-Programm „Gnotchi Claude“ und die eigenen Hook-Einträge
/// in `~/.claude/settings.json`, solange „Claude Code in der Notch“ an ist.
///
/// - Gnotchi prüft das Hook-Programm vor dem ersten Byte (Audit-Token gegen Developer ID + `dev.mwlr.gnotchi.claude`);
///   das Hook-Programm prüft Gnotchi, bevor es sendet.
/// - Einträge nur, wenn die Einstellungsdatei byte-genau erhalten bleibt (ClaudeSettings); sonst Hinweis.
/// - Beim Beenden von Gnotchi bleiben die Einträge (das Hook-Programm endet dann still); nur der Schalter „aus“ entfernt sie.
@MainActor
final class ClaudeLink: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "claude")
    nonisolated static let requirement = LiveText.peerRequirement(identifier: ClaudeWire.hookBundleID)

    private let activity: ActivityModel
    private let prefs: Preferences
    private let settingsURL: URL
    private var server: PeerSocketServer<ClaudeWire.Message>?
    private var pruneTimer: Timer?

    init(activity: ActivityModel, prefs: Preferences,
         settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")) {
        self.activity = activity
        self.prefs = prefs
        self.settingsURL = settingsURL
    }

    nonisolated static var hookURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Gnotchi Claude.app")
    }

    nonisolated static var hookExecutable: String {
        hookURL.appendingPathComponent("Contents/MacOS/Gnotchi Claude").path
    }

    func start() {
        guard server == nil, let dir = LiveTextLink.directory else { return }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(Self.requirement as CFString, [], &req) == errSecSuccess, let req else {
            return Self.log.error("Claude: Anforderung ungültig")
        }
        let s = PeerSocketServer<ClaudeWire.Message>(
            directory: dir, fileName: ClaudeWire.socketName, label: "Claude", peer: "Hook-Programm",
            requirement: req, maxFrame: ClaudeWire.maxFrame, coalesce: false,
            parse: { ClaudeWire.parse($0) },
            onValue: { [weak self] m in Task { @MainActor in if let m { self?.receive(m) } } })
        do {
            try s.start()
        } catch {
            return Self.log.error("Claude aus: \(String(describing: error), privacy: .public)")
        }
        server = s
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.activity.pruneClaude() }
        }
        pruneTimer?.tolerance = 6   // Weckzeiten bündeln (Akku, BAMA-Check 28.10.)
        installHooks()
    }

    /// Nur die Ereignis-Art ins Protokoll (Messpunkt Sichttest 22.10.), nie Projekt oder Text (G34).
    private func receive(_ m: ClaudeWire.Message) {
        activity.receiveClaude(m)
        Self.log.notice("Claude: Ereignis \(m.event.rawValue, privacy: .public), App \(m.app ?? "unbekannt", privacy: .public), \(self.activity.claudeSessions.count, privacy: .public) Sitzung(en)")
    }

    func stop() {
        server?.stop()
        server = nil
        pruneTimer?.invalidate()
        pruneTimer = nil
        activity.clearClaude()
        // Nur „aus“ entfernt die Einträge – nicht das Beenden von Gnotchi (sonst jedes Mal die Datei umschreiben).
        if !prefs.claudeCode { setHooks(nil) }
    }

    /// Eigene Einträge auf den aktuellen Paketpfad bringen (verschoben, Testkopie) – nur das signaturgeprüfte Programm.
    private func installHooks() {
        guard Self.isGenuineHook(Self.hookURL) else {
            activity.claudeSetupNote = "Hook-Programm fehlt oder Signatur ungültig – nichts eingetragen."
            return Self.log.error("Claude: Hook-Programm fehlt oder Signatur ungültig")
        }
        setHooks(Self.hookExecutable)
    }

    private func setHooks(_ path: String?) {
        do {
            try ClaudeSettings.apply(fileURL: settingsURL, hookPath: path)
            activity.claudeSetupNote = nil
            Self.log.notice("Claude: Hooks \(path == nil ? "entfernt" : "eingetragen", privacy: .public)")
        } catch {
            activity.claudeSetupNote = Self.note(for: error)
            Self.log.error("Claude: Einstellungen nicht geändert (\(String(describing: error), privacy: .public))")
        }
    }

    /// Beim Start mit Schalter „aus“: übrig gebliebene eigene Einträge (gelöschte Testkopie, Einstellung zurückgesetzt)
    /// entfernen – nur wenn welche drin sind, über denselben byte-genauen Weg (G35). Sonst wird die Datei nicht angefasst.
    static func removeLeftoverHooks(settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
                                        .appendingPathComponent(".claude/settings.json")) {
        guard let text = try? String(contentsOf: settingsURL, encoding: .utf8),
              text.contains(ClaudeWire.hookMarker) else { return }
        do {
            try ClaudeSettings.apply(fileURL: settingsURL, hookPath: nil)
            log.notice("Claude: übrig gebliebene Hooks entfernt")
        } catch {
            log.error("Claude: übrig gebliebene Hooks nicht entfernt (\(String(describing: error), privacy: .public))")
        }
    }

    nonisolated static func note(for failure: ClaudeSettings.Failure) -> String {
        switch failure {
        case .notIdentical:
            "~/.claude/settings.json hat ein Format, das Gnotchi nicht unverändert zurückschreiben kann – nichts geändert."
        case .notJSON, .notObject: "~/.claude/settings.json ist kein gültiges JSON – nichts geändert."
        case .tooLarge: "~/.claude/settings.json ist größer als 1 MB – nichts geändert."
        case .unreadable: "~/.claude/settings.json ließ sich nicht lesen oder schreiben – nichts geändert."
        }
    }

    nonisolated static func isGenuineHook(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req) == errSecSuccess
    }

    /// Klick auf eine Sitzung: nur das laufende Programm mit genau dieser PID **und** Kennung nach vorn (G34).
    /// Über LaunchServices (`openApplication`, activates) – `NSRunningApplication.activate()` ignoriert macOS, wenn
    /// Gnotchi selbst nicht vorn ist (Sichttest 22.10.: Obsidian kam nicht nach vorn).
    static func open(_ session: ClaudeSession) {
        guard let pid = session.pid, let id = session.app,
              let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == id,
              let url = app.bundleURL else {
            return log.notice("Claude: Klick – Programm der Sitzung läuft nicht mehr")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            log.notice("Claude: Klick – \(error == nil ? "nach vorn geholt" : "fehlgeschlagen", privacy: .public)")
        }
    }
}
