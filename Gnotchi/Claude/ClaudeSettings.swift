import Foundation

/// `~/.claude/settings.json` bearbeiten (0.9.0, SECURE-DESIGN G35): **nur** Gnotchis eigene Hook-Einträge, und nur, wenn
/// die Datei nach Lesen und Zurückschreiben byte-gleich herauskommt. Sonst wird nichts geschrieben.
///
/// Die Datei wird von Claude Code und von Hand gepflegt (Michael: 20 eigene Hooks, Schlüssel in eigener Reihenfolge).
/// `JSONSerialization` verliert die Reihenfolge – deshalb ein kleiner reihenfolgetreuer Leser/Schreiber im Format von
/// Pythons `json.dumps(indent=2, ensure_ascii=False)` (gemessen 22.10.: genau das Format der Datei).
enum ClaudeSettings {

    /// Reihenfolgetreuer JSON-Wert. Zahlen bleiben als Originaltext (kein Rundungsunterschied beim Zurückschreiben).
    indirect enum JSON: Equatable {
        case object([(String, JSON)])
        case array([JSON])
        case string(String)
        case number(String)
        case bool(Bool)
        case null

        static func == (a: JSON, b: JSON) -> Bool {
            switch (a, b) {
            case (.object(let x), .object(let y)):
                x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            case (.array(let x), .array(let y)): x == y
            case (.string(let x), .string(let y)): x == y
            case (.number(let x), .number(let y)): x == y
            case (.bool(let x), .bool(let y)): x == y
            case (.null, .null): true
            default: false
            }
        }

        subscript(key: String) -> JSON? {
            guard case .object(let pairs) = self else { return nil }
            return pairs.first { $0.0 == key }?.1
        }
    }

    enum Failure: Error, Equatable {
        case unreadable, tooLarge, notJSON, notIdentical, notObject
    }

