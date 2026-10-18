import AppKit

/// Zweite Notch-App erkennen (Michael, 18.10.: „sollen nicht vorkommen“). Reine Rechnungen, getestet
/// (IslandControllerTests); der Ablauf (Fensterliste lesen, zweite Prüfung) steht in IslandController.
/// Ausgelagert, weil der Controller sonst die Längengrenze von SwiftLint überschreitet.
extension IslandController {

    /// Was über eine fremde App bekannt ist – über `NSRunningApplication(processIdentifier:)` aus dem
    /// lokalen Bundle, nie aus der Fensterliste (dort nur die PID).
    struct OtherApp: Equatable {
        let name: String?
        let bundleID: String?
        let bundlePath: String?
        /// Menüleisten-App ohne Dock-Symbol (`activationPolicy == .accessory`) – so laufen Notch-Apps.
        let isAccessory: Bool
    }

    /// Notch bzw. Pille und der zugehörige Bildschirm, beide in CG-Koordinaten (Ursprung oben links).
    struct NotchTarget: Equatable {
        let notch: CGRect
        let screen: CGRect
    }

    /// Ab dieser Ebene liegt ein Fenster über der Menüleiste (kCGStatusWindowLevel). Gemessen 18.10.:
    /// eigenes Panel 27, Thaws Menüleisten-Fenster 23/24 (dürfen nicht zählen).
    nonisolated static let competingMinLayer = 25

    /// Zeichnet eine andere App über der Notch (bzw. Pille)? Ein fremdes Fenster zählt nur, wenn ALLES gilt
    /// (Review 18.10., gegen Fehlalarme): Ebene ≥ 25; oben bündig (± 2 pt); schmaler als 90 % des Bildschirms
    /// (kein Overlay); deckt waagrecht mindestens die halbe Notch-/Pillenbreite ab (kein Symbol-Fenster);
    /// die App ist eine Menüleisten-App (`.accessory`) und gehört nicht zu macOS (`com.apple.` bzw.
    /// `/System/`). Ergebnis: Name der App (lokalisiert, bereinigt; ohne Namen die Bundle-ID) – über
    /// NSRunningApplication(PID), nie ein Fenstertitel oder Name aus der Fensterliste (G10).
    nonisolated static func competingNotchApp(windows: [WindowInfo], ownPID: pid_t, targets: [NotchTarget],
                                              app: (pid_t) -> OtherApp?) -> String? {
        var checked: Set<pid_t> = []
        for w in windows where w.pid != ownPID && !checked.contains(w.pid)
            && targets.contains(where: { isNotchWindow(w, target: $0) }) {
            checked.insert(w.pid)
            guard let other = app(w.pid), other.isAccessory,
                  other.bundleID?.hasPrefix("com.apple.") != true,
                  other.bundlePath?.hasPrefix("/System/") != true else { continue }
            if let name = AppIcons.cleanName(other.name) ?? other.bundleID.flatMap({ BundleID.isValid($0) ? $0 : nil }) {
                return name
            }
        }
        return nil
    }

    /// Lage-Regeln für ein Notch-App-Fenster (CG-Koordinaten).
    nonisolated static func isNotchWindow(_ w: WindowInfo, target t: NotchTarget) -> Bool {
        let b = w.bounds
        let overlap = min(b.maxX, t.notch.maxX) - max(b.minX, t.notch.minX)
        return w.layer >= competingMinLayer && b.height > 0
            && abs(b.minY - t.screen.minY) <= 2
            && b.width < 0.9 * t.screen.width
            && overlap >= 0.5 * t.notch.width
    }

    /// Hinweis nur, wenn die zweite Prüfung dieselbe App findet.
    nonisolated static func confirmedCompetitor(first: String?, second: String?) -> String? {
        guard let first, first == second else { return nil }
        return first
    }

    nonisolated static func competingWarning(name: String) -> String {
        "„\(name)“ zeichnet ebenfalls über die Notch – bitte nur eine Notch-App verwenden."
    }
}
