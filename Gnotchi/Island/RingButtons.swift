import CoreGraphics
import Foundation

/// Tasten-Ring (0.28.0, specs/2026-11-15-gnotchi-0.28.0-tasten-ring.md): runde Glas-Tasten um die schwebende große
/// Insel statt kleiner Symbole in der Leiste. Reine Rechnungen, getestet (RingButtonsTests); die Ansicht steht in
/// `IslandView+Ring`, die Tasten-Aktionen in `ActivityModel+Ring`.
enum RingButton: String, CaseIterable, Sendable, Hashable {
    // Bisherige Werkzeug-Symbole der Leiste – nur der Ort ist neu.
    case timer, awake, mirror, weather, shelf, clipboard
    /// Schnelleingabe (G61): neuer Termin oder neue Erinnerung. Nur sichtbar mit eingeschalteter Schnelleingabe.
    case quickEntry
    /// Mixer groß in der Insel (0.30.0), ab Werk an.
    case mixer
    case pin
    /// Neue Tasten mit Nebenwirkung (0.28.0): ab Werk aus.
    case mic, screenshot, speedtest
    case settings

    enum Side: Sendable { case left, right, bottomLeading, bottomTrailing }

    /// Links Timer-Werkzeuge, rechts Inhalte, unten Insel-Steuerung (Spec Punkt 3).
    var side: Side {
        switch self {
        case .timer, .awake, .mirror, .quickEntry: .left
        case .weather, .shelf, .clipboard, .mixer: .right
        case .pin, .mic, .screenshot, .speedtest: .bottomLeading
        case .settings: .bottomTrailing
        }
    }

    /// Name für Einstellungen und Bedienungshilfen.
    var label: String {
        switch self {
        case .timer: "Timer"
        case .awake: "Wach bleiben"
        case .mirror: "Spiegel"
        case .weather: "Wetter"
        case .shelf: "Ablage"
        case .clipboard: "Zwischenablage"
        case .quickEntry: "Neuer Eintrag"
        case .mixer: "Mixer"
        case .pin: "Anheften"
        case .mic: "Mikrofon stumm"
        case .screenshot: "Bildschirmfoto"
        case .speedtest: "Geschwindigkeitstest"
        case .settings: "Einstellungen"
        }
    }

    /// Ab Werk eingeschaltet: alle bisherigen Werkzeuge. Neue Tasten mit Nebenwirkung kommen ab Werk aus (Spec Punkt 9).
    var onByDefault: Bool {
        switch self {
        case .mic, .screenshot, .speedtest: false
        default: true
        }
    }

    /// Anheften und Einstellungen lassen sich nicht abwählen (Spec Punkt 9).
    var alwaysOn: Bool { self == .pin || self == .settings }

    /// Gespeicherte Kennungen → Tasten: nur bekannte, ohne Doppelte; per `defaults write` Eingeschleustes fällt weg.
    nonisolated static func valid(_ stored: Any?) -> Set<RingButton>? {
        guard let list = stored as? [Any] else { return nil }
        return Set(list.compactMap { ($0 as? String).flatMap(RingButton.init(rawValue:)) })
    }

    nonisolated static var defaults: Set<RingButton> { Set(allCases.filter(\.onByDefault)) }
}

enum Ring {
    /// Durchmesser einer Taste, Abstand zur Insel und Abstand der Tasten untereinander (Spec Punkt 2).
    static let button: CGFloat = 40
    static let gap: CGFloat = 10
    static let spacing: CGFloat = 10

    /// Zusätzlicher Platz, den der Ring dem Panel gibt: seitlich je Seite (symmetrisch, damit die Insel mittig bleibt)
    /// und unten.
    struct Margins: Equatable, Sendable {
        var side: CGFloat
        var bottom: CGFloat
        static let zero = Margins(side: 0, bottom: 0)
    }

    /// Welche Tasten stehen im Ring: eingeschaltet **und** verfügbar (ihre Funktion ist an bzw. hat etwas zu zeigen),
    /// in der festen Reihenfolge von `RingButton.allCases`. Anheften und Einstellungen sind immer da.
    nonisolated static func visible(enabled: Set<RingButton>, available: Set<RingButton>) -> [RingButton] {
        RingButton.allCases.filter { ($0.alwaysOn || enabled.contains($0)) && ($0.alwaysOn || available.contains($0)) }
    }

    /// Platz jeder Taste, Ursprung oben links an der Insel, y nach unten (SwiftUI-Richtung). Links und rechts je eine
    /// Spalte von oben nach unten, unten eine Reihe: vorn von links, hinten rechtsbündig.
    nonisolated static func rects(buttons: [RingButton], island: CGSize) -> [RingButton: CGRect] {
        var counts: [RingButton.Side: Int] = [:]
        var result: [RingButton: CGRect] = [:]
        let step = button + spacing
        for b in buttons {
            let i = counts[b.side, default: 0]
            counts[b.side] = i + 1
            let origin: CGPoint
            switch b.side {
            case .left: origin = CGPoint(x: -(gap + button), y: CGFloat(i) * step)
            case .right: origin = CGPoint(x: island.width + gap, y: CGFloat(i) * step)
            case .bottomLeading: origin = CGPoint(x: CGFloat(i) * step, y: island.height + gap)
            case .bottomTrailing: origin = CGPoint(x: island.width - button - CGFloat(i) * step, y: island.height + gap)
            }
            result[b] = CGRect(origin: origin, size: CGSize(width: button, height: button))
        }
        return result
    }

    /// Randzugabe fürs Panel: seitlich, wenn links oder rechts eine Taste steht; unten, soweit Tasten unter die Insel
    /// ragen (die Reihe unten, oder eine Spalte, die länger ist als die Insel hoch).
    nonisolated static func margins(buttons: [RingButton], island: CGSize) -> Margins {
        let rects = rects(buttons: buttons, island: island)
        let hasSide = buttons.contains { $0.side == .left || $0.side == .right }
        let bottom = rects.values.map { $0.maxY - island.height }.max() ?? 0
        return Margins(side: hasSide ? gap + button : 0, bottom: max(0, bottom))
    }
}

extension Ring {
    /// Fläche, über der die Insel offen bleibt: jede Taste samt Lücke zur Insel und zu den Nachbartasten, in
    /// Bildschirmkoordinaten (AppKit, y nach oben). `island` ist das Rechteck der Insel auf dem Bildschirm.
    nonisolated static func zones(buttons: [RingButton], island: CGRect) -> [CGRect] {
        rects(buttons: buttons, island: island.size).values.map { r in
            CGRect(x: island.minX + r.minX, y: island.maxY - r.maxY, width: r.width, height: r.height)
                .insetBy(dx: -gap, dy: -gap)
        }
    }
}

/// Was die Insel für den Ring braucht: Inselgröße, sichtbare Tasten, Randzugabe. **Eine** Rechnung für Panel
/// (Controller) und Ansicht, damit Fenster und Form nie auseinanderlaufen (Falle 0.21.0).
struct RingLayout: Equatable, Sendable {
    var island: CGSize
    var buttons: [RingButton]
    var margins: Ring.Margins

    /// Panel ohne Schattenrand: Insel plus Randzugabe.
    var outerSize: CGSize {
        CGSize(width: island.width + 2 * margins.side, height: island.height + margins.bottom)
    }
}

extension RingButton.Side: Hashable {}
