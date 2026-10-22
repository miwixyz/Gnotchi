import SwiftUI

/// Code & KI (0.9.0, G34): Ansichten. Alle Texte aus der Sitzung nur `Text(verbatim:)`, gekürzt.
enum ClaudeStyle {
    /// Farbe je Zustand – arbeitet Orange (Claude), wartet Gelb, fertig Grün.
    static func color(_ state: ClaudeSession.State) -> Color {
        switch state {
        case .working: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .waiting: .yellow
        case .done: .green
        }
    }

    static let symbol = "sparkles"
}

/// Kleine Insel: Symbol + Status. Mit Notch nur Symbol links und Punkt rechts (40-pt-Flügel), ohne Notch dazu
/// Projekt und Status.
struct ClaudeCompact: View {
    let session: ClaudeSession
    let count: Int
    let pill: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ClaudeStyle.symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ClaudeStyle.color(session.state))
            if pill {
                Text(verbatim: session.project).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail)
                // Nur „wartet“ als Wort (Michael-GIF 22.10.: „arbeitet“ kürzte den Projektnamen) – arbeitet = oranger Punkt.
                if session.state == .waiting {
                    Text(verbatim: "wartet").font(.system(size: 11, weight: .medium)).foregroundStyle(.yellow).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if count > 1 {
                Text(verbatim: "\(count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
            Circle().fill(ClaudeStyle.color(session.state)).frame(width: 6, height: 6)
        }
        .padding(.horizontal, pill ? 12 : 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Claude: \(session.project), \(session.statusLine)"))
        .transition(.opacity)
    }
}

/// Große Insel: bis zu zwei Sitzungen untereinander, Klick holt das Programm der Sitzung nach vorn.
struct ClaudeBig: View {
    let sessions: [ClaudeSession]
    let onOpen: (ClaudeSession) -> Void

    static let maxShown = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sessions.prefix(Self.maxShown)) { s in
                Button { onOpen(s) } label: { row(s).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "\(s.project), \(s.statusLine)"))
            }
            if sessions.count > Self.maxShown {
                Text(verbatim: "+\(sessions.count - Self.maxShown) weitere").font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private func row(_ s: ClaudeSession) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ClaudeStyle.symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ClaudeStyle.color(s.state)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: s.project).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Text(verbatim: s.statusLine).font(.system(size: 11)).foregroundStyle(ClaudeStyle.color(s.state))
                }
                .lineLimit(1).truncationMode(.tail)
                if !s.text.isEmpty {
                    Text(verbatim: s.text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        .lineLimit(s.state == .done ? 2 : 1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Band: eine Zeile (Symbol, Projekt, Status).
struct ClaudeBandLabel: View {
    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ClaudeStyle.symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ClaudeStyle.color(session.state))
            Text(verbatim: session.project).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text(verbatim: session.statusLine).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .lineLimit(1).truncationMode(.tail)
    }
}
