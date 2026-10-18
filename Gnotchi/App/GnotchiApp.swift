import AppKit
import OSLog
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
            Image(nsImage: MenuBarGlyph.image)
                .accessibilityLabel("Gnotchi")
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

    let prefs: Preferences
    /// Updates (Sparkle). Im Testlauf nicht gestartet: kein Netz aus dem Test-Host.
    private(set) var updater: Updater?
    /// Was die Insel zeigt (Adapter + AppleScript-Rückfall). Läuft ohne Bedienungshilfen-Freigabe.
    let nowPlaying: NowPlayingModel
    /// Quelle der Insel; im Betrieb `nowPlaying`, im Test eine Attrappe.
    @ObservationIgnored private let source: NotchPart
    @ObservationIgnored private let makeIsland: () -> NotchPart
    /// Erst beim ersten Einschalten angelegt: Bei „aus“ entsteht kein Panel, kein Beobachter.
    @ObservationIgnored private lazy var island: NotchPart = makeIsland()
    /// false im Testlauf: Dann startet `applyNotchSetting` nichts (kein perl, keine Apple Events).
    @ObservationIgnored private let allowStart: Bool
    /// Ob Quelle und Insel laufen. Verhindert doppelte Starts und Stopps.
    private(set) var notchRunning = false
    /// Beobachter-Token der Beenden-Meldung. Lebt so lange wie die App; aufgehoben statt `_ =`,
    /// damit klar ist, dass die Anmeldung gewollt bestehen bleibt.
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?

    /// Im Testlauf startet die App als Test-Host. Dann weder Sparkle noch der Medien-Adapter
    /// (er startete perl, der Rückfall schickte Apple Events): Die Tests prüfen reine Logik.
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Alle Parameter außer den Standardwerten nur für Tests: eigene Einstellungen (der Test-Host
    /// teilt sich sonst die echten), Attrappen für Quelle und Insel, Start trotz Testlauf erlauben.
    init(prefs: Preferences = Preferences(),
         allowStart: Bool = !AppModel.isRunningTests,
         source: NotchPart? = nil,
         makeIsland: (() -> NotchPart)? = nil) {
        self.prefs = prefs
        self.allowStart = allowStart
        let nowPlaying = NowPlayingModel()
        self.nowPlaying = nowPlaying
        self.source = source ?? nowPlaying
        self.makeIsland = makeIsland ?? { IslandController(model: nowPlaying) }
        FamilyTheme.app = .gnotchi
        if !FamilyTheme.registerFonts() {
            // Seam-Code-Audit 09.10., C12: sonst fällt SwiftUI still auf die Systemschrift zurück.
            Self.log.error("Schrift Plus Jakarta Sans nicht registriert, Systemschrift im Einsatz")
        }
        guard !Self.isRunningTests else { return }
        updater = Updater()
        Self.log.notice("Start")
        applyNotchSetting()
        // Beim Beenden den perl-Kindprozess und den Rückfall sauber stoppen, nicht verwaisen lassen.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopNotch() }
        }
    }

    /// Schalter „Musik in der Notch“: an → Adapter und Insel starten, aus → beide stoppen.
    /// Beim Start und bei jeder Änderung des Schalters aufgerufen; im Testlauf wirkungslos.
    func applyNotchSetting() {
        guard allowStart else { return }
        if prefs.notchMedia {
            guard !notchRunning else { return }
            source.start()
            island.start()
            notchRunning = true
        } else {
            stopNotch()
        }
    }

    /// Insel zuerst abbauen, dann die Quelle: So reagiert keine Insel mehr auf das Leeren des Titels.
    private func stopNotch() {
        guard notchRunning else { return }
        island.stop()
        source.stop()
        notchRunning = false
    }
}

/// Teil der Notch-Kette mit Start/Stopp. Nur, damit der Test die Reihenfolge an Attrappen prüfen kann.
@MainActor
protocol NotchPart: AnyObject {
    func start()
    func stop()
}

extension NowPlayingModel: NotchPart {}
extension IslandController: NotchPart {}

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
