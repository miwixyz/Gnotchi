import Foundation
import ImageIO
import os
import Vision

/// Texterkennung in Bild-Einträgen (G50): lokal mit Apple Vision, einmal je Eintrag, seriell im Hintergrund.
///
/// Eingabe sind nur die schon entschlüsselten gespeicherten Bilddaten (G37-Formate, nie die verwiesene Datei).
/// Ergebnis ist reiner Text; ein erkanntes Geheimnis führt zu `""` (nicht durchsuchbar). Protokoll nur Zahlen (G8).
enum ImageText {
    /// Längste Kante vor der Erkennung (≈ 4 MP): begrenzt Speicher und Rechenzeit, Schrift bleibt lesbar.
    nonisolated static let maxPixelSize = 2_560
    /// Höchstens so viel Text wird gespeichert.
    nonisolated static let maxCharacters = 20_000
    nonisolated static let languages = ["de-DE", "en-US", "es-ES"]

    /// Erkennt Text, filtert Geheimnisse. Gibt `""` zurück bei keinem Text, Fehler oder Geheimnis – „erledigt“.
    nonisolated static func recognize(_ data: Data) -> String {
        guard let image = downscaled(data) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            // Bewusst ohne `error`: Vision hängt in manchen Fehlerfällen Fragmente an (Tippi-Befund 27.09.).
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return sanitized(lines.joined(separator: "\n"))
    }

    /// Text kürzen, und `""`, sobald der ganze Text, eine Zeile oder ein Stück einer Zeile ein Geheimnis ist (G43-Muster).
    /// Ein umbrochener oder verlesener Schlüssel rutscht durch – Restrisiko in G50.
    nonisolated static func sanitized(_ raw: String) -> String {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCharacters))
        guard !text.isEmpty else { return "" }
        if SecretDetector.kind(of: text) != nil { return "" }
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "=:,;\"'`"))
        for line in text.split(whereSeparator: \.isNewline) {
            if SecretDetector.kind(of: String(line)) != nil { return "" }
            for piece in line.components(separatedBy: separators) where piece.count >= 8 {
                if SecretDetector.kind(of: piece) != nil { return "" }
            }
        }
        return text
    }

    private nonisolated static func downscaled(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}

/// Läuft die Erkennung für alle noch offenen Bilder ab – eine Aufgabe zur Zeit, nie im Öffnen-Pfad (Vorfall 0.17.1).
@MainActor
final class ImageTextIndexer {
    private var task: Task<Void, Never>?
    /// Zählt Durchgänge hoch, damit ein abgebrochener alter Durchgang einen neuen nicht als beendet markiert.
    private var generation = 0
    private var rerun = false
    private nonisolated static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "zwischenablage")
    /// Nach so vielen Bildern einmal speichern (statt je Bild neu zeichnen).
    nonisolated static let batchSize = 10
    /// In der App immer `.background` (bremst nie). Tests übergeben eine höhere Stufe: Unter Last bekam `.background` so wenig
    /// Rechenzeit, dass der Test seine Frist riss, obwohl die Erkennung stimmte (gemessen 17.11.: 4,7 s statt 0,2 s je Bild).
    let priority: TaskPriority

    init(priority: TaskPriority = .background) {
        self.priority = priority
    }

    var isRunning: Bool { task != nil }

    /// Offene Bilder erkennen. Läuft schon eine Aufgabe, kommt danach noch ein Durchgang.
    func run(_ store: ClipboardStore) {
        guard store.imageTextEnabled else { return }
        guard task == nil else { rerun = true; return }
        let jobs = store.pendingImageText()
        guard !jobs.isEmpty else { return }
        generation += 1
        let mine = generation
        task = Task.detached(priority: priority) { [weak self, weak store] in
            let start = Date()
            var batch: [UUID: String] = [:]
            var withText = 0
            for (id, data) in jobs {
                if Task.isCancelled { break }
                let text = ImageText.recognize(data)
                if !text.isEmpty { withText += 1 }
                batch[id] = text
                if batch.count >= Self.batchSize {
                    let done = batch
                    batch = [:]
                    await MainActor.run { store?.storeImageTexts(done) }
                }
            }
            let rest = batch
            let cancelled = Task.isCancelled
            if !cancelled { await MainActor.run { store?.storeImageTexts(rest) } }
            // G8: nur Anzahl und Dauer.
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Self.log.notice("Bildtext: \(jobs.count, privacy: .public) Bilder in \(ms, privacy: .public) ms, \(withText, privacy: .public) mit Text")
            await MainActor.run {
                guard let self, self.generation == mine else { return }
                self.task = nil
                if self.rerun, !cancelled, let store {
                    self.rerun = false
                    self.run(store)
                }
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        rerun = false
    }
}
