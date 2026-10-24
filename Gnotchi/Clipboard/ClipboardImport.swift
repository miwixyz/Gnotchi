import AppKit
import CryptoKit
import Foundation

/// Einmaliger Import aus PastePal (0.11.0, docs/SECURE-DESIGN.md G41): nur Sammlungen und ihre Einträge, kein Verlauf.
/// Datei nur über Michaels Auswahl, strikt dekodiert, begrenzt; Werte erscheinen nie in Vorschau oder Protokoll.
/// Gemessen 24.10. am echten Export: `string` = nur reiner Text (Formatdaten fehlen), `createdAt` = Sekunden ab 2001.
enum PastePalImport {
    static let maxFileBytes = 50_000_000
    static let maxItems = 10_000
    static let maxTextBytes = ClipboardCapture.maxTextBytes

    struct Export: Decodable {
        let folders: [PastePalFolder]
        let items: [PastePalItem]
    }

    /// Vorschau ohne Inhalte: Sammlung → Anzahl Einträge.
    struct Plan {
        let collections: [PastePalPlanCollection]
        let skipped: Int
    }

    enum ImportError: Error, Equatable {
        case tooLarge, unreadable, tooManyItems
    }

    static func plan(from data: Data) throws -> Plan {
        guard data.count <= maxFileBytes else { throw ImportError.tooLarge }
        guard let export = try? JSONDecoder().decode(Export.self, from: data) else { throw ImportError.unreadable }
        guard export.items.count <= maxItems else { throw ImportError.tooManyItems }
        var skipped = 0
        var byFolder: [String: [(String, Date)]] = [:]
        for item in export.items {
            guard let text = item.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count <= maxTextBytes, let folder = item.collectionId else { skipped += 1; continue }
            let date = item.createdAt.map { Date(timeIntervalSinceReferenceDate: $0) } ?? Date()
            byFolder[folder, default: []].append((text, date))
        }
        let collections = export.folders.compactMap { f -> PastePalPlanCollection? in
            let name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return PastePalPlanCollection(id: f.id, name: String(name.prefix(100)), color: color(f.color),
                                   symbol: symbol(f.icon), items: byFolder[f.id] ?? [])
        }
        let known = Set(collections.map(\.id))
        skipped += byFolder.filter { !known.contains($0.key) }.values.reduce(0) { $0 + $1.count }
        return Plan(collections: collections, skipped: skipped)
    }

    /// Feste Zuordnung; Unbekanntes → Standard.
    static func color(_ raw: String?) -> ClipColor {
        switch raw?.lowercased() {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "teal", "mint", "cyan": .teal
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        default: .gray
        }
    }

    /// PastePal-eigene Symbolnamen → SF Symbols (gemessen am echten Export); echte SF-Namen bleiben.
    static func symbol(_ raw: String?) -> String {
        switch raw {
        case "pc": "desktopcomputer"
        case "magic": "wand.and.stars"
        case "book-open": "book"
        case "bookmark": "bookmark"
        case let name? where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil: name
        default: "folder"
        }
    }

    /// Alles oder nichts (G41): erst alles vormerken, dann einmal sichern; jeder Fehler verwirft den ganzen Import.
    @MainActor
    static func run(_ plan: Plan, vaultIDs: Set<String>, store: ClipboardStore, vaultKey: SymmetricKeyProvider?) throws -> Int {
        var count = 0
        let start = (store.collections().map(\.sortIndex).max() ?? 0) + 1
        do {
            for (offset, collection) in plan.collections.enumerated() {
                let isVault = vaultIDs.contains(collection.id)
                let target = store.stageCollection(name: collection.name, color: isVault ? .red : collection.color,
                                                   symbol: isVault ? "lock.fill" : collection.symbol, isVault: isVault,
                                                   sortIndex: start + Double(offset))
                for item in collection.items {
                    let payload = ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data(item.text.utf8))],
                                              plain: item.text)
                    let kind: ClipKind = ClipboardCapture.isSingleWebURL(item.text) ? .link : .text
                    if isVault {
                        guard let key = vaultKey?.key else { throw ClipboardStore.StoreError.needsVaultKey }
                        let draft = ClipboardStore.VaultDraft(payload: payload, kind: kind,
                                                              title: VaultTitles.suggest(item.text), createdAt: item.createdAt)
                        try store.stageVaultImport(draft, to: target, vaultKey: key)
                    } else {
                        try store.stageImport(payload, kind: kind, to: target, createdAt: item.createdAt)
                    }
                    count += 1
                }
            }
            try store.commitImport()
        } catch {
            store.rollbackImport()
            throw error
        }
        return count
    }
}

/// Tresor-Schlüssel für den Import (einmal Touch ID für alle Tresor-Sammlungen).
struct SymmetricKeyProvider {
    let key: SymmetricKey
}

struct PastePalFolder: Decodable {
    let id: String
    let name: String
    let icon: String?
    let color: String?
    let createdAt: Double?
}

struct PastePalItem: Decodable {
    let id: String?
    let string: String?
    let createdAt: Double?
    let collectionId: String?
    let appBundleId: String?
}

struct PastePalPlanCollection: Identifiable {
    let id: String
    let name: String
    let color: ClipColor
    let symbol: String
    let items: [(text: String, createdAt: Date)]
}
