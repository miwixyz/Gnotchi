// responsible-pid.swift — welcher Prozess ist für eine PID „verantwortlich“ (TCC-Zuordnung)?
//
// Sichttest G2 (docs/SECURE-DESIGN.md, 2026-10-18): Erbt der von Gnotchi gestartete
// Perl-Adapter Gnotchis Datenschutz-Freigaben? macOS rechnet TCC-Anfragen dem
// „verantwortlichen“ Prozess zu. Diese Abfrage liest ihn nur aus, sie ändert nichts.
//
// Aufruf: swift tools/responsible-pid.swift <pid> [<pid> …]
// Nur ein Messwerkzeug, nicht Teil der App (liegt außerhalb von Gnotchi/, wird nicht gelintet).

import Darwin
import Foundation

typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
    print("✗ responsibility_get_pid_responsible_for_pid nicht gefunden")
    exit(2)
}
let responsible = unsafeBitCast(sym, to: ResponsibleFn.self)

func path(of pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "?"
}

for arg in CommandLine.arguments.dropFirst() {
    guard let pid = pid_t(arg) else { print("✗ keine PID: \(arg)"); continue }
    let r = responsible(pid)
    print("pid \(pid) (\(path(of: pid))) → verantwortlich: \(r) (\(r > 0 ? path(of: r) : "Fehler"))")
}
