import SwiftUI

/// Zwischenablage in der großen Insel (0.11.0): Schnellzugriff. Angeheftetes vorn, dann die letzten Kopien; Klick
/// kopiert (⇧-Klick als reiner Text), danach ⌘V. Tresor-Einträge nie hier (G39). „Alle …“ öffnet die Seitenansicht.
struct ClipboardBig: View {
    let link: ClipboardLink
    /// Höchstens 4 gleich breite Kacheln (24.10., Michael: „sieht nicht übersichtlich aus“ – bei 6 Kacheln brach
    /// Text mitten im Wort um, ein Bild nahm die halbe Breite).
    static let limit = 4
    static let allWidth: CGFloat = 64
    static let spacing: CGFloat = 8

    private var items: [ClipEntry] {
        guard let store = link.store else { return [] }
        // Erkannte Geheimnisse nie in der Notch (G43), wie Tresor-Einträge.
        let pinned = (store.pinned.map { store.entries(in: $0) } ?? []).filter { !store.isConcealed($0) }
        let recent = store.entries().filter { e in !store.isConcealed(e) && !pinned.contains { $0.id == e.id } }
        return Array((pinned + recent).prefix(Self.limit))
    }

    var body: some View {
        GeometryReader { geo in
            let list = items
            let slots = CGFloat(Self.limit)
            let tileWidth = max(80, (geo.size.width - Self.allWidth - Self.spacing * slots) / slots)
            HStack(spacing: Self.spacing) {
                if list.isEmpty {
                    Text("Noch nichts kopiert").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(list, id: \.id) { entry in
                        tile(entry, width: tileWidth, height: geo.size.height)
                    }
                    Spacer(minLength: 0)
                }
                allButton
            }
        }
    }

    private var allButton: some View {
        Button { link.panel.open() } label: {
            VStack(spacing: 4) {
                Image(systemName: "sidebar.right").font(.system(size: 16, weight: .semibold))
                Text("Alle …").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(width: Self.allWidth)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.10)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Alle Einträge in der Seitenansicht"))
    }

    private func tile(_ entry: ClipEntry, width: CGFloat, height: CGFloat) -> some View {
        let store = link.store
        let payload = store?.payload(entry)
        let pinned = (entry.collections ?? []).contains(where: \.isPinned)
        return Button {
            link.copy(entry, plain: NSEvent.modifierFlags.contains(.shift))
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    if let source = entry.sourceBundleID { AppSymbol(bundleID: source, size: 13) }
                    if pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
                    Spacer(minLength: 0)
                    Text(entry.lastUsedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                content(entry, payload: payload, title: store?.title(entry))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(8)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Klick kopiert, ⇧-Klick als reinen Text")
    }

    @ViewBuilder private func content(_ entry: ClipEntry, payload: ClipPayload?, title: String?) -> some View {
        if entry.kind == .image, let payload, let image = ClipThumbnails.image(for: entry, payload: payload) {
            Color.clear.overlay { Image(nsImage: image).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if entry.kind == .link, title == nil, let plain = payload?.plain {
            Label { Text(verbatim: Self.host(plain)).lineLimit(2) } icon: { Image(systemName: "link") }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
        } else {
            Text(verbatim: title ?? Self.preview(payload?.plain ?? ""))
                .font(.system(size: 11)).foregroundStyle(.white).lineLimit(4)
        }
    }

    /// Nur die Domain, ohne „www.“ (Vorschau, kein Netzzugriff).
    nonisolated static func host(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: trimmed)?.host else { return trimmed }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Leerraum zusammenziehen, damit vier Zeilen echten Text zeigen statt Leerzeilen.
    nonisolated static func preview(_ text: String) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200))
    }
}

extension ClipboardBig {
    /// Für die große Insel (0.11.0) – hier statt in IslandView.swift (Dateilänge).
    @MainActor @ViewBuilder static func island(_ link: ClipboardLink?, top: CGFloat) -> some View {
        if let link {
            ClipboardBig(link: link)
                .padding(EdgeInsets(top: top, leading: 12, bottom: 10, trailing: 12))
                .transition(.opacity)
        }
    }
}
