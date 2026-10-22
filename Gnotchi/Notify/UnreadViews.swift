import AppKit
import SwiftUI

/// Ungelesen-Zahlen (0.9.0, G33): App-Symbol + Zahl, Klick öffnet die App – wie ein Klick aufs Dock-Symbol. Nur
/// Kennung + Zahl, kein Text aus der App. Steht in der Symbolleiste der großen Insel und im Band.
struct UnreadMini: View {
    let badges: [NotifyWire.Badge]
    /// Mehr passt neben die anderen Symbole nicht.
    static let maxShown = 4

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges.prefix(Self.maxShown), id: \.bundle) { b in
                Button { Self.open(b.bundle) } label: {
                    HStack(spacing: 3) {
                        AppSymbol(bundleID: b.bundle, size: 14)
                        Text(verbatim: Self.short(b.count)).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "\(Self.name(b.bundle)), \(b.count) ungelesen"))
            }
        }
    }

    /// „999+“ statt vierstelliger Zahlen – sonst sprengt eine App die Leiste.
    nonisolated static func short(_ n: Int) -> String { n > 999 ? "999+" : "\(n)" }

    static func name(_ bundle: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? "App"
    }

    /// Nur die installierte App mit genau dieser Kennung (LaunchServices), wie ein Klick aufs Dock-Symbol.
    static func open(_ bundle: String) {
        guard NotifyWire.isValidBundleID(bundle),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Kleine Insel: Summe als Glas-Kapsel mit kleinem roten Punkt (Michael 22.10.: „dezenter, passend zum Glass Look“ –
/// die volle rote Kapsel war zu laut).
struct UnreadDot: View {
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(Color.red.opacity(0.9)).frame(width: 5, height: 5)
            Text(verbatim: UnreadMini.short(total)).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85)).monospacedDigit()
        }
        .padding(.horizontal, 6).frame(minHeight: 16)
        .background(Capsule().fill(.white.opacity(0.12)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(total) ungelesen"))
    }
}
