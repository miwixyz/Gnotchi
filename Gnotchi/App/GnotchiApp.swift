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

/// Hält Einstellungen und Updater. Bewusst ohne Bedienungshilfen (docs/SECURE-DESIGN.md G1):
/// kein `AXIsProcessTrusted`, keine Freigabe-Anfrage, keine Event-Taps.
@MainActor
@Observable
final class AppModel {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "start")

    /// IDs der Fenster-Szenen; gebraucht von Menüleisten-Menü und Kontextmenü der Insel.
    enum WindowID {
        static let settings = "einstellungen"
        static let help = "hilfe"
    }

    let prefs: Preferences
    /// Updates (Sparkle). Im Testlauf nicht gestartet: kein Netz aus dem Test-Host.
    private(set) var updater: Updater?
    /// Musik (Adapter + AppleScript-Rückfall). Läuft ohne Bedienungshilfen-Freigabe.
    let nowPlaying: NowPlayingModel
    /// Was die Insel zeigt: Musik und die weiteren Aktivitäten.
    let activity: ActivityModel
    /// Quellen der Insel, je mit eigenem Schalter; die erste ist die Musik (im Test Attrappen).
    @ObservationIgnored private let features: [NotchFeature]
    /// Indizes der laufenden Quellen.
    @ObservationIgnored private var runningFeatures: Set<Int> = []
    @ObservationIgnored private let makeIsland: (() -> NotchPart)?
    /// Erst beim ersten Einschalten angelegt: Bei „aus“ entsteht kein Panel, kein Beobachter.
    @ObservationIgnored private lazy var island: NotchPart = makeIsland?() ?? IslandController(
        activity: activity, expandDelay: { [prefs] in prefs.expandDelay },
        openWindow: { [weak self] id in self?.showWindow(id) },
        openUpdate: { [weak self] app in self?.openUpdate(app) },
        openEvent: { KalliEventLink.openCalendar() })
    /// `openWindow` aus einer SwiftUI-Szene (Menüleisten-Symbol, Menü). Das Insel-Panel liegt außerhalb
    /// jeder Szene und hat keins – es öffnet Fenster über `showWindow`.
    @ObservationIgnored private var windowOpener: ((String) -> Void)?
    /// false im Testlauf: Dann startet `applyNotchSetting` nichts (kein perl, keine Apple Events).
    @ObservationIgnored private let allowStart: Bool
    /// Ob die Insel läuft (mindestens eine Quelle an). Verhindert doppelte Starts und Stopps.
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
         extraFeatures: [NotchFeature]? = nil,
         makeIsland: (() -> NotchPart)? = nil) {
        self.prefs = prefs
        self.allowStart = allowStart
        let nowPlaying = NowPlayingModel()
        self.nowPlaying = nowPlaying
        let activity = ActivityModel(media: nowPlaying)
        self.activity = activity
        let kalli = extraFeatures == nil && source == nil ? KalliEventLink(activity: activity) : nil
        // Mit Attrappen-Quelle (Test) ohne echte Zusatzquellen, sonst liefen Core-Audio-Beobachter im Test-Host.
        let extras = extraFeatures ?? (source == nil ? [
            // Ein Beobachter für Hinweis und Aktivität (G19: einmal angemeldet).
            NotchFeature(part: HeadphoneWatcher(activity: activity, noticeOn: { [prefs] in prefs.headphoneNotice },
                                                activityOn: { [prefs] in prefs.headphoneActivity })) {
                $0.headphoneNotice || $0.headphoneActivity
            },
            NotchFeature(part: PrivacyMonitor(activity: activity)) { $0.micCamera },
            NotchFeature(part: TippiLink(activity: activity)) { $0.tippiRecording },
            NotchFeature(part: LiveTextLink(activity: activity)) { $0.tippiRecording },
            NotchFeature(part: QottiLink(activity: activity)) { $0.qottiQuota },
            NotchFeature(part: FamilyUpdateLink(activity: activity)) { $0.familyUpdates },
            // 0.6.0 (G28–G30): startet das Hilfsprogramm mit der Bedienungshilfen-Freigabe, nicht Gnotchi selbst.
            NotchFeature(part: NotifyLink(activity: activity, prefs: prefs)) { $0.notifications },
            // 0.7.0 (G31): einziger Netzzugriff außer Updates, nur bei eingeschaltetem Wetter.
            NotchFeature(part: WeatherLink(activity: activity, prefs: prefs)) { $0.weather },
            // 0.8.0 (G32): Ziehen erkennen ohne Freigabe, Verweise statt Kopien.
            NotchFeature(part: ShelfLink(activity: activity, prefs: prefs)) { $0.shelf },
            // 0.10.0 (G36): Bildschirmfotos per Spotlight-Abfrage, NACH der Ablage gestartet (braucht activity.shelf).
            NotchFeature(part: ScreenshotWatcher(activity: activity)) { $0.shelf && $0.shelfScreenshots },
            // 0.9.0 Code & KI (G34/G35): Hooks in ~/.claude/settings.json nur bei eingeschaltetem Schalter.
            NotchFeature(part: ClaudeLink(activity: activity, prefs: prefs)) { $0.claudeCode },
            // 0.11.0 Zwischenablage (G37–G41): ab Werk aus, liest nur bei Änderung. Einfügen nur übers Hilfsprogramm (G42).
            NotchFeature(part: ClipboardLink(activity: activity, prefs: prefs)) { $0.clipboard },
        ] + (kalli.map { [NotchFeature(part: $0) { $0.kalliEvents }] } ?? []) : [])
        nowPlaying.isExcluded = { [prefs] id in prefs.isMediaExcluded(id) }
        features = [NotchFeature(part: source ?? nowPlaying) { $0.notchMedia }] + extras
        self.makeIsland = makeIsland
        FamilyTheme.app = .gnotchi
        if !FamilyTheme.registerFonts() {
            // Seam-Code-Audit 09.10., C12: sonst fällt SwiftUI still auf die Systemschrift zurück.
            Self.log.error("Schrift Plus Jakarta Sans nicht registriert, Systemschrift im Einsatz")
        }
        guard !Self.isRunningTests else { return }
        updater = Updater()
        updater?.onPendingChange = { [weak self] _ in self?.syncOwnUpdate() }
        Self.log.notice("Start")
        #if DEBUG
        ClipboardKeysProbe.runIfRequested()
        #endif
        if !prefs.claudeCode { ClaudeLink.removeLeftoverHooks() }
        // Einen Takt später, nicht im init: AppModel entsteht INNERHALB von SwiftUIs Aktualisierung der App (@State-
        // Startwert). Startet die Insel hier, zeichnet sich ihr NSHostingView mitten darin → Absturz „precondition
        // failure: setting value during update“ (24.10. im Debugger gemessen, traf auch das veröffentlichte 0.10.0).
        DispatchQueue.main.async { [weak self] in self?.applyNotchSetting() }
        // Beim Beenden den perl-Kindprozess und den Rückfall sauber stoppen, nicht verwaisen lassen.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopNotch() }
        }
    }

    /// Schalter der Insel-Quellen („Musik in der Notch“ …): jede Quelle läuft, solange ihr Schalter an ist;
    /// die Insel, solange irgendeine an ist. Erst die Quellen, dann die Insel starten.
    /// Beim Start und bei jeder Änderung eines Schalters aufgerufen; im Testlauf wirkungslos.
    func applyNotchSetting() {
        activity.setRotationEnabled(prefs.liveRotation)
        activity.setMirrorEnabled(prefs.mirror)
        activity.timerAlarmEnabled = prefs.timerAlarm
        activity.playerFirst = prefs.playerFirst
        activity.compactControls = prefs.compactControls
        activity.compactUnread = prefs.compactUnread
        activity.bandStyle = prefs.bandStyle
        if !prefs.playerFirst { activity.overlayActivity = nil }
        syncOwnUpdate()
        guard allowStart else { return }
        let wanted = Set(features.indices.filter { features[$0].isOn(prefs) })
        guard !wanted.isEmpty else { return stopNotch() }
        for i in runningFeatures.subtracting(wanted).sorted() {
            features[i].part.stop()
            runningFeatures.remove(i)
        }
        for i in wanted.subtracting(runningFeatures).sorted() {
            features[i].part.start()
            runningFeatures.insert(i)
        }
        // Laufende Quellen lesen geänderte Schalter neu (Kopfhörer: Hinweis und Aktivität teilen sich einen Beobachter).
        for i in runningFeatures.sorted() { features[i].part.recheck() }
        guard !notchRunning else { return }
        island.start()
        notchRunning = true
    }

    /// Medienfilter geändert: laufende Wiedergabe sofort neu bewerten.
    func applyMediaFilter() {
        nowPlaying.refilter()
    }

    /// Gnotchis eigenes Update (Sparkle) als Aktivität, nur bei „Updates der App-Familie“.
    private func syncOwnUpdate() {
        let version = prefs.familyUpdates ? updater?.pendingVersion : nil
        activity.setOwnUpdate(FamilyUpdates.ownEntry(version, now: Date()))
    }

    /// Klick auf ein Update in der Insel. Gnotchi selbst: Sparkles Fenster. Familien-App: nur die echte,
    /// signaturgeprüfte App öffnen (G24); scheitert das, ein Hinweis statt eines Starts.
    func openUpdate(_ app: FamilyApp) {
        guard app != .gnotchi else {
            NSApp.activate()
            updater?.checkForUpdates()
            return
        }
        FamilyLauncher.open(app) { [weak self] ok in
            guard !ok else { return }
            self?.activity.post(ActivityModel.Notice(symbol: "exclamationmark.triangle.fill", title: app.name,
                                                     subtitle: "App nicht gefunden"))
        }
    }

    func registerWindowOpener(_ open: @escaping (String) -> Void) {
        windowOpener = open
    }

    /// Fenster öffnen und nach vorn holen. Menüleisten-App ohne Dock-Symbol: aktivieren und das Fenster
    /// ausdrücklich zum Schlüsselfenster machen, sonst liegt es oben, bleibt aber inaktiv (Seam, gemessen 09.10.).
    func showWindow(_ id: String) {
        guard let windowOpener else {
            Self.log.error("Fenster \(id, privacy: .public) nicht geöffnet: noch keine Szene hat openWindow gemeldet")
            return
        }
        windowOpener(id)
        guard !Self.isRunningTests else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate()
            NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true }?.makeKeyAndOrderFront(nil)
        }
    }

    /// Einstellungen geöffnet: Insel und Hinweis auf eine zweite Notch-App neu prüfen (nur wenn sie läuft –
    /// sonst entstünde hier erst die Insel).
    func recheckNotch() {
        guard notchRunning else { return }
        island.recheck()
    }

    /// Insel zuerst abbauen, dann die Quellen: So reagiert keine Insel mehr auf das Leeren des Titels.
    private func stopNotch() {
        if notchRunning {
            island.stop()
            notchRunning = false
        }
        for i in runningFeatures.sorted() { features[i].part.stop() }
        runningFeatures.removeAll()
    }
}

/// Teil der Notch-Kette mit Start/Stopp. Nur, damit der Test die Reihenfolge an Attrappen prüfen kann.
@MainActor
protocol NotchPart: AnyObject {
    func start()
    func stop()
    func recheck()
}

extension NotchPart {
    func recheck() {}
}

/// Quelle der Insel mit ihrem Schalter in den Einstellungen.
struct NotchFeature {
    let part: NotchPart
    let isOn: @MainActor (Preferences) -> Bool

    init(part: NotchPart, isOn: @escaping @MainActor (Preferences) -> Bool) {
        self.part = part
        self.isOn = isOn
    }
}

extension NowPlayingModel: NotchPart {}
extension IslandController: NotchPart {}

/// Menüleisten-Symbol. Meldet beim Erscheinen (gleich beim Start) `openWindow` an AppModel, damit auch
/// das Kontextmenü der Insel Fenster öffnen kann, bevor das Menü je offen war.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarGlyph.image)
            .accessibilityLabel("Gnotchi")
            .onAppear { model.registerWindowOpener { openWindow(id: $0) } }
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
