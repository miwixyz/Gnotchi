// SYNTHETISCH – Mess-App ohne Daten: protokolliert nur Zähler, Typenanzahl, Längen und App-Kennungen.
// Mess-App 0.11.0 (24.10.): Fragt macOS 27 nach, wenn eine App NSPasteboard.general selbst liest?
// Protokolliert nur Zähler, Typenanzahl und Längen – nie Inhalte. Läuft 600 s, dann Ende.
import AppKit
import Carbon.HIToolbox

let logURL = URL(fileURLWithPath: "/tmp/clipboard-probe.log")
func log(_ s: String) {
    let line = "\(Date().timeIntervalSince1970) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

final class Probe: NSObject, NSApplicationDelegate {
    let pb = NSPasteboard.general
    var last = 0
    func applicationDidFinishLaunching(_ n: Notification) {
        last = pb.changeCount
        log("start changeCount=\(last) accessBehavior=\(pb.accessBehavior.rawValue) mode=\(CommandLine.arguments.dropFirst().joined(separator: ","))")
        // Messpunkt 2: Ctrl + Taste „<“ links neben Y – auf deutscher ISO-Tastatur Tastencode 50 (kVK_ANSI_Grave), gemessen 24.10.
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let hs = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            log("hotkey gedrueckt front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")"); return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        let rs = RegisterEventHotKey(UInt32(kVK_ANSI_Grave), UInt32(controlKey), EventHotKeyID(signature: 0x474E4F54, id: 1),
                                     GetApplicationEventTarget(), 0, &ref)
        log("hotkey handler=\(hs) register=\(rs)")
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in self.tick() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { log("ende"); NSApp.terminate(nil) }
    }
    func tick() {
        let c = pb.changeCount
        guard c != last else { return }
        last = c
        log("change \(c) accessBehavior=\(pb.accessBehavior.rawValue) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")
        let t0 = Date()
        let types = pb.types ?? []
        log("  types n=\(types.count) dt=\(String(format: "%.3f", Date().timeIntervalSince(t0)))")
        let t1 = Date()
        let s = pb.string(forType: .string)
        log("  string len=\(s.map { String($0.count) } ?? "nil") dt=\(String(format: "%.3f", Date().timeIntervalSince(t1))) accessBehavior=\(pb.accessBehavior.rawValue)")
    }
}
let app = NSApplication.shared
let d = Probe(); app.delegate = d
app.setActivationPolicy(.accessory)
app.run()
