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
    /// Welche Stufe gerade offen ist (nil = zu).
    private(set) var openEdge: Preferences.PanelEdge?

    /// Kürzel stufenweise (Michael 26.10.): zu → aus der Notch → große Ansicht am Rand → zu.
    /// Ohne „Zuerst aus der Notch“: zu ↔ große Ansicht.
    func toggle() {
        switch openEdge {
        case nil: open()
        case .notch?: expand()
        default: close()
        }
    }

    /// Vom Herunterklappen in die große Ansicht – Suche und gewählte Sammlung kommen mit.
    func expand() {
        guard let link, let state else { return }
        let query = state.query
        let collectionID = state.collectionID
        close()
        open(link.panelEdge, query: query, collectionID: collectionID)
    }

    func open(_ requested: Preferences.PanelEdge? = nil, query: String = "", collectionID: UUID? = nil) {
        guard let link, link.store != nil else { return }
        let edge = requested ?? (link.notchFirst ? .notch : link.panelEdge)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let frame: CGRect
        var topInset: CGFloat = 0
        if edge == .notch {
            (frame, topInset) = Self.dropFrame(IslandGeometry.metrics(of: screen))
        } else {
            frame = Self.frame(edge: edge, in: screen.visibleFrame)
        }
        let p = panel ?? makePanel()
        panel = p
        // Herunterklappen über der Menüleiste, eine Ebene unter der Insel (mainMenu + 3) – beide schwarz an der Notch.
        p.level = edge == .notch ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2) : .statusBar
        p.hasShadow = edge != .notch
        let state = ClipboardPanelState(link: link, edge: edge) { [weak self] in self?.close() }
        state.topInset = topInset
        state.collectionID = collectionID
        state.query = query
        if edge == .notch { state.onExpand = { [weak self] in self?.expand() } }
        self.state = state
        openEdge = edge
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
        openEdge = nil
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
        case .bottom, .notch:
            return CGRect(x: area.minX + inset, y: area.minY + inset, width: area.width - 2 * inset, height: bottomHeight)
        }
    }

    nonisolated static let dropSize = CGSize(width: 680, height: 230)

    /// Herunterklappen (0.14.0): oben bündig am Bildschirmrand, mittig unter der Notch bzw. Pille, um die Höhe der
    /// Notch/Menüleiste länger (der Inhalt beginnt darunter). Schmale Bildschirme: Breite gekürzt.
    nonisolated static func dropFrame(_ m: IslandGeometry.ScreenMetrics) -> (frame: CGRect, topInset: CGFloat) {
        let layout = IslandGeometry.layout(for: m)
        let topInset = layout.notch?.height ?? max(m.menuBarHeight, IslandGeometry.pillSize.height)
        let midX = layout.notch?.midX ?? m.frame.midX
        let width = min(dropSize.width, m.frame.width - 16)
        let height = dropSize.height + topInset
        let x = min(max(midX - width / 2, m.frame.minX + 8), m.frame.maxX - 8 - width)
        return (CGRect(x: x, y: m.frame.maxY - height, width: width, height: height), topInset)
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
            // Kommt verspätet (Warteschlange). Ist das Fenster inzwischen wieder Schlüsselfenster – etwa nach
            // „Mehr“ – gehört der Fokusverlust zur alten Stufe: nicht schließen.
            MainActor.assumeIsolated {
                guard let self, self.panel?.isKeyWindow != true else { return }
                self.close()
            }
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
    /// Herunterklappen: Höhe der Notch bzw. Menüleiste über dem Inhalt (0 an den Rändern).
    var topInset: CGFloat = 0
    /// Herunterklappen: „Mehr“ → große Ansicht am Rand (nil an den Rändern).
    @ObservationIgnored var onExpand: (() -> Void)?
    @ObservationIgnored private var mouseWasInside = false
    @ObservationIgnored private var leaveTask: Task<Void, Never>?

    /// Herunterklappen: Maus raus schließt – aber nur, wenn sie vorher drin war (sonst ginge es nach dem Öffnen per
    /// Tastatur sofort zu) und nicht, solange ein Menü offen ist.
    func hover(_ inside: Bool) {
        leaveTask?.cancel()
        if inside { mouseWasInside = true; return }
        guard mouseWasInside else { return }
        leaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, RunLoop.main.currentMode != .eventTracking else { return }
            self.onClose()
        }
    }

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
        case 124 where edge == .bottom || edge == .notch: move(1)    // →
        case 123 where edge == .bottom || edge == .notch: move(-1)   // ←
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

    /// Einfacher Klick: nur markieren (0.12.0, Michael 26.10.: wie Finder/PastePal).
    func select(_ entry: ClipEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { selection = index }
    }

    /// Kopieren, schließen und – wenn das Hilfsprogramm verbunden ist – einfügen (G42). `paste: false` = nur kopieren
    /// (Kontextmenü).
    func pick(_ entry: ClipEntry, plain: Bool, paste: Bool = true) {
        if entry.isVault {
            // `link` fest halten, nicht über `self`: Der Touch-ID-/Passwort-Dialog nimmt der Seitenansicht den Fokus,
            // sie schließt sich und ihr Zustand ist weg, bevor die Freigabe zurückkommt (Sichttest 26.10.: erst
            // der zweite Doppelklick fügte ein, das Hilfsprogramm bekam beim ersten keinen Befehl).
            let link = link
            link.copyVault(entry) { [weak self] ok in
                guard ok else { self?.message = String(localized: "Tresor nicht entsperrt."); return }
                self?.onClose()
                if paste { link.pasteAfterClose() }
            }
        } else {
            link.copy(entry, plain: plain)
            onClose()
            if paste { link.pasteAfterClose() }
        }
    }
}

