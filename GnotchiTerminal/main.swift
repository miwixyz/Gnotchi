import AppKit

// „Gnotchi Terminal“ (docs/SECURE-DESIGN.md G65). Ein normales Programm mit Dock-Symbol und Menü, solange ein Fenster offen ist.
let app = NSApplication.shared
let delegate = TerminalAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
