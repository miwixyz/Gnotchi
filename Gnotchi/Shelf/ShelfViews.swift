import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Ablagefeld, solange irgendwo Dateien gezogen werden (0.8.0, G32). Das Lesen der Zieh-Zwischenablage
/// (Verweise und Dateiversprechen, 0.9.1/0.9.2) macht `ShelfLink.dropDragged`.
struct ShelfDropZone: View {
    let count: Int
    let topInset: CGFloat
    let onDrop: (NSDraggingInfo) -> Void
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Hier ablegen").font(.system(size: 15, weight: .semibold))
                Text(verbatim: count == 0 ? "Datei parken, später woanders rausziehen" : "\(count) in der Ablage")
                    .font(.system(size: 12, weight: .medium)).opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(targeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(targeted ? 0.12 : 0.04))))
        .padding(EdgeInsets(top: topInset + 8, leading: 10, bottom: 8, trailing: 10))
        .contentShape(Rectangle())
        .overlay(ShelfDropTarget(targeted: $targeted, onDrop: onDrop))
        .accessibilityLabel(Text(verbatim: "Ablage: hier ablegen"))
    }
}

/// AppKit-Ablagefläche (0.9.2). SwiftUI-`onDrop` reicht kein `NSDraggingInfo` durch – ohne das lassen sich alte
/// Dateiversprechen (Gmail in Helium/Chromium, Outlook) nicht einlösen; `NSFilePromiseReceiver` brach bei ihnen mit
/// einer Ausnahme ab und macOS den ganzen Ziehvorgang (gemessen 23.10.).
struct ShelfDropTarget: NSViewRepresentable {
    @Binding var targeted: Bool
    let onDrop: (NSDraggingInfo) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.registerForDraggedTypes(DragWatcher.fileTypes)
        return view
    }

    func updateNSView(_ view: DropView, context: Context) {
        view.onDrop = onDrop
        view.onTarget = { inside in if targeted != inside { targeted = inside } }
    }

    final class DropView: NSView {
        var onDrop: ((NSDraggingInfo) -> Void)?
        var onTarget: ((Bool) -> Void)?

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            onTarget?(true)
            return .copy
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }
        override func draggingExited(_ sender: (any NSDraggingInfo)?) { onTarget?(false) }
        override func draggingEnded(_ sender: any NSDraggingInfo) { onTarget?(false) }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            onDrop?(sender)
            return true
        }
    }
}

/// Ablage groß (0.8.0): Kacheln (rausziehen, Rechtsklick-Menü, ×) und Knöpfe für alle.
struct ShelfBig: View {
    let items: [ShelfStore.Item]
    let link: ShelfLink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in ShelfTile(item: item, link: link) }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 104)
            HStack(spacing: 6) {
                if !link.busy {
                    if items.count > 1 { dragAll }
                    ShareLink(items: link.urls()) { bar("square.and.arrow.up", "Teilen") }.buttonStyle(.plain)
                    Button { link.airDrop(link.urls()) } label: { bar("airplayaudio", "AirDrop") }.buttonStyle(.plain)
                    Button { link.zip(password: false) } label: { bar("doc.zipper", "ZIP") }.buttonStyle(.plain)
                    Button { link.zip(password: true) } label: { bar("lock.doc", "ZIP mit Passwort") }.buttonStyle(.plain)
                } else {
                    ProgressView().controlSize(.small)
                    Text(verbatim: "Packt …").font(.system(size: 12, weight: .medium))
                }
                Spacer(minLength: 0)
                Button { link.clear() } label: { bar("trash", "Leeren") }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
    }

    /// Alle Dateien in einem Zug herausziehen (0.18, Michael 28.10.). Nur Einträge, deren Datei noch auffindbar ist,
    /// werden mitgenommen und danach (Schalter „Nach dem Rausziehen entfernen“) aus der Ablage genommen.
    private var dragAll: some View {
        let present = items.filter { link.url(for: $0) != nil }
        return bar("square.stack.3d.up", "Alle ziehen")
            .overlay(DragSource(urls: present.compactMap { link.url(for: $0) },
                                onEnded: { moved in if moved { link.draggedOut(present) } },
                                menu: { _ in nil }))
            .help("Alle Dateien auf einmal herausziehen")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Alle \(present.count) Dateien herausziehen"))
    }

    private func bar(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(verbatim: title).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.14)))
        .contentShape(Capsule())
    }
}

