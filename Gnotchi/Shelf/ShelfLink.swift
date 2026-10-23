import AppKit
import Observation
import OSLog

/// Ein Ablegen mit Dateiversprechen (0.9.1): zählt erwartete Dateien, sammelt geprüfte Kopien; endet genau einmal
/// (alles da oder Zeitlimit). Was nicht ankam, zählt als gescheitert.
@MainActor
final class PromiseBatch {
    private var copies: [URL] = []
    private var failed: Int
    private var expected = 0
    private var done: (@MainActor ([URL], Int) -> Void)?
    var onFinish: (() -> Void)?

    init(failed: Int = 0, done: @escaping @MainActor ([URL], Int) -> Void) {
        self.failed = failed
        self.done = done
    }

    func expect(_ n: Int) { expected += n }
    func fail() { failed += 1 }

    /// Eine Datei kam an (nil = Fehler oder Prüfung nicht bestanden).
    func arrived(_ url: URL?) {
        guard done != nil else { return }
        if let url { copies.append(url) } else { failed += 1 }
        expected -= 1
        check()
    }

    func check() { if expected <= 0 { finish() } }

    func finish() {
        guard let d = done else { return }
        done = nil
        failed += max(0, expected)
        onFinish?()
        d(copies, failed)
    }
}

/// Dateiablage (0.8.0, G32): verbindet Speicher, Ziehen-Erkennung und Aktionen mit der Insel. Läuft, solange
/// „Dateiablage in der Notch“ an ist. Nichts wird geöffnet oder ausgeführt; Entfernen löscht nur eigene Kopien
/// aus Dateiversprechen (0.9.1), nie die Datei hinter einem Verweis. Protokoll nur Zahlen.
@MainActor
@Observable
final class ShelfLink: NotchPart {

