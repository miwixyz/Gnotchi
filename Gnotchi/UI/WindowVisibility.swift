import AppKit
import Combine
import SwiftUI

/// Meldet, ob das Fenster, in dem die Ansicht steht, gerade sichtbar ist (0.30.0). Beim Menüleisten-Popover im Fenster-Stil
/// ruft SwiftUI `onDisappear` nicht zuverlässig beim Schließen auf – der Mixer fragte sonst dauerhaft im Hintergrund ab.
/// `NSWindow.isVisible` ist KVO-fähig; es wird nur beobachtet, nichts gelesen oder gespeichert.
struct WindowVisibility: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe(onChange: onChange) }
    func updateNSView(_ view: Probe, context: Context) { view.onChange = onChange }

    final class Probe: NSView {
        var onChange: (Bool) -> Void
        private var bag = Set<AnyCancellable>()

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("nicht aus einem Archiv") }

        override func viewDidMoveToWindow() {
            bag.removeAll()
            guard let window else { return onChange(false) }
            window.publisher(for: \.isVisible).removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.onChange($0) }
                .store(in: &bag)
        }

    }
}
