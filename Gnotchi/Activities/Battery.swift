import Foundation
import IOKit.ps

/// Batterie in der Ruhe-Insel (0.28.0): Prozent und Ladezustand der eingebauten Batterie. Quelle sind die
/// Strom-Quellen von macOS (`IOPSCopyPowerSourcesInfo`), **ohne Freigabe**; Änderungen kommen per
/// `IOPSNotificationCreateRunLoopSource` (kein Abfragen im Takt). Zubehör-Akkus (Bluetooth) fehlen bewusst: Sie bräuchten
/// die Bluetooth-Freigabe. Nur Arbeitsspeicher, nichts wird gespeichert.
struct BatteryStatus: Equatable, Sendable {
    let percent: Int
    let charging: Bool
    /// Am Netzteil (auch wenn voll und nicht mehr lädt).
    let pluggedIn: Bool

    /// SF-Symbol nach Füllstand; beim Laden mit Blitz.
    var symbol: String {
        let level = percent >= 88 ? "100" : (percent >= 63 ? "75" : (percent >= 38 ? "50" : (percent >= 13 ? "25" : "0")))
        return "battery.\(level)percent" + (charging ? ".bolt" : "")
    }

    var text: String { "\(percent) %" }

    /// Aus der Beschreibung einer Strom-Quelle. Nur die eingebaute Batterie, nur plausible Werte (sonst nil).
    nonisolated static func parse(_ d: [String: Any]) -> BatteryStatus? {
        guard d["Type"] as? String == "InternalBattery",
              let cur = (d["Current Capacity"] as? NSNumber)?.intValue,
              let max = (d["Max Capacity"] as? NSNumber)?.intValue, max > 0, cur >= 0 else { return nil }
        let percent = min(100, Int((Double(cur) / Double(max) * 100).rounded()))
        return BatteryStatus(percent: percent, charging: (d["Is Charging"] as? Bool) ?? false,
                             pluggedIn: (d["Power Source State"] as? String) == "AC Power")
    }

    /// Aktueller Stand; nil = keine eingebaute Batterie (Mac mini) oder nicht lesbar.
    nonisolated static func read() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let s = parse(d) { return s }
        }
        return nil
    }
}

/// Hält den Monitor nur schwach: Der C-Rückruf von IOKit bekommt einen Zeiger, der nach dem Freigeben des Monitors nicht
/// mehr auf ihn zeigen darf (Fund `/code-audit` 15.11.: `passUnretained(self)` wäre dann ein hängender Zeiger).
private final class WeakMonitor: @unchecked Sendable {
    weak var monitor: BatteryMonitor?
    init(_ m: BatteryMonitor) { monitor = m }
}

@MainActor
@Observable
final class BatteryMonitor {
    private(set) var status: BatteryStatus?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var box: Unmanaged<WeakMonitor>?

    /// Beobachten nur, solange die Ruhe-Insel die Batterie zeigen soll.
    func setActive(_ on: Bool) {
        if on, source == nil {
            let held = Unmanaged.passRetained(WeakMonitor(self))
            guard let s = IOPSNotificationCreateRunLoopSource({ ctx in
                guard let ctx else { return }
                let weak = Unmanaged<WeakMonitor>.fromOpaque(ctx).takeUnretainedValue()
                // Der Rückruf kommt über den Haupt-Run-Loop; trotzdem über den Haupt-Thread, nicht auf Annahme.
                DispatchQueue.main.async { MainActor.assumeIsolated { weak.monitor?.refresh() } }
            }, held.toOpaque())?.takeRetainedValue() else { held.release(); return }
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
            source = s
            box = held
            refresh()
        } else if !on, let s = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode)
            CFRunLoopSourceInvalidate(s)
            source = nil
            box?.release()
            box = nil
            status = nil
        }
    }

    func refresh() {
        let new = BatteryStatus.read()
        if new != status { status = new }
    }
}
