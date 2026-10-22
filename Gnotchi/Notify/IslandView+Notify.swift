import AppKit
import SwiftUI

/// Mitteilung in der Insel (0.6.0, Vorbild DynamicLake). Alle Texte kommen aus fremden Apps → nur `Text(verbatim:)`
/// (G5/G29), nie protokolliert. Klick auf die Fläche öffnet die App (macOS entscheidet wohin), Knöpfe lösen genau die
/// von macOS gemeldete Aktion aus (G30).
struct NoteIsland: View {
    let note: NotifyWire.Note
    /// Wartende Mitteilungen dahinter.
    let queued: Int
    /// Mit Notch: deren Höhe – die Hardware verdeckt den oberen Streifen.
    let topInset: CGFloat
    let onOpen: () -> Void
    let onAction: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: note.app).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1)
                    if queued > 0 {
                        Text(verbatim: "+\(queued)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 5).background(Capsule().fill(.white.opacity(0.85)))
                    }
                    Spacer(minLength: 0)
                    if let close = NotifyWire.closeAction(note) {
                        Button { onAction(close) } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                .frame(width: 18, height: 18).background(Circle().fill(.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: close))
                    }
                }
                if !note.title.isEmpty {
                    Text(verbatim: note.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                }
                if !note.subtitle.isEmpty {
                    Text(verbatim: note.subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                }
                if !note.body.isEmpty {
                    Text(verbatim: note.body).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
                let buttons = NotifyWire.buttonActions(note)
                if !buttons.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(buttons, id: \.self) { name in
                            Button { onAction(name) } label: {
                                Text(verbatim: name).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                                    .lineLimit(1).padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(.white.opacity(0.16)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: topInset + 10, leading: 14, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Mitteilung von \(note.app)"))
        .transition(.opacity)
    }

    @ViewBuilder private var icon: some View {
        if let b = note.bundle, let image = AppIcons.icon(for: b) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: 30, height: 30)
        } else {
            Image(systemName: "app.badge").font(.system(size: 20)).foregroundStyle(.white).frame(width: 30, height: 30)
        }
    }
}

/// Eingehender Anruf (0.6.0, Vorbild DynamicLake DynaCall): Anrufart, Anrufer, rot Ablehnen, grün Annehmen; im Gespräch
/// nur rot Beenden.
/// Knöpfe erst nach `ActivityModel.callArmDelay` aktiv (kein versehentliches Annehmen beim Überfahren, G30).
struct CallIsland: View {
    let call: NotifyWire.Note
    let armed: Bool
    let topInset: CGFloat
    let onAnswer: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: call.app.localizedCaseInsensitiveContains("facetime") ? "video.fill" : "phone.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.green).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: call.title.isEmpty ? "Unbekannt" : call.title)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(verbatim: NotifyWire.isOngoing(call) ? "\(call.app) · Gespräch" : call.app)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            ForEach(call.actions, id: \.self) { action in
                let accept = NotifyWire.acceptActions.contains(action)
                Button { onAnswer(action) } label: {
                    Image(systemName: accept ? "phone.fill" : "phone.down.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(accept ? Color.green : Color.red))
                }
                .buttonStyle(.plain)
                .disabled(!armed)
                .opacity(armed ? 1 : 0.5)
                .accessibilityLabel(Text(verbatim: action))
            }
        }
        .padding(EdgeInsets(top: topInset + 6, leading: 16, bottom: 6, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Anruf: \(call.title)"))
        .transition(.opacity)
    }
}
