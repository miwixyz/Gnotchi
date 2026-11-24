import Foundation

/// Reine Regeln des Terminalfensters (G65): Shell wählen, Umgebung bauen, Titel säubern, „läuft noch etwas?“.
/// Ohne AppKit und ohne SwiftTerm, damit die Tests sie ohne Hilfsprogramm prüfen (project.yml: Testziel).
enum TerminalRules {

    static let fallbackShell = "/bin/zsh"
    static let programName = "GnotchiTerminal"

    // MARK: Shell

    /// Zeilen aus `/etc/shells`: nur absolute Pfade, Kommentare und Leerzeilen fallen weg.
    static func parseShells(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") && !$0.hasPrefix("#") }
    }

    /// Die Login-Shell des Nutzers, aber nur, wenn sie in `/etc/shells` steht und ausführbar ist. Sonst `/bin/zsh`.
    /// Bewusst nicht `$SHELL`: Die Umgebung ist keine Quelle für ein Programm, das gestartet wird.
    static func chooseShell(userShell: String?, allowed: [String], isExecutable: (String) -> Bool) -> String {
        if let userShell, userShell.hasPrefix("/"), allowed.contains(userShell), isExecutable(userShell) { return userShell }
        return fallbackShell
    }

    /// `argv[0]` einer Login-Shell: der Name mit führendem Bindestrich (`-zsh`).
    static func loginName(_ shell: String) -> String {
        "-" + (shell as NSString).lastPathComponent
    }

    /// Echte Werte aus dem System (Benutzerdatenbank, `/etc/shells`).
    static func systemShell() -> String {
        let user = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) }
        let text = (try? String(contentsOfFile: "/etc/shells", encoding: .utf8)) ?? ""
        return chooseShell(userShell: user, allowed: parseShells(text),
                           isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    static func systemHome() -> String {
        if let dir = getpwuid(getuid()).flatMap({ $0.pointee.pw_dir }).map({ String(cString: $0) }), dir.hasPrefix("/") { return dir }
        return NSHomeDirectory()
    }

    // MARK: Umgebung

    /// Diese Namen und Vorsätze bekommt die Shell nicht mit: Fehlersuch-Schalter und Zwischenstand von Systemdiensten.
    private static let droppedPrefixes = ["XPC_", "DYLD_", "__CF", "OS_ACTIVITY", "Malloc", "NSZombie", "CFNETWORK_DIAGNOSTICS"]
    private static let droppedNames: Set<String> = ["TERM_SESSION_ID", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "COLORTERM", "TERM"]

    /// `LANG` aus der Systemsprache (`de_DE` → `de_DE.UTF-8`); nur bekannte Form, sonst `en_US.UTF-8`.
    static func langValue(localeIdentifier: String) -> String {
        let base = localeIdentifier.split(separator: "@").first.map(String.init) ?? localeIdentifier
        let parts = base.split(separator: "_")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              parts[0].allSatisfy({ $0.isLowercase && $0.isLetter }), parts[1].allSatisfy({ $0.isUppercase && $0.isLetter })
        else { return "en_US.UTF-8" }
        return base + ".UTF-8"
    }

    /// Umgebung der Shell: die des Hilfsprogramms (kommt von launchd, nie von Gnotchi: `SSH_AUTH_SOCK`, `TMPDIR` bleiben),
    /// ohne Fehlersuch-Schalter, mit festen Terminal-Angaben. `PATH` setzt die Login-Shell selbst (`/etc/zprofile`).
    static func environment(inherited: [String: String], shell: String, home: String, version: String,
                            localeIdentifier: String) -> [String] {
        var env = inherited.filter { key, _ in
            !droppedNames.contains(key) && !droppedPrefixes.contains { key.hasPrefix($0) }
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = programName
        env["TERM_PROGRAM_VERSION"] = version
        env["SHELL"] = shell
        env["HOME"] = home
        if env["LANG"] == nil { env["LANG"] = langValue(localeIdentifier: localeIdentifier) }
        return env.keys.sorted().map { "\($0)=\(env[$0] ?? "")" }
    }

    // MARK: Anzeige

    /// Fenstertitel aus dem Programm im Terminal (Steuerzeichen entfernen, kürzen). Leer → „Terminal“.
    static func sanitizeTitle(_ raw: String, limit: Int = 120) -> String {
        let cleaned = String(raw.unicodeScalars.filter { !$0.properties.generalCategory.isControl })
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return "Terminal" }
        return cleaned.count > limit ? String(cleaned.prefix(limit)) + "…" : cleaned
    }

    // MARK: Läuft noch etwas?

    /// Im Vordergrund steht etwas anderes als die Shell selbst. `foregroundGroup` kommt aus `tcgetpgrp`, `shellPid`
    /// ist zugleich die Prozessgruppe der Shell (Sitzungsführer). Unbekannt (≤ 0) → nicht „beschäftigt“, damit ein
    /// Messfehler das Schließen nie blockiert.
    static func isBusy(foregroundGroup: pid_t, shellPid: pid_t) -> Bool {
        foregroundGroup > 0 && shellPid > 0 && foregroundGroup != shellPid
    }

    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 36
    static let defaultFontSize: CGFloat = 13

    static func clampedFontSize(_ size: CGFloat) -> CGFloat {
        guard size.isFinite else { return defaultFontSize }
        return min(maxFontSize, max(minFontSize, size))
    }
}

private extension Unicode.GeneralCategory {
    var isControl: Bool {
        switch self {
        case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: true
        default: false
        }
    }
}
