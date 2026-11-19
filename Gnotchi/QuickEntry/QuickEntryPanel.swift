import AppKit
import OSLog
import SwiftUI

/// Eingabezeile der Schnelleingabe (G61): klappt wie die Zwischenablage aus der Notch herunter (ohne Notch unter der
/// Pille), nimmt Tastatur an, ohne die Arbeits-App zu deaktivieren (`KeyPanel`), nicht in Bildschirmfreigaben
/// sichtbar. Schließt bei Esc, Klick daneben und nach dem Speichern.
@MainActor
final class QuickEntryPanelController {
    nonisolated static let size = CGSize(width: 560, height: 72)
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "schnelleingabe")

    private var panel: KeyPanel?
    private var state: QuickEntryState?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var openToken: UUID?
    private let submit: (QuickEntryParser.Entry) async -> Result<UUID, QuickEntryFailure>
    private let undo: (UUID) async -> String?

    init(submit: @escaping (QuickEntryParser.Entry) async -> Result<UUID, QuickEntryFailure>,
         undo: @escaping (UUID) async -> String?) {
        self.submit = submit
        self.undo = undo
    }

    var isOpen: Bool { panel?.isVisible == true }

    /// Kürzel nochmal → zu.
    func toggle() {
        if isOpen { close(reason: "Kürzel") } else { open() }
    }

    func open() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let (frame, topInset) = Self.dropFrame(IslandGeometry.metrics(of: screen))
        let p = panel ?? makePanel()
        panel = p
        // Schließt nur die eigene Zeile: Speichert eine ältere noch, während schon eine neue offen ist, darf deren
        // Selbst-Schließen die neue nicht zumachen.
        let token = UUID()
        openToken = token
        let state = QuickEntryState(submit: submit, undo: undo) { [weak self] in
            guard let self else { return }
            guard self.openToken == token else { return Self.log.notice("Schließen für ältere Zeile ignoriert") }
            self.close(reason: "selbst")
        }
        self.state = state
        p.contentView = NSHostingView(rootView: QuickEntryView(state: state, topInset: topInset))
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        p.makeKey()
        installKeys()
        focusField(in: p)
        Self.log.notice("Zeile auf, Tastatur-Fenster \(p.isKeyWindow, privacy: .public)")
    }

    /// Fokus direkt aufs Eingabefeld (Sichttest 19.11.: `@FocusState` in `onAppear` kam manchmal zu spät, getippte
    /// Zeichen gingen ins Leere – zweimal „Text 0 Zeichen“ gemessen). Im nächsten Durchlauf, wenn SwiftUI das Feld
    /// angelegt hat; danach noch einmal kurz später, falls nicht.
    private func focusField(in p: NSPanel, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) { [weak self, weak p] in
            guard let p, p.isVisible else { return }
            if let field = Self.textField(in: p.contentView) {
                if !(p.firstResponder is NSText) { p.makeFirstResponder(field) }
                Self.log.notice("Eingabefeld fokussiert (Versuch \(attempt + 1, privacy: .public))")
            } else if attempt < 5 {
                self?.focusField(in: p, attempt: attempt + 1)
            } else {
                Self.log.error("Eingabefeld nicht gefunden")
            }
        }
    }

    private static func textField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews { if let f = textField(in: sub) { return f } }
        return nil
    }

    /// Grund nur fürs Protokoll (Sichttest 19.11.: Zeile ging unerklärt zu).
    func close(reason: String = "aus") {
        Self.log.notice("Zeile zu: \(reason, privacy: .public), sichtbar \(self.panel?.isVisible == true, privacy: .public)")
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        state?.cancelPendingClose()
        panel?.orderOut(nil)
        panel?.contentView = nil   // Eingabe nicht länger als nötig im Speicher
        state = nil
    }

    /// Oben bündig, mittig unter Notch bzw. Pille, um die Höhe der Notch/Menüleiste länger (Inhalt darunter).
    nonisolated static func dropFrame(_ m: IslandGeometry.ScreenMetrics) -> (frame: CGRect, topInset: CGFloat) {
        let layout = IslandGeometry.layout(for: m)
        let topInset = layout.notch?.height ?? max(m.menuBarHeight, IslandGeometry.pillSize.height)
        let midX = layout.notch?.midX ?? m.frame.midX
        let width = min(size.width, m.frame.width - 16)
        let height = size.height + topInset
        let x = min(max(midX - width / 2, m.frame.minX + 8), m.frame.maxX - 8 - width)
        return (CGRect(x: x, y: m.frame.maxY - height, width: width, height: height), topInset)
    }

    /// Tab, ↵ und ⌘Z vor dem Textfeld abfangen (sonst springt Tab aus dem Feld, wie bei der Zwischenablage gemessen).
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let command = event.modifierFlags.contains(.command)
            let characters = event.charactersIgnoringModifiers
            let consumed = MainActor.assumeIsolated { () -> Bool in
                // „Unser Fenster ist Tastatur-Fenster“ statt Fensternummer: Künstlich zugestellte Tasten (Sichttest
                // 19.11.) trugen die Nummer nicht, ↵ kam dann nie an. Ein lokaler Monitor sieht nur Gnotchis Tasten.
                guard let self, let panel = self.panel, panel.isKeyWindow, let state = self.state else {
                    return false
                }
                let used = state.handle(keyCode: code, command: command, characters: characters)
                if used { Self.log.notice("Taste \(code, privacy: .public) verarbeitet") }
                return used
            }
            return consumed ? nil : event
        }
    }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Eine Ebene unter der Insel, beide schwarz an der Notch (wie das Herunterklappen der Zwischenablage).
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.onEscape = { [weak self] in self?.close(reason: "Esc") }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel?.isKeyWindow != true else { return }
                // Während des Speicherns offen lassen: Die Antwort (oder ein Fehler) soll sichtbar ankommen.
                if let state = self.state, case .saving = state.phase { return }
                self.close(reason: "Fokus verloren")
            }
        }
        return p
    }
}

