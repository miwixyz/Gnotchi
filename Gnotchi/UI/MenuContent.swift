import AppKit
import SwiftUI

/// Menü am Menüleisten-Symbol: einziger Zugang zu Einstellungen, Hilfe und Updates.
/// Die Insel zeigt nur den Titel und steuert die Wiedergabe.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Zweite Notch-App (Michael, 18.10.: „sollen nicht vorkommen“): ganz oben, führt zur Hilfe.
        // App-Name aus dem lokalen Bundle, trotzdem nur `Text(verbatim:)`.
        if let other = model.nowPlaying.competingNotchApp {
            Button { open(AppModel.WindowID.help) } label: {
                Label { Text(verbatim: IslandController.competingWarning(name: other)) }
                    icon: { Image(systemName: "exclamationmark.triangle") }
            }
            Divider()
        }
        // Wie Seam: keine Mitteilung bei einem gefundenen Update, stattdessen ein Eintrag hier.
        if let updater = model.updater, let version = updater.pendingVersion {
            Button("Update \(version) verfügbar …") { updater.checkForUpdates() }
            Divider()
        }
        Button("Einstellungen …") { open(AppModel.WindowID.settings) }
            .keyboardShortcut(",")
        Button("Hilfe …") { open(AppModel.WindowID.help) }
        Button("Nach Updates suchen …") { model.updater?.checkForUpdates() }
            .disabled(!(model.updater?.canCheck ?? false))
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Meldet zugleich `openWindow` an AppModel (falls das Menüleisten-Symbol es nicht schon getan hat).
    private func open(_ id: String) {
        let action = openWindow
        model.registerWindowOpener { action(id: $0) }
        model.showWindow(id)
    }
}