    nonisolated static let maxSize = 1024 * 1024
    /// Ereignisse, für die Gnotchi einen Hook einträgt (Spec Code & KI).
    nonisolated static let events = ["UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]

    // MARK: Eintragen / Entfernen (rein, getestet)

    /// Der Shell-Befehl im Hook: läuft auch, wenn Gnotchi gelöscht wurde (dann still). Pfad in einfachen Anführungszeichen;
    /// ein `'` im Pfad wird verweigert (nil).
    nonisolated static func command(hookPath: String) -> String? {
        guard !hookPath.contains("'"), hookPath.contains(ClaudeWire.hookMarker) else { return nil }
        return "test -x '\(hookPath)' && '\(hookPath)' || true"
    }

    /// Text → Text mit Gnotchis Hooks (`hookPath` nil = entfernen). Wirft, wenn das Original nicht byte-gleich
    /// wiederhergestellt werden kann – dann darf nichts geschrieben werden.
    nonisolated static func updated(_ text: String, hookPath: String?) throws(Failure) -> String {
        guard text.utf8.count <= maxSize else { throw .tooLarge }
        guard let root = Parser.parse(text) else { throw .notJSON }
        guard Printer.print(root.value) + root.trailing == text else { throw .notIdentical }
        guard case .object = root.value else { throw .notObject }
        let new = withHooks(root.value, command: hookPath.flatMap(command(hookPath:)))
        return Printer.print(new) + root.trailing
    }

    /// Sind Gnotchis Hooks (genau mit diesem Pfad) für alle Ereignisse drin?
    nonisolated static func isInstalled(_ text: String, hookPath: String) -> Bool {
        guard let root = Parser.parse(text), let cmd = command(hookPath: hookPath),
              case .object(let hooks)? = root.value["hooks"] else { return false }
        return events.allSatisfy { ev in
            guard case .array(let groups)? = hooks.first(where: { $0.0 == ev })?.1 else { return false }
            return groups.contains { ownCommands($0).contains(cmd) }
        }
    }

    nonisolated private static func withHooks(_ root: JSON, command: String?) -> JSON {
        guard case .object(var top) = root else { return root }
        var hooks: [(String, JSON)] = []
        if case .object(let h)? = root["hooks"] { hooks = h }
        // Erst alle eigenen Einträge raus (auch alte Pfade), leere Gruppen/Ereignisse dabei weg.
        hooks = hooks.compactMap { ev, value in
            guard case .array(let groups) = value else { return (ev, value) }
            let kept = groups.compactMap(removingOwn)
            if kept.isEmpty && groups.contains(where: { removingOwn($0) == nil }) { return nil }
            return (ev, .array(kept))
        }
        if let command {
            let entry = JSON.object([("hooks", .array([.object([("type", .string("command")), ("command", .string(command)),
                                                               ("async", .bool(true))])]))])
            for ev in events {
                if let i = hooks.firstIndex(where: { $0.0 == ev }), case .array(let groups) = hooks[i].1 {
                    hooks[i].1 = .array(groups + [entry])
                } else {
                    hooks.append((ev, .array([entry])))
                }
            }
        }
        if let i = top.firstIndex(where: { $0.0 == "hooks" }) {
            if hooks.isEmpty { top.remove(at: i) } else { top[i].1 = .object(hooks) }
        } else if !hooks.isEmpty {
            top.append(("hooks", .object(hooks)))
        }
        return .object(top)
    }

    /// Gruppe ohne eigene Hook-Einträge; nil, wenn danach keiner mehr übrig ist (Gruppe war nur Gnotchis).
    nonisolated private static func removingOwn(_ group: JSON) -> JSON? {
        guard case .object(var pairs) = group, let i = pairs.firstIndex(where: { $0.0 == "hooks" }),
              case .array(let list) = pairs[i].1 else { return group }
        let kept = list.filter { !isOwn($0) }
        guard kept.count != list.count else { return group }
        if kept.isEmpty { return nil }
        pairs[i].1 = .array(kept)
        return .object(pairs)
    }

    nonisolated private static func ownCommands(_ group: JSON) -> [String] {
        guard case .array(let list)? = group["hooks"] else { return [] }
        return list.compactMap { if case .string(let c)? = $0["command"], c.contains(ClaudeWire.hookMarker) { c } else { nil } }
    }

    nonisolated private static func isOwn(_ hook: JSON) -> Bool {
        if case .string(let c)? = hook["command"] { return c.contains(ClaudeWire.hookMarker) }
        return false
    }

    // MARK: Datei (atomar, mit Sicherung)

    /// Liest, ändert, sichert, schreibt atomar mit gleichen Rechten. Fehlt die Datei und es soll eingetragen werden →
    /// neue Datei nur mit den Hooks.
    nonisolated static func apply(fileURL: URL, hookPath: String?) throws(Failure) {
        let fm = FileManager.default
        var isLink = false
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path) {
            isLink = (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
            if let size = attrs[.size] as? Int, size > maxSize { throw .tooLarge }
        }
        guard !isLink else { throw .unreadable }
        let original: String
        if fm.fileExists(atPath: fileURL.path) {
            guard let t = try? String(contentsOf: fileURL, encoding: .utf8) else { throw .unreadable }
            original = t
        } else {
            guard hookPath != nil else { return }
            original = "{}\n"
        }
        let new = try updated(original, hookPath: hookPath)
        guard new != original else { return }
        let exists = fm.fileExists(atPath: fileURL.path)
        let perms = (try? fm.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int) ?? 0o600
        if exists {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("settings.json.gnotchi-backup")
            try writeAtomically(Data(original.utf8), to: backup, permissions: 0o600)
        }
        // Unmittelbar davor noch einmal lesen (Review 22.10.): Hat Claude Code die Datei inzwischen geändert, ginge
        // dessen Änderung sonst verloren → nichts schreiben, beim nächsten Start/Schalten erneut.
        let now = exists ? (try? String(contentsOf: fileURL, encoding: .utf8)) : nil
        guard !exists || now == original else { throw .unreadable }
        try writeAtomically(Data(new.utf8), to: fileURL, permissions: perms)
    }

    /// Temporäre Datei gleich mit den Zielrechten anlegen, dann umbenennen (Review 22.10.: `.atomic` legte sie erst mit
    /// Standardrechten an – kurz für andere lesbar).
    nonisolated static func writeAtomically(_ data: Data, to url: URL, permissions: Int) throws(Failure) {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).gnotchi-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: tmp.path, contents: data,
                                             attributes: [.posixPermissions: permissions]) else { throw .unreadable }
        guard rename(tmp.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw .unreadable
        }
    }

    // MARK: Leser

    struct Parsed { let value: JSON; let trailing: String }

    enum Parser {
        nonisolated static func parse(_ text: String) -> Parsed? {
            var p = ClaudeJSONCursor(Array(text.unicodeScalars))
            p.skipSpace()
            guard let v = p.value(depth: 0) else { return nil }
            let rest = String(String.UnicodeScalarView(p.s[p.i...]))
            guard rest.unicodeScalars.allSatisfy({ $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }) else { return nil }
            return Parsed(value: v, trailing: rest)
        }

    }

    // MARK: Schreiber (Format wie Python json.dumps(indent=2, ensure_ascii=False))

    enum Printer {
        nonisolated static func print(_ v: JSON, level: Int = 0) -> String {
            let pad = String(repeating: "  ", count: level + 1)
            let end = String(repeating: "  ", count: level)
            switch v {
            case .object(let pairs):
                if pairs.isEmpty { return "{}" }
                let body = pairs.map { "\(pad)\(quote($0.0)): \(print($0.1, level: level + 1))" }.joined(separator: ",\n")
                return "{\n\(body)\n\(end)}"
            case .array(let items):
                if items.isEmpty { return "[]" }
                let body = items.map { pad + print($0, level: level + 1) }.joined(separator: ",\n")
                return "[\n\(body)\n\(end)]"
            case .string(let s): return quote(s)
            case .number(let n): return n
            case .bool(let b): return b ? "true" : "false"
            case .null: return "null"
            }
        }

        nonisolated static func quote(_ s: String) -> String {
            var out = "\""
            for c in s.unicodeScalars {
                switch c {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\u{8}": out += "\\b"
                case "\u{C}": out += "\\f"
                default:
                    if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
                }
            }
            return out + "\""
        }
    }
}

