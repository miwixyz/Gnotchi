import AppKit

/// Wo die Insel liegt. Reine Rechnung, getestet; `metrics(of:)` liest nur NSScreen.
/// Koordinaten: AppKit (Ursprung unten links), wie `NSScreen.frame`.
enum IslandGeometry {

    struct ScreenMetrics: Equatable {
        let frame: CGRect
        let safeTop: CGFloat
        let auxLeftWidth: CGFloat?
        let auxRightWidth: CGFloat?
        /// Höhe der Menüleiste (0 = keine sichtbar). Nur fürs Band ohne Notch (0.5.0, gemessen 21.10.: 30 pt
        /// auf Michaels 3440er-Bildschirm, die Pille hat 24 pt – das Band wirkte schmaler als die Leiste).
        var menuBarHeight: CGFloat = 0
    }

    struct Layout: Equatable {
        /// nil = Bildschirm ohne Notch.
        let notch: CGRect?
        let compact: CGRect
        let expanded: CGRect
        /// Kurzer Hinweis (0.2.0, Kopfhörer): Streifen unter der Notch bzw. breitere Pille.
        let notice: CGRect
        /// Tippis Live-Text (0.3.0): Aufnahme-Zeile und zwei Zeilen Text unter der Notch bzw. Pille.
        let live: CGRect
        /// Trackwechsel (0.4.0): kurz breiter, Titel · Interpret neben der Notch bzw. in der breiteren Pille.
        /// Mit Standardwert, damit bestehende Tests ihr Layout ohne ihn bauen können.
        var wide: CGRect = .zero
        /// Band (0.5.0, Michael 21.10., Vorbild-Video): seitlich breit in Menüleisten-Höhe statt nach unten.
        var band: CGRect = .zero
        /// Mitteilung (0.6.0): App, Titel, Text, Knöpfe – so breit wie die große Insel.
        var message: CGRect = .zero
        /// Eingehender Anruf (0.6.0): Anrufer und zwei runde Knöpfe.
        var call: CGRect = .zero
        /// Ablagefeld beim Ziehen (0.8.0): „Hier ablegen“.
        var shelfDrop: CGRect = .zero
    }

    /// Platz links (Cover) und rechts (Pegel) neben der Notch.
    static let wing: CGFloat = 40
    static let pillSize = CGSize(width: 180, height: 24)
    /// Inhaltsfläche der grossen Ansicht. Mit Notch kommt deren Höhe oben dazu: Die Hardware-Notch
    /// verdeckt den oberen Streifen (Sichtprüfung 18.10.: 110 pt inkl. Notch reichten nicht).
    static let expandedSize = CGSize(width: 460, height: 110)
    /// Spiegel (0.5.0): Inhaltshöhe statt 110 – Bild 16:9 über die Breite (428 × 240) plus Rand.
    static let mirrorHeight: CGFloat = 256   // 0.5.0: 380 → 460 (Michael 21.10.: „breiter“)
    /// Wetter groß (0.7.0): Kopf, 8 Stunden, 7 Tage, Einzelwerte, Quellenangabe (Testbild 22.10.: 262 ließ 28 pt leer).
    static let weatherHeight: CGFloat = 300
    /// Michael 22.10.: „zu klein, kann es kaum lesen“ → Wetter breiter als die übrige große Insel, Schrift ~⅓ größer.
    /// Ab 0.8.0 auch die Ablage (Testbild: Knopfleiste bei 460 pt abgeschnitten).
    static let weatherWidth: CGFloat = 600
    /// Ablage (0.8.0): Ablagefeld beim Ziehen und große Ablage (Kacheln + Knopfleiste).
    static let shelfDropSize = CGSize(width: 460, height: 84)
    static let shelfHeight: CGFloat = 160
    /// Zwischenablage groß (0.11.0): eine Reihe Karten unter der Leiste.
    static let clipboardHeight: CGFloat = 190
    /// Kachelreihe unter der großen Sache (Michael 22.10.: „Rack schneller zugänglich“ → immer unten, sobald etwas liegt).
    static let shelfStripHeight: CGFloat = 70
    /// Hinweis-Streifen: Symbol, darunter-gestapelt Gerätename und Zustand – neben der Notch (40-pt-Flügel) passt
    /// kein Name; nebeneinander kürzte der Zustand den Namen schon nach 15 Zeichen (Testbild 20.10.).
    static let noticeSize = CGSize(width: 260, height: 44)
    /// Zusätzliche Zeile „Mikrofon · App / Kamera“ über der großen Musik-Ansicht (0.2.0).
    static let privacyLineHeight: CGFloat = 20
    /// Live-Text (0.3.0, Michael 20.10.: „klappt auf, 2 Zeilen“): Zeile mit Mikrofon/Pegel + zwei Textzeilen.
    static let liveSize = CGSize(width: 340, height: 68)
    /// Trackwechsel (0.4.0, Michael 21.10.: „kurz breiter“): Flügel neben der Notch bzw. Pillenbreite.
    static let wideWing: CGFloat = 130
    static let widePillWidth: CGFloat = 340
    /// Band: je Seite neben der Notch bzw. Gesamtbreite ohne Notch. Nicht bis an den Rand: Menüs der aktiven App
    /// und Menüleisten-Symbole blieben sonst verdeckt, und macOS verrät nicht, wo die Symbole beginnen.
    static let bandWing: CGFloat = 300
    static let bandPillWidth: CGFloat = 720
    /// Mitteilung (0.6.0): größte Form (Kopfzeile, Titel, Untertitel, zwei Zeilen Text, Knopfzeile); die Insel ist nur
    /// so hoch wie ihr Inhalt (`messageHeight`, Testbild 22.10.: fest 118 pt quetschte den Text auf eine Zeile).
    static let messageSize = CGSize(width: 460, height: 140)

