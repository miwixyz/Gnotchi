import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Umwandeln aus der Ablage (0.43.0, G63): Bild verkleinern, Bildformat ändern, zu einem PDF zusammenfügen.
/// **Im Prozess** über ImageIO und PDFKit (keine Shell, kein ffmpeg, keine Argumente aus Dateinamen). Das Original bleibt
/// unberührt, das Ergebnis ist immer eine **neue** Datei mit eindeutigem Namen (nie überschrieben), erst als Hilfsdatei
/// geschrieben und dann umbenannt, damit nach Abbruch oder Fehler nichts Halbes liegt.
enum ShelfConvert {

    /// Grenzen gegen Ressourcenmissbrauch; Tests setzen kleinere.
    struct Limits: Sendable {
        var maxFileBytes = 200 * 1_024 * 1_024
        var maxPixels = 400_000_000
        var maxPDFPages = 500
        /// Längste Seite eines Bildes auf einer PDF-Seite (A4 bei 300 dpi ≈ 3508).
        var pdfImageSide = 2_480
    }

    enum Format: String, CaseIterable, Sendable {
        case jpeg, png, heic
        var type: UTType {
            switch self {
            case .jpeg: .jpeg
            case .png: .png
            case .heic: .heic
            }
        }

        var ext: String { self == .jpeg ? "jpg" : rawValue }
        var title: String { rawValue.uppercased() }
    }

    enum Kind: Equatable, Sendable {
        case shrink(longSide: Int)
        case format(Format)
        case pdf
    }

    struct Failure: Equatable, Sendable {
        let name: String
        let reason: String
    }

    struct Outcome: Equatable, Sendable {
        var created: [URL] = []
        var failed: [Failure] = []
        var cancelled = false
    }

    /// Fester Wert für Qualität (Entscheidung Spec: 0,85).
    nonisolated static let quality = 0.85
    nonisolated static let shrinkSides = [2_048, 1_280, 800]

    /// Alles, was ein Lauf braucht. `isCancelled` wird zwischen den Dateien und vor dem Umbenennen gefragt
    /// (läuft auf einem Hintergrund-Faden).
    struct Context: Sendable {
        let directory: URL
        var stripLocation = true
        var limits = Limits()
        var isCancelled: @Sendable () -> Bool = { false }
    }

    // MARK: Einstieg

    nonisolated static func run(_ kind: Kind, sources: [URL], in ctx: Context) -> Outcome {
        if kind == .pdf { return mergePDF(sources, ctx) }
        var outcome = Outcome()
        for src in sources {
            if ctx.isCancelled() { outcome.cancelled = true; break }
            switch convertImage(src, kind: kind, ctx) {
            case .success(let url): outcome.created.append(url)
            case .failure(.cancelled): outcome.cancelled = true
            case .failure(let reason): outcome.failed.append(Failure(name: src.lastPathComponent, reason: reason.text))
            }
        }
        if ctx.isCancelled() { outcome.cancelled = true }
        return outcome
    }

    // MARK: Prüfung der Quelle

    enum Reason: Error, Equatable {
        case link, folder, notConvertible, empty, tooLarge, tooManyPixels, tooManyPages, unreadable, sameFormat, writeFailed, cancelled
        var text: String {
            switch self {
            case .link: "Verknüpfung übersprungen"
            case .folder: "Ordner übersprungen"
            case .notConvertible: "Kein Bild"
            case .empty: "Datei ist leer"
            case .tooLarge: "Zu groß"
            case .tooManyPixels: "Zu viele Pixel"
            case .tooManyPages: "Zu viele Seiten"
            case .unreadable: "Nicht lesbar"
            case .sameFormat: "Schon in diesem Format"
            case .writeFailed: "Konnte nicht schreiben"
            case .cancelled: "Abgebrochen"
            }
        }
    }

