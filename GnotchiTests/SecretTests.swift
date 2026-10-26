import CryptoKit
import XCTest
@testable import Gnotchi

/// 0.13.0 Geheimnisse (docs/SECURE-DESIGN.md G43): Erkennung, Verdecken, Ablauf, Umfang des Löschens.
///
/// Test-Schlüssel stehen nie wörtlich im Code (sonst schlagen Secret-Scanner und GitHubs Push-Sperre an): Vorsilbe
/// und Rumpf werden zur Laufzeit zusammengesetzt, der Rumpf ist erkennbar unecht (Wiederholungen).
@MainActor
final class SecretTests: XCTestCase {

    /// Vorsilbe in zwei Teilen + Rumpf aus `filler`, `count` Zeichen lang.
    static func fake(_ a: String, _ b: String, _ count: Int, filler: String = "aB3") -> String {
        let body = String(String(repeating: filler, count: count / filler.count + 1).prefix(count))
        return a + b + body
    }

    static var github: String { fake("gh", "p_", 36) }
    /// PEM-Kopf zusammengesetzt (der Scanner schlägt schon auf die wörtliche Kopfzeile an).
    static func pem(_ label: String) -> (begin: String, end: String) {
        let dashes = String(repeating: "-", count: 5)
        return (dashes + "BEGIN " + label + dashes, dashes + "END " + label + dashes)
    }