/// Kachelreihe unter der großen Sache (0.8.0, Michael 22.10.): kleine Kacheln, sonst wie in der Ablage (rausziehen,
/// Rechtsklick, ×). Die Knöpfe für alle (ZIP, AirDrop …) bleiben hinter dem Ablage-Symbol.
struct ShelfStrip: View {
    let items: [ShelfStore.Item]
    let link: ShelfLink

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in ShelfTile(item: item, link: link, compact: true) }
                }
            }
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Ablage, \(items.count)"))
    }
}

/// Ablage im Band (0.8.0): Ablage-Symbol (Klick → volle Ablage) und bis zu 3 Datei-Symbole, die man direkt herauszieht.
struct ShelfMini: View {
    let items: [ShelfStore.Item]
    let link: ShelfLink
    let onOpen: () -> Void
    nonisolated static let shown = 3

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                Image(systemName: "tray.full.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Ablage öffnen, \(items.count)"))
            ForEach(items.prefix(Self.shown)) { item in
                let url = link.url(for: item)
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                    .resizable().interpolation(.high).frame(width: 20, height: 20)
                    .overlay(DragSource(url: url, onEnded: { moved in if moved { link.draggedOut(item) } },
                                        menu: { link.menu(for: item, anchor: $0) }))
                    .help(item.name)
                    .accessibilityLabel(Text(verbatim: item.name))
            }
            if items.count > Self.shown {
                Text(verbatim: "+\(items.count - Self.shown)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Eine Kachel: Symbol + Name. Ziehen und Rechtsklick übernimmt eine AppKit-Ansicht (SwiftUI meldet nicht, ob ein
/// Ziehen angekommen ist – das braucht „nach dem Rausziehen entfernen“). × entfernt nur aus der Ablage.
struct ShelfTile: View {
    let item: ShelfStore.Item
    let link: ShelfLink
    /// Kleine Kachel für die Reihe unter der großen Sache.
    var compact = false
    @State private var hovered = false

    var body: some View {
        let url = link.url(for: item)
        ZStack(alignment: .topTrailing) {
            VStack(spacing: compact ? 2 : 4) {
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                    .resizable().interpolation(.high).frame(width: compact ? 30 : 48, height: compact ? 30 : 48)
                Text(verbatim: item.name).font(.system(size: compact ? 10 : 11, weight: .medium)).lineLimit(compact ? 1 : 2)
                    .multilineTextAlignment(.center).frame(width: compact ? 62 : 84)
            }
            .frame(width: compact ? 68 : 92, height: compact ? 56 : 98)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovered ? 0.14 : 0.06)))
            .overlay(DragSource(url: url, onEnded: { moved in if moved { link.draggedOut(item) } },
                                menu: { link.menu(for: item, anchor: $0) }))
            if hovered {
                Button { link.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain).padding(3)
                .accessibilityLabel(Text(verbatim: "Aus der Ablage entfernen"))
            }
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: item.name))
    }
}

/// AppKit-Ziehquelle über einer Kachel: Ziehen → Datei-URL(s) (wie aus dem Finder), Ende mit Ergebnis; Rechtsklick → Menü.
/// Mehrere URLs ziehen in einer Sitzung (wie eine Mehrfachauswahl im Finder, 0.18).
struct DragSource: NSViewRepresentable {
    let urls: [URL]
    let onEnded: (Bool) -> Void
    let menu: (NSView) -> NSMenu?

    init(url: URL?, onEnded: @escaping (Bool) -> Void, menu: @escaping (NSView) -> NSMenu?) {
        self.init(urls: url.map { [$0] } ?? [], onEnded: onEnded, menu: menu)
    }

