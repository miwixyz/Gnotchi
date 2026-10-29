import CryptoKit
import XCTest

/// 0.11.0 Zwischenablage (docs/SECURE-DESIGN.md G37–G39): Aufnahme-Regeln, Verschlüsselung, Speicher.
@MainActor
final class ClipboardTests: XCTestCase {

    private typealias UTI = ClipboardCapture.UTI

    private func snapshot(_ items: [String: Data], source: String? = "com.apple.Safari") -> ClipboardCapture.Snapshot {
        ClipboardCapture.Snapshot(types: Array(items.keys), read: { items[$0] }, sourceBundleID: source)
    }

    private func decide(_ items: [String: Data], source: String? = "com.apple.Safari",
                        excluded: Set<String> = []) -> ClipboardCapture.Decision {
        ClipboardCapture.decide(snapshot(items, source: source), isExcluded: excluded.contains)
    }

    // MARK: - Aufnahme (G37)

    func testConcealedNeverTaken() {
        for marker in ClipboardCapture.neverTypes {
            XCTAssertEqual(decide([UTI.plain: Data("geheim".utf8), marker: Data()]), .skip(.confidential), marker)
        }
    }

    func testExcludedAppSkipped() {
        XCTAssertEqual(decide([UTI.plain: Data("x".utf8)], source: "com.bank.app", excluded: ["com.bank.app"]),
                       .skip(.excluded))
    }

    func testPlainText() {
        guard case let .take(payload, kind) = decide([UTI.plain: Data("Hallo".utf8)]) else { return XCTFail("nicht übernommen") }
        XCTAssertEqual(kind, .text)
        XCTAssertEqual(payload.plain, "Hallo")
    }

    func testRichTextKeepsFormatsButNeverParses() {
        let html = Data("<b>fett</b><img src=\"https://example.com/x.png\">".utf8)
        guard case let .take(payload, kind) = decide([UTI.plain: Data("fett".utf8), UTI.html: html]) else {
            return XCTFail("nicht übernommen")
        }
        XCTAssertEqual(kind, .richText)
        XCTAssertEqual(payload.plain, "fett")
        XCTAssertEqual(payload.formats.first { $0.type == UTI.html }?.data, html, "HTML unverändert, nie umgewandelt")
    }

    func testBrowserInternalAndWebarchiveDropped() {
        guard case let .take(payload, _) = decide([UTI.plain: Data("a".utf8),
                                                   "org.chromium.source-url": Data("https://x".utf8),
                                                   "com.apple.webarchive": Data("y".utf8)]) else { return XCTFail("nicht übernommen") }
        XCTAssertEqual(payload.formats.map(\.type), [UTI.plain])
    }

    func testLinkDetected() {
        guard case let .take(_, kind) = decide([UTI.plain: Data("https://gnotchi.mwlr.dev/hilfe".utf8)]) else {
            return XCTFail("nicht übernommen")
        }
        XCTAssertEqual(kind, .link)
        XCTAssertFalse(ClipboardCapture.isSingleWebURL("siehe https://x.de bitte"))
        XCTAssertFalse(ClipboardCapture.isSingleWebURL("file:///etc/passwd"))
    }

    func testImageOnlyOneFormatPngFirst() {
        guard case let .take(payload, kind) = decide([UTI.tiff: Data(repeating: 1, count: 10),
                                                      UTI.png: Data(repeating: 2, count: 5)]) else { return XCTFail("nicht übernommen") }
        XCTAssertEqual(kind, .image)
        XCTAssertEqual(payload.formats.map(\.type), [UTI.png])
    }

    /// Gemessen 24.10.: Safari „Bild kopieren“ liefert TIFF + HTML (<img src>), RTFD, Webarchiv – kein Klartext.
    func testSafariImageCopyIsImageOnly() {
        let html = Data("<img src=\"https://example.com/bild.jpg\">".utf8)
        guard case let .take(payload, kind) = decide([UTI.tiff: Data(repeating: 7, count: 2_768_326), UTI.html: html,
                                                      "com.apple.flat-rtfd": Data(repeating: 1, count: 70),
                                                      "com.apple.webarchive": Data(repeating: 2, count: 56)]) else {
            return XCTFail("Safari-Bild nicht übernommen")
        }
        XCTAssertEqual(kind, .image)
        XCTAssertEqual(payload.formats.map(\.type), [UTI.tiff], "nur das Bild, kein HTML mit Webadresse")
    }

