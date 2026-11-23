import AppKit
import Foundation

/// Abbruch-Schalter für den Hintergrundlauf von „Umwandeln“.
final class ShelfCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Umwandeln (0.43.0, G63): Bild verkleinern, Bildformat ändern, zu einem PDF zusammenfügen. Die Umwandlung selbst steht in
/// `ShelfConvert`; hier nur Auswahl der Quellen, Hintergrundlauf, Abbruch und die Meldung.
extension ShelfLink {

    func cancelConvert() { convertCancel.set() }

    /// Auswahl bzw. alle (oder die übergebenen Einträge) umwandeln; Ergebnis nach Downloads, danach auch in der Ablage.
    func convert(_ kind: ShelfConvert.Kind, items: [ShelfStore.Item]? = nil) {
        guard !busy else { return }
        let all = (items ?? actionItems).compactMap(url(for:))
        let sources = kind == .pdf ? all.filter(ShelfConvert.isConvertible) : all.filter(ShelfConvert.isImage)
        guard !sources.isEmpty else {
            return activity.post(.init(symbol: "exclamationmark.triangle.fill", title: "Umwandeln",
                                       subtitle: kind == .pdf ? "Keine Bilder oder PDFs" : "Keine Bilder"))
        }
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        busy = true
        converting = true
        let flag = ShelfCancelFlag()
        convertCancel = flag
        let ctx = ShelfConvert.Context(directory: downloads, stripLocation: prefs.shelfStripLocation, isCancelled: { flag.isSet })
        Task.detached(priority: .userInitiated) {
            let outcome = ShelfConvert.run(kind, sources: sources, in: ctx)
            await MainActor.run { [weak self] in self?.convertFinished(outcome, total: sources.count) }
        }
    }

    private func convertFinished(_ o: ShelfConvert.Outcome, total: Int) {
        busy = false
        converting = false
        // Protokoll nur Zahlen (G63).
        Self.log.notice("Umwandeln: \(o.created.count, privacy: .public) erstellt, \(o.failed.count, privacy: .public) fehlgeschlagen, abgebrochen \(o.cancelled, privacy: .public)")
        if !o.created.isEmpty {
            store.add(o.created)
            publish()
        }
        let title = o.cancelled ? "Abgebrochen" : (o.created.isEmpty ? "Nicht umgewandelt" : "\(o.created.count) umgewandelt")
        var subtitle = "In Downloads"
        if let first = o.failed.first {
            subtitle = o.failed.count == 1 ? "\(first.name): \(first.reason)" : "\(o.failed.count) fehlgeschlagen, z. B. \(first.reason)"
        } else if o.created.isEmpty {
            subtitle = "Nichts erstellt"
        }
        activity.post(.init(symbol: o.created.isEmpty ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath",
                            title: title, subtitle: subtitle))
    }

    /// Untermenü „Umwandeln“ für bestimmte Einträge (Rechtsklick).
    func convertMenu(for items: [ShelfStore.Item]) -> NSMenu {
        let m = NSMenu()
        for side in ShelfConvert.shrinkSides {
            m.addItem(ClosureMenuItem(title: "Verkleinern auf \(side) px") { [weak self] in
                self?.convert(.shrink(longSide: side), items: items)
            })
        }
        m.addItem(.separator())
        for f in ShelfConvert.Format.allCases {
            m.addItem(ClosureMenuItem(title: "In \(f.title) umwandeln") { [weak self] in self?.convert(.format(f), items: items) })
        }
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(title: "Zu einem PDF zusammenfügen") { [weak self] in self?.convert(.pdf, items: items) })
        return m
    }
}
