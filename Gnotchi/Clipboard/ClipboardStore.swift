import CryptoKit
import Foundation
import Observation
import os
import SwiftData

/// Verlauf, Sammlungen und Tresor (0.11.0, docs/SECURE-DESIGN.md G37–G39).
///
/// Auf der Platte nur Chiffrat (SwiftData-Datei im eigenen Ordner, `0700`). Entschlüsselt wird beim Laden in den
/// Speicher – Tresor-Inhalte nie, die gibt es nur mit dem Tresor-Schlüssel (Touch ID) und nur für den Moment.
@MainActor
@Observable
final class ClipboardStore {
    static let maxLoose = 1_000
    static let maxAge: TimeInterval = 30 * 24 * 3600

    /// Steigt bei jeder Änderung – die Ansichten lesen ihn, um neu zu zeichnen.
    private(set) var revision = 0

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let key: SymmetricKey
    @ObservationIgnored private var payloads: [UUID: ClipPayload] = [:]
    @ObservationIgnored private var titles: [UUID: String] = [:]
    /// 0.13.0 (G43): erkannte Art je Eintrag, nur im Speicher, immer zusammen mit `payloads` gefüllt und geleert.
    @ObservationIgnored private var secretKinds: [UUID: String] = [:]
    /// Erkennung an seit … (nil = aus). Für Altbestand zählt die Restzeit frühestens ab hier (G43).
    var secretsSince: Date? { didSet { revision += 1 } }
    static var secretLifetime: TimeInterval {
        #if DEBUG
        // Mess-Schalter nur in der Testfassung (wie debugVaultOpenSeconds):
        // `defaults write dev.mwlr.gnotchi debugSecretSeconds 20`
        if let seconds = UserDefaults.standard.object(forKey: "debugSecretSeconds") as? Double { return seconds }
        #endif
        return 5 * 60
    }
    @ObservationIgnored private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "zwischenablage")

    /// `directory == nil` → nur im Speicher (Tests).
    init(directory: URL?, key: SymmetricKey) throws {
        self.key = key
        let schema = Schema([ClipEntry.self, ClipCollection.self])
        let configuration: ModelConfiguration
        if let directory {
            try Self.prepare(directory)
            configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "Verlauf.store"),
                                               cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
        ensurePinned()
        loadCaches()
    }

    /// Standardort: ~/Library/Application Support/Gnotchi/Zwischenablage (nur für Michael lesbar).
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Gnotchi/Zwischenablage", directoryHint: .isDirectory)
    }

    private static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    // MARK: - Lesen

    /// Verlauf (`collection == nil`: alle Nicht-Tresor-Einträge) oder eine Sammlung, neueste zuerst, gefiltert.
    func entries(in collection: ClipCollection? = nil, matching query: String = "") -> [ClipEntry] {
        _ = revision
        let base: [ClipEntry]
        if let collection {
            base = collection.entries ?? []
        } else {
            base = (try? context.fetch(FetchDescriptor<ClipEntry>(predicate: #Predicate { !$0.isVault }))) ?? []
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return base
            .filter { needle.isEmpty || matches($0, needle) }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    /// Suche: Titel immer, Inhalt nur außerhalb des Tresors (G39). Erkannte Geheimnisse nur über die Art (G43).
    private func matches(_ entry: ClipEntry, _ needle: String) -> Bool {
        if let title = titles[entry.id], title.localizedStandardContains(needle) { return true }
        if let kind = secretKind(entry) { return kind.localizedStandardContains(needle) }
        guard !entry.isVault, let plain = payloads[entry.id]?.plain else { return false }
        return plain.localizedStandardContains(needle)
    }

    func collections() -> [ClipCollection] {
        _ = revision
        let all = (try? context.fetch(FetchDescriptor<ClipCollection>())) ?? []
        return all.sorted { ($0.isPinned ? 0 : 1, $0.sortIndex) < ($1.isPinned ? 0 : 1, $1.sortIndex) }
    }

    var pinned: ClipCollection? { collections().first(where: \.isPinned) }

    /// Inhalt eines Nicht-Tresor-Eintrags (aus dem Speicher).
    func payload(_ entry: ClipEntry) -> ClipPayload? {
        entry.isVault ? nil : payloads[entry.id]
    }

    func title(_ entry: ClipEntry) -> String? { titles[entry.id] }

    /// Tresor-Inhalt – nur mit dem Schlüssel aus `ClipboardKeys.vaultKey` (Touch ID). Nicht zwischengespeichert.
    func openVault(_ entry: ClipEntry, vaultKey: SymmetricKey) throws -> ClipPayload {
        guard entry.isVault, let sealed = entry.sealedPayload else { throw StoreError.notVault }
        return try ClipCrypto.openPayload(sealed, key: vaultKey, id: entry.id)
    }

    enum StoreError: Error { case notVault, needsVaultKey }

    // MARK: - Schreiben

    /// Neue Kopie. Gleicher Inhalt wie ein vorhandener Eintrag → der rückt nach oben, kein Duplikat.
    @discardableResult
    func add(_ payload: ClipPayload, kind: ClipKind, source: String?, now: Date = Date()) throws -> ClipEntry {
        let print = ClipCrypto.fingerprint(payload, key: key)
        let same = try context.fetch(FetchDescriptor<ClipEntry>(predicate: #Predicate { $0.fingerprint == print }))
        if let existing = same.first(where: { !$0.isVault }) {
            existing.lastUsedAt = now
            try save()
            return existing
        }
        let entry = ClipEntry(kind: kind, sourceBundleID: source)
        entry.createdAt = now
        entry.lastUsedAt = now
        entry.fingerprint = print
        entry.byteCount = payload.formats.reduce(0) { $0 + $1.data.count }
        entry.sealedPayload = try ClipCrypto.sealPayload(payload, key: key, id: entry.id)
        context.insert(entry)
        remember(payload, for: entry.id)
        prune(now: now)
        try save()
        return entry
    }

    /// Eintrag direkt im Tresor anlegen (Import, G41).
    @discardableResult
    func addVault(_ draft: VaultDraft, to collection: ClipCollection, vaultKey: SymmetricKey) throws -> ClipEntry {
        let entry = try insertVault(draft, to: collection, vaultKey: vaultKey)
        try save()
        return entry
    }

    /// Tresor-Eintrag vor dem Verschlüsseln (Inhalt, Art, Pflicht-Titel, Datum).
    struct VaultDraft {
        let payload: ClipPayload
        let kind: ClipKind
        let title: String
        let createdAt: Date
    }

    private func insertVault(_ draft: VaultDraft, to collection: ClipCollection, vaultKey: SymmetricKey) throws -> ClipEntry {
        let entry = ClipEntry(kind: draft.kind, sourceBundleID: nil, isVault: true)
        entry.createdAt = draft.createdAt
        entry.lastUsedAt = draft.createdAt
        entry.byteCount = draft.payload.formats.reduce(0) { $0 + $1.data.count }
        entry.sealedPayload = try ClipCrypto.sealPayload(draft.payload, key: vaultKey, id: entry.id)
        try setTitleUnsaved(entry, draft.title)
        entry.collections = [collection]
        context.insert(entry)
        return entry
    }

    /// Import (G41): direkt in die Sammlung, ohne Aufräumen (sonst wären Einträge älter als 30 Tage sofort weg) und
    /// ohne Speichern – `commitImport` bzw. `rollbackImport` entscheiden am Ende (alles oder nichts).
    /// Gleicher Inhalt schon vorhanden → nur die Zugehörigkeit; Rückgabe `nil` = kein neuer Eintrag.
    @discardableResult
    func stageImport(_ payload: ClipPayload, kind: ClipKind, to collection: ClipCollection, createdAt: Date) throws -> ClipEntry? {
        let print = ClipCrypto.fingerprint(payload, key: key)
        let same = try context.fetch(FetchDescriptor<ClipEntry>(predicate: #Predicate { $0.fingerprint == print }))
        if let existing = same.first(where: { !$0.isVault }) {
            if !(existing.collections ?? []).contains(where: { $0.id == collection.id }) {
                existing.collections = (existing.collections ?? []) + [collection]
            }
            return nil
        }
        let entry = ClipEntry(kind: kind, sourceBundleID: nil)
        entry.createdAt = createdAt
        entry.lastUsedAt = createdAt
        entry.fingerprint = print
        entry.byteCount = payload.formats.reduce(0) { $0 + $1.data.count }
        entry.sealedPayload = try ClipCrypto.sealPayload(payload, key: key, id: entry.id)
        entry.collections = [collection]
        context.insert(entry)
        remember(payload, for: entry.id)
        return entry
    }

    /// Wie `stageImport`, aber in den Tresor (Inhalt mit dem Tresor-Schlüssel).
    func stageVaultImport(_ draft: VaultDraft, to collection: ClipCollection, vaultKey: SymmetricKey) throws {
        _ = try insertVault(draft, to: collection, vaultKey: vaultKey)
    }

    /// Sammlung für den Import anlegen, noch nicht gesichert.
    func stageCollection(name: String, color: ClipColor, symbol: String, isVault: Bool, sortIndex: Double) -> ClipCollection {
        let collection = ClipCollection(name: String(name.prefix(100)), color: color, symbol: symbol,
                                        sortIndex: sortIndex, isVault: isVault)
        context.insert(collection)
        return collection
    }

    func commitImport() throws { try save() }

    /// Alles Ungesicherte verwerfen und den Speicher-Zwischenstand neu laden.
    func rollbackImport() {
        context.rollback()
        payloads.removeAll()
        titles.removeAll()
        secretKinds.removeAll()
        loadCaches()
        revision += 1
    }

    func touch(_ entry: ClipEntry, now: Date = Date()) {
        entry.lastUsedAt = now
        try? save()
    }

    func setTitle(_ entry: ClipEntry, _ title: String?) throws {
        try setTitleUnsaved(entry, title)
        try save()
    }

    private func setTitleUnsaved(_ entry: ClipEntry, _ title: String?) throws {
        let clean = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clean.isEmpty {
            entry.sealedTitle = nil
            titles[entry.id] = nil
        } else {
            entry.sealedTitle = try ClipCrypto.sealString(String(clean.prefix(200)), key: key, id: entry.id)
            titles[entry.id] = String(clean.prefix(200))
        }
    }

    func delete(_ entry: ClipEntry) {
        forget(entry.id)
        context.delete(entry)
        try? save()
    }

    /// „Verlauf löschen“: alle Einträge außerhalb von Sammlungen. Sammlungen und Tresor bleiben.
    func clearHistory() throws {
        for entry in try context.fetch(FetchDescriptor<ClipEntry>()) where entry.isLoose && !entry.isVault {
            forget(entry.id)
            context.delete(entry)
        }
        try save()
    }

    /// „Zwischenablage zurücksetzen“: alles weg. Danach die Schlüssel löschen (ClipboardKeys.deleteAll).
    func eraseEverything() throws {
        try context.delete(model: ClipEntry.self)
        try context.delete(model: ClipCollection.self)
        payloads.removeAll()
        titles.removeAll()
        secretKinds.removeAll()
        try save()
    }

    /// Ablauf (G37): Einträge außerhalb von Sammlungen nach 30 Tagen und jenseits der 1 000 jüngsten.
    func prune(now: Date = Date()) {
        guard let all = try? context.fetch(FetchDescriptor<ClipEntry>()) else { return }
        let loose = all.filter { $0.isLoose && !$0.isVault }.sorted { $0.lastUsedAt > $1.lastUsedAt }
        for (index, entry) in loose.enumerated()
        where index >= Self.maxLoose || now.timeIntervalSince(entry.lastUsedAt) > Self.maxAge {
            forget(entry.id)
            context.delete(entry)
        }
    }

    // MARK: - Geheimnisse (0.13.0, G43)

    /// Erkannte Art („GitHub-Token“), nil = kein Geheimnis, Tresor-Eintrag oder Erkennung aus.
    func secretKind(_ entry: ClipEntry) -> String? {
        guard secretsSince != nil, !entry.isVault else { return nil }
        return secretKinds[entry.id]
    }

    /// Wert nie zeigen, nicht in die Notch, nicht herausziehen: Tresor oder erkanntes Geheimnis.
    func isConcealed(_ entry: ClipEntry) -> Bool { entry.isVault || secretKind(entry) != nil }

    /// Ablauf eines erkannten Geheimnisses – nur für lose Einträge (Sammlungen werden nie automatisch gelöscht).
    func secretExpiry(_ entry: ClipEntry) -> Date? {
        guard let since = secretsSince, entry.isLoose, secretKind(entry) != nil else { return nil }
        return max(entry.lastUsedAt, since).addingTimeInterval(Self.secretLifetime)
    }

    /// Bewusst gespeicherte Geheimnisse (in Sammlungen/Angeheftet, nicht im Tresor) – für das einmalige Angebot.
    func savedSecrets() -> [ClipEntry] {
        guard secretsSince != nil, let all = try? context.fetch(FetchDescriptor<ClipEntry>()) else { return [] }
        return all.filter { !$0.isLoose && secretKind($0) != nil }
    }

    /// Abgelaufene lose Geheimnisse löschen. Umfang hart begrenzt (G43 a–d). Gibt die Anzahl zurück (Protokoll: nur
    /// Zahlen).
    @discardableResult
    func pruneSecrets(now: Date = Date()) -> Int {
        guard secretsSince != nil, !secretKinds.isEmpty,
              let all = try? context.fetch(FetchDescriptor<ClipEntry>()) else { return 0 }
        var removed = 0
        for entry in all where !entry.isVault && entry.isLoose {
            guard let expiry = secretExpiry(entry), expiry <= now else { continue }
            forget(entry.id)
            context.delete(entry)
            removed += 1
        }
        if removed > 0 { try? save() }
        return removed
    }

    /// Gespeichertes Geheimnis wird wieder lose (aus Sammlung genommen, Sammlung gelöscht): volle 5 Minuten ab jetzt,
    /// nicht sofort weg, weil es vielleicht seit Wochen in der Sammlung lag (G43).
    private func restartSecretLifetime(_ entry: ClipEntry, now: Date = Date()) {
        guard secretKind(entry) != nil else { return }
        entry.lastUsedAt = max(entry.lastUsedAt, now)
    }

    private func remember(_ payload: ClipPayload, for id: UUID) {
        payloads[id] = payload
        secretKinds[id] = SecretDetector.kind(of: payload)
    }

    private func forget(_ id: UUID) {
        payloads[id] = nil
        titles[id] = nil
        secretKinds[id] = nil
    }

    // MARK: - Sammlungen

    @discardableResult
    func createCollection(name: String, color: ClipColor, symbol: String, isVault: Bool = false) throws -> ClipCollection {
        let next = (collections().map(\.sortIndex).max() ?? 0) + 1
        let collection = ClipCollection(name: String(name.prefix(100)), color: color, symbol: symbol,
                                        sortIndex: next, isVault: isVault)
        context.insert(collection)
        try save()
        return collection
    }

    func deleteCollection(_ collection: ClipCollection) throws {
        guard !collection.isPinned else { return }
        // Tresor-Einträge gibt es nur in ihrer Tresor-Sammlung – mit ihr verschwinden sie.
        for entry in collection.entries ?? [] where entry.isVault { delete(entry) }
        for entry in collection.entries ?? [] { restartSecretLifetime(entry) }
        context.delete(collection)
        try save()
    }

    func move(_ collection: ClipCollection, before target: ClipCollection) throws {
        let ordered = collections().filter { !$0.isPinned && $0.id != collection.id }
        guard !collection.isPinned, let index = ordered.firstIndex(where: { $0.id == target.id }) else { return }
        var list = ordered
        list.insert(collection, at: index)
        for (position, item) in list.enumerated() { item.sortIndex = Double(position + 1) }
        try save()
    }

    /// In eine Sammlung legen. Normale Einträge können in mehreren stecken; in einen Tresor geht es nur über
    /// `moveToVault` (Inhalt wird mit dem Tresor-Schlüssel neu verschlüsselt).
    func add(_ entry: ClipEntry, to collection: ClipCollection) throws {
        guard !collection.isVault, !entry.isVault else { throw StoreError.needsVaultKey }
        var list = entry.collections ?? []
        guard !list.contains(where: { $0.id == collection.id }) else { return }
        list.append(collection)
        entry.collections = list
        try save()
    }

    func remove(_ entry: ClipEntry, from collection: ClipCollection) throws {
        entry.collections = (entry.collections ?? []).filter { $0.id != collection.id }
        if entry.isVault { delete(entry); return }
        restartSecretLifetime(entry)
        try save()
    }

    func togglePinned(_ entry: ClipEntry) throws {
        guard let pinned else { return }
        if (entry.collections ?? []).contains(where: { $0.id == pinned.id }) {
            try remove(entry, from: pinned)
        } else {
            try add(entry, to: pinned)
        }
    }

    /// Normalen Eintrag in den Tresor verschieben: neu verschlüsseln, aus allen anderen Sammlungen nehmen.
    func moveToVault(_ entry: ClipEntry, collection: ClipCollection, title: String, vaultKey: SymmetricKey) throws {
        guard collection.isVault, !entry.isVault, let payload = payloads[entry.id] else { throw StoreError.notVault }
        entry.sealedPayload = try ClipCrypto.sealPayload(payload, key: vaultKey, id: entry.id)
        entry.isVault = true
        entry.fingerprint = nil
        payloads[entry.id] = nil
        secretKinds[entry.id] = nil
        try setTitleUnsaved(entry, title)
        entry.collections = [collection]
        try save()
    }

    // MARK: - Intern

    private func ensurePinned() {
        let all = (try? context.fetch(FetchDescriptor<ClipCollection>())) ?? []
        guard !all.contains(where: \.isPinned) else { return }
        context.insert(ClipCollection(name: String(localized: "Angeheftet"), color: .yellow, symbol: "pin.fill",
                                      sortIndex: 0, isPinned: true))
        try? save()
    }

    private func loadCaches() {
        guard let all = try? context.fetch(FetchDescriptor<ClipEntry>()) else { return }
        var broken = 0
        for entry in all {
            if let sealed = entry.sealedTitle {
                titles[entry.id] = try? ClipCrypto.openString(sealed, key: key, id: entry.id)
            }
            guard !entry.isVault, let sealed = entry.sealedPayload else { continue }
            if let payload = try? ClipCrypto.openPayload(sealed, key: key, id: entry.id) {
                remember(payload, for: entry.id)
            } else {
                broken += 1
            }
        }
        if broken > 0 { Self.log.error("\(broken, privacy: .public) Einträge nicht entschlüsselbar") }
    }

    private func save() throws {
        try context.save()
        revision += 1
    }
}
