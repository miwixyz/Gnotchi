import CoreGraphics
import Foundation
import SwiftUI

/// 3 × 3-Perspektive, zeilenweise: x' = (a·x + b·y + c) / (g·x + h·y + i), y' = (d·x + e·y + f) / (…).
struct Homography: Equatable {
    var m: [Double]

    static let identity = Homography(m: [1, 0, 0, 0, 1, 0, 0, 0, 1])

    static func * (l: Homography, r: Homography) -> Homography {
        var o = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                o[i * 3 + j] = (0..<3).reduce(0) { $0 + l.m[i * 3 + $1] * r.m[$1 * 3 + j] }
            }
        }
        return Homography(m: o)
    }

    static func scale(_ s: Double) -> Homography { Homography(m: [s, 0, 0, 0, s, 0, 0, 0, 1]) }

    /// Drehung um `c` (Grad, im Uhrzeigersinn bei y nach unten).
    static func rotation(about c: CGPoint, degrees: Double) -> Homography {
        let a = degrees * .pi / 180, cs = cos(a), sn = sin(a)
        let x = Double(c.x), y = Double(c.y)
        return Homography(m: [cs, -sn, x - cs * x + sn * y, sn, cs, y - sn * x - cs * y, 0, 0, 1])
    }

    func apply(_ p: CGPoint) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        let w = m[6] * x + m[7] * y + m[8]
        return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / w, y: (m[3] * x + m[4] * y + m[5]) / w)
    }

    var inverse: Homography {
        let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        return Homography(m: [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
                              (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
                              (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det])
    }

    /// Für `projectionEffect` (SwiftUI rechnet mit Zeilenvektoren: m11 = a, m21 = b, m31 = c …).
    var projection: ProjectionTransform {
        var t = CATransform3DIdentity
        t.m11 = m[0]; t.m21 = m[1]; t.m41 = m[2]
        t.m12 = m[3]; t.m22 = m[4]; t.m42 = m[5]
        t.m14 = m[6]; t.m24 = m[7]; t.m44 = m[8]
        return ProjectionTransform(t)
    }
}

/// Perspektive der KI-Fotos, gemessen 27.10. mit tools/turntable-ebenen.py (Werte aus geometrie.json).
enum TurntableGeometry {
    /// Kreisbild-Pixel (Platte entzerrt, 1120 × 1120) → Gerätebild-Pixel (1991 × 1080).
    static let circle = Homography(m: [0.897294, -0.169567, 344.63746, 0.003421, 0.403474, 77.325742,
                                       0.00001, -0.000201, 1])
    /// Ebene (Plattenradius = 1, Mitte = Achse) → Gerätebild-Pixel.
    static let plane = Homography(m: [562.766637, -106.349502, 842.4, 2.14583, 253.051827, 341.8,
                                      0.006278, -0.126246, 1])
    static let circleSize: CGFloat = 1120
    /// Tonarmlager in Ebenen-Koordinaten.
    static let pivot = CGPoint(x: 1.29562, y: -0.41128)
    /// Armwinkel relativ zur Stellung im Spielfoto: Ablage, Einlaufrille (r = 0,93), Ende (r = 0,5).
    static let restAngle = -21.31
    static let outerAngle = 0.74
    static let innerAngle = 19.3
    /// Etikett-Radius in Plattenradien.
    static let labelRadius = 0.3159
    /// Nadel in der Spielstellung des Fotos (Ebene).
    static let needle = CGPoint(x: 0.55022, y: 0.77033)

    /// Bewegung des Arms mit der Platte (Michael 27.10.: „bewegt sich minimal mit dem Lauf der Platte“), gekoppelt an
    /// den Plattenwinkel – steht die Platte, steht der Arm. Der Arm selbst bewegt sich nur starr und kaum seitlich
    /// (Höhenschlag); die Welligkeit zeigt nur der Schatten (rückt näher/weiter). Erste Fassung kippte den Arm im Bild
    /// und verbog ihn – Michael: „zu viel … wirkt, als ob der Arm wabbelig ist“.
    /// `lateral` in Grad, `shadowShift` in Gerätebild-Pixeln.
    static func wobble(plateAngle: Double) -> (lateral: Double, shadowShift: Double) {
        let a = plateAngle * .pi / 180
        // ±0,18° war noch „zu stark“ (Michael 27.10.) → ein Drittel.
        let lateral = 0.06 * sin(a + 0.4) + 0.008 * sin(7 * a + 1.1)
        let shadowShift = 2.5 * sin(a + 1.9) + 0.6 * sin(2 * a + 0.3)
        return (lateral, shadowShift)
    }

    /// Schatten verschieben in Lichtrichtung (wie im Foto: nach links unten).
    static func shadowOffset(_ px: Double) -> Homography {
        Homography(m: [1, 0, -0.5 * px, 0, 1, 0.87 * px, 0, 0, 1])
    }

    /// Arm um das Lager gedreht, in Gerätebild-Pixeln.
    static func arm(_ degrees: Double) -> Homography {
        plane * .rotation(about: pivot, degrees: degrees) * plane.inverse
    }
}

/// Wo der Arm ist: 0 = Ablage, 1 = auf der Platte; dazu der Winkel auf der Platte nach Titelfortschritt.
struct TurntableArmMotion: Equatable {
    var from = 0.0
    var to = 0.0
    var start = Date.distantPast
    /// Titelwechsel: Arm fährt vom alten Winkel zur Einlaufrille.
    var retrackFrom: Double?
    var retrackStart = Date.distantPast
    static let swing: TimeInterval = 1.2
    static let retrack: TimeInterval = 1.6

    static func ease(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    func phase(at t: Date) -> Double {
        from + (to - from) * Self.ease(t.timeIntervalSince(start) / Self.swing)
    }

    /// Start (auf die Platte) bzw. Pause (in die Ablage) – ohne Sprung, auch mitten im Schwenk.
    func switched(toPlaying playing: Bool, at t: Date) -> TurntableArmMotion {
        let target = playing ? 1.0 : 0.0
        guard target != to else { return self }
        var next = self
        next.from = phase(at: t)
        next.to = target
        next.start = t
        return next
    }

    /// Winkel auf der Platte: außen → innen über den Titel; nach einem Titelwechsel weich zurück.
    func needleAngle(progress: Double, at t: Date) -> Double {
        let p = min(1, max(0, progress.isFinite ? progress : 0))
        let target = TurntableGeometry.outerAngle + p * (TurntableGeometry.innerAngle - TurntableGeometry.outerAngle)
        guard let from = retrackFrom else { return target }
        let f = Self.ease(t.timeIntervalSince(retrackStart) / Self.retrack)
        return from + (target - from) * f
    }

    func retracked(from angle: Double, at t: Date) -> TurntableArmMotion {
        var next = self
        next.retrackFrom = angle
        next.retrackStart = t
        return next
    }

    func moving(at t: Date) -> Bool {
        t.timeIntervalSince(start) < Self.swing || (retrackFrom != nil && t.timeIntervalSince(retrackStart) < Self.retrack)
    }
}
