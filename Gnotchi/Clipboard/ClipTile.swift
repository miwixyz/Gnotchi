import AppKit
import SwiftUI

/// Karte je Inhaltsart (0.14.0 „Kartenbild“, Vorbild Supaste): gleich groß, für die Reihe unter der Notch.
/// Text · Link (Domain, nichts laden – G40) · Farbe (ganze Kopie) · Bild randlos · Datei · Tresor/Geheimnis verdeckt.
/// Beim Drüberfahren Stern (anheften) und Papierkorb.
struct ClipTile: View {
    static let size = CGSize(width: 132, height: 100)

    let link: ClipboardLink
    let entry: ClipEntry
    let number: Int?
    let selected: Bool
    @State private var hovering = false

    private var store: ClipboardStore? { link.store }

    var body: some View {
        let payload = store?.payload(entry)
        let concealed = store?.isConcealed(entry) ?? true
        let color = concealed ? nil : payload.flatMap { Self.color(entry, $0) }
        ZStack(alignment: .topTrailing) {
            content(payload, concealed: concealed, color: color)
                .frame(width: Self.size.width, height: Self.size.height)
                .background(background(color: color, concealed: concealed))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if hovering { actions }
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.accentColor.opacity(selected ? 0.95 : 0), lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .modifier(DragOut(entry: entry, payload: payload, concealed: concealed))
        .onHover { hovering = $0 }
        .help(Text(verbatim: store?.title(entry) ?? store?.secretKind(entry) ?? ""))
    }

    // MARK: Inhalt je Art

    @ViewBuilder
    private func content(_ payload: ClipPayload?, concealed: Bool, color: ColorCode?) -> some View {
        if concealed {
            concealedBody
        } else if let color {
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                Text(verbatim: color.hex).font(.system(size: 13, weight: .semibold, design: .monospaced))
                footer(light: color.isLight)
            }
            .foregroundStyle(color.isLight ? Color.black : Color.white)
            .padding(9)
        } else if let payload, entry.kind == .image, let image = ClipThumbnails.image(for: entry, payload: payload) {
            ZStack(alignment: .bottomLeading) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: Self.size.width, height: Self.size.height).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    if let name = store?.title(entry) {
                        Text(verbatim: name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }
                    footer(light: false)
                }
                .foregroundStyle(.white)
                .padding(9)
            }
        } else if let payload {
            VStack(alignment: .leading, spacing: 4) {
                switch entry.kind {
                case .link: linkBody(payload.plain)
                case .file: fileBody(payload.plain)
                default:
                    if let title = store?.title(entry) {
                        Text(verbatim: title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }
                    Text(verbatim: String(payload.plain.prefix(300)))
                        .font(.system(size: 11)).lineLimit(store?.title(entry) == nil ? 4 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                footer(light: false)
            }
            .padding(9)
        } else {
            Color.clear
        }
    }

    private var concealedBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.isVault ? "lock.fill" : "key.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            Text(verbatim: "••••••").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
            Text(verbatim: store?.title(entry) ?? store?.secretKind(entry) ?? "")
                .font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            footer(light: false)
        }
        .padding(9)
    }

    @ViewBuilder private func linkBody(_ text: String) -> some View {
        let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        let host = url?.host() ?? text
        Text(verbatim: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
        Text(verbatim: url.map { $0.path() + ($0.query().map { "?" + $0 } ?? "") } ?? "")
            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
    }

    @ViewBuilder private func fileBody(_ text: String) -> some View {
        let url = URL(string: text).flatMap { $0.isFileURL ? $0 : nil } ?? URL(fileURLWithPath: text)
        let exists = FileManager.default.fileExists(atPath: url.path)
        Image(nsImage: exists ? NSWorkspace.shared.icon(forFile: url.path) : NSImage(systemSymbolName: "doc",
                                                                                     accessibilityDescription: nil)!)
            .resizable().frame(width: 34, height: 34)
        Text(verbatim: url.lastPathComponent).font(.system(size: 11)).lineLimit(2)
    }

    private func footer(light: Bool) -> some View {
        HStack(spacing: 4) {
            if let source = entry.sourceBundleID { AppSymbol(bundleID: source, size: 12) }
            Group {
                // Unter einer Minute „jetzt“ (sonst „in 0 s“, wenn die Uhr knapp hinter dem Eintrag liegt).
                if abs(entry.lastUsedAt.timeIntervalSinceNow) < 60 {
                    Text("jetzt")
                } else {
                    Text(entry.lastUsedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let number { Text(verbatim: "⌘\(number)") }
        }
        .font(.system(size: 9))
        .opacity(0.7)
        .foregroundStyle(light ? Color.black : Color.white)
    }

    @ViewBuilder private func background(color: ColorCode?, concealed: Bool) -> some View {
        if let color, !concealed {
            Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: max(color.alpha, 0.15))
        } else {
            Color.white.opacity(selected ? 0.16 : 0.08)
        }
    }

    // MARK: Drüberfahren: Stern + Papierkorb

    private var actions: some View {
        HStack(spacing: 4) {
            if !(store?.isConcealed(entry) ?? true) {
                let pinned = (entry.collections ?? []).contains(where: \.isPinned)
                hoverButton(pinned ? "star.fill" : "star", label: pinned ? "Lösen" : "Anheften") {
                    try? store?.togglePinned(entry)
                }
            }
            hoverButton("trash", label: "Löschen") { store?.delete(entry) }
        }
        .padding(5)
    }

    private func hoverButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    /// Farbe nur für Text-Einträge, deren ganze Kopie ein Farbcode ist.
    static func color(_ entry: ClipEntry, _ payload: ClipPayload) -> ColorCode? {
        guard entry.kind == .text || entry.kind == .richText else { return nil }
        return ColorCode.parse(payload.plain)
    }
}
