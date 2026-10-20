import CoreGraphics

/// Form und Größe der Insel je Zustand – reine Rechnungen (getestet), ausgelagert aus IslandController.
extension IslandController {

    /// Form einer sichtbaren Insel: Ein Hinweis verdrängt „klein“, nicht „groß“ (dort wird gerade bedient);
    /// endet er, geht es zurück auf klein.
    /// Die Tippi-Aufnahme bleibt klein und verdrängt Hinweis und groß (Spezifikation 0.2.0); mit Live-Text
    /// klappt sie zu `live` auf (0.3.0).
    nonisolated static func nextMode(current: IslandState.Mode, notice: Bool, recording: Bool = false,
                                     liveText: Bool = false) -> IslandState.Mode {
        if recording { return liveText ? .live : .compact }
        if current == .live { return notice ? .notice : .compact }
        if notice { return current == .expanded ? .expanded : .notice }
        return current == .hidden || current == .notice ? .compact : current
    }

    /// Panelgröße je Zustand; nil = Panel ist weg. Groß hängt am Inhalt (0.2.0): ohne Musik nur die
    /// Mikrofon/Kamera-Zeilen in Hinweis-Größe, mit Musik und aktivem Mikrofon/Kamera eine Zeile höher.
    nonisolated static func panelFrame(mode: IslandState.Mode, layout: IslandGeometry.Layout,
                                       hasMedia: Bool = true, privacy: Bool = false, quota: Bool = false) -> CGRect? {
        switch mode {
        case .hidden: return nil
        case .compact: return layout.compact
        case .notice: return layout.notice
        case .live: return layout.live
        case .expanded:
            guard hasMedia else { return layout.notice }
            let lines = CGFloat((privacy ? 1 : 0) + (quota ? 1 : 0))
            guard lines > 0 else { return layout.expanded }
            var r = layout.expanded
            r.origin.y -= IslandGeometry.privacyLineHeight * lines
            r.size.height += IslandGeometry.privacyLineHeight * lines
            return r
        }
    }
}
