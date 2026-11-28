import AppKit
import SwiftUI

/// Karte je Inhaltsart (0.14.0 „Kartenbild“, Vorbild Supaste): gleich groß, für die Reihe unter der Notch.
/// Text · Link (Domain, nichts laden – G40) · Farbe (ganze Kopie) · Bild randlos · Datei · Tresor/Geheimnis verdeckt.
/// Beim Drüberfahren Stern (anheften) und Papierkorb.
struct ClipTile: View {
    static let size = CGSize(width: 132, height: 100)
    /// Kopfzeile (0.50.0, Idee aus Paste, in der Sprache der App-Familie): Symbol-Kachel der Quell-App, Art, Alter.
    static let headerHeight: CGFloat = 22
    /// Kleine Karte nach Design-System (Feld/kleine Karte 14).
    static let radius: CGFloat = FamilyTheme.Radius.field

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
        let detail = concealed ? nil : payload.flatMap {
            ClipMeta.detail(kind: entry.kind, payload: $0, isColor: color != nil, id: entry.id)
        }
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                header(color: color, concealed: concealed)
                content(payload, concealed: concealed, color: color, detail: detail)
                    .frame(width: Self.size.width, height: Self.size.height - Self.headerHeight)
                    .background(background(color: color, concealed: concealed))
            }
            .background(cardBackground(concealed: concealed))
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            if hovering { actions }
        }
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .stroke(selected ? FamilyTheme.accent : FamilyTheme.cardStroke, lineWidth: selected ? 2 : 0.8))
        .contentShape(RoundedRectangle(cornerRadius: Self.radius))
        .modifier(DragOut(entry: entry, payload: payload, concealed: concealed))
        .onHover { hovering = $0 }
        .help(Text(verbatim: store?.title(entry) ?? store?.secretKind(entry) ?? ""))
    }

    // MARK: Inhalt je Art

    @ViewBuilder
    private func content(_ payload: ClipPayload?, concealed: Bool, color: ColorCode?, detail: String?) -> some View {
        if concealed {
            concealedBody(detail)
        } else if let color {
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                Text(verbatim: color.hex).font(.system(size: 13, weight: .semibold, design: .monospaced))
                footer(detail, light: color.isLight)
            }
            .foregroundStyle(color.isLight ? Color.black : Color.white)
            .padding(9)
        } else if let payload, let image = ClipThumbnails.image(for: entry, payload: payload) {
            ZStack(alignment: .bottomLeading) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: Self.size.width, height: Self.size.height - Self.headerHeight).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    if let name = store?.title(entry) {
                        Text(verbatim: name).font(FamilyTheme.font(11, weight: .semibold)).lineLimit(1)
                    }
                    footer(detail, light: false)
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
                        Text(verbatim: title).font(FamilyTheme.font(11, weight: .semibold)).lineLimit(1)
                    }
                    Text(verbatim: String(payload.plain.prefix(300)))
                        .font(FamilyTheme.font(11)).lineLimit(store?.title(entry) == nil ? 3 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                footer(detail, light: false)
            }
            .padding(9)
        } else {
            Color.clear
        }
    }

    private func concealedBody(_ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.isVault ? "lock.fill" : "key.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            Text(verbatim: "••••••").font(.system(size: 13, design: .monospaced)).foregroundStyle(FamilyTheme.textSecondary)
            Text(verbatim: store?.title(entry) ?? store?.secretKind(entry) ?? "")
                .font(FamilyTheme.font(11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            footer(detail, light: false)
        }
        .padding(9)
    }

    @ViewBuilder private func linkBody(_ text: String) -> some View {
        let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        let host = url?.host() ?? text
        Text(verbatim: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
            .font(FamilyTheme.font(13, weight: .semibold)).lineLimit(1)
        Text(verbatim: url.map { $0.path() + ($0.query().map { "?" + $0 } ?? "") } ?? "")
            .font(FamilyTheme.font(10)).foregroundStyle(FamilyTheme.textSecondary).lineLimit(2)
    }

    @ViewBuilder private func fileBody(_ text: String) -> some View {
        let url = URL(string: text).flatMap { $0.isFileURL ? $0 : nil } ?? URL(fileURLWithPath: text)
        let exists = FileManager.default.fileExists(atPath: url.path)
        Image(nsImage: exists ? NSWorkspace.shared.icon(forFile: url.path) : NSImage(systemSymbolName: "doc",
                                                                                     accessibilityDescription: nil)!)
            .resizable().frame(width: 34, height: 34)
        Text(verbatim: url.lastPathComponent).font(FamilyTheme.font(11)).lineLimit(2)
    }

    /// Kopfzeile auf der festen Karte: App-Symbol in einer Symbol-Kachel mit 18 % App-Farbe (Design-System:
    /// „Symbol-Kachel, Farbe 14 %“), daneben Art und Alter. Keine bunte Leiste (Verbot „bunte Kacheln“).
    private func header(color: ColorCode?, concealed: Bool) -> some View {
        let label = ClipMeta.kindLabel(entry.kind, isColor: color != nil, concealed: concealed, vault: entry.isVault)
        return HStack(spacing: 5) {
            symbolTile(concealed: concealed)
            Text(verbatim: label).font(FamilyTheme.font(10, weight: .semibold)).foregroundStyle(FamilyTheme.textPrimary)
            age.font(FamilyTheme.font(9)).foregroundStyle(FamilyTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(width: Self.size.width, height: Self.headerHeight)
    }

    @ViewBuilder private func symbolTile(concealed: Bool) -> some View {
        let tint = concealed ? nil : entry.sourceBundleID.flatMap(AppTint.tint(for:))
        Group {
            if !concealed, let source = entry.sourceBundleID {
                AppSymbol(bundleID: source, size: 12)
            } else {
                Image(systemName: concealed ? (entry.isVault ? "lock.fill" : "key.fill") : "doc.on.clipboard")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(concealed ? Color.orange : FamilyTheme.textSecondary)
                    .frame(width: 12, height: 12)
            }
        }
        .padding(2.5)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill((tint?.color ?? FamilyTheme.textSecondary).opacity(0.18)))
    }

    /// Feste Schiefer-Karte, oben ein leiser Schimmer in der App-Farbe (nur Hinweis, keine Fläche).
    private func cardBackground(concealed: Bool) -> some View {
        let tint = concealed ? nil : entry.sourceBundleID.flatMap(AppTint.tint(for:))
        return ZStack {
            FamilyTheme.card
            if let tint {
                LinearGradient(colors: [tint.color.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
            }
        }
    }

    /// Unter einer Minute „jetzt“ (sonst „in 0 s“, wenn die Uhr knapp hinter dem Eintrag liegt).
    @ViewBuilder private var age: some View {
        if abs(entry.lastUsedAt.timeIntervalSinceNow) < 60 {
            Text("jetzt")
        } else {
            Text(entry.lastUsedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
        }
    }

    private func footer(_ detail: String?, light: Bool) -> some View {
        HStack(spacing: 4) {
            if let detail { Text(verbatim: detail).lineLimit(1) }
            Spacer(minLength: 0)
            if let number { Text(verbatim: "⌘\(number)") }
        }
        .font(FamilyTheme.font(9))
        .foregroundStyle(light ? Color.black.opacity(0.7) : FamilyTheme.textSecondary)
    }

    @ViewBuilder private func background(color: ColorCode?, concealed: Bool) -> some View {
        if let color, !concealed {
            Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: max(color.alpha, 0.15))
        } else {
            Color.clear
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
