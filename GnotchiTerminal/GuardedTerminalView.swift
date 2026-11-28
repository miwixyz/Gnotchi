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

    // MARK: Ablegen (0.48)

    /// Nur Dateien und Ordner (Finder), kein freier Text: Abgelegter Text aus Browsern ist fremd und brächte nichts.
    func enableFileDrop() {
        registerForDraggedTypes([.fileURL])
    }

    private func droppedText(_ info: any NSDraggingInfo) -> String? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return TerminalRules.dropText(paths: urls.map(\.path))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedText(sender) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedText(sender) == nil ? [] : .copy
    }

    /// Pfad wie beim Einsetzen (⌘V) eingeben: In Shells mit Klammermodus (zsh) löst das nie einen Befehl aus.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let text = droppedText(sender) else { return false }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        insertText(text, replacementRange: NSRange(location: 0, length: 0), isPaste: true)
        return true
    }

    /// Schriftgröße in Punkt (geklemmt auf `TerminalRules.minFontSize … maxFontSize`).
    func applyFontSize(_ size: CGFloat) {
        font = NSFont.monospacedSystemFont(ofSize: TerminalRules.clampedFontSize(size), weight: .regular)
    }

    var currentFontSize: CGFloat { font.pointSize }
}
