// SYNTHETISCH – erfundene Titel, keine echten Hördaten.
import CryptoKit
import XCTest

/// 0.41.0 (G62): Signaturen passen zur Tippi-Firmware, nur signierte Antworten mit bekannten Befehlen wirken.
final class TippiDeviceTests: XCTestCase {

    private func info(_ title: String, artist: String? = "Beispielband", playing: Bool = true) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, album: nil, appBundleID: "com.example.player", isPlaying: playing,
                       duration: 200, elapsedAtStamp: 0, stamp: Date(), rate: 1, contentID: nil, artworkBase64: nil)
    }

    func testBodyIsShortAndHasOnlyFourFields() throws {
        let body = TippiDevice.body(info: info(String(repeating: "x", count: 300)), appName: "Beispiel-Player mit langem Namen")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(o.keys), ["t", "a", "q", "s"])
        XCTAssertEqual((o["t"] as? String)?.count, TippiDevice.maxTitle)
        XCTAssertEqual((o["q"] as? String)?.count, TippiDevice.maxApp)
        XCTAssertEqual(o["s"] as? Int, 1)
        let leer = try XCTUnwrap(JSONSerialization.jsonObject(with: TippiDevice.body(info: nil, appName: nil)) as? [String: Any])
        XCTAssertEqual(leer as NSDictionary, ["s": 0] as NSDictionary)
    }

    func testSignatureMatchesFirmwareFormat() {
        let data = Data(#"{"k":["next"]}"#.utf8)
        let expected = HMAC<SHA256>.authenticationCode(for: Data("1800000000\n".utf8) + data, using: SymmetricKey(data: Data("k".utf8)))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(TippiDevice.signature(key: "k", time: 1_800_000_000, data: data), expected)
    }

    func testCommandsOnlyFromSignedResponse() {
        let key = String(repeating: "a", count: 40)
        let data = Data(#"{"k":["toggle","next","rm","lauter","stumm","prev"]}"#.utf8)
        let sig = TippiDevice.signature(key: key, time: 100, data: data)
        XCTAssertEqual(TippiDevice.commands(response: data, signature: sig, key: key, time: 100), [.toggle, .next, .lauter],
                       "höchstens 4 Einträge ansehen, Unbekanntes verwerfen")
        XCTAssertEqual(TippiDevice.commands(response: data, signature: sig, key: key, time: 101), [], "andere Zeit")
        XCTAssertEqual(TippiDevice.commands(response: data, signature: nil, key: key, time: 100), [], "ohne Signatur")
        XCTAssertEqual(TippiDevice.commands(response: data, signature: String(repeating: "0", count: 64), key: key, time: 100), [])
        XCTAssertEqual(TippiDevice.commands(response: data, signature: sig, key: "b" + key.dropFirst(), time: 100), [], "anderer Schlüssel")
    }

    func testKeyCheck() {
        XCTAssertTrue(TippiDevice.validKey(String(repeating: "a", count: 40)))
        XCTAssertFalse(TippiDevice.validKey("kurz"))
        XCTAssertFalse(TippiDevice.validKey(String(repeating: "a", count: 39) + " "))
    }
}
