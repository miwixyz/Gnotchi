import AppKit

/// Wo die Insel liegt. Reine Rechnung, getestet; `metrics(of:)` liest nur NSScreen.
/// Koordinaten: AppKit (Ursprung unten links), wie `NSScreen.frame`.
enum IslandGeometry {

    struct ScreenMetrics: Equatable {
        let frame: CGRect
        let safeTop: CGFloat
        let auxLeftWidth: CGFloat?
        let auxRightWidth: CGFloat?
    }

    struct Layout: Equatable {
        /// nil = Bildschirm ohne Notch.
        let notch: CGRect?
        let compact: CGRect
        let expanded: CGRect
    }

    /// Platz links (Cover) und rechts (Pegel) neben der Notch.
    static let wing: CGFloat = 40
    static let pillSize = CGSize(width: 180, height: 24)
    static let expandedSize = CGSize(width: 380, height: 110)

    static func layout(for m: ScreenMetrics) -> Layout {
        let top = m.frame.maxY
        // `l + r < Breite`: sonst hätte die Notch Breite <= 0 (kaputte Messwerte) — dann lieber Pille.
        if m.safeTop > 0, let l = m.auxLeftWidth, let r = m.auxRightWidth, l + r < m.frame.width {
            // Die Notch ist die Lücke zwischen den beiden Seitenflächen. Sind die ungleich
            // breit, sitzt sie nicht mittig — Kompakt und Gross folgen ihr, nicht der Bildschirmmitte.
            let notch = CGRect(x: m.frame.minX + l, y: top - m.safeTop,
                               width: m.frame.width - l - r, height: m.safeTop)
            let compact = notch.insetBy(dx: -wing, dy: 0)
            return Layout(notch: notch, compact: compact, expanded: expanded(midX: notch.midX, top: top, in: m.frame))
        }
        let midX = m.frame.midX
        let pill = CGRect(x: midX - pillSize.width / 2, y: top - pillSize.height,
                          width: pillSize.width, height: pillSize.height)
        return Layout(notch: nil, compact: pill, expanded: expanded(midX: midX, top: top, in: m.frame))
    }

    private static func expanded(midX: CGFloat, top: CGFloat, in frame: CGRect) -> CGRect {
        // Schmaler Bildschirm: Breite auf die Bildschirmbreite kürzen, sonst ragt die Insel hinaus.
        let width = min(expandedSize.width, frame.width)
        var x = midX - width / 2
        x = min(max(x, frame.minX), frame.maxX - width)
        return CGRect(x: x, y: top - expandedSize.height, width: width, height: expandedSize.height)
    }

    @MainActor
    static func metrics(of s: NSScreen) -> ScreenMetrics {
        let l = s.auxiliaryTopLeftArea?.width
        let r = s.auxiliaryTopRightArea?.width
        return ScreenMetrics(frame: s.frame, safeTop: s.safeAreaInsets.top, auxLeftWidth: l, auxRightWidth: r)
    }
}
