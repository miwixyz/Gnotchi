#if DEBUG
import AppKit
import CryptoKit
import SwiftUI

/// Zwischenablage für Fensterbilder der Bild-Testkopie (G45, ab 0.49.0): nur ERFUNDENE Einträge in einem Speicher im
/// Arbeitsspeicher mit Wegwerf-Schlüssel – kein Schlüsselbund, keine Verlaufsdatei, keine echte Zwischenablage
/// (eigene benannte Ablage, Einfügen nie ausgelöst). Damit bleibt die Regel „nie echte Inhalte im Bild“ gewahrt.
@MainActor
enum DebugClipboardDemo {
    /// Fenster-Kennungen für `snapshot`: Herunterklappen aus der Notch bzw. große Ansicht am rechten Rand, je mit
    /// aktivem Filter (Safari · 7 Tage). `…-ohne` = ohne Filter (Knopf leer).
    nonisolated static let windows: Set<String> = ["zwischenablage-notch", "zwischenablage-rand", "zwischenablage-ohne"]

    private static var panels: [String: NSPanel] = [:]
    private static var link: ClipboardLink?

    static func show(_ id: String, activity: ActivityModel) throws {
        let link = try link ?? makeLink(activity: activity)
        Self.link = link
        let edge: Preferences.PanelEdge = id == "zwischenablage-rand" ? .right : .notch
        let state = ClipboardPanelState(link: link, edge: edge) {}
        if id != "zwischenablage-ohne" { state.filter = ClipFilter(period: .week, sourceBundleID: "com.apple.Safari") }
        let size = edge == .notch ? ClipboardPanelController.dropSize : CGSize(width: ClipboardPanelController.sideWidth, height: 620)
        let panel = panels[id] ?? NSPanel(contentRect: CGRect(origin: .zero, size: size),
                                          styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier(id)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(state: state).frame(width: size.width, height: size.height))
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            let x = edge == .notch ? area.midX - size.width / 2 : area.maxX - size.width - 8
            panel.setFrame(CGRect(x: x, y: area.maxY - size.height - 8, width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        panels[id] = panel
    }

    private static func makeLink(activity: ActivityModel) throws -> ClipboardLink {
        // Fester Name: eine Wegwerf-Datei statt einer neuen je Lauf; vorher leeren.
        let suite = "gnotchi-bild-demo"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
        let link = ClipboardLink(activity: activity, prefs: Preferences(defaults: defaults),
                                 pasteboard: NSPasteboard(name: .init("dev.mwlr.gnotchi.bild.demo")))
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        func text(_ s: String) -> ClipPayload {
            ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data(s.utf8))], plain: s)
        }
        let now = Date()
        struct Sample { let text: String; let kind: ClipKind; let source: String; let age: TimeInterval }
        let samples = [
            Sample(text: "Erfundene Notiz: Plakat für den Filmabend bestellen, 20 Stück A1.", kind: .text,
                   source: "com.apple.Notes", age: 9 * 86_400),
            Sample(text: "https://example.com/alt/archiv", kind: .link, source: "com.apple.Safari", age: 12 * 86_400),
            Sample(text: "#E50914", kind: .text, source: "com.apple.Notes", age: 3 * 86_400),
            Sample(text: "Erfundene Antwort an das Kino: Termin passt am Donnerstag.", kind: .text,
                   source: "com.apple.mail", age: 2 * 86_400),
            Sample(text: "https://example.com/kino/programm?woche=48", kind: .link, source: "com.apple.Safari", age: 86_400),
            Sample(text: "https://example.com/kino/trailer", kind: .link, source: "com.apple.Safari", age: 3_600),
            Sample(text: "https://example.com/kino/tickets", kind: .link, source: "com.apple.Safari", age: 60),
        ]
        for sample in samples {
            try store.add(text(sample.text), kind: sample.kind, source: sample.source, now: now.addingTimeInterval(-sample.age))
        }
        link.attachForRendering(store)
        return link
    }
}
#endif
