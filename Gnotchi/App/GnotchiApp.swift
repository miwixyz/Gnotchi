import AppKit
import SwiftUI

@main
struct GnotchiApp: App {

    @State private var model = AppModel()

    var body: some Scene {
        // Menüleisten-Symbol „Insel mit Pegel“ (Michael, 18.10.: Variante C) als Vorlagenbild:
        // macOS färbt es selbst für hell, dunkel, Glas und getönt.
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }

        Window("Gnotchi – Einstellungen", id: AppModel.WindowID.settings) {
            SettingsView()
                .environment(model)
                .environment(model.prefs)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)

        // Hilfe, Änderungen, Fremdcode-Lizenzen (Sparkle, Plus Jakarta Sans und mediaremote-adapter
        // verlangen, dass ihr Lizenztext mit ausgeliefert und erreichbar ist).
        Window("Gnotchi", id: AppModel.WindowID.help) {
            HelpView()
                .padding(16)
                .frame(width: 520)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)
    }
}

/// Menüleisten-Symbol. Meldet beim Erscheinen (gleich beim Start) `openWindow` an AppModel, damit auch
/// das Kontextmenü der Insel Fenster öffnen kann, bevor das Menü je offen war.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Restzeit neben dem Symbol, solange ein Timer läuft oder pausiert (Michael 06.11.). Bewusst ohne
        // `TimelineView`: im MenuBarExtra-Label erzeugte sie eine Endlosschleife (06.11., Hauptthread 99 %).
        // Der Text kommt fertig aus dem Modell und ändert sich höchstens einmal pro Sekunde.
        Group {
            if let clock = model.activity.menuBarClock {
                HStack(spacing: 4) {
                    Image(nsImage: MenuBarGlyph.image)
                    Text(verbatim: clock).monospacedDigit()
                }
                .accessibilityLabel(Text(verbatim: "Gnotchi, Timer \(clock)"))
            } else {
                Image(nsImage: MenuBarGlyph.image)
                    .accessibilityLabel("Gnotchi")
            }
        }
        .onAppear { model.registerWindowOpener { openWindow(id: $0) } }
    }
}
