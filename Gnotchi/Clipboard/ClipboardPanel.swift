import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Seitenansicht der Zwischenablage (0.11.0): rechts/links in voller Höhe oder unten. Nimmt Tastatur an, ohne die
/// Arbeits-App zu deaktivieren (`nonactivatingPanel` + `canBecomeKey`, Muster aus Tippi). Nicht in Bildschirmfreigaben
/// sichtbar (`sharingType = .none`, G40). Schließt bei Esc, Klick daneben und nach dem Kopieren.
@MainActor
final class ClipboardPanelController {
    nonisolated static let sideWidth: CGFloat = 380
    nonisolated static let bottomHeight: CGFloat = 300

    private weak var link: ClipboardLink?
    private var panel: KeyPanel?
    private var resignObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var state: ClipboardPanelState?

    init(link: ClipboardLink) { self.link = link }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard let link, link.store != nil else { return }
        let edge = link.panelEdge
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let frame = Self.frame(edge: edge, in: area)
        let p = panel ?? makePanel()
        panel = p
        let state = ClipboardPanelState(link: link, edge: edge) { [weak self] in self?.close() }
        self.state = state
        p.contentView = NSHostingView(rootView: ClipboardPanelView(state: state))
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        p.makeKey()
        installKeys()
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        panel?.contentView = nil   // Ansicht mit entschlüsselten Vorschauen freigeben
        state = nil
    }

    /// Tasten VOR dem Suchfeld abfangen (24.10. gemessen: im Suchfeld kamen ↑/↓/↵ nie bei der Liste an).
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let flags = event.modifierFlags
            let characters = event.charactersIgnoringModifiers
            let window = event.windowNumber
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel, panel.windowNumber == window, let state = self.state else {
                    return false
                }
                return state.handle(keyCode: code, flags: flags, characters: characters)
            }
            return consumed ? nil : event
        }
    }

    nonisolated static func frame(edge: Preferences.PanelEdge, in area: CGRect) -> CGRect {
        let inset: CGFloat = 8
        switch edge {
        case .right:
            return CGRect(x: area.maxX - sideWidth - inset, y: area.minY + inset, width: sideWidth,
                          height: area.height - 2 * inset)
        case .left:
            return CGRect(x: area.minX + inset, y: area.minY + inset, width: sideWidth, height: area.height - 2 * inset)
        case .bottom:
            return CGRect(x: area.minX + inset, y: area.minY + inset, width: area.width - 2 * inset, height: bottomHeight)
        }
    }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.onEscape = { [weak self] in self?.close() }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        return p
    }
}

/// Panel, das Tastatur annimmt, ohne die App zu aktivieren.
final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

// MARK: - Zustand (Auswahl, Suche, Tasten)

/// Gemeinsamer Zustand der Seitenansicht. Tasten kommen über den Monitor des Fensters (vor dem Suchfeld).
@MainActor
@Observable
final class ClipboardPanelState {
    let link: ClipboardLink
    let edge: Preferences.PanelEdge
    let onClose: () -> Void
    var query = "" { didSet { selection = 0 } }
    var collectionID: UUID? { didSet { selection = 0 } }
    var selection = 0
    var message: String?

    init(link: ClipboardLink, edge: Preferences.PanelEdge, onClose: @escaping () -> Void) {
        self.link = link
        self.edge = edge
        self.onClose = onClose
    }

    var store: ClipboardStore? { link.store }
    var collection: ClipCollection? {
        guard let collectionID else { return nil }
        return store?.collections().first { $0.id == collectionID }
    }
    var entries: [ClipEntry] { store?.entries(in: collection, matching: query) ?? [] }