/// Ansicht: Eingabe, darunter die Vorschau bzw. der Stand (gespeichert, Fehler).
struct QuickEntryView: View {
    @Bindable var state: QuickEntryState
    let topInset: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: topInset)
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary).font(.system(size: 13, weight: .semibold))
                TextField("Zahnarzt morgen 15 Uhr", text: $state.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .disabled(!state.isEditable)
                    // Zweiter Weg für ↵, falls der Tastenmonitor sie nicht abfängt (dann landet sie hier).
                    .onSubmit { Task { await state.save() } }
                    .accessibilityLabel(Text("Neuer Termin oder neue Erinnerung"))
            }
            status
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
            .fill(.black))
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
    }

    @ViewBuilder private var status: some View {
        switch state.phase {
        case .saved:
            line(symbol: "checkmark", color: .green, Text("Gespeichert · Rückgängig (⌘Z)"))
        case .undone:
            line(symbol: "arrow.uturn.backward", color: .secondary, Text("Zurückgenommen"))
        case .saving:
            line(symbol: "ellipsis", color: .secondary, Text("Speichert über Kalli …"))
        case .failed(let message):
            line(symbol: "exclamationmark.triangle.fill", color: .orange, Text(message))
        case .editing:
            preview
        }
    }

    private var preview: some View {
        let e = state.entry
        return HStack(spacing: 6) {
            Image(systemName: QuickEntryPreview.symbol(e)).foregroundStyle(.secondary)
            Text(QuickEntryPreview.kindLabel(e)).foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Text(QuickEntryPreview.when(e))
            if !e.title.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Text(e.title).fontWeight(.semibold).lineLimit(1)
            } else if !state.text.isEmpty {
                Text("· Titel fehlt").foregroundStyle(.orange)
            }
            if e.urgent { Text("dringend").foregroundStyle(.red) }
            Spacer(minLength: 4)
            if e.needsCheck {
                Text("Prüfen").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.yellow))
                    .accessibilityLabel(Text("Bitte Datum und Uhrzeit prüfen"))
            }
            Text("Tab · ↵ · Esc").foregroundStyle(.tertiary).font(.system(size: 10))
        }
        .font(.system(size: 12))
    }

    private func line(symbol: String, color: Color, _ text: Text) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            text.lineLimit(2)
        }
        .font(.system(size: 12))
    }
}