    func testFileReference() {
        guard case let .take(payload, kind) = decide([UTI.fileURL: Data("file:///Users/x/Bericht.pdf".utf8)]) else {
            return XCTFail("nicht übernommen")
        }
        XCTAssertEqual(kind, .file)
        XCTAssertEqual(payload.plain, "Bericht.pdf")
    }

    func testSizeLimits() {
        XCTAssertEqual(decide([UTI.plain: Data(repeating: 65, count: ClipboardCapture.maxTextBytes + 1)]),
                       .skip(.tooLarge))
        XCTAssertEqual(decide([UTI.png: Data(repeating: 1, count: ClipboardCapture.maxTotalBytes + 1)]),
                       .skip(.tooLarge))
    }

    func testEmptyAndUnsupported() {
        XCTAssertEqual(decide([UTI.plain: Data("   \n".utf8)]), .skip(.empty))
        XCTAssertEqual(decide(["com.adobe.pdf": Data("x".utf8)]), .skip(.unsupported))
        XCTAssertEqual(decide([:]), .skip(.empty))
    }

    // MARK: - Verschlüsselung (G38)

    func testSealOpenRoundTripAndBoundToID() throws {
        let key = SymmetricKey(size: .bits256)
        let id = UUID()
        let payload = ClipPayload(formats: [.init(type: UTI.plain, data: Data("Hallo".utf8))], plain: "Hallo")
        let sealed = try ClipCrypto.sealPayload(payload, key: key, id: id)
        XCTAssertNil(sealed.range(of: Data("Hallo".utf8)), "kein Klartext im Chiffrat")
        XCTAssertEqual(try ClipCrypto.openPayload(sealed, key: key, id: id), payload)
        XCTAssertThrowsError(try ClipCrypto.openPayload(sealed, key: key, id: UUID()), "andere ID → abgelehnt")
        XCTAssertThrowsError(try ClipCrypto.openPayload(sealed, key: SymmetricKey(size: .bits256), id: id))
    }

    func testFingerprintKeyedAndStable() {
        let payload = ClipPayload(formats: [.init(type: UTI.plain, data: Data("a".utf8))], plain: "a")
        let key = SymmetricKey(size: .bits256)
        XCTAssertEqual(ClipCrypto.fingerprint(payload, key: key), ClipCrypto.fingerprint(payload, key: key))
        XCTAssertNotEqual(ClipCrypto.fingerprint(payload, key: key),
                          ClipCrypto.fingerprint(payload, key: SymmetricKey(size: .bits256)))
    }

    // MARK: - Speicher

    private func text(_ string: String) -> ClipPayload {
        ClipPayload(formats: [.init(type: UTI.plain, data: Data(string.utf8))], plain: string)
    }