    init(urls: [URL], onEnded: @escaping (Bool) -> Void, menu: @escaping (NSView) -> NSMenu?) {
        self.urls = urls
        self.onEnded = onEnded
        self.menu = menu
    }

    func makeNSView(context: Context) -> SourceView { SourceView() }

    func updateNSView(_ v: SourceView, context: Context) {
        v.urls = urls
        v.onEnded = onEnded
        v.makeMenu = menu
    }

    final class SourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var onEnded: (Bool) -> Void = { _ in }
        var makeMenu: (NSView) -> NSMenu? = { _ in nil }
        private var down: NSEvent?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { down = event }

        override func mouseDragged(with event: NSEvent) {
            guard let start = down, !urls.isEmpty else { return }
            down = nil
            // Leicht versetzter Stapel; macOS zeigt bei mehreren die Anzahl am Zeiger.
            let items = urls.enumerated().map { i, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let shift = CGFloat(min(i, 4)) * 4
                item.setDraggingFrame(NSRect(x: shift, y: -shift, width: 48, height: 48),
                                      contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            beginDraggingSession(with: items, event: start, source: self)
        }

        override func menu(for event: NSEvent) -> NSMenu? { makeMenu(self) }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Nur kopieren (Michael 23.10.): mit `.move` verschob der Finder ein Bildschirmfoto aus iCloud/Screenshots
            // auf den Schreibtisch (Ziel meldete 16 = verschieben). Das Original bleibt jetzt, wo es war.
            context == .outsideApplication ? [.copy] : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            // Messpunkt (23.10.): was das Ziel meldet (1 = kopiert, 16 = verschoben) – nur die Zahl, nie Name/Pfad.
            // Achtung: Bei gleichnamiger Datei am Ziel meldet der Finder „kopiert“ und legt nichts an (dupFNErr, gemessen).
            Logger(subsystem: "dev.mwlr.gnotchi", category: "ablage")
                .notice("Rausgezogen, Ziel meldet Übernahme \(operation.rawValue, privacy: .public)")
            onEnded(operation != [])
        }
    }
}

/// Ruhe-Insel (0.8.0, Michael 22.10.: „mit Inhalt“): läuft nichts anderes, Wetter (Symbol + Temperatur) und/oder Ablage
/// (Symbol + Anzahl). Mit Notch links Symbol, rechts Wert; ohne Notch beides in der Pille.
struct IdleCompact: View {
    let weather: Weather.Forecast?
    let shelfCount: Int
    /// Ungelesen-Summe (0.9.0, G33); 0 = nichts.
    var unread = 0
    let pill: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            if shelfCount > 0 {
                Image(systemName: "tray.full.fill").font(.system(size: 11, weight: .semibold))
                if pill || weather == nil { Text(verbatim: "\(shelfCount)").font(.system(size: 11, weight: .semibold)) }
            } else if let w = weather {
                Image(systemName: Weather.symbol(w.code, day: w.isDay)).symbolRenderingMode(.multicolor)
                    .font(.system(size: 12))
            }
            Spacer(minLength: 0)
            if let w = weather {
                if pill && shelfCount > 0 {
                    Image(systemName: Weather.symbol(w.code, day: w.isDay)).symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                }
                Text(verbatim: WeatherBig.deg(w.temperature)).font(.system(size: 12, weight: .semibold))
            }
            if unread > 0 { UnreadDot(total: unread) }
        }
        // `.primary`: in der dunklen Insel weiß, in der ruhigen Insel (0.16.0) wie die Menüleiste.
        .foregroundStyle(.primary)
        .padding(.horizontal, pill ? 12 : 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .transition(.opacity)
    }

    private var label: String {
        [weather.map { "Wetter \(WeatherBig.deg($0.temperature))" }, shelfCount > 0 ? "\(shelfCount) in der Ablage" : nil,
         unread > 0 ? "\(unread) ungelesen" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