    /// Datei: kein Link (lstat, nicht nur Eigenschaft), kein Ordner, nicht leer, nicht zu groß. Liefert den Typ.
    nonisolated static func check(_ url: URL, limits: Limits) -> Result<UTType, Reason> {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return .failure(.unreadable) }
        if (st.st_mode & S_IFMT) == S_IFLNK { return .failure(.link) }
        if (st.st_mode & S_IFMT) == S_IFDIR { return .failure(.folder) }
        if st.st_size == 0 { return .failure(.empty) }
        if st.st_size > limits.maxFileBytes { return .failure(.tooLarge) }
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return .failure(.notConvertible) }
        return .success(type)
    }

    /// Ist die Datei etwas, das „Umwandeln“ anfasst (Bild oder PDF)? Für das Menü (ohne Grenzen).
    nonisolated static func isConvertible(_ url: URL) -> Bool {
        guard let t = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return false }
        return t.conforms(to: .image) || t.conforms(to: .pdf)
    }

    nonisolated static func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) == true
    }

    // MARK: Bilder

    /// Ziel einer Bildumwandlung: Typ, längste Seite, Dateiname ohne Endung, Endung.
    private struct Target {
        let type: UTType
        let maxSide: Int
        let base: String
        let ext: String
    }

    nonisolated private static func convertImage(_ src: URL, kind: Kind, _ ctx: Context) -> Result<URL, Reason> {
        let type: UTType
        switch check(src, limits: ctx.limits) {
        case .failure(let r): return .failure(r)
        case .success(let t): type = t
        }
        guard type.conforms(to: .image) else { return .failure(.notConvertible) }
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return .failure(.unreadable) }
        guard w * h <= ctx.limits.maxPixels else { return .failure(.tooManyPixels) }
        let name = ShelfZip.safeComponent(src.deletingPathExtension().lastPathComponent)
        let target: Target
        switch kind {
        case .shrink(let side):
            // Format bleibt, wenn wir ihn schreiben können; sonst JPEG.
            let keep = Format.allCases.first { type.conforms(to: $0.type) } ?? .jpeg
            target = Target(type: keep.type, maxSide: min(side, max(w, h)), base: name + " (klein)", ext: keep.ext)
        case .format(let f):
            if type.conforms(to: f.type) { return .failure(.sameFormat) }
            target = Target(type: f.type, maxSide: max(w, h), base: name, ext: f.ext)
        case .pdf:
            return .failure(.notConvertible)
        }
        return write(source, props, target, sources: [src], ctx)
    }

    /// Vorschaubild in Zielgröße (trägt keine Orts- und Kameradaten, Ausrichtung eingerechnet) → Hilfsdatei → umbenennen.
    nonisolated private static func write(_ source: CGImageSource, _ props: [CFString: Any], _ target: Target,
                                          sources: [URL], _ ctx: Context) -> Result<URL, Reason> {
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, target.maxSide),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary) else { return .failure(.unreadable) }
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if !ctx.stripLocation {
            // „Behalten“: übrige Angaben (Kamera, Ort …) übernehmen, nur Maße und Ausrichtung gehören nicht mehr dazu.
            for (key, value) in props where !dropKeys.contains(key) { options[key] = value }
        }
        let temp = ctx.directory.appendingPathComponent(".gnotchi-umwandeln-\(UUID().uuidString.prefix(8)).tmp")
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, target.type.identifier as CFString, 1, nil) else {
            return .failure(.writeFailed)
        }
        CGImageDestinationAddImage(dest, cg, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { discard(temp); return .failure(.writeFailed) }
        return finish(temp, base: target.base, ext: target.ext, sources: sources, ctx)
    }

    nonisolated private static var dropKeys: Set<CFString> { [
        kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyOrientation, kCGImagePropertyTIFFOrientation,
        kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyDepth, kCGImagePropertyColorModel,
        kCGImagePropertyProfileName, kCGImagePropertyHasAlpha, kCGImagePropertyIsFloat, kCGImagePropertyIsIndexed,
    ] }

    // MARK: PDF

    nonisolated private static func mergePDF(_ sources: [URL], _ ctx: Context) -> Outcome {
        var outcome = Outcome()
        let doc = PDFDocument()
        var used: [URL] = []
        for src in sources {
            if ctx.isCancelled() { outcome.cancelled = true; return outcome }
            if let reason = addToPDF(src, doc, ctx) {
                outcome.failed.append(Failure(name: src.lastPathComponent, reason: reason.text))
            } else {
                used.append(src)
            }
        }
        guard doc.pageCount > 0 else { return outcome }
        let temp = ctx.directory.appendingPathComponent(".gnotchi-umwandeln-\(UUID().uuidString.prefix(8)).tmp")
        guard doc.write(to: temp) else {
            discard(temp)
            outcome.failed.append(Failure(name: "PDF", reason: Reason.writeFailed.text))
            return outcome
        }
        switch finish(temp, base: "Ablage", ext: "pdf", sources: used, ctx) {
        case .success(let url): outcome.created = [url]
        case .failure(.cancelled): outcome.cancelled = true
        case .failure(let r): outcome.failed.append(Failure(name: "PDF", reason: r.text))
        }
        return outcome
    }

    /// Hängt die Seiten einer PDF oder ein Bild (eine Seite) an. nil = gelungen, sonst der Grund.
    nonisolated private static func addToPDF(_ src: URL, _ doc: PDFDocument, _ ctx: Context) -> Reason? {
        let type: UTType
        switch check(src, limits: ctx.limits) {
        case .failure(let r): return r
        case .success(let t): type = t
        }
        if type.conforms(to: .pdf) {
            guard let d = PDFDocument(url: src), d.pageCount > 0, !d.isLocked else { return .unreadable }
            guard doc.pageCount + d.pageCount <= ctx.limits.maxPDFPages else { return .tooManyPages }
            for i in 0..<d.pageCount { if let p = d.page(at: i)?.copy() as? PDFPage { doc.insert(p, at: doc.pageCount) } }
            return nil
        }
        guard type.conforms(to: .image) else { return .notConvertible }
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return .unreadable }
        guard w * h <= ctx.limits.maxPixels else { return .tooManyPixels }
        guard doc.pageCount < ctx.limits.maxPDFPages else { return .tooManyPages }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(ctx.limits.pdfImageSide, max(w, h)),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary), let page = PDFPage(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))) else {
            return .unreadable
        }
        doc.insert(page, at: doc.pageCount)
        return nil
    }

    // MARK: Fertigstellen

    /// Hilfsdatei → eindeutiger Name (nie überschreiben); Quarantäne von den Quellen übernehmen. Abbruch räumt auf.
    nonisolated private static func finish(_ temp: URL, base: String, ext: String, sources: [URL],
                                           _ ctx: Context) -> Result<URL, Reason> {
        if ctx.isCancelled() { discard(temp); return .failure(.cancelled) }
        for _ in 0..<20 {   // Name könnte zwischen Prüfung und Verknüpfen vergeben werden → neu versuchen
            let dest = ShelfZip.uniqueURL(in: ctx.directory, base: base, ext: ext)
            // `link` scheitert, wenn das Ziel schon existiert (anders als `rename`, das überschriebe).
            if link(temp.path, dest.path) == 0 {
                discard(temp)
                ShelfZip.copyQuarantine(from: sources, to: dest)
                return .success(dest)
            }
            if errno != EEXIST { break }
        }
        discard(temp)
        return .failure(.writeFailed)
    }

    nonisolated private static func discard(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
