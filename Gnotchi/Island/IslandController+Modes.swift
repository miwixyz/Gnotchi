import CoreGraphics

/// Form und Größe der Insel je Zustand – reine Rechnungen (getestet), ausgelagert aus IslandController.
extension IslandController {

    /// Form einer sichtbaren Insel: Ein Hinweis verdrängt „klein“, nicht „groß“ (dort wird gerade bedient);
    /// endet er, geht es zurück auf klein.
    /// Die Tippi-Aufnahme bleibt klein und verdrängt Hinweis und groß (Spezifikation 0.2.0); mit Live-Text
    /// klappt sie zu `live` auf (0.3.0).
    /// Trackwechsel (0.4.0): `wide` statt klein, solange `trackFlash`; groß bleibt groß.
    /// Mitteilungen (0.6.0): Ein Anruf geht vor alles (auch vor die Aufnahme). Eine Mitteilung verdrängt wie ein
    /// Hinweis nur „klein“, nicht „groß“/Band (dort wird gerade bedient) und nicht die Aufnahme – sie wartet dann,
    /// Apples Banner bleibt so lange stehen (ActivityModel.noteDisplayed).
    nonisolated static func nextMode(current: IslandState.Mode, notice: Bool, recording: Bool = false,
                                     liveText: Bool = false, trackFlash: Bool = false,
                                     alarm: Bool = false, call: Bool = false, message: Bool = false,
                                     drag: Bool = false) -> IslandState.Mode {
        if let urgent = urgentMode(current: current, call: call, drag: drag,
                                   recordMode: recording ? (liveText ? .live : .compact) : nil,
                                   message: message) { return urgent }
        // Timer-Alarm (0.5.0): anklickbar – deshalb klein/groß, nie Hinweis (der lässt Klicks durch) oder breit.
        if alarm { return current == .expanded ? .expanded : .compact }
        if message { return current == .expanded || current == .band ? current : .message }
        if current == .message { return notice ? .notice : .compact }
        if current == .live { return notice ? .notice : .compact }
        if notice { return current == .expanded || current == .band ? current : .notice }
        if current == .expanded || current == .band { return current }
        return trackFlash ? .wide : .compact
    }

    /// Was vor allem anderen gilt: Anruf (0.6.0), Ablagefeld beim Ziehen (0.8.0, auch über groß/Aufnahme), Aufnahme;
    /// und der Weg zurück, wenn Anruf bzw. Ziehen enden. nil = normale Regeln.
    nonisolated static func urgentMode(current: IslandState.Mode, call: Bool, drag: Bool,
                                       recordMode: IslandState.Mode?, message: Bool) -> IslandState.Mode? {
        if call { return .call }
        if drag { return .shelfDrop }
        if current == .shelfDrop { return .compact }
        if let recordMode { return recordMode }
        if current == .call { return message ? .message : .compact }
        return nil
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
        case .band: return layout.band
        case .notice: return layout.notice
        case .live: return layout.live
        case .message: return layout.message
        case .call: return layout.call
        case .shelfDrop: return layout.shelfDrop
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

    /// Große Insel „Eine Sache groß“ (0.5.0): alles in Player-Größe (Michael 21.10.: Hinweis-Größe war zu klein),
    /// nur „nur Mikrofon/Kamera“ in Hinweis-Größe; die Symbolleiste eine Zeile höher.
    nonisolated static func bigFrame(layout: IslandGeometry.Layout, small: Bool, chipRow: Bool,
                                     mirror: Bool = false, weather: Bool = false, shelf: Bool = false,
                                     strip: Bool = false) -> CGRect? {
        guard var r = panelFrame(mode: .expanded, layout: layout, hasMedia: !small || mirror || weather || shelf,
                                 updates: chipRow ? 1 : 0, rows: chipRow ? 3 : 2) else { return nil }
        if strip {   // Kachelreihe der Ablage unten dran (0.8.0)
            r.origin.y -= IslandGeometry.shelfStripHeight
            r.size.height += IslandGeometry.shelfStripHeight
        }
        guard mirror || weather || shelf else { return r }
        let tall = mirror ? IslandGeometry.mirrorHeight : (weather ? IslandGeometry.weatherHeight : IslandGeometry.shelfHeight)
        let extra = tall - IslandGeometry.expandedSize.height
        r.origin.y -= extra
        r.size.height += extra
        if weather || shelf {   // breiter (Wetter: Lesbarkeit, Ablage: Kacheln + Knopfleiste), mittig um dieselbe Achse
            let wider = IslandGeometry.weatherWidth - r.width
            r.origin.x -= wider / 2
            r.size.width += wider
        }
        return r
    }

    /// Mitteilung (0.6.0): oben bündig wie `layout.message`, unten nur so lang wie der Inhalt.
    nonisolated static func messageFrame(layout: IslandGeometry.Layout, note: NotifyWire.Note?) -> CGRect {
        var r = layout.message
        guard let note else { return r }
        let h = IslandGeometry.messageHeight(title: !note.title.isEmpty, subtitle: !note.subtitle.isEmpty,
                                             bodyChars: note.body.count, buttons: !NotifyWire.buttonActions(note).isEmpty)
        let cut = IslandGeometry.messageSize.height - h
        r.origin.y += cut
        r.size.height -= cut
        return r
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