    func testAddDedupsAndOrdersNewestFirst() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = try store.add(text("eins"), kind: .text, source: nil, now: start)
        try store.add(text("zwei"), kind: .text, source: nil, now: start.addingTimeInterval(1))
        let again = try store.add(text("eins"), kind: .text, source: nil, now: start.addingTimeInterval(2))
        XCTAssertEqual(again.id, first.id, "gleicher Inhalt → kein Duplikat")
        XCTAssertEqual(store.entries().compactMap { store.payload($0)?.plain }, ["eins", "zwei"])
    }

    func testSearchFindsTitleAndContent() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let entry = try store.add(text("DE12 3456"), kind: .text, source: nil)
        try store.add(text("anderes"), kind: .text, source: nil)
        try store.setTitle(entry, "IBAN CineSocial")
        XCTAssertEqual(store.entries(matching: "cinesocial").map(\.id), [entry.id])
        XCTAssertEqual(store.entries(matching: "3456").map(\.id), [entry.id])
    }

    func testPruneKeepsCollectionsDropsOldAndOverflow() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let now = Date(timeIntervalSince1970: 10_000_000)
        let old = try store.add(text("alt"), kind: .text, source: nil, now: now.addingTimeInterval(-31 * 24 * 3600))
        let keep = try store.add(text("angeheftet"), kind: .text, source: nil,
                                 now: now.addingTimeInterval(-40 * 24 * 3600))
        try store.togglePinned(keep)
        try store.add(text("neu"), kind: .text, source: nil, now: now)
        let plains = Set(store.entries().compactMap { store.payload($0)?.plain })
        XCTAssertFalse(plains.contains("alt"), "älter als 30 Tage → weg")
        XCTAssertTrue(plains.contains("angeheftet"), "in Sammlung → bleibt")
        XCTAssertTrue(plains.contains("neu"))
        _ = old
    }

    func testCollectionsPinnedFirstAndMultiMembership() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let mails = try store.createCollection(name: "Mails", color: .blue, symbol: "envelope")
        let forms = try store.createCollection(name: "Formulare", color: .green, symbol: "doc")
        XCTAssertEqual(store.collections().first?.isPinned, true)
        let entry = try store.add(text("Adresse"), kind: .text, source: nil)
        try store.add(entry, to: mails)
        try store.add(entry, to: forms)
        XCTAssertEqual(store.entries(in: mails).map(\.id), [entry.id])
        XCTAssertEqual(store.entries(in: forms).map(\.id), [entry.id])
        try store.clearHistory()
        XCTAssertEqual(store.entries().map(\.id), [entry.id], "in Sammlungen → übersteht „Verlauf löschen“")
    }

    func testVaultNeverInHistoryOrContentSearch() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let vaultKey = SymmetricKey(size: .bits256)
        let vault = try store.createCollection(name: "Tresor", color: .red, symbol: "lock", isVault: true)
        let draft = ClipboardStore.VaultDraft(payload: text("sk-ant-geheim"), kind: .text, title: "Anthropic",
                                              createdAt: Date())
        let entry = try store.addVault(draft, to: vault, vaultKey: vaultKey)
        XCTAssertTrue(store.entries().isEmpty, "nie im Verlauf")
        XCTAssertNil(store.payload(entry), "Inhalt ohne Tresor-Schlüssel nicht verfügbar")
        XCTAssertTrue(store.entries(in: vault, matching: "geheim").isEmpty, "Suche nur über Titel")
        XCTAssertEqual(store.entries(in: vault, matching: "anthro").map(\.id), [entry.id])
        XCTAssertEqual(try store.openVault(entry, vaultKey: vaultKey).plain, "sk-ant-geheim")
        XCTAssertThrowsError(try store.openVault(entry, vaultKey: SymmetricKey(size: .bits256)))
        XCTAssertThrowsError(try store.add(entry, to: store.pinned!), "Tresor-Eintrag nicht in andere Sammlungen")
    }

    func testPersistsOnlyCiphertext() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gnotchi-clip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        do {
            let store = try ClipboardStore(directory: dir, key: key)
            let entry = try store.add(text("UNVERWECHSELBAR-4711"), kind: .text, source: nil)
            try store.setTitle(entry, "TITEL-0815")
        }
        let files = try FileManager.default.subpathsOfDirectory(atPath: dir.path)
        for file in files {
            let data = (try? Data(contentsOf: dir.appending(path: file))) ?? Data()
            XCTAssertNil(data.range(of: Data("UNVERWECHSELBAR-4711".utf8)), file)
            XCTAssertNil(data.range(of: Data("TITEL-0815".utf8)), file)
        }
        let perms = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o700)
        let reopened = try ClipboardStore(directory: dir, key: key)
        XCTAssertEqual(reopened.entries().compactMap { reopened.payload($0)?.plain }, ["UNVERWECHSELBAR-4711"])
    }
}

/// 0.11.0 PastePal-Import (G41): Format wie der echte Export vom 24.10. (nur Struktur, erfundene Werte).
@MainActor
final class PastePalImportTests: XCTestCase {