    /// true = Taste verbraucht.
    func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> Bool {
        let shift = flags.contains(.shift)
        switch keyCode {
        case 125: move(1)                                        // ↓
        case 126: move(-1)                                       // ↑
        case 124 where edge == .bottom: move(1)                  // →
        case 123 where edge == .bottom: move(-1)                 // ←
        case 36, 76: pick(at: selection, plain: shift)           // ↵, Enter (Ziffernblock)
        case 53: onClose()                                       // Esc
        default:
            guard flags.contains(.command), let c = characters, let n = Int(c), (1...9).contains(n) else { return false }
            pick(at: n - 1, plain: shift)
        }
        return true
    }

    func move(_ delta: Int) {
        let count = entries.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func pick(at index: Int, plain: Bool) {
        let list = entries
        guard list.indices.contains(index) else { return }
        pick(list[index], plain: plain)
    }

    func pick(_ entry: ClipEntry, plain: Bool) {
        if entry.isVault {
            link.copyVault(entry) { [weak self] ok in
                if ok { self?.onClose() } else { self?.message = String(localized: "Tresor nicht entsperrt.") }
            }
        } else {
            link.copy(entry, plain: plain)
            onClose()
        }
    }
}

// MARK: - Ansicht

struct ClipboardPanelView: View {
    @Bindable var state: ClipboardPanelState
    @FocusState private var searchFocused: Bool

    private var link: ClipboardLink { state.link }
    private var edge: Preferences.PanelEdge { state.edge }
    private var store: ClipboardStore? { state.store }
    private var collection: ClipCollection? { state.collection }

