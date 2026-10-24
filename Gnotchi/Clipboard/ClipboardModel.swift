import CryptoKit
import Foundation
import SwiftData

/// Datenmodell des Zwischenablage-Verlaufs (0.11.0, docs/SECURE-DESIGN.md G38).
///
/// CloudKit-tauglich ab Tag 1 (Abgleich kommt in einer späteren Version): alle Eigenschaften mit Standardwert oder
/// optional, kein `.unique`, Beziehungen optional. Inhalt und Titel liegen nur verschlüsselt vor (`sealed…`);
/// im Klartext stehen nur Zeitstempel, Art, Quell-App, Sammlungs-Zugehörigkeit und Sortierung.
@Model
final class ClipEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    /// Zuletzt kopiert oder benutzt – bestimmt Reihenfolge und Ablauf nach 30 Tagen.
    var lastUsedAt: Date = Date()
    var kindRaw: String = ClipKind.text.rawValue
    var sourceBundleID: String?
    /// Tresor-Eintrag: Inhalt mit dem Tresor-Schlüssel verschlüsselt (G39).
    var isVault: Bool = false
    /// AES-GCM über `ClipPayload` (Formate + reiner Text), AAD = `id`. Große Bilder lagert SwiftData aus.
    @Attribute(.externalStorage) var sealedPayload: Data?
    /// AES-GCM über den Titel (immer mit dem Verlauf-Schlüssel, damit die Suche Tresor-Titel findet).
    var sealedTitle: Data?
    /// Schlüsselgebundener Fingerabdruck (HMAC) zum Erkennen erneuter Kopien – verrät ohne Schlüssel nichts.
    var fingerprint: Data?
    var byteCount: Int = 0
    @Relationship(inverse: \ClipCollection.entries) var collections: [ClipCollection]? = []

    init(id: UUID = UUID(), kind: ClipKind, sourceBundleID: String?, isVault: Bool = false) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.sourceBundleID = sourceBundleID
        self.isVault = isVault
    }

    var kind: ClipKind { ClipKind(rawValue: kindRaw) ?? .text }
    /// In keiner Sammlung (auch nicht „Angeheftet“) → läuft nach 30 Tagen bzw. jenseits von 1 000 ab.
    var isLoose: Bool { (collections ?? []).isEmpty }
}

@Model
final class ClipCollection {
    var id: UUID = UUID()
    var name: String = ""
    var colorRaw: String = ClipColor.blue.rawValue
    var symbol: String = "folder"
    var sortIndex: Double = 0
    /// Die feste erste Sammlung „Angeheftet“ (genau eine).
    var isPinned: Bool = false
    /// Tresor-Sammlung (G39): Einträge darin sind Tresor-Einträge.
    var isVault: Bool = false
    var createdAt: Date = Date()
    var entries: [ClipEntry]? = []

    init(name: String, color: ClipColor, symbol: String, sortIndex: Double, isPinned: Bool = false, isVault: Bool = false) {
        self.name = name
        self.colorRaw = color.rawValue
        self.symbol = symbol
        self.sortIndex = sortIndex
        self.isPinned = isPinned
        self.isVault = isVault
    }

    var color: ClipColor { ClipColor(rawValue: colorRaw) ?? .blue }
}

enum ClipKind: String, Codable, CaseIterable {
    case text, richText, link, image, file
}

enum ClipColor: String, CaseIterable, Codable {
    case red, orange, yellow, green, teal, blue, indigo, purple, pink, gray
}

/// Was in `sealedPayload` steckt. Binär-Plist (keine ausführbaren Typen, G40).
struct ClipPayload: Codable, Equatable {
    struct Format: Codable, Equatable {
        let type: String
        let data: Data
    }
    var formats: [Format]
    /// Reiner Text für Vorschau, Suche und „als reiner Text einfügen“ (bei Bildern leer).
    var plain: String
}

/// AES-GCM je Feld, Datensatz-ID als zusätzliche authentifizierte Daten (G38): ein Chiffrat lässt sich nicht
/// unbemerkt einem anderen Eintrag unterschieben.
enum ClipCrypto {
    enum CryptoError: Error { case sealFailed }

    static func seal(_ data: Data, key: SymmetricKey, id: UUID) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key, authenticating: aad(id)).combined else {
            throw CryptoError.sealFailed
        }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey, id: UUID) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: aad(id))
    }

    static func sealPayload(_ payload: ClipPayload, key: SymmetricKey, id: UUID) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try seal(encoder.encode(payload), key: key, id: id)
    }

    static func openPayload(_ sealed: Data, key: SymmetricKey, id: UUID) throws -> ClipPayload {
        try PropertyListDecoder().decode(ClipPayload.self, from: open(sealed, key: key, id: id))
    }

    static func sealString(_ text: String, key: SymmetricKey, id: UUID) throws -> Data {
        try seal(Data(text.utf8), key: key, id: id)
    }

    static func openString(_ sealed: Data, key: SymmetricKey, id: UUID) throws -> String {
        String(bytes: try open(sealed, key: key, id: id), encoding: .utf8) ?? ""
    }

    /// Fingerabdruck für „gleicher Inhalt erneut kopiert“: HMAC über alle Formate, schlüsselgebunden.
    static func fingerprint(_ payload: ClipPayload, key: SymmetricKey) -> Data {
        var hmac = HMAC<SHA256>(key: key)
        for format in payload.formats.sorted(by: { $0.type < $1.type }) {
            hmac.update(data: Data(format.type.utf8))
            hmac.update(data: withUnsafeBytes(of: UInt64(format.data.count).bigEndian) { Data($0) })
            hmac.update(data: format.data)
        }
        return Data(hmac.finalize())
    }

    private static func aad(_ id: UUID) -> Data { Data(id.uuidString.utf8) }
}
