import XCTest

/// G45: Der Befehlskanal der Bild-Testkopie nimmt nur die feste Befehlsliste an.
final class DebugCommandTests: XCTestCase {
    private func parse(_ json: String) -> DebugCommand? { DebugCommand.parse(Data(json.utf8)) }

    func testAcceptsTheFixedCommands() {
        XCTAssertEqual(parse(#"{"v":1,"id":"abc123","cmd":"status"}"#), DebugCommand(id: "abc123", kind: .status))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"snapshot","window":"einstellungen"}"#)?.kind, .snapshot(window: "einstellungen"))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"snapshot","window":"hilfe"}"#)?.kind, .snapshot(window: "hilfe"))
        XCTAssertEqual(parse(#"{"v":1,"id":"a","cmd":"appearance","mode":"dark"}"#)?.kind, .appearance("dark"))
    }

    func testRejectsEverythingElse() {
        // Fremde Befehle, fremde Fenster (Insel/Zwischenablage zeigen echte Inhalte), fremde Werte.
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"play"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"snapshot","window":"zwischenablage"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"snapshot"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"a","cmd":"appearance","mode":"rot"}"#))
        // Version: Zahl 1, kein Wahrheitswert, keine 2.
        XCTAssertNil(parse(#"{"v":true,"id":"a","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":2,"id":"a","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"id":"a","cmd":"status"}"#))
        XCTAssertNil(parse("kein json"))
    }

    func testIDCannotEscapeTheAnswerFolder() {
        // Die id wird Dateiname – nur Buchstaben und Ziffern, 1–32 Zeichen.
        XCTAssertNil(parse(#"{"v":1,"id":"../x","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"a/b","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"ä","cmd":"status"}"#))
        XCTAssertNil(parse(#"{"v":1,"id":"\#(String(repeating: "a", count: 33))","cmd":"status"}"#))
        XCTAssertNotNil(parse(#"{"v":1,"id":"\#(String(repeating: "a", count: 32))","cmd":"status"}"#))
    }

    func testReleaseNameStaysGnotchi() {
        // Im Testlauf ist die Kennung nicht die der Bild-Kopie: echter Ordnername.
        XCTAssertFalse(AppDirectory.isBildCopy)
        XCTAssertEqual(AppDirectory.name, "Gnotchi")
    }
}
