import AppKit

extension IslandController {

    /// Ausgabe-Knopf (0.2.0): Geräteliste beim Öffnen frisch gelesen, aktuelles Gerät mit Häkchen.
    /// Auswahl setzt das Standard-Ausgabegerät von macOS (OutputDevices.select prüft erneut).
    func showOutputMenu(displayID: CGDirectDisplayID) {
        let devices = OutputDevices.ordered(OutputDevices.list())
        let current = OutputDevices.current()
        let menu = NSMenu()
        for d in devices {
            let item = ClosureMenuItem(title: d.name) { OutputDevices.select(d.id) }
            item.state = d.id == current ? .on : .off
            item.image = NSImage(systemSymbolName: d.kind.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        if devices.isEmpty {
            let none = NSMenuItem(title: "Kein Ausgabegerät gefunden", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        runMenu(displayID: displayID) { _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    }
}
