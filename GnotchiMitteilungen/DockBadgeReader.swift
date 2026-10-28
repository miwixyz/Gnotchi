import AppKit
import ApplicationServices
import OSLog

/// Ungelesen-Zahlen aus den Dock-Abzeichen (0.9.0, SECURE-DESIGN G28 erweitert, G33). **Nur lesen:** Prozess
/// `com.apple.dock`, je `AXApplicationDockItem` nur `AXURL` (→ Kennung der App) und `AXStatusLabel` (Abzeichen).
/// Kein Schreiben, keine Aktion, kein `AXPress` am Dock.
///
/// Gemessen 22.10. (macOS 27.0.1): `AXStatusLabel` „5“ bei Mail, `AXURL` als `NSURL` auf das App-Paket.
/// Abzeichen-Texte setzt jede App selbst → nur die Zahl verlässt diesen Teil (`NotifyWire.badgeCount`).
@MainActor
final class DockBadgeReader {

    private static let log = Logger(subsystem: NotifyWire.helperBundleID, category: "dock")
    private static let dockBundleID = "com.apple.dock"
    private static let interval: TimeInterval = 5
    private static let maxNodes = 300

    /// Nur diese Apps (G29-Filter). Leer → nichts lesen.
    var apps: Set<String> = [] {
        didSet { if apps != oldValue { last = nil; read() } }
    }
    var onChange: ([NotifyWire.Badge]) -> Void = { _ in }

    private var timer: Timer?
    private var last: [NotifyWire.Badge]?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.read() }
        }
        timer?.tolerance = Self.interval / 10   // Weckzeiten bündeln (Akku, BAMA-Check 28.10.)
        read()
    }

    /// Aus: einmal „nichts“ melden, damit Gnotchi keine alten Zahlen stehen lässt.
    func stop() {
        timer?.invalidate()
        timer = nil
        if last?.isEmpty == false { onChange([]) }
        last = nil
    }

    private func read() {
        guard timer != nil else { return }
        let badges = apps.isEmpty ? [] : Self.readDock(apps)
        guard badges != last else { return }
        last = badges
        onChange(badges)
        // Nur die Zahl der Apps – nie Kennungen oder Zahlen je App (G33).
        Self.log.notice("Ungelesen: \(badges.count, privacy: .public) App(s)")
    }

    private static func readDock(_ apps: Set<String>) -> [NotifyWire.Badge] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID).first else { return [] }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        var out: [NotifyWire.Badge] = []
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var nodes = 0
        while let (e, depth) = stack.popLast(), nodes < maxNodes {
            nodes += 1
            if AXQuery.string(e, kAXSubroleAttribute) == "AXApplicationDockItem" {
                if let bundle = bundleID(e), apps.contains(bundle), !out.contains(where: { $0.bundle == bundle }),
                   let count = NotifyWire.badgeCount(AXQuery.string(e, "AXStatusLabel")) {
                    out.append(NotifyWire.Badge(bundle: bundle, count: count))
                }
                continue
            }
            if depth < 4 { stack.append(contentsOf: AXQuery.children(e).map { ($0, depth + 1) }) }
        }
        return out.sorted { $0.bundle < $1.bundle }
    }

    /// `AXURL` des Dock-Symbols → Kennung aus dem App-Paket. Nur gültige Kennungen (Schema wie G29).
    private static func bundleID(_ item: AXUIElement) -> String? {
        guard let raw = AXQuery.value(item, kAXURLAttribute) else { return nil }
        let url = (raw as? URL) ?? (raw as? NSURL).map { $0 as URL }
        guard let url, url.isFileURL, let id = Bundle(url: url)?.bundleIdentifier, NotifyWire.isValidBundleID(id) else {
            return nil
        }
        return id
    }
}
