import AppKit
import Observation
import OSLog

/// Dateiablage (0.8.0, G32): verbindet Speicher, Ziehen-Erkennung und Aktionen mit der Insel. Läuft, solange
/// „Dateiablage in der Notch“ an ist. Nichts wird geöffnet oder ausgeführt; Entfernen löscht nie eine Datei.
/// Protokoll nur Zahlen.
@MainActor
@Observable
final class ShelfLink: NotchPart {

    @ObservationIgnored private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "ablage")

    @ObservationIgnored private let activity: ActivityModel
    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private let store: ShelfStore
    @ObservationIgnored private var watcher: DragWatcher?
    /// ZIP wird gerade gepackt.
    private(set) var busy = false

    init(activity: ActivityModel, prefs: Preferences, store: ShelfStore = ShelfStore()) {
        self.activity = activity
        self.prefs = prefs
        self.store = store
    }

    func start() {
        guard watcher == nil else { return }
        activity.shelf = self
        let w = DragWatcher { [weak self] dragging in self?.activity.fileDragActive = dragging }
        w.start()
        watcher = w
        prune()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        activity.fileDragActive = false
        activity.shelfActive = false
        activity.shelfItems = []
        activity.shelf = nil
    }

    // MARK: Inhalt

    func drop(_ urls: [URL]) {
        let n = store.add(urls)
        publish()
        Self.log.notice("\(n, privacy: .public) abgelegt")
        let full = store.items.count >= ShelfStore.maxItems
        // Protokoll 22.10.: „0 abgelegt“ hieß „lag schon drin“ – die Meldung sagte trotzdem „Nichts abgelegt“.
        let title = n > 0 ? "\(n) abgelegt" : (full ? "Ablage voll" : "Schon in der Ablage")
        activity.post(.init(symbol: "tray.and.arrow.down.fill", title: title,
                            subtitle: full ? "Höchstens \(ShelfStore.maxItems)" : "\(store.items.count) in der Ablage"))
    }

    func url(for item: ShelfStore.Item) -> URL? { store.resolve(item) }

    func urls() -> [URL] { store.items.compactMap(store.resolve) }

    func remove(_ item: ShelfStore.Item) {
        store.remove(item.id)
        publish()
    }

    func clear() {
        store.clear()
        publish()
    }

    func prune() {
        store.prune()
        publish()
    }

    /// Rausgezogen und angekommen → aus der Ablage (Schalter, ab Werk an).
    func draggedOut(_ item: ShelfStore.Item) {
        guard prefs.shelfRemoveOnDrag else { return }
        remove(item)
    }

    private func publish() {
        if activity.shelfItems != store.items { activity.shelfItems = store.items }
        if store.items.isEmpty { activity.shelfActive = false }
    }

    // MARK: Aktionen (macOS-Dienste, nichts öffnen)

    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let s = NSSharingService(named: .sendViaAirDrop), s.canPerform(withItems: urls) else { return }
        s.perform(withItems: urls)
    }

    /// Rechtsklick-Menü einer Kachel.
    func menu(for item: ShelfStore.Item, anchor: NSView) -> NSMenu? {
        guard let url = url(for: item) else { return nil }
        let m = NSMenu()
        m.addItem(ClosureMenuItem(title: "Im Finder zeigen") { [weak self] in self?.reveal([url]) })
        m.addItem(ClosureMenuItem(title: "Teilen …") {
            NSSharingServicePicker(items: [url]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        })
        m.addItem(ClosureMenuItem(title: "AirDrop") { [weak self] in self?.airDrop([url]) })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(title: "Aus der Ablage entfernen") { [weak self] in self?.remove(item) })
        return m
    }

    // MARK: ZIP (G32)

    /// Alle Einträge als ZIP nach Downloads, danach selbst in der Ablage. Mit Passwort: Abfrage (zweimal, ≥ 8 Zeichen).
    func zip(password: Bool) {
        let sources = urls()
        guard !sources.isEmpty, !busy else { return }
        var secret: String?
        if password {
            guard let p = Self.askPassword() else { return }
            secret = p
        }
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        busy = true
        let pw = secret
        Task.detached(priority: .userInitiated) {
            let result = Result { () throws(ShelfZip.Failure) -> ShelfZip.Result in
                try ShelfZip.create(sources, password: pw, directory: downloads)
            }
            await MainActor.run { [weak self] in self?.zipFinished(result, encrypted: pw != nil) }
        }
    }

    private func zipFinished(_ result: Result<ShelfZip.Result, ShelfZip.Failure>, encrypted: Bool) {
        busy = false
        switch result {
        case .success(let r):
            Self.log.notice("ZIP erstellt, \(r.files, privacy: .public) Dateien, \(r.skippedLinks, privacy: .public) Links übersprungen")
            store.add([r.url])
            publish()
            activity.post(.init(symbol: encrypted ? "lock.doc.fill" : "doc.zipper", title: r.url.lastPathComponent,
                                subtitle: encrypted ? "In Downloads · öffnen mit Keka/7-Zip" : "In Downloads"))
        case .failure(let f):
            Self.log.error("ZIP fehlgeschlagen (\(String(describing: f), privacy: .public))")
            let text: String = switch f {
            case .tooMany: "Zu viele Dateien (max. \(ShelfZip.maxFiles))"
            case .tooLarge: "Zu groß (max. 4 GB)"
            case .empty: "Nichts zu packen"
            case .read, .write: "Konnte nicht packen"
            }
            activity.post(.init(symbol: "exclamationmark.triangle.fill", title: "ZIP", subtitle: text))
        }
    }

    /// Passwort zweimal; nur im Speicher, nie gespeichert oder protokolliert (G32).
    private static func askPassword() -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "ZIP mit Passwort"
        alert.informativeText = "Verschlüsselt mit AES-256. Öffnet sich mit Keka, The Unarchiver oder 7-Zip – "
            + "nicht per Doppelklick auf dem Mac. Mindestens \(ShelfZip.minPassword) Zeichen."
        let first = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        first.placeholderString = "Passwort"
        let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        second.placeholderString = "Wiederholen"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        box.addSubview(first)
        box.addSubview(second)
        alert.accessoryView = box
        alert.addButton(withTitle: "Packen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = first
        while alert.runModal() == .alertFirstButtonReturn {
            let p = first.stringValue
            if p.count >= ShelfZip.minPassword && p == second.stringValue { return p }
            alert.informativeText = p.count < ShelfZip.minPassword
                ? "Mindestens \(ShelfZip.minPassword) Zeichen." : "Die Passwörter stimmen nicht überein."
        }
        return nil
    }
}
