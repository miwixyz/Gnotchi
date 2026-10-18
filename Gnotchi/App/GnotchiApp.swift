import AppKit
import OSLog
import SwiftUI

@main
struct GnotchiApp: App {

    @State private var model = AppModel()

    var body: some Scene {
        // Platzhalter-Symbol, bis Michaels App-Symbol da ist.
        MenuBarExtra("Gnotchi", systemImage: "capsule.fill") {
            MenuContent()
                .environment(model)
        }

        Window("Gnotchi – Einstellungen", id: "einstellungen") {
            SettingsView()
                .environment(model)
                .environment(model.prefs)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)

        // Hilfe, Änderungen, Fremdcode-Lizenzen (Sparkle, Plus Jakarta Sans und mediaremote-adapter
        // verlangen, dass ihr Lizenztext mit ausgeliefert und erreichbar ist).
        Window("Gnotchi", id: "hilfe") {
            HelpView()
                .padding(16)
                .frame(width: 520)
                .background(MoveToActiveSpace())
        }
        .windowResizability(.contentSize)
    }
}

/// Hält Einstellungen und Updater. Bewusst ohne Bedienungshilfen (docs/SECURE-DESIGN.md G1):
/// kein `AXIsProcessTrusted`, keine Freigabe-Anfrage, keine Event-Taps.
@MainActor
@Observable
final class AppModel {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "start")

    let prefs = Preferences()
    /// Updates (Sparkle). Im Testlauf nicht gestartet: kein Netz aus dem Test-Host.
    private(set) var updater: Updater?

    /// Im Testlauf startet die App als Test-Host. Dann weder Sparkle noch (später) der
    /// Medien-Adapter: Die Tests prüfen reine Logik.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        FamilyTheme.app = .gnotchi
        if !FamilyTheme.registerFonts() {
            // Seam-Code-Audit 09.10., C12: sonst fällt SwiftUI still auf die Systemschrift zurück.
            Self.log.error("Schrift Plus Jakarta Sans nicht registriert, Systemschrift im Einsatz")
        }
        guard !Self.isRunningTests else { return }
        updater = Updater()
        Self.log.notice("Start")
    }
}

/// Fenster (Einstellungen, Hilfe) kommen in den Space, in dem man gerade ist. Ohne das holt
/// macOS beim zweiten Öffnen den Space nach vorn, in dem das Fenster zuerst aufging
/// (Seam, Michael 09.10.: „Die Einstellungen müssen im selben Space angezeigt werden!“).
struct MoveToActiveSpace: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Hook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.collectionBehavior.insert(.moveToActiveSpace)
        }
    }
}
