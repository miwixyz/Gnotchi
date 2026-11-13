import AppKit
import OSLog
import WidgetKit

/// Versorgt das Schreibtisch-Widget (0.26.0, docs/SECURE-DESIGN.md G49) und nimmt seine Knopfbefehle an.
///
/// Schreibt nur den **aktuellen** Titel (kein Verlauf) und ein auf 256 px verkleinertes Cover in den Gruppen-Ordner.
/// Nichts läuft, Funktion aus oder Gnotchi endet → beide Dateien weg. Protokoll nie mit Inhalten (G8).
@MainActor
final class DesktopWidgetFeed {
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "widget")
    nonisolated static let coverSide: CGFloat = 256

    private let execute: (WidgetWire.Action) -> Void
    private var last: WidgetWire.Now?
    private weak var lastArtwork: NSImage?
    private var listening = false
    /// Schon ausgeführte Befehle (begrenzt) – derselbe Befehl löst nie zweimal aus.
    private var handled: [UUID] = []

    init(execute: @escaping (WidgetWire.Action) -> Void) {
        self.execute = execute
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - Daten fürs Widget

    nonisolated static func makeNow(info: NowPlayingInfo, hasCover: Bool) -> WidgetWire.Now {
        let subtitle = [info.artist, info.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return WidgetWire.Now(title: WidgetWire.clip(info.title), subtitle: WidgetWire.clip(subtitle),
                              playing: info.isPlaying, hasCover: hasCover)
    }

    /// `info == nil` → nichts anzeigen (Dateien weg).
    func publish(info: NowPlayingInfo?, artwork: NSImage?) {
        guard let info else { clear(); return }
        let now = Self.makeNow(info: info, hasCover: artwork != nil)
        if now == last && artwork === lastArtwork { return }
        guard let dir = WidgetWire.container() else {
            Self.log.error("Widget: kein Gruppen-Ordner")
            return
        }
        let coverURL = dir.appendingPathComponent(WidgetWire.coverFile)
        if artwork !== lastArtwork {
            if let artwork, let png = Self.png(artwork) {
                try? png.write(to: coverURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: coverURL)
            }
        }
        guard let data = try? JSONEncoder().encode(now) else { return }
        do {
            try data.write(to: dir.appendingPathComponent(WidgetWire.nowFile), options: .atomic)
        } catch {
            Self.log.error("Widget: Schreiben fehlgeschlagen")
            return
        }
        last = now
        lastArtwork = artwork
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWire.kind)
    }

    func clear() {
        let hadData = last != nil
        last = nil
        lastArtwork = nil
        guard let dir = WidgetWire.container() else { return }
        for name in [WidgetWire.nowFile, WidgetWire.coverFile, WidgetWire.commandFile] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        if hadData { WidgetCenter.shared.reloadTimelines(ofKind: WidgetWire.kind) }
    }

    /// Cover auf höchstens 256 px neu zeichnen und als PNG – das Widget nimmt nur PNG bis 512 px an.
    nonisolated static func png(_ image: NSImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, coverSide / max(size.width, size.height))
        let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]), data.count <= WidgetWire.maxCover else { return nil }
        return data
    }

    // MARK: - Knöpfe im Widget

    func startListening() {
        guard !listening else { return }
        listening = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let feed = Unmanaged<DesktopWidgetFeed>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { feed.commandArrived() } }
        }, WidgetWire.commandNote as CFString, nil, .deliverImmediately)
    }

    func stopListening() {
        guard listening else { return }
        listening = false
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                           Unmanaged.passUnretained(self).toOpaque(),
                                           CFNotificationName(WidgetWire.commandNote as CFString), nil)
    }

    /// Weckruf: Befehl aus dem Gruppen-Ordner lesen, löschen, prüfen, höchstens einmal ausführen.
    private func commandArrived() {
        guard listening, last != nil, let dir = WidgetWire.container() else { return }
        let url = dir.appendingPathComponent(WidgetWire.commandFile)
        let data = WidgetWire.read(url, limit: WidgetWire.maxCommand)
        try? FileManager.default.removeItem(at: url)
        guard let data, let cmd = WidgetWire.decodeCommand(data, now: Date()) else { return }
        guard Self.accept(cmd.id, handled: &handled) else { return }
        Self.log.notice("Widget-Knopf: \(cmd.action.rawValue, privacy: .public)")
        execute(cmd.action)
    }

    /// true = neu (und gemerkt); höchstens 32 gemerkte Kennungen.
    nonisolated static func accept(_ id: UUID, handled: inout [UUID]) -> Bool {
        guard !handled.contains(id) else { return false }
        handled.append(id)
        if handled.count > 32 { handled.removeFirst(handled.count - 32) }
        return true
    }
}
