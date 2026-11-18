import AppKit
import Carbon.HIToolbox
import XCTest

/// G60: Als reinen Text einfügen per Kürzel – Umwandeln, Einfügen, Zurückholen, vertrauliche Kopien leeren.
@MainActor
final class PlainPasteTests: XCTestCase {

    private var board: NSPasteboard!
    private var defaults: UserDefaults!
    private let suite = "dev.mwlr.gnotchi.tests.plainpaste"
    private let rtf = NSPasteboard.PasteboardType.rtf

    override func setUp() {
        super.setUp()
        board = NSPasteboard(name: NSPasteboard.Name("dev.mwlr.gnotchi.tests.plainpaste.\(UUID().uuidString)"))
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        board.releaseGlobally()
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeLink(canPaste: Bool = true, onPaste: @escaping (NSPasteboard) -> Void = { _ in }) -> PlainPasteLink {
        let link = PlainPasteLink(activity: ActivityModel(media: NowPlayingModel()), prefs: Preferences(defaults: defaults),
                                  pasteboard: board)
        link.canPaste = { canPaste }
        let pb = board!
        link.sendPaste = { onPaste(pb) }
        link.modifiersHeld = { false }
        link.restoreDelay = 0.01
        link.concealedClearDelay = 0.01
        return link
    }

    private func copyFormatted(_ text: String, concealed: Bool = false) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data("{\\rtf1 {\\b \(text)}}".utf8), forType: rtf)
        if concealed { item.setData(Data(), forType: PlainPaste.concealedType) }
        board.clearContents()
        board.writeObjects([item])
    }

    func testOffByDefault() {
        XCTAssertFalse(Preferences(defaults: defaults).plainPaste)
    }

    func testDefaultHotKeyIsShiftCommand() {
        let key = PlainPasteLink.defaultHotKey()
        XCTAssertEqual(key?.modifiers, UInt32(shiftKey | cmdKey))
    }

    func testPastesPlainThenRestoresFormatting() async {
        copyFormatted("fett")
        var during: [NSPasteboard.PasteboardType] = []
        let link = makeLink { during = $0.types ?? [] }
        let outcome = await link.run()
        XCTAssertEqual(outcome, .restored)
        XCTAssertTrue(during.contains(.string))
        XCTAssertFalse(during.contains(rtf), "beim Einfügen nur reiner Text")
        XCTAssertTrue(during.contains(PlainPaste.transientType), "Zwischenstand nie in einen Verlauf")
        XCTAssertNotNil(board.data(forType: rtf), "Formatierung zurück")
        XCTAssertEqual(board.string(forType: .string), "fett")
        XCTAssertTrue(board.types?.contains(PlainPaste.transientType) == true, "Rückschrift nicht als neue Kopie")
    }

    func testConcealedIsClearedNotRestored() async {
        copyFormatted("passwort", concealed: true)
        var markedDuring = false
        let link = makeLink { markedDuring = $0.types?.contains(PlainPaste.concealedType) == true }
        let outcome = await link.run()
        XCTAssertEqual(outcome, .cleared)
        XCTAssertTrue(markedDuring, "reiner Text bleibt vertraulich markiert")
        XCTAssertNil(board.string(forType: .string), "danach leer")
    }

    func testWithoutHelperOnlyConverts() async {
        copyFormatted("fett")
        var pasted = false
        let link = makeLink(canPaste: false) { _ in pasted = true }
        let outcome = await link.run()
        XCTAssertEqual(outcome, .convertedOnly)
        XCTAssertFalse(pasted)
        XCTAssertNil(board.data(forType: rtf))
        XCTAssertEqual(board.string(forType: .string), "fett")
    }

    func testWithoutHelperConcealedClearedLater() async throws {
        copyFormatted("passwort", concealed: true)
        _ = await makeLink(canPaste: false).run()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(board.string(forType: .string))
    }

    func testNewerCopyIsKept() async {
        copyFormatted("alt")
        let link = makeLink { pb in
            pb.clearContents()
            pb.setString("neu", forType: .string)
        }
        let outcome = await link.run()
        XCTAssertEqual(outcome, .newerCopy)
        XCTAssertEqual(board.string(forType: .string), "neu")
        XCTAssertNil(board.data(forType: rtf))
    }

    func testNoTextLeavesBoardUntouched() async {
        board.clearContents()
        board.setData(Data([1, 2, 3]), forType: .png)
        let before = board.changeCount
        var pasted = false
        let outcome = await makeLink { _ in pasted = true }.run()
        XCTAssertEqual(outcome, .noText)
        XCTAssertFalse(pasted)
        XCTAssertEqual(board.changeCount, before)
    }

    func testWaitsForModifierRelease() async {
        copyFormatted("fett")
        var held = 3
        var heldAtPaste = -1
        let link = makeLink { _ in heldAtPaste = held }
        link.modifiersHeld = {
            held -= 1
            return held >= 0
        }
        _ = await link.run()
        XCTAssertLessThan(heldAtPaste, 0, "⌘V erst, wenn ⇧/⌥/⌃ losgelassen sind")
    }

    /// Code-Audit 18.11.: Gnotchi erkennt den Schlüssel (G43) und leert ihn nach 5 Min. – das Zurückschreiben setzte
    /// diese Uhr außer Kraft, der Schlüssel blieb unbegrenzt in der Zwischenablage.
    func testDetectedSecretIsClearedNotRestored() async {
        let prefs = Preferences(defaults: defaults)
        prefs.clipboard = true
        prefs.clipboardSecrets = true
        copyFormatted("ghp_" + String(repeating: "A1b2", count: 9))
        let outcome = await makeLink().run()
        XCTAssertEqual(outcome, .cleared)
        XCTAssertNil(board.string(forType: .string))
    }

    /// Code-Audit 18.11.: Zweimal ⇧⌘V kurz hintereinander (zwei Felder) – der zweite Druck darf nicht verloren gehen.
    func testSecondPressPastesAgain() async {
        copyFormatted("fett")
        var pastes = 0
        let link = makeLink { _ in pastes += 1 }
        link.restoreDelay = 0.2
        async let first = link.run()
        try? await Task.sleep(for: .milliseconds(50))
        let second = await link.run()
        XCTAssertEqual(second, .again)
        let firstOutcome = await first
        XCTAssertEqual(firstOutcome, .restored)
        XCTAssertEqual(pastes, 2)
        XCTAssertNotNil(board.data(forType: rtf))
    }

    func testTooLargeSnapshotIsNotHeld() {
        copyFormatted("fett")
        let snapshot = PlainPaste.capture(board, limit: 5)
        XCTAssertNil(snapshot.items)
        XCTAssertNotNil(PlainPaste.capture(board).items)
    }
}