// MARK: - Ansicht

struct ClipboardPanelView: View {
    @Bindable var state: ClipboardPanelState
    @FocusState var searchFocused: Bool

    var link: ClipboardLink { state.link }
    var edge: Preferences.PanelEdge { state.edge }
    var store: ClipboardStore? { state.store }
    private var collection: ClipCollection? { state.collection }

    var body: some View {
        if edge == .notch { dropBody } else { sideBody }
    }

    private var sideBody: some View {
        VStack(spacing: 10) {
            header
            if link.secretsToOffer > 0 { secretOffer(link.secretsToOffer) }
            title
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
            Text(link.canPaste ? "Doppelklick oder ↵ fügt ein · ⇧ als reinen Text · ⌘1–9 · Esc"
                               : "↵ kopieren · ⇧↵ als reinen Text · ⌘1–9 · Esc schließt · danach ⌘V")
                .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .familyGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { searchFocused = true }
    }

    var header: some View {
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

    /// Einmaliges Angebot (G43): offen gespeicherte Schlüssel in den Tresor. Nur Anzahl, nie Inhalt oder Art.
    private func secretOffer(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(count == 1 ? "In deinen Sammlungen liegt 1 Schlüssel offen."
                             : "In deinen Sammlungen liegen \(count) Schlüssel offen.", systemImage: "key.fill")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Button("Alle in den Tresor") {
                    link.moveSavedSecretsToVault { moved in
                        state.message = moved.map { String(localized: "\($0) in den Tresor verschoben.") }
                            ?? String(localized: "Tresor nicht entsperrt.")
                    }
                }
                Button("Später") { link.dismissSecretOffer() }
            }
            .font(.system(size: 11)).buttonStyle(.borderless)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.15)))
    }

    /// Name der offenen Sammlung als Überschrift (Michael, 26.10.: Symbole allein schwer erkennbar, Namen in den
    /// Reitern zu breit – deshalb unten nur Symbole, oben der Name).
    private var title: some View {
        HStack(spacing: 6) {
            Image(systemName: collection.map { $0.isVault ? "lock.fill" : $0.symbol } ?? "clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(collection?.color.swiftUI ?? .secondary)
            Text(verbatim: collection?.name ?? String(localized: "Verlauf"))
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
                            // Doppelklick fügt ein (G42), einfacher Klick markiert sofort (gleichzeitig, ohne
                            // auf einen möglichen zweiten Klick zu warten).
                            .onTapGesture(count: 2) {
                                state.pick(entry, plain: NSEvent.modifierFlags.contains(.shift))
                            }
                            .simultaneousGesture(TapGesture().onEnded { state.select(entry) })
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

    @ViewBuilder func menu(for entry: ClipEntry) -> some View {
        if entry.isVault {
            if link.canPaste { Button("Einfügen (Touch ID)") { state.pick(entry, plain: true) } }
            Button("Kopieren (Touch ID)") { state.pick(entry, plain: true, paste: false) }
        } else if store?.secretKind(entry) != nil {
            // Erkanntes Geheimnis (G43): kein Anheften, keine normale Sammlung – nur Tresor oder weg.
            if link.canPaste { Button("Einfügen") { state.pick(entry, plain: true) } }
            Button("Kopieren") { state.pick(entry, plain: true, paste: false) }
            vaultMenu(for: entry)
        } else {
            if link.canPaste { Button("Einfügen") { state.pick(entry, plain: false) } }
            Button("Kopieren") { state.pick(entry, plain: false, paste: false) }
            Button("Als reinen Text kopieren") { state.pick(entry, plain: true, paste: false) }
            Button(isPinned(entry) ? "Lösen" : "Anheften") { try? store?.togglePinned(entry) }
            Menu("Zu Sammlung") {
                ForEach((store?.collections() ?? []).filter { !$0.isPinned && !$0.isVault }, id: \.id) { c in
                    Button(c.name) { try? store?.add(entry, to: c) }
                }
            }
            vaultMenu(for: entry)
        }
        Button("Titel …") { askTitle(entry) }
        if let collection, !entry.isVault {
            Button("Aus „\(collection.name)“ entfernen") { try? store?.remove(entry, from: collection) }
        }
        Divider()
        Button("Löschen", role: .destructive) { store?.delete(entry) }
    }

    /// „In Tresor“: vorhandene Tresore, sonst einen anlegen (G43: erkannte Geheimnisse gehören dorthin).
    @ViewBuilder private func vaultMenu(for entry: ClipEntry) -> some View {
        let vaults = (store?.collections() ?? []).filter(\.isVault)
        if vaults.isEmpty {
            Button("In neuen Tresor verschieben …") {
                if let vault = try? store?.createCollection(name: String(localized: "Tresor"), color: .red,
                                                             symbol: "lock.fill", isVault: true) {
                    moveToVault(entry, vault)
                }
            }
        } else {
            Menu("In Tresor") {
                ForEach(vaults, id: \.id) { c in Button(c.name) { moveToVault(entry, c) } }
            }
        }
    }

    // MARK: Aktionen

    private func isPinned(_ entry: ClipEntry) -> Bool {
        (entry.collections ?? []).contains(where: \.isPinned)
    }

    func drop(_ ids: [String], on collection: ClipCollection) -> Bool {
        guard let store else { return false }
        let all = store.entries() + store.collections().flatMap { $0.entries ?? [] }
        var moved = false
        for id in ids {
            guard let entry = all.first(where: { $0.id.uuidString == id }) else { continue }
            if collection.isVault {
                moveToVault(entry, collection)
            } else if store.secretKind(entry) == nil {
                try? store.add(entry, to: collection)
            } else {
                continue   // Geheimnis nur in den Tresor (G43)
            }
            moved = true
        }
        return moved
    }

    private func moveToVault(_ entry: ClipEntry, _ collection: ClipCollection) {
        guard !entry.isVault else { return }
        let suggested = store?.title(entry) ?? store?.secretKind(entry) ?? VaultTitles.suggest(store?.payload(entry)?.plain ?? "")
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

    func newCollection(vault: Bool) {
        guard let name = ClipboardPrompts.text(title: vault ? "Neuer Tresor" : "Neue Sammlung", message: "", value: ""),
              !name.isEmpty else { return }
        _ = try? store?.createCollection(name: name, color: vault ? .red : .blue,
                                         symbol: vault ? "lock.fill" : "folder", isVault: vault)
    }

    func deleteCollection(_ c: ClipCollection) {
        let note = c.isVault ? "Die Einträge im Tresor werden mit gelöscht." : "Die Einträge bleiben im Verlauf."
        guard ClipboardPrompts.confirm(title: "„\(c.name)“ löschen?", message: note) else { return }
        if state.collectionID == c.id { state.collectionID = nil }
        try? store?.deleteCollection(c)
    }
}
