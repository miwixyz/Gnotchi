import os
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Karte

struct ClipCard: View {
    let link: ClipboardLink
    let entry: ClipEntry
    let number: Int?
    let selected: Bool
    let compactWidth: Bool

    var body: some View {
        let store = link.store
        let payload = store?.payload(entry)
        let secret = store?.secretKind(entry)
        let title = store?.title(entry) ?? secret
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if secret != nil {
                    Image(systemName: "key.fill").font(.system(size: 11)).foregroundStyle(.orange)
                } else if let source = entry.sourceBundleID {
                    AppSymbol(bundleID: source, size: 16)
                } else {
                    Image(systemName: entry.isVault ? "lock.fill" : "doc.on.clipboard").font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let title { Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
                Spacer(minLength: 0)
                Text(entry.lastUsedAt, format: .relative(presentation: .named))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if let number { Text(verbatim: "⌘\(number)").font(.system(size: 10)).foregroundStyle(.tertiary) }
            }
            preview(payload)
            if let expiry = store?.secretExpiry(entry) { SecretCountdown(expiry: expiry) }
        }
        .padding(10)
        .frame(width: compactWidth ? 220 : nil, alignment: .leading)
        .frame(maxWidth: compactWidth ? 220 : .infinity, minHeight: 54, maxHeight: compactWidth ? .infinity : 180,
               alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(selected ? 0.16 : 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.accentColor.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .modifier(DragOut(entry: entry, payload: payload, concealed: store?.isConcealed(entry) ?? true))
    }

    @ViewBuilder private func preview(_ payload: ClipPayload?) -> some View {
        if link.store?.isConcealed(entry) ?? true {
            Text(verbatim: "••••••••").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
        } else if let payload {
            switch entry.kind {
            case .image:
                if let image = ClipThumbnails.image(for: entry, payload: payload) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            case .file:
                Label(payload.plain, systemImage: "doc").font(.system(size: 12)).lineLimit(2)
            case .link:
                // 0.14.0 Kartenbild: Domain groß, Pfad klein – nichts laden (G40).
                let url = URL(string: payload.plain.trimmingCharacters(in: .whitespacesAndNewlines))
                VStack(alignment: .leading, spacing: 2) {
                    Label(url?.host() ?? payload.plain, systemImage: "link")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let path = url?.path(), path.count > 1 {
                        Text(verbatim: path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            case .text, .richText:
                if let color = ClipTile.color(entry, payload) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue,
                                        opacity: color.alpha))
                            .frame(width: 48, height: 32)
                        Text(verbatim: color.hex).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                } else {
                    Text(verbatim: String(payload.plain.prefix(400)))
                        .font(.system(size: 12)).lineLimit(compactWidth ? 8 : 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Rausziehen in andere Apps (G40): gespeicherte Formate, nie Tresor-Einträge. Innerhalb der Ansicht trägt der Zug
/// die Kennung (für das Ablegen auf einem Sammlungs-Reiter).
struct DragOut: ViewModifier {
    let entry: ClipEntry
    let payload: ClipPayload?
    /// Tresor oder erkanntes Geheimnis (G43): nie Inhalt nach außen.
    let concealed: Bool

    func body(content: Content) -> some View {
        if entry.isVault || payload == nil {
            content
        } else if concealed {
            // Erkanntes Geheimnis: nur die Kennung, nur im eigenen Prozess – zum Ablegen auf dem Tresor-Reiter.
            content.onDrag {
                let provider = NSItemProvider()
                provider.registerObject(entry.id.uuidString as NSString, visibility: .ownProcess)
                return provider
            }
        } else {
            content.onDrag {
                let provider = NSItemProvider()
                provider.registerObject(entry.id.uuidString as NSString, visibility: .ownProcess)
                for format in payload?.formats ?? [] where format.type != ClipboardCapture.UTI.fileURL {
                    let data = format.data
                    provider.registerDataRepresentation(forTypeIdentifier: format.type, visibility: .all) { done in
                        done(data, nil)
                        return nil
                    }
                }
                if let file = payload?.formats.first(where: { $0.type == ClipboardCapture.UTI.fileURL }),
                   let url = String(bytes: file.data, encoding: .utf8).flatMap(URL.init(string:)), url.isFileURL,
                   FileManager.default.fileExists(atPath: url.path) {
                    provider.registerObject(url as NSURL, visibility: .all)
                }
                return provider
            }
        }
    }
}

/// Vorschaubilder nur verkleinert, im Speicher, nur aus den erlaubten Bildformaten (G40).
@MainActor
enum ClipThumbnails {
    private static let cache = NSCache<NSUUID, NSImage>()
    private nonisolated static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "zwischenablage")

    static func image(for entry: ClipEntry, payload: ClipPayload) -> NSImage? {
        // Auch Datei-Einträge mit mitkopiertem Bild (0.15.1, gemessen 26.10.: CleanShot/Clop legt public.file-url +
        // public.png in die Zwischenablage). Angezeigt wird nur das gespeicherte Bild, die Datei wird nie gelesen (G40).
        guard entry.kind == .image || entry.kind == .file else { return nil }
        if let hit = cache.object(forKey: entry.id as NSUUID) { return hit }
        guard let data = imageData(payload), let cg = thumbnail(data) else { return nil }
        return remember(cg, for: entry.id)
    }

    /// Vorab im Hintergrund verkleinern (gemessen 27.10.: Strg+< wartete vor allem aufs Entpacken der gespeicherten
    /// Bildschirmfotos in voller Größe, auf dem Hauptthread). Nach dem Start alle, danach jedes neue Bild. Nur das
    /// gespeicherte Bild, nie die Datei (G40); Ergebnis nur im Speicher.
    static func prewarm(_ store: ClipboardStore, entries: [ClipEntry]? = nil) {
        let jobs: [(UUID, Data)] = (entries ?? store.entries()).compactMap { e in
            guard e.kind == .image || e.kind == .file, cache.object(forKey: e.id as NSUUID) == nil,
                  let payload = store.payload(e), let data = imageData(payload) else { return nil }
            return (e.id, data)
        }
        guard !jobs.isEmpty else { return }
        Task.detached(priority: .utility) {
            let start = Date()
            for (id, data) in jobs {
                guard let cg = thumbnail(data) else { continue }
                await MainActor.run { _ = remember(cg, for: id) }
            }
            // G8: nur Anzahl und Dauer.
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            log.notice("Vorschaubilder vorbereitet: \(jobs.count, privacy: .public) in \(ms, privacy: .public) ms")
        }
    }

    private static func imageData(_ payload: ClipPayload) -> Data? {
        payload.formats.first(where: { ClipboardCapture.imageTypes.contains($0.type) })?.data
    }

    private nonisolated static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }

    private static func remember(_ cg: CGImage, for id: UUID) -> NSImage {
        if let hit = cache.object(forKey: id as NSUUID) { return hit }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: id as NSUUID)
        return image
    }
}

/// Kleine Rückfragen (Titel, Name, Bestätigung) als Systemdialog.
@MainActor
enum ClipboardPrompts {
    static func text(title: String, message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Löschen")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension ClipColor {
    var swiftUI: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}

/// Restzeit eines erkannten Geheimnisses (G43), alle 15 s neu gezeichnet. Gelöscht wird im `ClipboardLink`, nicht hier.
private struct SecretCountdown: View {
    let expiry: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let minutes = max(0, Int((expiry.timeIntervalSince(context.date) / 60).rounded(.up)))
            Text(minutes <= 1 ? "Wird gleich gelöscht" : "Noch \(minutes) Min., dann gelöscht")
                .font(.system(size: 10)).foregroundStyle(.orange)
        }
    }
}
