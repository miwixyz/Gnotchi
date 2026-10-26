import Foundation

/// Farbcode in einer Kopie erkennen (0.14.0, specs/2026-10-26-gnotchi-0.14.0-kartenbild.md). Rein, getestet.
///
/// Nur wenn die **ganze** Kopie (nach Trimmen) ein Farbcode ist: `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`,
/// `rgb(…)`, `rgba(…)`, `hsl(…)`, `hsla(…)`. Höchstens 64 Zeichen, verankerte einfache Muster (Fremdtext).
struct ColorCode: Equatable {
    /// Komponenten 0…1.
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let maxLength = 64

    /// Hex-Darstellung `#RRGGBB` (ohne Alpha) für die Karte.
    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }

    /// Wahrgenommene Helligkeit (Rec. 709) – für helle bzw. dunkle Schrift auf der Karte.
    var isLight: Bool { 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6 }

    static func parse(_ text: String) -> ColorCode? {
        guard text.count <= maxLength * 2 else { return nil }
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty, s.count <= maxLength else { return nil }
        if s.hasPrefix("#") { return hex(String(s.dropFirst())) }
        if let args = arguments(s, names: ["rgba", "rgb"]) { return rgb(args) }
        if let args = arguments(s, names: ["hsla", "hsl"]) { return hsl(args) }
        return nil
    }

    // MARK: - Intern

    private static func hex(_ h: String) -> ColorCode? {
        guard [3, 4, 6, 8].contains(h.count), h.allSatisfy(\.isHexDigit) else { return nil }
        let digits = h.count <= 4 ? h.map { "\($0)\($0)" }.joined() : h
        var values: [Double] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let v = UInt8(digits[index..<next], radix: 16) else { return nil }
            values.append(Double(v) / 255)
            index = next
        }
        return ColorCode(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1)
    }

    /// `name(a, b, c[, d])` oder `name(a b c[ / d])` → Argumente als Text, sonst nil.
    private static func arguments(_ s: String, names: [String]) -> [String]? {
        guard let name = names.first(where: { s.hasPrefix($0 + "(") }), s.hasSuffix(")") else { return nil }
        let inner = s.dropFirst(name.count + 1).dropLast()
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
        return (3...4).contains(parts.count) ? parts : nil
    }

    private static func rgb(_ a: [String]) -> ColorCode? {
        let channels = a.prefix(3).compactMap { channel($0, max: 255) }
        guard channels.count == 3, let alpha = alpha(a) else { return nil }
        return ColorCode(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    private static func hsl(_ a: [String]) -> ColorCode? {
        guard let h = number(a[0].replacingOccurrences(of: "deg", with: "")), (0...360).contains(h),
              let s = percent(a[1]), let l = percent(a[2]), let alpha = alpha(a) else { return nil }
        // Standard-Umrechnung HSL → RGB.
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let rgb: [Double] = switch h {
        case ..<60: [c, x, 0]
        case ..<120: [x, c, 0]
        case ..<180: [0, c, x]
        case ..<240: [0, x, c]
        case ..<300: [x, 0, c]
        default: [c, 0, x]
        }
        return ColorCode(red: rgb[0] + m, green: rgb[1] + m, blue: rgb[2] + m, alpha: alpha)
    }

    /// 0…max oder 0…100 % → 0…1.
    private static func channel(_ t: String, max: Double) -> Double? {
        if t.hasSuffix("%") { return percent(t) }
        guard let v = number(t), (0...max).contains(v) else { return nil }
        return v / max
    }

    private static func percent(_ t: String) -> Double? {
        guard t.hasSuffix("%"), let v = number(String(t.dropLast())), (0...100).contains(v) else { return nil }
        return v / 100
    }

    private static func alpha(_ a: [String]) -> Double? {
        guard a.count == 4 else { return 1 }
        if a[3].hasSuffix("%") { return percent(a[3]) }
        guard let v = number(a[3]), (0...1).contains(v) else { return nil }
        return v
    }

    private static func number(_ t: String) -> Double? {
        guard !t.isEmpty, t.count <= 8, t.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Double(t)
    }
}
