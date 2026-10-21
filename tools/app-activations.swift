// SYNTHETISCH – Testwerkzeug, enthält keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
// Sichttest 0.4.0: zeichnet jeden App-Wechsel mit Uhrzeit auf („kommt Kalli nach dem Klick nach vorn?“). Besser als
// „was ist jetzt vorn“: Michael arbeitet parallel. Aufruf: swiftc -O tools/app-activations.swift -o /tmp/gnotchi-act && /tmp/gnotchi-act [sekunden=8]
import AppKit
setbuf(stdout, nil)
let secs = Double(CommandLine.arguments.dropFirst().first ?? "8") ?? 8
let t = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
    let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    print("\(Date().formatted(date: .omitted, time: .standard)) aktiv: \(a?.localizedName ?? "?")")
}
print("start, vorn: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
RunLoop.current.run(until: Date().addingTimeInterval(secs))
withExtendedLifetime(t) {}
