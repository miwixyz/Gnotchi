import SwiftUI

/// Schwebende große Insel (0.22.0): eigenes Panel, Glas mit leichter Schwarz-Tönung im Glas, vier runde Ecken,
/// Schatten im Rand `DetachedIsland.pad`. Ziehen und Doppelklick nur auf freiem Hintergrund – Knöpfe, Regler,
/// Fortschrittsbalken und Kacheln liegen darüber und behalten ihr eigenes Klicken und Ziehen (Entschieden 10).
extension IslandView {

    /// Was diese Ansicht zeigt: Die kleine Insel bleibt klein, solange groß schwebt (Entschieden 1).
    var shownMode: IslandState.Mode { !detached && state.mode == .expanded ? .compact : state.mode }

    @ViewBuilder var detachedIsland: some View {
        if state.mode == .expanded {
            let shape = RoundedRectangle(cornerRadius: DetachedIsland.corner, style: .continuous)
            ZStack(alignment: .top) {
                shape.fill(.clear)
                    .contentShape(shape)
                    .onTapGesture(count: 2) { onDetached(.reset) }
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { _ in onDetached(.dragChanged) }
                        .onEnded { _ in onDetached(.dragEnded) })
                content.clipShape(shape)   // nur der Inhalt – ein Zuschnitt des Glases nähme ihm den Lichtrand
            }
            .frame(width: size.width, height: size.height)
            // Tönung IM Glas statt Schwarz darüber: Lesbarkeit über hellem Schreibtisch, Brechung und Rand bleiben.
            .glassEffect(.regular.tint(.black.opacity(DetachedIsland.glassTint)), in: shape)
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            .onHover(perform: onHover)
            .id(state.hoverEpoch)
            .padding(DetachedIsland.pad)
            // Feder aus Richtung Pille, auch wenn die Insel verschoben ist (Entschieden 9).
            .transition(.scale(scale: 0.4, anchor: state.anchor).combined(with: .opacity))
        }
    }
}
