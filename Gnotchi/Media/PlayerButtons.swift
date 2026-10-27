import SwiftUI

/// Knopfzeile der Wiedergabe für große Insel und Plattenspieler (0.17.0): Shuffle · Zurück · Pause/Wiedergabe · Weiter.
/// Shuffle nur bei Spotify und Musik. Ein Favoriten-Herz folgt später (über das Hilfsprogramm, siehe Spec).
/// Beschriftungen nennen, was der Knopf JETZT tut (VoiceOver).
struct PlayerButtons: View {
    let model: NowPlayingModel
    let isPlaying: Bool
    var iconSize: CGFloat = 15
    var spacing: CGFloat = 16

    var body: some View {
        HStack(spacing: spacing) {
            if model.canShuffle {
                let on = model.extras.shuffle == true
                // An: helle Fläche + Punkt darunter (wie bei Apple); aus: gedimmt (Michael 27.10.: „deutlicher“).
                button("shuffle", label: on ? "Zufallswiedergabe aus" : "Zufallswiedergabe an", dimmed: !on) {
                    model.toggleShuffle()
                }
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(on ? 0.22 : 0))
                    .padding(-4))
                .overlay(alignment: .bottom) {
                    Circle().fill(.white).frame(width: 4, height: 4).offset(y: 7).opacity(on ? 1 : 0)
                }
            }
            button("backward.fill", label: "Zurück") { model.previous() }
            button(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Wiedergabe") { model.playPause() }
            button("forward.fill", label: "Weiter") { model.next() }
        }
        // Ohne Animation-Transaktion springt das Symbol; `.replace` braucht sie zum Überblenden.
        .animation(.snappy, value: isPlaying)
        .animation(.snappy, value: model.extras)
    }

    private func button(_ symbol: String, label: String, dimmed: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(dimmed ? 0.45 : 1))
                .frame(width: iconSize + 7, height: iconSize + 7)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}
