import AppKit
import SwiftUI

/// Abgekoppelte große Insel (0.22.0, Spezifikation `specs/2026-11-06-gnotchi-0.22.0-abgekoppelte-insel.md`): schwebt mit
/// Lücke unter Notch bzw. Pille, verschiebbar. Reine Rechnungen (getestet) und die gemerkte Lage.
/// Koordinaten: AppKit (Ursprung unten links). „Insel“ = sichtbare Form, „Panel“ = Insel plus Schattenrand `pad`.
enum DetachedIsland {
    /// Lücke zwischen Unterkante Notch/Pille und Oberkante der Insel in der Grundlage (Michael 06.11.).
    static let gap: CGFloat = 8
    /// Näher als das an der Grundlage losgelassen → rastet dort ein.
    static let snap: CGFloat = 24
    /// Einheitliche Breite aller großen Ansichten (Michael 06.11.).
    static let width: CGFloat = 600
    /// Schattenrand rund um die Insel im Panel.
    static let pad: CGFloat = 20
    static let corner: CGFloat = 22
    /// Schwarz-Anteil der Glas-Tönung: genug für weiße Schrift über hellem Hintergrund, wenig genug, dass es Glas bleibt.
    static let glassTint: Double = 0.2
    /// Zeit nach dem Aufgehen, die Insel mit der Maus zu erreichen (Muster Band, `collapseDelayAfterBandShrink`).
    static let grace: Duration = .milliseconds(1500)

    /// Grundgerüst ohne Notch: Die schwebende Insel hat keinen verdeckten Streifen oben, ihr Inhalt beginnt am Rand.
    static let base = IslandGeometry.Layout(
        notch: nil, compact: .zero,
        expanded: CGRect(origin: .zero, size: IslandGeometry.expandedSize),
        notice: CGRect(origin: .zero, size: IslandGeometry.noticeSize), live: .zero)

    /// Oberkante-Mitte der Insel in der Grundlage: mittig unter der kleinen Insel, `gap` darunter.
    nonisolated static func baseTop(compact: CGRect) -> CGPoint {
        CGPoint(x: compact.midX, y: compact.minY - gap)
    }

    /// Insel-Rechteck: Grundlage + Versatz, wächst von der Oberkante nach unten, in `visible` hineingeschoben.
    /// Der gespeicherte Versatz bleibt dabei unverändert (Entschieden 3).
    nonisolated static func frame(compact: CGRect, size: CGSize, offset: CGSize, visible: CGRect) -> CGRect {
        let top = baseTop(compact: compact)
        let w = min(size.width, visible.width), h = min(size.height, visible.height)
        var x = top.x + offset.width - w / 2
        var y = top.y + offset.height - h
        x = min(max(x, visible.minX), visible.maxX - w)
        y = min(max(y, visible.minY), visible.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Versatz aus der losgelassenen Lage; nah an der Grundlage → 0 (Einrasten).
    nonisolated static func offset(island: CGRect, compact: CGRect) -> CGSize {
        let top = baseTop(compact: compact)
        let o = CGSize(width: island.midX - top.x, height: island.maxY - top.y)
        return hypot(o.width, o.height) <= snap ? .zero : o
    }

    /// Fläche, über der die Insel offen bleibt: kleine Insel, große Insel und – nur in der Grundlage – die Lücke dazwischen.
    nonisolated static func zones(compact: CGRect, island: CGRect?) -> [CGRect] {
        guard let island else { return [compact] }
        var result = [compact, island]
        if island.maxY <= compact.minY, island.minX <= compact.midX, compact.midX <= island.maxX {
            let left = max(compact.minX, island.minX), right = min(compact.maxX, island.maxX)
            result.append(CGRect(x: left, y: island.maxY, width: right - left, height: compact.minY - island.maxY))
        }
        return result
    }

    nonisolated static func contains(_ p: CGPoint, _ zones: [CGRect]) -> Bool {
        zones.contains { $0.insetBy(dx: -0.5, dy: -0.5).contains(p) }
    }

    /// Wo die Insel beim Aufgehen herkommt (Feder aus Richtung Pille): Mitte der kleinen Insel relativ zum Panel,
    /// in SwiftUI-Richtung (y = 0 oben). Darf außerhalb von 0…1 liegen.
    nonisolated static func growAnchor(compact: CGRect, panel: CGRect) -> UnitPoint {
        guard panel.width > 0, panel.height > 0 else { return .top }
        return UnitPoint(x: (compact.midX - panel.minX) / panel.width, y: (panel.maxY - compact.midY) / panel.height)
    }

    // MARK: Gemerkte Lage – eine für alle Bildschirme (Entschieden 3)

    static let offsetXKey = "islandOffsetX"
    static let offsetYKey = "islandOffsetY"

    static func offset(in defaults: UserDefaults = .standard) -> CGSize {
        let x = defaults.double(forKey: offsetXKey), y = defaults.double(forKey: offsetYKey)
        guard x.isFinite, y.isFinite, abs(x) < 20_000, abs(y) < 20_000 else { return .zero }
        return CGSize(width: x, height: y)
    }

    static func setOffset(_ o: CGSize, in defaults: UserDefaults = .standard) {
        if o == .zero {
            defaults.removeObject(forKey: offsetXKey)
            defaults.removeObject(forKey: offsetYKey)
        } else {
            defaults.set(Double(o.width), forKey: offsetXKey)
            defaults.set(Double(o.height), forKey: offsetYKey)
        }
    }
}

extension IslandController {
    /// Größe der schwebenden Insel – **eine** Rechnung für Panel (Controller) und Form (IslandView), damit Fenster und
    /// Form nie auseinanderlaufen (Falle 0.21.0: Fenster 310 pt, Form 200 pt).
    @MainActor
    static func detachedSize(_ activity: ActivityModel) -> CGSize {
        let r = bigFrame(layout: DetachedIsland.base, small: activity.bigContent == .privacy, chipRow: activity.showsChipRow,
                         mirror: activity.mirrorActive, weather: activity.bigContent == .weather,
                         shelf: activity.bigContent == .shelf, strip: activity.showsShelfStrip,
                         clipboard: activity.bigContent == .clipboard, tall: tallHeight(activity.bigContent))
        return CGSize(width: DetachedIsland.width, height: r?.height ?? IslandGeometry.expandedSize.height)
    }
}
