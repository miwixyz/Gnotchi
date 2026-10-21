import CoreGraphics

/// Form und Größe der Insel je Zustand – reine Rechnungen (getestet), ausgelagert aus IslandController.
extension IslandController {

    /// Form einer sichtbaren Insel: Ein Hinweis verdrängt „klein“, nicht „groß“ (dort wird gerade bedient);
    /// endet er, geht es zurück auf klein.
    /// Die Tippi-Aufnahme bleibt klein und verdrängt Hinweis und groß (Spezifikation 0.2.0); mit Live-Text
    /// klappt sie zu `live` auf (0.3.0).
    /// Trackwechsel (0.4.0): `wide` statt klein, solange `trackFlash`; groß bleibt groß.
    nonisolated static func nextMode(current: IslandState.Mode, notice: Bool, recording: Bool = false,
                                     liveText: Bool = false, trackFlash: Bool = false) -> IslandState.Mode {
        if recording { return liveText ? .live : .compact }
        if current == .live { return notice ? .notice : .compact }
        if notice { return current == .expanded ? .expanded : .notice }
        if current == .expanded { return .expanded }
        return trackFlash ? .wide : .compact
    }

    /// Panelgröße je Zustand; nil = Panel ist weg. Groß hängt am Inhalt (0.2.0): ohne Musik nur die
    /// Mikrofon/Kamera-Zeilen in Hinweis-Größe, mit Musik und aktivem Mikrofon/Kamera eine Zeile höher.
    /// 0.4.0: je Update eine Zeile über der Musik (`updates`); ohne Musik `rows` Zeilen (detailRows), ab der
    /// dritten wächst die Hinweis-Größe nach unten.
    nonisolated static func panelFrame(mode: IslandState.Mode, layout: IslandGeometry.Layout,
                                       hasMedia: Bool = true, privacy: Bool = false, quota: Bool = false,
                                       updates: Int = 0, rows: Int = 0) -> CGRect? {
        switch mode {
        case .hidden: return nil
        case .compact: return layout.compact
        case .wide: return layout.wide
        case .notice: return layout.notice
        case .live: return layout.live
        case .expanded:
            guard hasMedia else {
                var r = layout.notice
                let extra = CGFloat(max(0, rows - 2)) * IslandGeometry.privacyLineHeight
                r.origin.y -= extra
                r.size.height += extra
                return r
            }
            let lines = CGFloat((privacy ? 1 : 0) + (quota ? 1 : 0) + updates)
            guard lines > 0 else { return layout.expanded }
            var r = layout.expanded
            r.origin.y -= IslandGeometry.privacyLineHeight * lines
            r.size.height += IslandGeometry.privacyLineHeight * lines
            return r
        }
    }

    /// Große Insel „Eine Sache groß“ (0.5.0): Musik in Player-Größe, alles andere in Hinweis-Größe, die
    /// Symbolleiste eine Zeile höher.
    nonisolated static func bigFrame(layout: IslandGeometry.Layout, bigIsMedia: Bool, chipRow: Bool) -> CGRect? {
        panelFrame(mode: .expanded, layout: layout, hasMedia: bigIsMedia, updates: chipRow ? 1 : 0, rows: chipRow ? 3 : 2)
    }

    /// Nach der Verzögerung aufklappen? Nur wenn die Maus noch über der Insel ist, keine Taste gedrückt
    /// ist (Fenster an den oberen Rand ziehen, Spezifikation) und die Insel klein ist bzw. breit (nicht weg, nicht schon groß).
    nonisolated static func shouldExpand(stillInside: Bool, mouseDown: Bool, mode: IslandState.Mode) -> Bool {
        stillInside && !mouseDown && (mode == .compact || mode == .wide)
    }

    /// Neu aufbauen nur, wenn sich Bildschirme oder deren Inselmaße wirklich geändert haben.
    nonisolated static func layoutsChanged(old: [CGDirectDisplayID: IslandGeometry.Layout],
                                           new: [CGDirectDisplayID: IslandGeometry.Layout]) -> Bool {
        old != new
    }
}
