// Messprogramm für „Umwandeln“ (Spec G63). Liest einen Ordner mit Bildern/PDFs, wandelt jede Datei in einen
// Wegwerf-Ordner um und gibt NUR Zahlen aus (Pixel, Größe, Zeit, Speicherspitze, Ortsdaten ja/nein) – keine Dateinamen.
// Nichts wird im Quellordner verändert. Aufruf: ./probe <ordner>   (siehe README.md)
import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

setvbuf(stdout, nil, _IOLBF, 0)
guard CommandLine.arguments.count > 1 else { print("Aufruf: probe <ordner>"); exit(2) }
let src = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let out = FileManager.default.temporaryDirectory.appendingPathComponent("transform-probe-\(UUID().uuidString.prefix(6))")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: out) }

func peakMB() -> Double { var u = rusage(); getrusage(RUSAGE_SELF, &u); return Double(u.ru_maxrss) / 1_048_576 }
func ms(_ f: () -> Void) -> Int { let t = Date(); f(); return Int(Date().timeIntervalSince(t) * 1000) }
func kb(_ u: URL) -> Int { ((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) / 1024 }
func hasGPS(_ u: URL) -> Bool {
    guard let s = CGImageSourceCreateWithURL(u as CFURL, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return false }
    return p[kCGImagePropertyGPSDictionary] != nil
}

/// Verkleinert (längste Seite `maxSide`, 0 = Originalgröße) und schreibt `type`. `stripMeta`: Thumbnail-Weg (keine Ortsdaten).
func convert(_ u: URL, to type: UTType, maxSide: Int, quality: Double, stripMeta: Bool, name: String) -> URL? {
    guard let s = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
    let dst = out.appendingPathComponent(name)
    guard let d = CGImageDestinationCreateWithURL(dst as CFURL, type.identifier as CFString, 1, nil) else { return nil }
    let opts: CFDictionary = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    if stripMeta || maxSide > 0 {
        let big = (CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any]).flatMap {
            max($0[kCGImagePropertyPixelWidth] as? Int ?? 0, $0[kCGImagePropertyPixelHeight] as? Int ?? 0) } ?? 0
        guard let cg = CGImageSourceCreateThumbnailAtIndex(s, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide > 0 ? maxSide : max(big, 1),
            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        CGImageDestinationAddImage(d, cg, opts)   // Thumbnail trägt keine Ortsdaten
    } else {
        CGImageDestinationAddImageFromSource(d, s, 0, opts)   // Metadaten bleiben
    }
    return CGImageDestinationFinalize(d) ? dst : nil
}

let files = ((try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey])) ?? [])
    .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
var images: [URL] = [], pdfs: [URL] = []
for f in files {
    let t = (try? f.resourceValues(forKeys: [.contentTypeKey]))?.contentType
    if t?.conforms(to: .image) == true { images.append(f) } else if t?.conforms(to: .pdf) == true { pdfs.append(f) }
}
print("Bilder: \(images.count), PDFs: \(pdfs.count), Start-Speicher \(String(format: "%.0f", peakMB())) MB")
print("Nr | Typ | Pixel (MP) | Orig KB | GPS | → JPEG 0,85 (ms, KB, GPS) | → lange Seite 2048 (ms, KB) | 1280 (ms, KB) | 800 (ms, KB) | Spitze MB")

for (i, f) in images.enumerated() {
    let p = CGImageSourceCreateWithURL(f as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
    let w = p[kCGImagePropertyPixelWidth] as? Int ?? 0, h = p[kCGImagePropertyPixelHeight] as? Int ?? 0
    var cells: [String] = []
    var jpegURL: URL?
    let tj = ms { jpegURL = convert(f, to: .jpeg, maxSide: 0, quality: 0.85, stripMeta: false, name: "j\(i).jpg") }
    cells.append(jpegURL.map { "\(tj), \(kb($0)), \(hasGPS($0) ? "ja" : "nein")" } ?? "FEHLER")
    for side in [2048, 1280, 800] {
        var r: URL?
        let t = ms { r = convert(f, to: .jpeg, maxSide: side, quality: 0.85, stripMeta: true, name: "s\(side)-\(i).jpg") }
        cells.append(r.map { "\(t), \(kb($0))" + (hasGPS($0) ? " GPS!" : "") } ?? "FEHLER")
    }
    let type = f.pathExtension.uppercased()
    print("\(i + 1) | \(type) | \(w)×\(h) (\(String(format: "%.1f", Double(w * h) / 1e6))) | \(kb(f)) | \(hasGPS(f) ? "ja" : "nein") | "
          + cells.joined(separator: " | ") + " | \(String(format: "%.0f", peakMB()))")
}

// Zu einem PDF: die ersten drei Bilder (je eine Seite), danach alle PDFs hintereinander
let doc = PDFDocument()
let tp = ms {
    for u in images.prefix(3) {
        // Verkleinert auf 2048, damit die PDF-Größe handhabbar bleibt (Entscheidung offen, hier gemessen)
        if let small = convert(u, to: .jpeg, maxSide: 2048, quality: 0.85, stripMeta: true, name: "pdf-\(u.hashValue).jpg"),
           let img = NSImage(contentsOf: small), let page = PDFPage(image: img) { doc.insert(page, at: doc.pageCount) }
    }
    for u in pdfs.prefix(2) { if let d = PDFDocument(url: u) { for k in 0..<d.pageCount { if let pg = d.page(at: k) { doc.insert(pg, at: doc.pageCount) } } } }
}
let pdfURL = out.appendingPathComponent("zusammen.pdf")
let tw = ms { doc.write(to: pdfURL) }
print("PDF aus \(min(3, images.count)) Bildern + \(min(2, pdfs.count)) PDFs: \(doc.pageCount) Seiten, \(tp) ms Aufbau, \(tw) ms Schreiben, \(kb(pdfURL)) KB, Spitze \(String(format: "%.0f", peakMB())) MB")
print("Fertig. Wegwerf-Ordner wird gelöscht.")
