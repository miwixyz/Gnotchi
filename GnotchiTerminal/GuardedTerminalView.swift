import AppKit

/// Terminalansicht mit den Sicherheitsvorgaben aus G65. SwiftTerms Standard erlaubt einem Programm im Terminal,
/// die Zwischenablage zu **lesen** und zu **schreiben** (OSC 52). Beides gibt es hier nicht: Ein Programm (oder ein
/// `cat` auf eine fremde Datei) darf weder Kopiertes mitlesen noch die Zwischenablage ändern. Normales Kopieren und
/// Einsetzen per ⌘C/⌘V bleibt. Die Kitty-Zwischenablage meldet sich über `processDelegate` ohne Fähigkeiten (kein Delegat-Code).
final class GuardedTerminalView: LocalProcessTerminalView {

    override func clipboardCopy(source: TerminalView, content: Data) {
        // OSC 52 schreiben: nie.
    }

    override func clipboardRead(source: TerminalView) -> Data? {
        // OSC 52 lesen: nie.
        nil
    }

    /// Schriftgröße in Punkt (geklemmt auf `TerminalRules.minFontSize … maxFontSize`).
    func applyFontSize(_ size: CGFloat) {
        font = NSFont.monospacedSystemFont(ofSize: TerminalRules.clampedFontSize(size), weight: .regular)
    }

    var currentFontSize: CGFloat { font.pointSize }
}
