import AppKit
import SwiftUI

/// Menü am Menüleisten-Symbol. Die Insel selbst kommt später (Plan Aufgaben 8–12);
/// bis dahin ist das Menü der einzige Zugang zu Einstellungen, Hilfe und Updates.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Wie Seam: keine Mitteilung bei einem gefundenen Update, stattdessen ein Eintrag hier.
        if let updater = model.updater, let version = updater.pendingVersion {
            Button("Update \(version) verfügbar …") { updater.checkForUpdates() }
            Divider()
        }
        Button("Einstellungen …") { open("einstellungen") }
            .keyboardShortcut(",")
        Button("Hilfe …") { open("hilfe") }
        Button("Nach Updates suchen …") { model.updater?.checkForUpdates() }
            .disabled(!(model.updater?.canCheck ?? false))
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ id: String) {
        openWindow(id: id)
        // Menüleisten-App ohne Dock-Symbol: aktivieren und das neue Fenster ausdrücklich zum
        // Schlüsselfenster machen, sonst liegt es oben, bleibt aber inaktiv (Seam, gemessen 09.10.).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate()
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true }?.makeKeyAndOrderFront(nil)
        }
    }
}
