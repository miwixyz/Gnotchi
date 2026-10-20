import SwiftUI

/// Tippis Live-Text in der Insel (0.3.0, Michael 20.10.: „klappt auf, 2 Zeilen“). Oben die Aufnahme-Zeile
/// wie in der kleinen Insel, darunter höchstens zwei Zeilen Text – das Ende bleibt sichtbar (`.head`),
/// ältere Wörter laufen vorne raus. Text kommt von Tippi → nur `Text(verbatim:)` (G5/G21), nie protokolliert.
struct LiveTextIsland: View {
    let recording: ActivityModel.Recording
    let text: String
    let level: Double
    /// Mit Notch: deren Höhe – die Hardware verdeckt den oberen Streifen.
    let topInset: CGFloat
    /// Etwa zwei Zeilen bei 13 pt auf 312 pt Breite.
    static let displayChars = 85

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                switch recording {
                case .recording:
                    Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.red)
                    Text(verbatim: "Tippi").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    LiveLevelBars(level: level)
                case .transcribing:
                    Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    Text(verbatim: "wandelt um").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    WorkingDots()
                }
            }
            .frame(height: 16)
            Text(verbatim: LiveText.tail(text, limit: Self.displayChars))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.2), value: text)
        }
        .padding(EdgeInsets(top: topInset + 6, leading: 14, bottom: 8, trailing: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: recording == .transcribing ? "Tippi wandelt um" : "Tippi nimmt auf"))
        .transition(.opacity)
    }
}

/// Qotti-Kontingent als Zeile über der großen Musik-Ansicht (0.3.0, G22). Nur feste Texte und Zahlen.
struct QuotaLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "gauge.with.dots.needle.50percent").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary).frame(width: 14)
            Text(verbatim: text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .accessibilityElement(children: .combine)
    }
}