    private let sample = Data("""
    {"folders":[{"id":"F1","icon":"pc","name":"Arbeit","color":"Yellow","createdAt":747667664.35},
                {"id":"F2","icon":"bookmark","name":"Schlüssel","color":"Blue","createdAt":747667665}],
     "apps":[{"name":"","bundleId":"com.x","bundleUrl":"file:///x"}],
     "items":[{"id":"1","string":"Hallo Welt","createdAt":747667664.35,"collectionId":"F1","itemType":"Text","pbType":"public.utf8-plain-text"},
              {"id":"2","string":"https://cineweb.de","createdAt":814433252.41,"collectionId":"F1","itemType":"Rich Text"},
              {"id":"3","string":"sk-ant-test123","createdAt":800000000,"collectionId":"F2","itemType":"Text"},
              {"id":"4","string":"   ","createdAt":800000000,"collectionId":"F1"},
              {"id":"5","string":"verwaist","createdAt":800000000,"collectionId":"F9"}]}
    """.utf8)

    func testPlanMapsCollectionsDatesAndSkips() throws {
        let plan = try PastePalImport.plan(from: sample)
        XCTAssertEqual(plan.collections.map(\.name), ["Arbeit", "Schlüssel"])
        XCTAssertEqual(plan.collections[0].symbol, "desktopcomputer")
        XCTAssertEqual(plan.collections[0].color, .yellow)
        XCTAssertEqual(plan.collections[0].items.count, 2)
        XCTAssertEqual(plan.skipped, 2, "leer + unbekannte Sammlung")
        let year = Calendar(identifier: .gregorian).component(.year, from: plan.collections[0].items[0].createdAt)
        XCTAssertEqual(year, 2024, "Sekunden ab 2001, nicht ab 1970")
    }

    func testRejectsGarbageAndLimits() {
        XCTAssertThrowsError(try PastePalImport.plan(from: Data("kein json".utf8)))
        XCTAssertThrowsError(try PastePalImport.plan(from: Data(count: PastePalImport.maxFileBytes + 1)))
    }

    func testRunKeepsOldEntriesAndVault() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let plan = try PastePalImport.plan(from: sample)
        let vaultKey = SymmetricKey(size: .bits256)
        let n = try PastePalImport.run(plan, vaultIDs: ["F2"], store: store, vaultKey: SymmetricKeyProvider(key: vaultKey))
        XCTAssertEqual(n, 3)
        store.prune()
        let work = try XCTUnwrap(store.collections().first { $0.name == "Arbeit" })
        XCTAssertEqual(store.entries(in: work).count, 2, "zwei Jahre alt, aber in Sammlung → bleibt")
        let vault = try XCTUnwrap(store.collections().first { $0.isVault })
        let secret = try XCTUnwrap(store.entries(in: vault).first)
        XCTAssertEqual(store.title(secret), "Anthropic")
        XCTAssertEqual(try store.openVault(secret, vaultKey: vaultKey).plain, "sk-ant-test123")
        XCTAssertFalse(store.entries().contains { $0.id == secret.id }, "Tresor nie im Verlauf")
    }

    func testVaultWithoutKeyRollsBackEverything() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let plan = try PastePalImport.plan(from: sample)
        XCTAssertThrowsError(try PastePalImport.run(plan, vaultIDs: ["F2"], store: store, vaultKey: nil))
        XCTAssertEqual(store.collections().count, 1, "nur „Angeheftet“ – nichts halb importiert")
        XCTAssertTrue(store.entries().isEmpty)
    }

    func testVaultTitleCatalog() {
        XCTAssertEqual(VaultTitles.suggest("sk-ant-abc"), "Anthropic")
        XCTAssertEqual(VaultTitles.suggest("sk-proj-abc"), "OpenAI")
        XCTAssertEqual(VaultTitles.suggest("sk-xyz"), "API-Schlüssel")
        XCTAssertEqual(VaultTitles.suggest("irgendwas"), "Eintrag")
    }
}