    private func text(_ string: String) -> ClipPayload {
        ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data(string.utf8))], plain: string)
    }

    private func makeStore(since: Date?) throws -> ClipboardStore {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        store.secretsSince = since
        return store
    }

    // MARK: Erkennung – Grenzen, die für jedes Muster gelten

    func testWholeCopyOnly() {
        XCTAssertNotNil(SecretDetector.kind(of: Self.github))
        XCTAssertNotNil(SecretDetector.kind(of: "  \n" + Self.github + "\n "), "Leerraum außen zählt nicht")
        XCTAssertNil(SecretDetector.kind(of: "Mein Token ist " + Self.github), "eingebettet → normaler Eintrag")
        XCTAssertNil(SecretDetector.kind(of: Self.github + " und noch Text"))
        XCTAssertNil(SecretDetector.kind(of: Self.github + "\n" + Self.github), "zwei Schlüssel = Text, kein Geheimnis")
    }

    func testAllRulesCompile() {
        for rule in SecretDetector.rules {
            XCTAssertNoThrow(try NSRegularExpression(pattern: rule.pattern), rule.kind)
        }
    }

    /// Je Dienst ein unechter Schlüssel in der richtigen Form → richtige Art (Reihenfolge bei `sk-…`/`sk_` mitgeprüft).
    func testKnownFormats() {
        let hex = "0123456789abcdef"
        func hexes(_ n: Int) -> String { String(String(repeating: hex, count: n / 16 + 1).prefix(n)) }
        let jwtHead = "ey" + "JhbGciOiJIUzI1NiJ9"
        let pem = Self.pem("RSA PRIVATE KEY")
        let cases: [(String, String)] = [
            (Self.fake("sk-", "ant-api03-", 93) + "AA", "Anthropic-Schlüssel"),
            ("sk-" + "or-v1-" + hexes(64), "OpenRouter-Schlüssel"),
            (Self.fake("sk-", "proj-", 74) + "T3Blbk" + "FJ" + Self.fake("", "", 74), "OpenAI-Schlüssel"),
            ("sk" + "_" + hexes(48), "ElevenLabs-Schlüssel"),
            (Self.fake("AI", "za", 35), "Google-API-Schlüssel"),
            (Self.fake("gh", "p_", 36), "GitHub-Token"),
            ("AK" + "IA" + String(repeating: "ABCD", count: 4), "AWS-Zugangsschlüssel"),
            (Self.fake("cf", "ut_", 40) + hexes(8), "Cloudflare-Token"),
            ("RF" + "abc-" + hexes(64), "Rafter-Schlüssel"),
            (Self.fake("sk_", "live_", 24), "Stripe-Schlüssel"),
            (Self.fake("gs", "k_", 52), "Groq-Schlüssel"),
            (Self.fake("apify", "_api_", 36), "Apify-Token"),
            (pem.begin + "\n" + String(repeating: "QUJD", count: 20) + "\n" + pem.end, "Privater Schlüssel"),
            (jwtHead + "." + "ey" + "JzdWIiOiIxMjM0NTY3ODkwIn0" + "." + "abcDEF123_-", "JWT-Token"),
        ]
        for (value, kind) in cases { XCTAssertEqual(SecretDetector.kind(of: value), kind, kind) }
    }

    /// Bewusst nicht erkennbar (kein Präfix): dürfen nie als Geheimnis gelten.
    func testPrefixlessFormatsStayNormal() {
        XCTAssertNil(SecretDetector.kind(of: String(repeating: "aB3x", count: 12)), "48 Zeichen wie Hostinger")
        XCTAssertNil(SecretDetector.kind(of: String(repeating: "0123456789abcdef", count: 2)), "32 Hex wie Mistral/Twilio")
        XCTAssertNil(SecretDetector.kind(of: "sk" + "_" + String(repeating: "ab", count: 10)), "zu kurz für ElevenLabs")
    }

    func testCommonNonSecretsAreNeverDetected() {
        let samples = [
            String(repeating: "d670460b", count: 5),               // Git-SHA-Form (40 Hex)
            "3F2504E0-4F89-11D3-9A0C-0305E82C3301",                // UUID
            String(repeating: "e3b0c442", count: 8),               // SHA-256-Form (64 Hex)
            "https://example.com/path?id=123",
            "Hallo Welt",
            "sk-",                                                  // nur Vorsilbe
            "gh" + "p_",
            "skeleton-key",
            "AK" + "IA",
        ]
        for s in samples { XCTAssertNil(SecretDetector.kind(of: s), s) }
    }

    func testSizeLimit() {
        let big = String(repeating: "a", count: SecretDetector.maxBytes + 1)
        XCTAssertNil(SecretDetector.kind(of: big))
    }

    /// Kein katastrophales Zurückspringen: lange, fast passende Eingaben bleiben schnell.
    func testNoCatastrophicBacktracking() {
        let nearMisses = [
            "gh" + "p_" + String(repeating: "a", count: 8_000),
            "sk-" + String(repeating: "a-", count: 4_000),
            "eyJ" + String(repeating: "a.", count: 4_000),
            Self.pem("PRIVATE KEY").begin + String(repeating: "A\n", count: 3_900),
        ]
        let start = Date()
        for s in nearMisses { _ = SecretDetector.kind(of: s) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    // MARK: Speicher – Verdecken, Suche, Ablauf

    func testDetectionOffShowsNothingSpecial() throws {
        let store = try makeStore(since: nil)
        let entry = try store.add(text(Self.github), kind: .text, source: nil)
        XCTAssertNil(store.secretKind(entry))
        XCTAssertFalse(store.isConcealed(entry))
        XCTAssertEqual(store.pruneSecrets(now: .distantFuture), 0, "aus → nie löschen")
    }

    func testConcealedAndSearchOnlyByKind() throws {
        let store = try makeStore(since: Date(timeIntervalSince1970: 0))
        let entry = try store.add(text(Self.github), kind: .text, source: nil)
        let kind = try XCTUnwrap(store.secretKind(entry))
        XCTAssertTrue(store.isConcealed(entry))
        XCTAssertTrue(store.entries(matching: "aB3aB3").isEmpty, "Inhalt nie durchsuchbar")
        XCTAssertEqual(store.entries(matching: kind).map(\.id), [entry.id], "Art ist durchsuchbar")
    }

    func testLooseSecretExpiresAfterFiveMinutesOfLastUse() throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let store = try makeStore(since: t0.addingTimeInterval(-3600))
        let entry = try store.add(text(Self.github), kind: .text, source: nil, now: t0)
        XCTAssertEqual(store.secretExpiry(entry), t0.addingTimeInterval(300))
        XCTAssertEqual(store.pruneSecrets(now: t0.addingTimeInterval(299)), 0)
        store.touch(entry, now: t0.addingTimeInterval(200))   // Nutzung verlängert
        XCTAssertEqual(store.pruneSecrets(now: t0.addingTimeInterval(450)), 0)
        XCTAssertEqual(store.pruneSecrets(now: t0.addingTimeInterval(501)), 1)
        XCTAssertTrue(store.entries().isEmpty)
    }

    /// Altbestand und Wiedereinschalten: frühestens ab „an seit“, nie sofort.
    func testOldEntriesGetFullLifetimeFromSince() throws {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let since = old.addingTimeInterval(86_400)
        let store = try makeStore(since: since)
        let entry = try store.add(text(Self.github), kind: .text, source: nil, now: old)
        XCTAssertEqual(store.secretExpiry(entry), since.addingTimeInterval(300))
        XCTAssertEqual(store.pruneSecrets(now: since.addingTimeInterval(10)), 0)
        XCTAssertEqual(store.pruneSecrets(now: since.addingTimeInterval(301)), 1)
    }

    /// G43 (a)–(d): Gespeichertes, Normales und Tresor werden nie automatisch gelöscht.
    func testPruneScopeIsLooseDetectedOnly() throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let store = try makeStore(since: t0)
        let normal = try store.add(text("normaler Text"), kind: .text, source: nil, now: t0)
        let saved = try store.add(text(Self.fake("gh", "p_", 36, filler: "xY9")), kind: .text, source: nil, now: t0)
        try store.togglePinned(saved)
        let collection = try store.createCollection(name: "Arbeit", color: .blue, symbol: "folder")
        let inCollection = try store.add(text(Self.fake("gh", "p_", 36, filler: "Qw7")), kind: .text, source: nil, now: t0)
        try store.add(inCollection, to: collection)
        let loose = try store.add(text(Self.github), kind: .text, source: nil, now: t0)

        XCTAssertNil(store.secretExpiry(saved), "angeheftet → kein Ablauf")
        XCTAssertNil(store.secretExpiry(inCollection), "Sammlung → kein Ablauf")
        XCTAssertEqual(store.pruneSecrets(now: t0.addingTimeInterval(10_000)), 1)
        let left = Set(store.entries().map(\.id))
        XCTAssertTrue(left.contains(normal.id))
        XCTAssertTrue(left.contains(saved.id))
        XCTAssertTrue(left.contains(inCollection.id))
        XCTAssertFalse(left.contains(loose.id))
        XCTAssertEqual(Set(store.savedSecrets().map(\.id)), [saved.id, inCollection.id])
        XCTAssertTrue(store.isConcealed(saved), "gespeichert, aber verdeckt")
    }

    /// Aus Sammlung genommen bzw. Sammlung gelöscht: nicht sofort weg, sondern volle Frist ab jetzt.
    func testLeavingCollectionRestartsLifetime() throws {
        let long = Date(timeIntervalSince1970: 1_000_000)
        let store = try makeStore(since: long)
        let collection = try store.createCollection(name: "Alt", color: .blue, symbol: "folder")
        let entry = try store.add(text(Self.github), kind: .text, source: nil, now: long)
        try store.add(entry, to: collection)
        try store.remove(entry, from: collection)
        let expiry = try XCTUnwrap(store.secretExpiry(entry))
        XCTAssertGreaterThan(expiry, Date().addingTimeInterval(250), "Frist startet beim Herausnehmen neu")
        XCTAssertEqual(store.pruneSecrets(), 0)

        let other = try store.createCollection(name: "Weg", color: .blue, symbol: "folder")
        let second = try store.add(text(Self.fake("gh", "p_", 36, filler: "Zz1")), kind: .text, source: nil, now: long)
        try store.add(second, to: other)
        try store.deleteCollection(other)
        XCTAssertGreaterThan(try XCTUnwrap(store.secretExpiry(second)), Date().addingTimeInterval(250))
        XCTAssertEqual(store.pruneSecrets(), 0)
    }

    func testMoveToVaultClearsDetection() throws {
        let store = try makeStore(since: Date())
        let entry = try store.add(text(Self.github), kind: .text, source: nil)
        let vault = try store.createCollection(name: "Tresor", color: .red, symbol: "lock.fill", isVault: true)
        try store.moveToVault(entry, collection: vault, title: "GitHub", vaultKey: SymmetricKey(size: .bits256))
        XCTAssertNil(store.secretKind(entry), "im Tresor gilt der Tresor, nicht die Erkennung")
        XCTAssertTrue(store.isConcealed(entry))
        XCTAssertNil(store.secretExpiry(entry))
        XCTAssertTrue(store.savedSecrets().isEmpty)
    }
}