    var body: some View {
        VStack(spacing: 10) {
            header
            if state.entries.isEmpty {
                Spacer()
                Text(state.query.isEmpty ? "Noch nichts kopiert" : "Nichts gefunden")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            } else {
                cards
            }
            if let message = state.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            tabs
            Text("↵ kopieren · ⇧↵ als reinen Text · ⌘1–9 · Esc schließt · danach ⌘V")
                .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .familyGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Suchen", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
            if link.isPaused {
                Button("Fortsetzen") { link.resume() }.buttonStyle(.borderless).font(.system(size: 11))
            }
            if link.vaultUnlocked {
                Button { link.lockVault() } label: { Image(systemName: "lock.open.fill").foregroundStyle(.orange) }
                    .buttonStyle(.borderless)
                    .help("Tresor ist offen – Klick sperrt sofort")
                    .accessibilityLabel(Text("Tresor sperren"))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
    }

    @ViewBuilder private var cards: some View {
        let list = state.entries
        ScrollViewReader { proxy in
            ScrollView(edge == .bottom ? .horizontal : .vertical) {
                let layout = edge == .bottom
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                    : AnyLayout(VStackLayout(spacing: 8))
                layout {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                        ClipCard(link: link, entry: entry, number: index < 9 ? index + 1 : nil,
                                 selected: index == state.selection, compactWidth: edge == .bottom)
                            .id(entry.id)
                            .onTapGesture { state.pick(entry, plain: NSEvent.modifierFlags.contains(.shift)) }
                            .contextMenu { menu(for: entry) }
                    }
                }
                .padding(2)
            }
            .onChange(of: state.selection) {
                if list.indices.contains(state.selection) { proxy.scrollTo(list[state.selection].id) }
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tab(symbol: "clock", label: "Verlauf", color: .secondary, selected: state.collectionID == nil) {
                state.collectionID = nil
            }
            ForEach(store?.collections() ?? [], id: \.id) { c in
                tab(symbol: c.isVault ? "lock.fill" : c.symbol, label: c.name, color: c.color.swiftUI,
                    selected: state.collectionID == c.id) { state.collectionID = c.id }
                    .dropDestination(for: String.self) { ids, _ in drop(ids, on: c) }
                    .contextMenu {
                        if !c.isPinned {
                            Button("Sammlung löschen …", role: .destructive) { deleteCollection(c) }
                        }
                    }
            }
            Menu {
                Button("Neue Sammlung …") { newCollection(vault: false) }
                Button("Neuer Tresor …") { newCollection(vault: true) }
            } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
            Spacer(minLength: 0)
        }
        .frame(height: 30)
    }

    private func tab(symbol: String, label: String, color: Color, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                .frame(width: 30, height: 26)
                .background(Capsule().fill(.white.opacity(selected ? 0.18 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func menu(for entry: ClipEntry) -> some View {
        if entry.isVault {
            Button("Kopieren (Touch ID)") { state.pick(entry, plain: true) }
        } else {
            Button("Kopieren") { state.pick(entry, plain: false) }
            Button("Als reinen Text kopieren") { state.pick(entry, plain: true) }
            Button(isPinned(entry) ? "Lösen" : "Anheften") { try? store?.togglePinned(entry) }
            Menu("Zu Sammlung") {
                ForEach((store?.collections() ?? []).filter { !$0.isPinned && !$0.isVault }, id: \.id) { c in
                    Button(c.name) { try? store?.add(entry, to: c) }
                }
            }
            Menu("In Tresor") {
                ForEach((store?.collections() ?? []).filter(\.isVault), id: \.id) { c in
                    Button(c.name) { moveToVault(entry, c) }
                }
            }
        }
        Button("Titel …") { askTitle(entry) }
        if let collection, !entry.isVault {
            Button("Aus „\(collection.name)“ entfernen") { try? store?.remove(entry, from: collection) }
        }
        Divider()
        Button("Löschen", role: .destructive) { store?.delete(entry) }
    }

    // MARK: Aktionen

    private func isPinned(_ entry: ClipEntry) -> Bool {
        (entry.collections ?? []).contains(where: \.isPinned)
    }

    private func drop(_ ids: [String], on collection: ClipCollection) -> Bool {
        guard let store else { return false }
        let all = store.entries() + store.collections().flatMap { $0.entries ?? [] }
        var moved = false
        for id in ids {
            guard let entry = all.first(where: { $0.id.uuidString == id }) else { continue }
            if collection.isVault {
                moveToVault(entry, collection)
            } else {
                try? store.add(entry, to: collection)
            }
            moved = true
        }
        return moved
    }

    private func moveToVault(_ entry: ClipEntry, _ collection: ClipCollection) {
        guard !entry.isVault else { return }
        let suggested = store?.title(entry) ?? VaultTitles.suggest(store?.payload(entry)?.plain ?? "")
        guard let title = ClipboardPrompts.text(title: "Titel im Tresor", message: "Ohne Titel findest du den Eintrag nicht wieder.",
                                                value: suggested), !title.isEmpty else { return }
        link.unlockVault { key in
            guard let key else { state.message = "Tresor nicht entsperrt."; return }
            do {
                try store?.moveToVault(entry, collection: collection, title: title, vaultKey: key)
            } catch {
                state.message = "Verschieben fehlgeschlagen."
            }
        }
    }

    private func askTitle(_ entry: ClipEntry) {
        guard let title = ClipboardPrompts.text(title: "Titel", message: "", value: store?.title(entry) ?? "") else { return }
        try? store?.setTitle(entry, title)
    }

    private func newCollection(vault: Bool) {
        guard let name = ClipboardPrompts.text(title: vault ? "Neuer Tresor" : "Neue Sammlung", message: "", value: ""),
              !name.isEmpty else { return }
        _ = try? store?.createCollection(name: name, color: vault ? .red : .blue,
                                         symbol: vault ? "lock.fill" : "folder", isVault: vault)
    }

    private func deleteCollection(_ c: ClipCollection) {
        let note = c.isVault ? "Die Einträge im Tresor werden mit gelöscht." : "Die Einträge bleiben im Verlauf."
        guard ClipboardPrompts.confirm(title: "„\(c.name)“ löschen?", message: note) else { return }
        if state.collectionID == c.id { state.collectionID = nil }
        try? store?.deleteCollection(c)
    }
}

// MARK: - Karte

struct ClipCard: View {
    let link: ClipboardLink
    let entry: ClipEntry
    let number: Int?
    let selected: Bool
    let compactWidth: Bool

    var body: some View {
        let store = link.store
        let payload = store?.payload(entry)
        let title = store?.title(entry)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let source = entry.sourceBundleID {
                    AppSymbol(bundleID: source, size: 16)
                } else {
                    Image(systemName: entry.isVault ? "lock.fill" : "doc.on.clipboard").font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let title { Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
                Spacer(minLength: 0)
                Text(entry.lastUsedAt, format: .relative(presentation: .named))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if let number { Text(verbatim: "⌘\(number)").font(.system(size: 10)).foregroundStyle(.tertiary) }
            }
            preview(payload)
        }
        .padding(10)
        .frame(width: compactWidth ? 220 : nil, alignment: .leading)
        .frame(maxWidth: compactWidth ? 220 : .infinity, minHeight: 54, maxHeight: compactWidth ? .infinity : 180,
               alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(selected ? 0.16 : 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.accentColor.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .modifier(DragOut(entry: entry, payload: payload))
    }

    @ViewBuilder private func preview(_ payload: ClipPayload?) -> some View {
        if entry.isVault {
            Text(verbatim: "••••••••").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
        } else if let payload {
            switch entry.kind {
            case .image:
                if let image = ClipThumbnails.image(for: entry, payload: payload) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            case .file:
                Label(payload.plain, systemImage: "doc").font(.system(size: 12)).lineLimit(2)
            case .link:
                Label(payload.plain, systemImage: "link").font(.system(size: 12)).lineLimit(2)
                    .foregroundStyle(.blue)
            case .text, .richText:
                Text(verbatim: String(payload.plain.prefix(400)))
                    .font(.system(size: 12)).lineLimit(compactWidth ? 8 : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Rausziehen in andere Apps (G40): gespeicherte Formate, nie Tresor-Einträge. Innerhalb der Ansicht trägt der Zug
/// die Kennung (für das Ablegen auf einem Sammlungs-Reiter).
private struct DragOut: ViewModifier {
    let entry: ClipEntry
    let payload: ClipPayload?

    func body(content: Content) -> some View {
        if entry.isVault || payload == nil {
            content
        } else {
            content.onDrag {
                let provider = NSItemProvider()
                provider.registerObject(entry.id.uuidString as NSString, visibility: .ownProcess)
                for format in payload?.formats ?? [] where format.type != ClipboardCapture.UTI.fileURL {
                    let data = format.data
                    provider.registerDataRepresentation(forTypeIdentifier: format.type, visibility: .all) { done in
                        done(data, nil)
                        return nil
                    }
                }
                if let file = payload?.formats.first(where: { $0.type == ClipboardCapture.UTI.fileURL }),
                   let url = String(bytes: file.data, encoding: .utf8).flatMap(URL.init(string:)), url.isFileURL,
                   FileManager.default.fileExists(atPath: url.path) {
                    provider.registerObject(url as NSURL, visibility: .all)
                }
                return provider
            }
        }
    }
}

/// Vorschaubilder nur verkleinert, im Speicher, nur aus den erlaubten Bildformaten (G40).
@MainActor
enum ClipThumbnails {
    private static let cache = NSCache<NSUUID, NSImage>()

    static func image(for entry: ClipEntry, payload: ClipPayload) -> NSImage? {
        if let hit = cache.object(forKey: entry.id as NSUUID) { return hit }
        guard let data = payload.formats.first(where: { ClipboardCapture.imageTypes.contains($0.type) })?.data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: entry.id as NSUUID)
        return image
    }
}

/// Kleine Rückfragen (Titel, Name, Bestätigung) als Systemdialog.
@MainActor
enum ClipboardPrompts {
    static func text(title: String, message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Löschen")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension ClipColor {
    var swiftUI: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}
