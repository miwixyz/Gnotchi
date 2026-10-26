import AppKit
import SwiftUI

/// Große Vorschau per Leertaste (0.15.0). Text vollständig, Bild groß, Farbe mit HEX/RGB/HSL, Link als volle Adresse,
/// Datei mit Pfad. Nichts laden (G40); Tresor und erkannte Schlüssel bleiben verdeckt (G39/G43).
struct ClipPreview: View {
    let link: ClipboardLink
    let entry: ClipEntry
    let onClose: () -> Void

    private var store: ClipboardStore? { link.store }

    var body: some View {
        let payload = store?.payload(entry)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(verbatim: label(payload)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Leertaste schließt").font(.system(size: 10)).foregroundStyle(.tertiary)
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.borderless).accessibilityLabel(Text("Vorschau schließen"))
            }
            content(payload)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
    }

    private func label(_ payload: ClipPayload?) -> String {
        if let kind = store?.secretKind(entry) { return kind }
        if entry.isVault { return String(localized: "Tresor") }
        if let payload, ClipTile.color(entry, payload) != nil { return String(localized: "Farbe") }
        return switch entry.kind {
        case .text: String(localized: "Text")
        case .richText: String(localized: "Formatierter Text")
        case .link: String(localized: "Link")
        case .image: String(localized: "Bild")
        case .file: String(localized: "Datei")
        }
    }

    @ViewBuilder private func content(_ payload: ClipPayload?) -> some View {
        if store?.isConcealed(entry) ?? true {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: entry.isVault ? "lock.fill" : "key.fill").font(.system(size: 20)).foregroundStyle(.orange)
                Text(verbatim: "••••••••••••").font(.system(size: 16, design: .monospaced)).foregroundStyle(.secondary)
                Text(verbatim: store?.title(entry) ?? "").font(.system(size: 12, weight: .semibold))
            }
        } else if let payload, let color = ClipTile.color(entry, payload) {
            colorBody(color)
        } else if let payload {
            switch entry.kind {
            case .image:
                if let image = ClipThumbnails.image(for: entry, payload: payload) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8)).frame(maxWidth: .infinity)
                }
            case .file:
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "doc").font(.system(size: 24))
                    Text(verbatim: payload.plain).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            case .link, .text, .richText:
                ScrollView {
                    Text(verbatim: String(payload.plain.prefix(20_000)))
                        .font(.system(size: 12, design: entry.kind == .link ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func colorBody(_ c: ColorCode) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha))
                .frame(width: 120, height: 90)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.colorLines(c), id: \.0) { name, value in
                    HStack(spacing: 8) {
                        Text(verbatim: name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        Text(verbatim: value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// HEX, RGB, HSL – getestet.
    static func colorLines(_ c: ColorCode) -> [(String, String)] {
        let r = Int((c.red * 255).rounded()), g = Int((c.green * 255).rounded()), b = Int((c.blue * 255).rounded())
        let maxV = max(c.red, c.green, c.blue), minV = min(c.red, c.green, c.blue)
        let l = (maxV + minV) / 2
        let d = maxV - minV
        var h = 0.0, s = 0.0
        if d > 0 {
            s = d / (1 - abs(2 * l - 1))
            h = switch maxV {
            case c.red: 60 * ((c.green - c.blue) / d).truncatingRemainder(dividingBy: 6)
            case c.green: 60 * ((c.blue - c.red) / d + 2)
            default: 60 * ((c.red - c.green) / d + 4)
            }
            if h < 0 { h += 360 }
        }
        var lines = [("HEX", c.hex), ("RGB", "rgb(\(r), \(g), \(b))"),
                     ("HSL", "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)")]
        if c.alpha < 1 { lines.append(("Alpha", String(format: "%.2f", c.alpha))) }
        return lines
    }
}
