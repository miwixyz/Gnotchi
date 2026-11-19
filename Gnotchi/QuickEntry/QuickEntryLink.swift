import Carbon.HIToolbox
import Foundation
import OSLog

/// Schnelleingabe (G61): eigener Schalter, ab Werk aus. Meldet das Kürzel an (⌃⌥N, wählbar), öffnet die Zeile aus der
/// Notch und bietet die Ring-Taste „Neuer Eintrag“ an. Gespeichert wird nur über Kalli (`KalliEventLink.submit`);
/// Gnotchi selbst hat keinen Zugriff auf Kalender und Erinnerungen. Nie Eingaben ins Protokoll.
@MainActor
final class QuickEntryLink: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "schnelleingabe")

    private let activity: ActivityModel
    private let prefs: Preferences
    private let panel: QuickEntryPanelController
    private var hotKeyID: UInt32?
    private var registeredHotKey: Preferences.HotKey?

    init(activity: ActivityModel, prefs: Preferences, kalli: KalliEventLink) {
        self.activity = activity
        self.prefs = prefs
        panel = QuickEntryPanelController(submit: { [weak kalli] entry in
            guard let kalli else { return .failure(.kalliNotRunning) }
            return await kalli.submit(entry)
        }, undo: { [weak kalli] id in
            // Nicht `kalli?.undo(id) ?? …`: `undo` liefert bei Erfolg `nil`, das `??` machte daraus „Kalli läuft
            // nicht“ (Sichttest 19.11.: Kalli hatte gelöscht, die Zeile zeigte einen Fehler und blieb offen).
            guard let kalli else { return QuickEntryFailure.kalliNotRunning.message }
            return await kalli.undo(id)
        })
    }

    /// Vorschlag ⌃⌥N („N“ für neu). Gemessen 19.11.: per Carbon frei, kein Systemkürzel auf N.
    static func defaultHotKey() -> Preferences.HotKey? {
        HotKeyCenter.keyCode(producing: "n").map {
            Preferences.HotKey(keyCode: $0, modifiers: UInt32(controlKey | optionKey))
        }
    }

    func start() {
        if prefs.quickEntryHotKey == nil { prefs.quickEntryHotKey = Self.defaultHotKey() }
        registerHotKey()
        activity.openQuickEntry = { [weak self] in self?.panel.open() }
        Self.log.notice("Schnelleingabe an")
    }

    func stop() {
        if let hotKeyID { HotKeyCenter.shared.unregister(hotKeyID) }
        hotKeyID = nil
        registeredHotKey = nil
        activity.openQuickEntry = nil
        panel.close()
        Self.log.notice("Schnelleingabe aus")
    }

    func recheck() {
        guard registeredHotKey != prefs.quickEntryHotKey else { return }
        registerHotKey()
    }

    private func registerHotKey() {
        if let hotKeyID { HotKeyCenter.shared.unregister(hotKeyID) }
        hotKeyID = nil
        registeredHotKey = prefs.quickEntryHotKey
        guard let hotKey = prefs.quickEntryHotKey else { return }
        hotKeyID = HotKeyCenter.shared.register(hotKey) { [weak self] in self?.panel.toggle() }
        if hotKeyID == nil { Self.log.error("Tastenkürzel nicht registriert") }
    }
}
