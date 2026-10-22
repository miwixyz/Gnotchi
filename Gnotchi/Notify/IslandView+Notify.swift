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

/// Eingehender Anruf (0.6.0, Vorbild DynamicLake DynaCall). Zustände (0.9.0, gemessen 22.10.):
/// - **Klingeln:** rot Ablehnen (Apples Fenster ist danach weg, Anrufer auf der Mailbox), „Mitlesen“, grün Annehmen.
/// - **Mailbox** (nach „Mitlesen“): rot „Mitlesen beenden“, grün Annehmen.
/// - **Gespräch:** rot Beenden.
/// - **Unbekannt** (keine bekannten Knöpfe): nur der Hinweis, in macOS zu antworten – Apples Banner ist dann sichtbar.
/// Knöpfe erst nach `ActivityModel.callArmDelay` aktiv (kein versehentliches Annehmen beim Überfahren, G30).
struct CallIsland: View {
    let call: NotifyWire.Note
    let armed: Bool
    let topInset: CGFloat
    /// Annehmen, Beenden, „Mitlesen beenden“ – genau die gemeldete Aktion.
    let onAnswer: (String) -> Void
    var onDecline: () -> Void = {}
    var onScreen: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: call.app.localizedCaseInsensitiveContains("facetime") ? "video.fill" : "phone.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.green).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: call.title.isEmpty ? "Unbekannt" : call.title)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(verbatim: Self.status(call))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            ForEach(Self.buttons(call), id: \.self) { b in
                Button { tap(b) } label: {
                    Image(systemName: b.symbol)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(b.color))
                }
                .buttonStyle(.plain)
                .disabled(!armed)
                .opacity(armed ? 1 : 0.5)
                .help(Text(verbatim: b.label))
                .accessibilityLabel(Text(verbatim: b.label))
            }
        }
        .padding(EdgeInsets(top: topInset + 6, leading: 16, bottom: 6, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Anruf: \(call.title)"))
        .transition(.opacity)
    }

    private func tap(_ b: CallButton) {
        switch b.kind {
        case .decline: onDecline()
        case .screen: onScreen()
        case .action(let name): onAnswer(name)
        }
    }

    // MARK: Rein (getestet)

    enum CallButtonKind: Hashable { case decline, screen, action(String) }

    struct CallButton: Hashable {
        let kind: CallButtonKind
        let label: String
        let symbol: String
        let red: Bool
        var color: Color { red ? .red : (symbol == "phone.fill" ? .green : Color.white.opacity(0.22)) }
    }

    /// Reihenfolge links → rechts: Rot, Mitlesen, Grün (wie Apples Banner: Ablehnen vor Annehmen).
    nonisolated static func buttons(_ call: NotifyWire.Note) -> [CallButton] {
        let a = call.actions
        var out: [CallButton] = []
        if let end = a.first(where: { NotifyWire.endActions.contains($0) }) {
            return [CallButton(kind: .action(end), label: end, symbol: "phone.down.fill", red: true)]
        }
        if let stop = a.first(where: { NotifyWire.voicemailStopActions.contains($0) }) {
            out.append(CallButton(kind: .action(stop), label: "Mitlesen beenden", symbol: "stop.fill", red: true))
        } else if a.contains(where: { NotifyWire.declineActions.contains($0) }) {
            out.append(CallButton(kind: .decline, label: "Ablehnen", symbol: "phone.down.fill", red: true))
            out.append(CallButton(kind: .screen, label: "Mitlesen (Mailbox)", symbol: "text.bubble.fill", red: false))
        }
        if let accept = a.first(where: { NotifyWire.acceptActions.contains($0) }) {
            out.append(CallButton(kind: .action(accept), label: accept, symbol: "phone.fill", red: false))
        }
        return out
    }

    nonisolated static func status(_ call: NotifyWire.Note) -> String {
        if call.actions.isEmpty { return "\(call.app) · in macOS beantworten" }
        if NotifyWire.isOngoing(call) { return "\(call.app) · Gespräch" }
        if NotifyWire.isScreening(call) { return "Mailbox · Mitlesen" }
        return call.app
    }
}
