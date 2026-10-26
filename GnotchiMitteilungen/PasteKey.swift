import AppKit
import CoreGraphics
import OSLog

/// Einfügen (0.12.0, SECURE-DESIGN G42): drückt **genau** ⌘V an die vordere App – sonst nichts. Einzige Datei, die die
/// Lint-Regel `keine_eingaben_im_helfer` ausnimmt. Kein Text, keine andere Taste, kein Ziel von außen: Der Inhalt
/// liegt schon in der Zwischenablage (Gnotchi hat ihn auf Michaels Doppelklick/↵ dort abgelegt).
@MainActor
enum PasteKey {

    private static let log = Logger(subsystem: NotifyWire.helperBundleID, category: "einfuegen")
    /// Taste „V“ (kVK_ANSI_V) – auf QWERTZ und QWERTY dieselbe Stelle. Dvorak ohne „⌘-QWERTY“: Restrisiko G42.
    private static let keyV: CGKeyCode = 9
    /// Höchstens ein ⌘V je 0,3 s (G42, D).
    private static let minInterval: TimeInterval = 0.3
    private static var last: Date?

    /// `trusted` = Bedienungshilfen-Freigabe erteilt. Protokoll nur mit festen Texten, nie Inhalt oder App-Name.
    static func press(trusted: Bool) {
        guard trusted else { return log.notice("Einfügen verworfen: keine Freigabe") }
        let now = Date()
        if let last, now.timeIntervalSince(last) < minInterval { return log.notice("Einfügen verworfen: zu schnell") }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front != NotifyWire.gnotchiBundleID, front != NotifyWire.helperBundleID else {
            return log.notice("Einfügen verworfen: Gnotchi ist vorn")
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            return log.error("Einfügen: Tastenereignis nicht erzeugt")
        }
        // Nur ⌘ – gedrückte ⇧/⌥/⌃ des Nutzers nicht mitnehmen (sonst ⌥⌘V = „Einsetzen und Stil anpassen“ o. Ä.).
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        last = now
        log.notice("Einfügen")
    }
}
