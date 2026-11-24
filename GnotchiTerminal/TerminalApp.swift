import AppKit
import OSLog

/// „Gnotchi Terminal“ (G65): eigenes Programm mit eigener Kennung und ohne Berechtigungen. Gnotchi startet es nur auf Knopfdruck
/// bei eingeschaltetem Schalter. Kein Socket zu Gnotchi, keine Meldung zurück: Es gibt nichts zu prüfen und nichts zu fälschen.
@MainActor
final class TerminalAppDelegate: NSObject, NSApplicationDelegate {

    private var controllers: [TerminalWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        newWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controllers.contains(where: \.isBusy) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "In einem Fenster läuft noch ein Programm."
        alert.informativeText = "Beenden schließt alle Fenster und beendet es."
        alert.addButton(withTitle: "Abbrechen")
        alert.addButton(withTitle: "Beenden")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.forEach { $0.hangUpShell() }
    }

    // MARK: Aktionen

    @objc func newWindow(_ sender: Any?) {
        let controller = TerminalWindowController()
        controller.onClose = { [weak self] c in self?.controllers.removeAll { $0 === c } }
        controllers.append(controller)
        controller.start()
        NSApp.activate()
    }

    private var frontController: TerminalWindowController? {
        controllers.first { $0.window === NSApp.keyWindow } ?? controllers.last
    }

    @objc func fontBigger(_ sender: Any?) { frontController?.changeFontSize(by: 1) }
    @objc func fontSmaller(_ sender: Any?) { frontController?.changeFontSize(by: -1) }
    @objc func fontReset(_ sender: Any?) { frontController?.resetFontSize() }

    // MARK: Menü

    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "", tag: Int = 0,
                  _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
            i.tag = tag
            return i
        }
        add("Gnotchi Terminal", [
            item("Über Gnotchi Terminal", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Gnotchi Terminal ausblenden", #selector(NSApplication.hide(_:)), "h"),
            item("Andere ausblenden", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item("Gnotchi Terminal beenden", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("Ablage", [
            item("Neues Fenster", #selector(newWindow(_:)), "n"),
            item("Fenster schließen", #selector(NSWindow.performClose(_:)), "w"),
        ])
        add("Bearbeiten", [
            item("Kopieren", Selector(("copy:")), "c"),
            item("Einsetzen", Selector(("paste:")), "v"),
            item("Alles auswählen", #selector(NSResponder.selectAll(_:)), "a"),
            .separator(),
            item("Suchen …", #selector(NSResponder.performTextFinderAction(_:)), "f",
                 tag: NSTextFinder.Action.showFindInterface.rawValue),
        ])
        add("Darstellung", [
            item("Größere Schrift", #selector(fontBigger(_:)), "+"),
            item("Kleinere Schrift", #selector(fontSmaller(_:)), "-"),
            item("Normale Schriftgröße", #selector(fontReset(_:)), "0"),
        ])
        add("Fenster", [
            item("Im Dock ablegen", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoomen", #selector(NSWindow.performZoom(_:))),
        ])
        return main
    }
}
