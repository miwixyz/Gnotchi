import AppKit

/// Erkennt, dass irgendwo gerade **Dateien gezogen** werden (0.8.0, G32) – ohne Bedienungshilfen und ohne globalen
/// Ereignis-Beobachter (G1): alle 0,1 s Maustasten-Zustand und Zähler/Typen der Zieh-Zwischenablage lesen, keine
/// Inhalte. Gemessen 22.10. (`tools/drag-probe.swift`): Finder-Ziehen erhöht den Zähler ~200 ms nach dem Drücken,
/// Typ `public.file-url`; normale Klicks ändern ihn nicht.
@MainActor
final class DragWatcher {

    /// Reiner Zustand (getestet): Taste gedrückt UND Zähler seit dem letzten Stand ohne Taste geändert UND Datei-Typ.
    struct State: Equatable {
        var idleCount: Int
        var dragging = false

        mutating func step(pressed: Bool, count: Int, hasFiles: Bool) {
            guard pressed else {
                idleCount = count
                dragging = false
                return
            }
            if count != idleCount && hasFiles { dragging = true }
        }
    }

    private let onChange: (Bool) -> Void
    private var state: State
    private var timer: Timer?
    private let pasteboard = NSPasteboard(name: .drag)

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        state = State(idleCount: NSPasteboard(name: .drag).changeCount)
    }

    func start() {
        guard timer == nil else { return }
        state = State(idleCount: pasteboard.changeCount)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if state.dragging { onChange(false) }
        state.dragging = false
    }

    private func tick() {
        let before = state.dragging
        let pressed = NSEvent.pressedMouseButtons & 1 == 1
        let count = pasteboard.changeCount
        // Typen nur lesen, wenn sich der Zähler bei gedrückter Taste geändert hat (sonst nichts anfassen).
        let hasFiles = pressed && count != state.idleCount && (pasteboard.types ?? []).contains(.fileURL)
        state.step(pressed: pressed, count: count, hasFiles: hasFiles)
        if state.dragging != before { onChange(state.dragging) }
    }
}
