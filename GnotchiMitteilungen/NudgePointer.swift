import AppKit
import CoreGraphics
import IOKit
import OSLog

/// Wach bleiben (0.21.0, SECURE-DESIGN G47): bewegt den Zeiger um 1 pt und sofort zurück, damit Teams/Slack den Mac
/// nicht als „abwesend“ sehen. Zweite und letzte Datei, die die Lint-Regel `keine_eingaben_im_helfer` ausnimmt.
///
/// Erste **zeitgesteuerte** Eingabe des Hilfsprogramms – deshalb eng: Der Befehl `nudge` trägt nichts; Richtung und
/// Weg stehen fest im Code; bewegt wird nur, wenn seit ≥ 4 Min. keine Eingabe war (misst das Hilfsprogramm selbst,
/// nicht Gnotchi), nie bei gesperrtem Bildschirm, höchstens einmal je 60 s. Klickt nie, tippt nie.
@MainActor
enum NudgePointer {

    private static let log = Logger(subsystem: NotifyWire.helperBundleID, category: "wach")
    nonisolated static let minIdle: TimeInterval = 4 * 60
    nonisolated static let minInterval: TimeInterval = 60
    private static var last: Date?

    /// Reine Regel (getestet): bewegen?
    nonisolated static func shouldNudge(trusted: Bool, locked: Bool, idle: TimeInterval?, last: Date?, now: Date) -> Bool {
        guard trusted, !locked, let idle, idle >= minIdle else { return false }
        if let last, now.timeIntervalSince(last) < minInterval { return false }
        return true
    }

    static func nudge(trusted: Bool) {
        let now = Date()
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let idle = hidIdle()
        guard shouldNudge(trusted: trusted, locked: locked, idle: idle, last: last, now: now) else { return }
        guard let here = CGEvent(source: nil)?.location else { return log.error("Zeiger: Lage nicht lesbar") }
        let source = CGEventSource(stateID: .hidSystemState)
        let away = CGPoint(x: here.x + 1, y: here.y)
        guard let out = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: away, mouseButton: .left),
              let back = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: here, mouseButton: .left)
        else { return log.error("Zeiger: Ereignis nicht erzeugt") }
        out.post(tap: .cghidEventTap)
        back.post(tap: .cghidEventTap)
        last = now
        // Setzt `HIDIdleTime` zurück – gemessen 06.11. von außen (Rücksprung zur selben Zehntelsekunde wie die Bewegung).
        log.notice("Zeiger bewegt (Leerlauf vorher \(Int(idle ?? -1), privacy: .public) s)")
    }

    /// Sekunden seit der letzten Eingabe (IOHIDSystem, ohne Freigabe lesbar).
    private static func hidIdle() -> TimeInterval? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard let v = IORegistryEntryCreateCFProperty(svc, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return nil }
        return v.doubleValue / 1e9
    }
}
