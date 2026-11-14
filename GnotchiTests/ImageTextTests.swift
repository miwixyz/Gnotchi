import AppKit
import CryptoKit
import XCTest

/// Bildtext-Suche (docs/SECURE-DESIGN.md G50): Erkennung, Geheimnis-Filter, Speichern, Suche, Schalter.
@MainActor
final class ImageTextTests: XCTestCase {

    /// Schwarzer Text auf Weiß als PNG – echtes Eingabebild für Vision.
    private func png(_ text: String = "") -> Data {
        let size = NSSize(width: 900, height: 200)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 30, y: 70), withAttributes: [
            .font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black,
        ])
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private func image(_ data: Data) -> ClipPayload {
        ClipPayload(formats: [.init(type: ClipboardCapture.UTI.png, data: data)], plain: "")
    }

    private func makeStore(directory: URL? = nil, key: SymmetricKey = SymmetricKey(size: .bits256)) throws -> ClipboardStore {
        try ClipboardStore(directory: directory, key: key)
    }

    // MARK: Erkennung

    func testRecognizesRenderedText() {
        let text = ImageText.recognize(png("Kinoprogramm Donnerstag"))
        XCTAssertTrue(text.localizedStandardContains("Kinoprogramm"), "erkannt: \(text.count) Zeichen")
    }

    func testBlankImageAndGarbageAreDoneWithoutText() {
        XCTAssertEqual(ImageText.recognize(png()), "", "kein Text → erledigt, leer")
        XCTAssertEqual(ImageText.recognize(Data("kein Bild".utf8)), "", "Dekodierfehler → erledigt, leer")
    }

    // MARK: Geheimnis-Filter

    func testSanitizedKeepsNormalTextAndCaps() {
        XCTAssertEqual(ImageText.sanitized("  Rechnung März \n"), "Rechnung März")
        XCTAssertEqual(ImageText.sanitized(String(repeating: "a", count: 30_000)).count, ImageText.maxCharacters)
    }

    func testSanitizedDropsSecretsInLinesAndPieces() {
        let key = SecretTests.github
        XCTAssertEqual(ImageText.sanitized(key), "", "ganzer Text")
        XCTAssertEqual(ImageText.sanitized("Notizen\n" + key + "\nmehr"), "", "eigene Zeile")
        XCTAssertEqual(ImageText.sanitized("export GITHUB_TOKEN=" + key), "", "nach =")
        XCTAssertEqual(ImageText.sanitized("token: \"" + key + "\""), "", "nach : in Anführungszeichen")
        XCTAssertEqual(ImageText.sanitized("Mein Token ist " + key + " danke"), "", "zwischen Wörtern")
    }

    // MARK: Speicher und Suche

    func testStoredTextIsSearchableAndNotPendingAgain() throws {
        let store = try makeStore()
        let entry = try store.add(image(png()), kind: .image, source: nil)
        XCTAssertEqual(store.pendingImageText().map(\.0), [entry.id])
        store.storeImageTexts([entry.id: "Rechnung Kino Grafing"])
        XCTAssertEqual(store.entries(matching: "Grafing").map(\.id), [entry.id])
        XCTAssertEqual(store.imageText(entry), "Rechnung Kino Grafing")
        XCTAssertTrue(store.pendingImageText().isEmpty, "nie zweimal rechnen")
        XCTAssertNotNil(entry.sealedOCR)
        XCTAssertNil(entry.sealedOCR.flatMap { String(data: $0, encoding: .utf8) }?.range(of: "Grafing"),
                     "nur Chiffrat in der Datenbank")
    }

    func testEmptyResultMarksDone() throws {
        let store = try makeStore()
        let entry = try store.add(image(png()), kind: .image, source: nil)
        store.storeImageTexts([entry.id: ""])
        XCTAssertTrue(store.pendingImageText().isEmpty)
        XCTAssertNil(store.imageText(entry), "leer wird nicht angeboten")
    }

    func testSwitchOffHidesAndClearsOnReset() throws {
        let store = try makeStore()
        let entry = try store.add(image(png()), kind: .image, source: nil)
        store.storeImageTexts([entry.id: "Kassenbon"])
        store.imageTextEnabled = false
        XCTAssertTrue(store.entries(matching: "Kassenbon").isEmpty, "aus → Suche ohne Bildtext")
        XCTAssertNil(store.imageText(entry))
        store.storeImageTexts([entry.id: "neu"])   // spätes Ergebnis nach dem Ausschalten
        store.clearImageTexts()
        XCTAssertNil(entry.sealedOCR)
        store.imageTextEnabled = true
        XCTAssertEqual(store.pendingImageText().map(\.0), [entry.id], "wieder an → neu erkennen")
        XCTAssertNil(store.imageText(entry))
    }

    func testDeletedEntryIgnoredAndTextEntriesNeverPending() throws {
        let store = try makeStore()
        let entry = try store.add(image(png()), kind: .image, source: nil)
        let id = entry.id
        _ = try store.add(ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data("x".utf8))], plain: "x"),
                          kind: .text, source: nil)
        XCTAssertEqual(store.pendingImageText().map(\.0), [id], "nur Bilder")
        store.delete(entry)
        store.storeImageTexts([id: "weg"])   // Ergebnis kommt nach dem Löschen
        XCTAssertTrue(store.entries(matching: "weg").isEmpty)
        XCTAssertTrue(store.pendingImageText().isEmpty)
    }

    func testVaultImageNeverPending() throws {
        let store = try makeStore()
        let vault = try store.createCollection(name: "Tresor", color: .gray, symbol: "lock", isVault: true)
        let draft = ClipboardStore.VaultDraft(payload: image(png()), kind: .image, title: "Ausweis", createdAt: Date())
        _ = try store.addVault(draft, to: vault, vaultKey: SymmetricKey(size: .bits256))
        XCTAssertTrue(store.pendingImageText().isEmpty)
    }

    /// Code-Audit 14.11.: „In Tresor“ ließ den mit dem Verlauf-Schlüssel verschlüsselten Bildtext stehen –
    /// der Text eines Tresor-Bildes war damit ohne Touch ID lesbar (G39).
    func testMoveToVaultDropsImageText() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gnotchi-bildtext-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try makeStore(directory: dir, key: key)
        let entry = try store.add(image(png()), kind: .image, source: nil)
        store.storeImageTexts([entry.id: "Ausweisnummer"])
        let vault = try store.createCollection(name: "Tresor", color: .gray, symbol: "lock", isVault: true)
        try store.moveToVault(entry, collection: vault, title: "Ausweis", vaultKey: SymmetricKey(size: .bits256))
        XCTAssertNil(entry.sealedOCR, "kein Bildtext mit dem Verlauf-Schlüssel am Tresor-Eintrag")
        let reopened = try makeStore(directory: dir, key: key)
        XCTAssertTrue(reopened.entries(matching: "Ausweisnummer").isEmpty)
        XCTAssertTrue(reopened.pendingImageText().isEmpty, "Tresor wird nie erkannt")
    }

    func testTextSurvivesReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gnotchi-bildtext-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        var id = UUID()
        do {
            let store = try makeStore(directory: dir, key: key)
            id = try store.add(image(png()), kind: .image, source: nil).id
            store.storeImageTexts([id: "Spielplan"])
        }
        let reopened = try makeStore(directory: dir, key: key)
        XCTAssertEqual(reopened.entries(matching: "Spielplan").map(\.id), [id])
        XCTAssertTrue(reopened.pendingImageText().isEmpty)
    }

    // MARK: Hintergrund-Lauf

    func testIndexerFillsPendingAndRunsOnce() async throws {
        let store = try makeStore()
        let entry = try store.add(image(png("Vorstellung Samstag")), kind: .image, source: nil)
        let indexer = ImageTextIndexer()
        indexer.run(store)
        XCTAssertTrue(indexer.isRunning)
        indexer.run(store)   // zweiter Aufruf startet keinen zweiten Lauf
        for _ in 0..<200 where indexer.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(indexer.isRunning)
        XCTAssertNotNil(entry.sealedOCR)
        XCTAssertEqual(store.entries(matching: "Samstag").map(\.id), [entry.id])
    }
}