    /// Höhe der Mitteilung ohne Notch-Streifen: Ränder 20, Kopfzeile 18, je Zeile Abstand 2 + Zeilenhöhe; Text zweizeilig
    /// ab etwa 60 Zeichen (≈ 394 pt bei 12 pt), Knopfzeile 4 + 24.
    static func messageHeight(title: Bool, subtitle: Bool, bodyChars: Int, buttons: Bool) -> CGFloat {
        var h: CGFloat = 20 + 18
        if title { h += 2 + 18 }
        if subtitle { h += 2 + 16 }
        if bodyChars > 0 { h += 2 + (bodyChars > 60 ? 32 : 16) }
        if buttons { h += 2 + 28 }
        return min(h, messageSize.height)
    }
    /// Anruf (0.6.0, Vorbild DynamicLake): eine Zeile mit Anrufer und zwei Knöpfen.
    static let callSize = CGSize(width: 400, height: 60)

    static func layout(for m: ScreenMetrics) -> Layout {
        let top = m.frame.maxY
        // `l + r < Breite`: sonst hätte die Notch Breite <= 0 (kaputte Messwerte) — dann lieber Pille.
        if m.safeTop > 0, let l = m.auxLeftWidth, let r = m.auxRightWidth, l + r < m.frame.width {
            // Die Notch ist die Lücke zwischen den beiden Seitenflächen. Sind die ungleich
            // breit, sitzt sie nicht mittig — Kompakt und Gross folgen ihr, nicht der Bildschirmmitte.
            let notch = CGRect(x: m.frame.minX + l, y: top - m.safeTop,
                               width: m.frame.width - l - r, height: m.safeTop)
            let compact = notch.insetBy(dx: -wing, dy: 0)
            return Layout(notch: notch, compact: compact,
                          expanded: band(expandedSize, midX: notch.midX, top: top, extraHeight: notch.height, in: m.frame),
                          notice: band(noticeSize, midX: notch.midX, top: top, extraHeight: notch.height, in: m.frame),
                          live: band(liveSize, midX: notch.midX, top: top, extraHeight: notch.height, in: m.frame),
                          wide: band(CGSize(width: notch.width + 2 * wideWing, height: 0), midX: notch.midX, top: top,
                                     extraHeight: notch.height, in: m.frame),
                          band: band(CGSize(width: notch.width + 2 * bandWing, height: 0), midX: notch.midX, top: top,
                                     extraHeight: notch.height, in: m.frame),
                          message: band(messageSize, midX: notch.midX, top: top, extraHeight: notch.height, in: m.frame),
                          call: band(callSize, midX: notch.midX, top: top, extraHeight: notch.height, in: m.frame),
                          shelfDrop: band(shelfDropSize, midX: notch.midX, top: top, extraHeight: notch.height, in: m.frame))
        }
        let midX = m.frame.midX
        let pill = CGRect(x: midX - pillSize.width / 2, y: top - pillSize.height,
                          width: pillSize.width, height: pillSize.height)
        return Layout(notch: nil, compact: pill,
                      expanded: band(expandedSize, midX: midX, top: top, extraHeight: 0, in: m.frame),
                      notice: band(noticeSize, midX: midX, top: top, extraHeight: 0, in: m.frame),
                      live: band(liveSize, midX: midX, top: top, extraHeight: 0, in: m.frame),
                      wide: band(CGSize(width: widePillWidth, height: pillSize.height), midX: midX, top: top,
                                 extraHeight: 0, in: m.frame),
                      band: band(CGSize(width: bandPillWidth, height: max(pillSize.height, m.menuBarHeight)), midX: midX,
                                 top: top, extraHeight: 0, in: m.frame),
                      message: band(messageSize, midX: midX, top: top, extraHeight: 0, in: m.frame),
                      call: band(callSize, midX: midX, top: top, extraHeight: 0, in: m.frame),
                      shelfDrop: band(shelfDropSize, midX: midX, top: top, extraHeight: 0, in: m.frame))
    }

    /// Rechteck oben bündig, mittig über `midX`, mit Notch um deren Höhe länger (Inhalt beginnt darunter).
    private static func band(_ size: CGSize, midX: CGFloat, top: CGFloat, extraHeight: CGFloat,
                             in frame: CGRect) -> CGRect {
        // Schmaler Bildschirm: Breite auf die Bildschirmbreite kürzen, sonst ragt die Insel hinaus.
        let width = min(size.width, frame.width)
        var x = midX - width / 2
        x = min(max(x, frame.minX), frame.maxX - width)
        let height = size.height + extraHeight
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    @MainActor
    static func metrics(of s: NSScreen) -> ScreenMetrics {
        let l = s.auxiliaryTopLeftArea?.width
        let r = s.auxiliaryTopRightArea?.width
        return ScreenMetrics(frame: s.frame, safeTop: s.safeAreaInsets.top, auxLeftWidth: l, auxRightWidth: r,
                             menuBarHeight: max(0, s.frame.maxY - s.visibleFrame.maxY))
    }
}
