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
    }

    /// Platz links (Cover) und rechts (Pegel) neben der Notch.
    static let wing: CGFloat = 40
    static let pillSize = CGSize(width: 180, height: 24)
    /// Inhaltsfläche der grossen Ansicht. Mit Notch kommt deren Höhe oben dazu: Die Hardware-Notch
    /// verdeckt den oberen Streifen (Sichtprüfung 18.10.: 110 pt inkl. Notch reichten nicht).
    static let expandedSize = CGSize(width: 460, height: 110)
    /// Spiegel (0.5.0): Inhaltshöhe statt 110 – Bild 16:9 über die Breite (428 × 240) plus Rand.
    static let mirrorHeight: CGFloat = 256   // 0.5.0: 380 → 460 (Michael 21.10.: „breiter“)
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
                                     extraHeight: notch.height, in: m.frame))
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
                                 top: top, extraHeight: 0, in: m.frame))
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
