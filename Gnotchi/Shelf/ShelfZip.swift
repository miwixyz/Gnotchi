import Foundation

/// ZIP aus der Ablage (0.8.0, G32) – **im Prozess** über libarchive (System-Bibliothek), kein Kindprozess (G3), das
/// Passwort nie in einem Argument. Einträge nur relativ (Name bzw. Ordner/…), symbolische Links übersprungen, Grenzen
/// 10 000 Dateien / 4 GB, Ziel nie überschrieben. Optional AES-256 (gemessen 22.10.: macOS selbst öffnet das nicht).
enum ShelfZip {

    nonisolated static let maxFiles = 10_000
    nonisolated static let maxBytes: Int64 = 4 * 1024 * 1024 * 1024
    nonisolated static let minPassword = 8

    enum Failure: Error, Equatable {
        case tooMany, tooLarge, empty, write(String), read
    }

    struct Entry: Equatable {
        let source: URL
        /// Pfad im ZIP, immer relativ ohne `..`.
        let path: String
        let size: Int64
        let isDirectory: Bool
    }

    struct Result: Equatable {
        let url: URL
        let files: Int
        let skippedLinks: Int
    }

    // MARK: Einträge sammeln (rein bis aufs Dateisystem, getestet)

    /// Quellen → Einträge. Ordner rekursiv, Links (auch als Quelle) übersprungen und gezählt.
    nonisolated static func entries(for sources: [URL]) throws(Failure) -> (entries: [Entry], skippedLinks: Int) {
        var out: [Entry] = []
        var links = 0
        var total: Int64 = 0
        var usedRoots = Set<String>()
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        func append(_ e: Entry) throws(Failure) {
            out.append(e)
            total += e.size
            if out.count > maxFiles { throw .tooMany }
            if total > maxBytes { throw .tooLarge }
        }
        for src in sources {
            let v = try? src.resourceValues(forKeys: Set(keys))
            if v?.isSymbolicLink == true { links += 1; continue }
            // Zwei Quellen gleichen Namens → „Name 2“, damit nichts überschrieben wird.
            var root = safeComponent(src.lastPathComponent)
            var n = 2
            while usedRoots.contains(root) { root = "\(safeComponent(src.lastPathComponent)) \(n)"; n += 1 }
            usedRoots.insert(root)
            guard v?.isDirectory == true else {
                try append(Entry(source: src, path: root, size: Int64(v?.fileSize ?? 0), isDirectory: false))
                continue
            }
            try append(Entry(source: src, path: root, size: 0, isDirectory: true))
            guard let walker = FileManager.default.enumerator(at: src, includingPropertiesForKeys: keys,
                                                              options: [.skipsPackageDescendants]) else { continue }
            let base = src.standardizedFileURL.pathComponents.count
            for case let child as URL in walker {
                let cv = try? child.resourceValues(forKeys: Set(keys))
                if cv?.isSymbolicLink == true { links += 1; continue }
                let rel = child.standardizedFileURL.pathComponents.dropFirst(base).map(safeComponent)
                guard !rel.isEmpty else { continue }
                try append(Entry(source: child, path: ([root] + rel).joined(separator: "/"),
                                 size: Int64(cv?.fileSize ?? 0), isDirectory: cv?.isDirectory == true))
            }
        }
        guard !out.isEmpty else { throw .empty }
        return (out, links)
    }

    /// Ein Pfadteil ohne `/`, nie `.`/`..`, nie leer.
    nonisolated static func safeComponent(_ s: String) -> String {
        let c = s.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\u{0}", with: "")
        return c.isEmpty || c == "." || c == ".." ? "_" : c
    }

    /// `Ablage.zip`, `Ablage 2.zip` … im Ordner – nie eine bestehende Datei.
    nonisolated static func uniqueURL(in dir: URL, base: String = "Ablage") -> URL {
        var url = dir.appendingPathComponent("\(base).zip")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n).zip")
            n += 1
        }
        return url
    }

    // MARK: Schreiben

    /// Schreibt das ZIP nach `directory` (Standard: Downloads). Läuft lange bei großen Dateien → nicht im Hauptthread.
    nonisolated static func create(_ sources: [URL], password: String?, directory: URL) throws(Failure) -> Result {
        let (list, links) = try entries(for: sources)
        let dest = uniqueURL(in: directory)
        guard let a = archive_write_new() else { throw .write("new") }
        defer { archive_write_free(a) }
        func check(_ r: Int32, _ step: String) throws(Failure) {
            if r != 0 { throw .write(step) }
        }
        try check(archive_write_set_format_zip(a), "format")
        if let password {
            try check(archive_write_set_options(a, "zip:encryption=aes256"), "aes")
            try check(archive_write_set_passphrase(a, password), "passphrase")
        }
        try check(archive_write_open_filename(a, dest.path), "open")
        var files = 0
        var ok = false
        defer { if !ok { try? FileManager.default.removeItem(at: dest) } }   // halbes ZIP nicht liegen lassen
        for e in list {
            guard let entry = archive_entry_new() else { throw .write("entry") }
            defer { archive_entry_free(entry) }
            archive_entry_set_pathname_utf8(entry, e.isDirectory ? e.path + "/" : e.path)
            archive_entry_set_filetype(entry, e.isDirectory ? 0o040000 : 0o100000)
            archive_entry_set_perm(entry, e.isDirectory ? 0o755 : 0o644)
            let mtime = (try? e.source.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            archive_entry_set_mtime(entry, time_t(mtime?.timeIntervalSince1970 ?? 0), 0)
            archive_entry_set_size(entry, e.isDirectory ? 0 : e.size)
            try check(archive_write_header(a, entry), "header")
            if !e.isDirectory {
                // O_NOFOLLOW (Review 22.10.): Zwischen Durchlauf und Öffnen könnte ein anderes Programm die Datei durch
                // einen Link auf eine fremde Datei ersetzen – Links werden beim Öffnen abgelehnt, nicht nur beim Sammeln.
                let fd = open(e.source.path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { throw .read }
                let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? h.close() }
                while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty {
                    let n = chunk.withUnsafeBytes { archive_write_data(a, $0.baseAddress, chunk.count) }
                    if n < 0 { throw .write("data") }
                }
                files += 1
            }
            try check(archive_write_finish_entry(a), "finish")
        }
        try check(archive_write_close(a), "close")
        ok = true
        copyQuarantine(from: list.map(\.source), to: dest)
        return Result(url: dest, files: files, skippedLinks: links)
    }

    /// „Quarantäne bleibt“ (G32): Trug eine Quelle das Merkmal, bekommt das ZIP es auch (erster gefundener Wert).
    nonisolated static func copyQuarantine(from sources: [URL], to dest: URL) {
        let name = "com.apple.quarantine"
        for src in sources {
            let size = getxattr(src.path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size > 0, size < 4096 else { continue }
            var buf = [UInt8](repeating: 0, count: size)
            guard getxattr(src.path, name, &buf, size, 0, XATTR_NOFOLLOW) == size else { continue }
            setxattr(dest.path, name, buf, size, 0, XATTR_NOFOLLOW)
            return
        }
    }
}