    @ObservationIgnored private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "ablage")

    @ObservationIgnored private let activity: ActivityModel
    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private let store: ShelfStore
    @ObservationIgnored private var watcher: DragWatcher?
    @ObservationIgnored private let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()
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

    /// Loslassen auf der Insel (0.9.1): liest die Zieh-Zwischenablage. Element mit Dateiversprechen (Fotos) → die App
    /// schreibt eine Kopie in einen eigenen Ordner (ihr Datei-Verweis zeigt nur auf eine Vorschau, gemessen 23.10.);
    /// sonst Datei-Verweis wie bisher.
    func dropDragged(_ info: NSDraggingInfo) {
        let pb = info.draggingPasteboard
        let items = pb.pasteboardItems ?? []
        // 0.9.2: alte Versprechen (Chromium/Gmail, Outlook) nur über `NSDraggingInfo` – `NSFilePromiseReceiver` wirft dort.
        if items.contains(where: { Self.isLegacyPromise($0.types) }) {
            let urls = items.filter { !Self.isPromise($0.types) }
                .compactMap { $0.string(forType: .fileURL).flatMap(URL.init(string:)).flatMap { ($0 as NSURL).filePathURL } }
            return receiveLegacy(info, urls: urls)
        }
        let objects = pb.readObjects(forClasses: [NSFilePromiseReceiver.self, NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) ?? []
        // Finder liefert oft Referenz-URLs (`/.file/id=…`) → Pfad-URL.
        let urls = objects.compactMap { ($0 as? NSURL)?.filePathURL }
        let free = max(0, ShelfStore.maxItems - store.items.count - urls.count)
        let promises = objects.compactMap { $0 as? NSFilePromiseReceiver }
        guard !promises.isEmpty else { return drop(urls) }
        receive(Array(promises.prefix(free)), skipped: max(0, promises.count - free)) { [weak self] copies, failed in
            self?.drop(urls + copies, failed: failed)
        }
    }

    /// `failed`: Versprechen, die nichts Brauchbares geliefert haben (nur Zahl ins Protokoll).
    func drop(_ urls: [URL], failed: Int = 0) {
        let already = urls.filter(store.contains).count
        let n = store.add(urls)
        publish()
        store.cleanCopies()
        Self.log.notice("\(n, privacy: .public) abgelegt, \(failed, privacy: .public) Versprechen gescheitert")
        let full = store.items.count >= ShelfStore.maxItems
        let title = Self.dropTitle(added: n, offered: urls.count, already: already, failed: failed, full: full)
        activity.post(.init(symbol: n > 0 ? "tray.and.arrow.down.fill" : "exclamationmark.triangle.fill", title: title,
                            subtitle: full ? "Höchstens \(ShelfStore.maxItems)" : "\(store.items.count) in der Ablage"))
    }

    /// Bildschirmfotos (0.10.0, G36) – gleicher Weg wie Ziehen, eigene Meldung. Ablage voll → sichtbar, nicht still.
    func addScreenshots(_ urls: [URL]) {
        let n = store.add(urls)
        publish()
        Self.log.notice("\(n, privacy: .public) Bildschirmfotos abgelegt (\(urls.count, privacy: .public) gemeldet)")
        if n > 0 {
            activity.post(.init(symbol: "camera.viewfinder", title: n == 1 ? "Bildschirmfoto abgelegt" : "\(n) Bildschirmfotos abgelegt",
                                subtitle: "\(store.items.count) in der Ablage"))
        } else if store.items.count >= ShelfStore.maxItems {
            activity.post(.init(symbol: "exclamationmark.triangle.fill", title: "Ablage voll",
                                subtitle: "Bildschirmfoto nicht abgelegt"))
        }
    }

    /// Protokoll 22.10.: „0 abgelegt“ hieß „lag schon drin“. 23.10.: ein verworfenes Foto meldete ebenfalls
    /// „Schon in der Ablage“ – das stimmt nur, wenn wirklich alles schon drin war.
    nonisolated static func dropTitle(added: Int, offered: Int, already: Int, failed: Int, full: Bool) -> String {
        if added > 0 { return "\(added) abgelegt" }
        if full { return "Ablage voll" }
        if offered > 0 && already == offered && failed == 0 { return "Schon in der Ablage" }
        return "Nicht abgelegt"
    }

    // MARK: Alte Dateiversprechen (0.9.2)

    nonisolated static let promiseMetaData = NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")
    nonisolated static let promiseTypes: [NSPasteboard.PasteboardType] =
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        + [NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")]

    nonisolated static func isPromise(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(where: promiseTypes.contains)
    }

    /// Versprechen ohne `NSFilePromiseItemMetaData` – so bieten Chromium (Gmail) und Outlook Anhänge an (gemessen 23.10.).
    /// Fotos trägt die Metadaten und bleibt beim `NSFilePromiseReceiver`.
    nonisolated static func isLegacyPromise(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        isPromise(types) && !types.contains(promiseMetaData)
    }

    /// Alte Form: AppKit nennt der liefernden App den Zielordner, die App schreibt die Datei(en) selbst – Chromium lädt
    /// erst herunter. Abgelegt wird, sobald alle genannten Dateien im eigenen UUID-Ordner liegen (≤ 120 s); eine noch
    /// wachsende Download-Datei gilt dann schon als da (hingenommen, G32).
    private func receiveLegacy(_ info: NSDraggingInfo, urls: [URL]) {
        guard store.items.count + urls.count < ShelfStore.maxItems, let folder = store.newCopyFolder() else {
            return drop(urls, failed: 1)
        }
        // Gemessen 23.10.: Outlook und Gmail in Helium (4 von 4) liefern über diesen Weg. Ein früherer Gmail-Versuch
        // nannte nichts (Ursache offen) → dann sofort „Nicht abgelegt“, Zahl im Protokoll.
        let expected = info.namesOfPromisedFilesDropped(atDestination: folder)?.count ?? 0
        Self.log.notice("Altes Versprechen: AppKit-Weg nennt \(expected, privacy: .public) Datei(en)")
        let store = store
        guard expected > 0 else {
            store.release(folder)
            return drop(urls, failed: 1)
        }
        // Review 23.10.: nie mehr annehmen als Plätze frei sind; Überzähliges sofort löschen (sonst unsichtbare Kopien).
        let wanted = min(expected, ShelfStore.maxItems - store.items.count - urls.count)
        Task { @MainActor [weak self] in
            var copies: [URL] = []
            for _ in 0..<480 {
                guard let found = Self.arrivedCopies(in: folder, store: store) else { break }   // Flut → abbrechen
                copies = found
                if copies.count >= wanted { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            store.release(folder)
            let taken = Array(copies.prefix(wanted))
            for extra in copies.dropFirst(wanted) { try? FileManager.default.removeItem(at: extra) }
            // Ablage inzwischen ausgeschaltet → nichts mehr ablegen (Review 23.10.).
            guard let self, self.watcher != nil else { return store.cleanCopies() }
            self.drop(urls + taken, failed: max(0, expected - taken.count))
        }
    }

    /// Sichtbare Dateien direkt im Ordner, die die Prüfung bestehen (kein Link, uns gehörend). Versteckte
    /// Zwischendateien (`.…`) zählen nicht. nil = mehr als `2 × maxItems` Einträge (Flut, Review 23.10.).
    static func arrivedCopies(in folder: URL, store: ShelfStore) -> [URL]? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard names.count <= 2 * ShelfStore.maxItems else { return nil }
        return names.filter { !$0.hasPrefix(".") }.sorted()
            .map { folder.appendingPathComponent($0) }.filter { store.isValidCopy($0, in: folder) }
    }

    /// Rückruf für `receivePromisedFiles` – läuft auf `promiseQueue`, nie auf dem Hauptthread. Außerhalb des
    /// Hauptthread-Kontexts gebaut: als Abschluss in `receive` erbte er die Hauptthread-Bindung, Swift 6 prüfte sie
    /// zur Laufzeit und brach ab (Absturz im Sichttest 23.10., `_dispatch_assert_queue_fail`).
    nonisolated static func promiseReader(batch: PromiseBatch, store: ShelfStore,
                                          folder: URL) -> @Sendable (URL, (any Error)?) -> Void {
        { url, error in
            let ok = error == nil
            Task { @MainActor in batch.arrived(ok && store.isValidCopy(url, in: folder) ? url : nil) }
        }
    }

    /// Versprechen einlösen: je Versprechen ein frischer UUID-Ordner, nur geprüfte Kopien zählen, Zeitlimit 120 s.
    private func receive(_ promises: [NSFilePromiseReceiver], skipped: Int,
                         then done: @escaping @MainActor ([URL], Int) -> Void) {
        let batch = PromiseBatch(failed: skipped, done: done)
        let store = store
        var folders: [URL] = []
        for p in promises {
            guard let folder = store.newCopyFolder() else { batch.fail(); continue }
            folders.append(folder)
            batch.expect(max(p.fileNames.count, 1))
            p.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: promiseQueue,
                                   reader: Self.promiseReader(batch: batch, store: store, folder: folder))
        }
        let used = folders
        batch.onFinish = { for f in used { store.release(f) } }
        batch.check()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            batch.finish()
        }
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
        store.removeAfterDrag(item.id)
        publish()
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
