import SwiftUI

// Pegel- und Ladeanzeigen der Insel (0.5.0 aus IslandView.swift ausgelagert: Datei ≤ 650 Zeilen).

/// Echter Pegel aus Tippis Meldung (0…1), vier Balken unterschiedlich stark – wie Tippis eigene Pille.
struct LiveLevelBars: View {
    let level: Double
    private static let weights: [Double] = [0.55, 1, 0.8, 0.45]
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Self.weights.indices, id: \.self) { i in
                Capsule().fill(.white).frame(width: 2.5, height: 4 + 10 * level * Self.weights[i])
            }
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }
}

/// „Wandelt um“: drei Punkte, die nacheinander aufleuchten. Reines SwiftUI statt ProgressView (der
/// Testrenderer zeichnet AppKit-Bausteine nicht); 15 Bilder/s reichen, die Ansicht gibt es nur beim Umwandeln.
struct WorkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(.white)
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 4 - Double(i) * 0.9)))
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

/// Animierter Pegel – reine Animation, kein Audiosignal (Spezifikation „Nicht in diesem Schritt“).
struct LevelBars: View {
    let playing: Bool
    var body: some View {
        // 30 Bilder/s reichen für einen Pegel; ungebremst liefe er mit der Bildschirmrate (bis 120 Hz).
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(.white)
                        .frame(width: 2.5, height: playing ? 5 + 7 * abs(sin(t * (3 + Double(i)) + Double(i))) : 4)
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}
