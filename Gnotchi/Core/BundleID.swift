import Foundation

/// Plausibilitätsprüfung für Bundle-IDs aus nicht vertrauenswürdigen Quellen (Adapter-Strom, G4).
/// Übernommen aus Seam (`LinkRules.isBundleID`, 18.10.), gleiche Regeln: nicht leer, höchstens
/// 255 Zeichen, nur ASCII-Buchstaben/-Ziffern, Punkt und Bindestrich.
enum BundleID {
    static let maxLength = 255

    static func isValid(_ s: String) -> Bool {
        !s.isEmpty && s.count <= maxLength && s.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "." || $0 == "-"
        }
    }
}