/// Leser-Zeiger für `ClaudeSettings.Parser` (außerhalb, damit Typen höchstens eine Ebene tief verschachtelt sind).
struct ClaudeJSONCursor {
    let s: [Unicode.Scalar]
    var i = 0
    init(_ s: [Unicode.Scalar]) { self.s = s }

    mutating func skipSpace() {
        while i < s.count, [" ", "\n", "\r", "\t"].contains(s[i]) { i += 1 }
    }

    mutating func value(depth: Int) -> ClaudeSettings.JSON? {
        guard depth < 64, i < s.count else { return nil }
        switch s[i] {
        case "{": return object(depth: depth)
        case "[": return array(depth: depth)
        case "\"": return string().map(ClaudeSettings.JSON.string)
        case "t": return literal("true", .bool(true))
        case "f": return literal("false", .bool(false))
        case "n": return literal("null", .null)
        default: return number()
        }
    }

    mutating func literal(_ word: String, _ v: ClaudeSettings.JSON) -> ClaudeSettings.JSON? {
        let w = Array(word.unicodeScalars)
        guard i + w.count <= s.count, Array(s[i..<i + w.count]) == w else { return nil }
        i += w.count
        return v
    }

    mutating func number() -> ClaudeSettings.JSON? {
        let start = i
        while i < s.count, "-+.eE0123456789".unicodeScalars.contains(s[i]) { i += 1 }
        guard i > start else { return nil }
        let lex = String(String.UnicodeScalarView(s[start..<i]))
        guard Double(lex) != nil else { return nil }
        return .number(lex)
    }

    mutating func string() -> String? {
        guard s[i] == "\"" else { return nil }
        i += 1
        var out = String.UnicodeScalarView()
        while i < s.count {
            let c = s[i]
            i += 1
            if c == "\"" { return String(out) }
            if c.value < 0x20 { return nil }
            guard c == "\\" else { out.append(c); continue }
            guard let e = escape() else { return nil }
            out.append(e)
        }
        return nil
    }

    /// Nach einem `\`: das gemeinte Zeichen (auch `\uXXXX` und Ersatzpaare), nil = ungültig.
    mutating func escape() -> Unicode.Scalar? {
        guard i < s.count else { return nil }
        let e = s[i]
        i += 1
        switch e {
        case "\"", "\\", "/": return e
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "b": return "\u{8}"
        case "f": return "\u{C}"
        case "u":
            guard let unit = hex4() else { return nil }
            guard (0xD800...0xDBFF).contains(unit) else { return Unicode.Scalar(unit) }
            guard i + 1 < s.count, s[i] == "\\", s[i + 1] == "u" else { return nil }
            i += 2
            guard let low = hex4(), (0xDC00...0xDFFF).contains(low) else { return nil }
            return Unicode.Scalar(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
        default: return nil
        }
    }

    mutating func hex4() -> UInt32? {
        guard i + 4 <= s.count else { return nil }
        let h = String(String.UnicodeScalarView(s[i..<i + 4]))
        i += 4
        return UInt32(h, radix: 16)
    }

    mutating func object(depth: Int) -> ClaudeSettings.JSON? {
        i += 1
        var pairs: [(String, ClaudeSettings.JSON)] = []
        skipSpace()
        if i < s.count, s[i] == "}" { i += 1; return .object(pairs) }
        while i < s.count {
            skipSpace()
            guard i < s.count, let k = string() else { return nil }
            skipSpace()
            guard i < s.count, s[i] == ":" else { return nil }
            i += 1
            skipSpace()
            guard let v = value(depth: depth + 1) else { return nil }
            pairs.append((k, v))
            skipSpace()
            guard i < s.count else { return nil }
            if s[i] == "," { i += 1; continue }
            if s[i] == "}" { i += 1; return .object(pairs) }
            return nil
        }
        return nil
    }

    mutating func array(depth: Int) -> ClaudeSettings.JSON? {
        i += 1
        var items: [ClaudeSettings.JSON] = []
        skipSpace()
        if i < s.count, s[i] == "]" { i += 1; return .array(items) }
        while i < s.count {
            skipSpace()
            guard let v = value(depth: depth + 1) else { return nil }
            items.append(v)
            skipSpace()
            guard i < s.count else { return nil }
            if s[i] == "," { i += 1; continue }
            if s[i] == "]" { i += 1; return .array(items) }
            return nil
        }
        return nil
    }
}
