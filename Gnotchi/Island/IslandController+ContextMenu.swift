import AppKit

/// Rechtsklick/Ctrl-Klick auf die Insel (Michael, 18.10.): dieselben Fenster wie das Menüleisten-Menü.
/// Reine Teile getestet (IslandContextMenuTests); der Ablauf steht in IslandController.showContextMenu.
extension IslandController {

    struct ContextMenuItem: Equatable {
        let title: String
        let windowID: String
    }

    nonisolated static let contextMenuItems = [
        ContextMenuItem(title: "Einstellungen …", windowID: AppModel.WindowID.settings),
        ContextMenuItem(title: "Hilfe …", windowID: AppModel.WindowID.help),
    ]

    /// Rechtsklick, oder Linksklick mit gedrückter Ctrl-Taste (macOS-Konvention).
    nonisolated static func isContextClick(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseDown || (type == .leftMouseDown && modifiers.contains(.control))
    }
}

/// Menüeintrag mit Closure statt Ziel/Aktion-Paar.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("nicht aus einem Archiv") }

    @objc private func run() { handler() }
}
