import Darwin
import Foundation
import OSLog
import WidgetKit

/// Nach einem Update den alten Widget-Prozess beenden (0.26.1).
///
/// Gemessen 13.11. nach dem Sparkle-Update auf 0.26.0: Der Widget-Prozess aus der alten Fassung lief weiter, macOS zeigte
/// nur den grauen Platzhalter. Erst als der Prozess beendet war, startete macOS das Widget aus der neuen Fassung und es
/// zeigte wieder Musik. Deshalb beim ersten Start einer neuen Version: Widget-Prozesse **dieses** Bundles, die vor
/// Gnotchi gestartet sind, mit SIGTERM beenden. macOS startet das Widget beim nächsten Neuzeichnen selbst neu.
///
/// Sicherheit: nur exakt der Pfad der eigenen Widget-Programmdatei, nur Prozesse desselben Nutzers, nur einmal je
/// Version. Kein Fremdprozess, keine Eingabe von außen.
enum WidgetRestart {
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "widget")
    static let seenKey = "widgetRestartSeenVersion"

    struct Proc: Equatable {
        let pid: pid_t
        let path: String
        let uid: uid_t
        /// Startzeit, Sekunden seit 1970.
        let start: TimeInterval
        /// Prozessname laut Kernel. Bleibt lesbar, wenn der Pfad es nicht ist (Programmdatei gelöscht).
        var name: String = ""
    }

    /// Welche Prozesse sind alte Widget-Prozesse? Reine Logik, getestet.
    static func stale(_ procs: [Proc], widgetPath: String, uid: uid_t, ownPid: pid_t, ownStart: TimeInterval) -> [pid_t] {
        procs.filter {
            $0.pid != ownPid && $0.pid > 1 && $0.uid == uid && $0.start < ownStart
                && ($0.path == widgetPath || isUpdateCopy($0.path) || isOrphanWidget($0))
        }
        .map(\.pid)
    }

    /// Das Widget, dessen Programmdatei nach dem Update gelöscht ist (gemessen 16.11., 0.30.0 → 0.31.0): `proc_pidpath` liefert dann
    /// nichts, der Pfadvergleich sieht den Prozess nie. Erkennbar am Kernel-Namen. Nur mit leerem Pfad, damit kein fremdes Programm
    /// gleichen Namens mit lesbarem Pfad getroffen wird.
    static func isOrphanWidget(_ p: Proc) -> Bool { p.path.isEmpty && p.name == "GnotchiWidget" }

    /// Das Widget aus dem Zwischenordner von Sparkle (0.30.1, gemessen 16.11.): Nach dem Update vom 13.11. lief der Widget-Prozess
    /// weiter aus `…/org.sparkle-project.Sparkle/Installation/…/Gnotchi.app`, nicht aus `/Applications`; der Pfadvergleich fand
    /// „0 alte Prozesse“ und das Widget zeigte keine Musik. Nur dieser genaue Ordner und genau diese Programmdatei.
    static func isUpdateCopy(_ path: String) -> Bool {
        path.contains("/org.sparkle-project.Sparkle/Installation/")
            && path.hasSuffix("/Gnotchi.app/Contents/PlugIns/GnotchiWidget.appex/Contents/MacOS/GnotchiWidget")
    }

    /// Einmal je neuer Version beim Start aufrufen.
    @MainActor
    static func afterUpdate(defaults: UserDefaults = .standard) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard defaults.string(forKey: seenKey) != version else { return }
        defaults.set(version, forKey: seenKey)
        guard let widget = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("GnotchiWidget.appex/Contents/MacOS/GnotchiWidget").resolvingSymlinksInPath().path,
            let own = info(getpid()) else { return }
        let pids = stale(allProcs(), widgetPath: widget, uid: getuid(), ownPid: getpid(), ownStart: own.start)
        for pid in pids { kill(pid, SIGTERM) }
        log.notice("Neue Version \(version, privacy: .public): \(pids.count, privacy: .public) alte(r) Widget-Prozess(e) beendet")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func allProcs() -> [Proc] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        guard n > 0 else { return [] }
        return pids.prefix(Int(n)).compactMap(info)
    }

    static func info(_ pid: pid_t) -> Proc? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let hasPath = proc_pidpath(pid, &buf, UInt32(buf.count)) > 0
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return nil }
        let start = TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000
        let name = withUnsafeBytes(of: &bsd.pbi_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        let path = hasPath ? URL(fileURLWithPath: String(cString: buf)).resolvingSymlinksInPath().path : ""
        return Proc(pid: pid, path: path, uid: bsd.pbi_uid, start: start, name: name)
    }
}
