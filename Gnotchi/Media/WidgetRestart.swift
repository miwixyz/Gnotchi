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
    }

    /// Welche Prozesse sind alte Widget-Prozesse? Reine Logik, getestet.
    static func stale(_ procs: [Proc], widgetPath: String, uid: uid_t, ownPid: pid_t, ownStart: TimeInterval) -> [pid_t] {
        procs.filter { $0.pid != ownPid && $0.pid > 1 && $0.uid == uid && $0.path == widgetPath && $0.start < ownStart }
            .map(\.pid)
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
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return nil }
        let start = TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000
        return Proc(pid: pid, path: URL(fileURLWithPath: String(cString: buf)).resolvingSymlinksInPath().path,
                    uid: bsd.pbi_uid, start: start)
    }
}
