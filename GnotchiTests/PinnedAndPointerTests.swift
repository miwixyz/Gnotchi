import CryptoKit
import XCTest

/// Michael 14.11. (aus Hikidashi): Angeheftetes steht im Verlauf oben; große Ansicht am Mauszeiger.
@MainActor
final class PinnedAndPointerTests: XCTestCase {

    private func text(_ string: String) -> ClipPayload {
        ClipPayload(formats: [.init(type: ClipboardCapture.UTI.plain, data: Data(string.utf8))], plain: string)
    }

    func testPinnedFirstInHistoryOnly() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let now = Date()
        let old = try store.add(text("alt angeheftet"), kind: .text, source: nil, now: now.addingTimeInterval(-86_400 * 5))
        let new = try store.add(text("neu"), kind: .text, source: nil, now: now)
        let mid = try store.add(text("mitte"), kind: .text, source: nil, now: now.addingTimeInterval(-60))
        try store.togglePinned(old)
        XCTAssertEqual(store.entries().map(\.id), [old.id, new.id, mid.id], "Angeheftetes zuerst, Rest nach Zeit")
        XCTAssertEqual(store.entries(matching: "e").first?.id, old.id, "auch in der Suche")
        let pinned = try XCTUnwrap(store.pinned)
        XCTAssertEqual(store.entries(in: pinned).map(\.id), [old.id])
        try store.togglePinned(old)
        XCTAssertEqual(store.entries().map(\.id), [new.id, mid.id, old.id], "gelöst → wieder nach Zeit")
    }

    func testDayGroupsGetPinnedHeader() throws {
        let store = try ClipboardStore(directory: nil, key: SymmetricKey(size: .bits256))
        let now = Date()
        let old = try store.add(text("a"), kind: .text, source: nil, now: now.addingTimeInterval(-86_400 * 5))
        _ = try store.add(text("b"), kind: .text, source: nil, now: now)
        try store.togglePinned(old)
        let groups = ClipDays.group(store.entries(), pinnedFirst: true, now: now)
        XCTAssertEqual(groups.map(\.label).first, "Angeheftet")
        XCTAssertEqual(groups.first?.entries.map(\.id), [old.id])
        XCTAssertEqual(groups.count, 2)
        XCTAssertNotEqual(ClipDays.group(store.entries(), now: now).first?.label, "Angeheftet", "ohne Schalter wie bisher")
    }

    func testPointerFrameStaysOnScreen() {
        let area = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let w = ClipboardPanelController.sideWidth, h = ClipboardPanelController.pointerHeight
        let mid = ClipboardPanelController.pointerFrame(mouse: CGPoint(x: 400, y: 700), in: area)
        XCTAssertEqual(mid, CGRect(x: 400, y: 700 - h, width: w, height: h), "obere linke Ecke an der Maus")
        for mouse in [CGPoint(x: 1439, y: 5), CGPoint(x: -50, y: 2000), CGPoint(x: 1440, y: 875)] {
            let f = ClipboardPanelController.pointerFrame(mouse: mouse, in: area)
            XCTAssertTrue(area.insetBy(dx: 7.9, dy: 7.9).contains(f), "\(mouse) → \(f)")
        }
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 300)
        XCTAssertTrue(tiny.contains(ClipboardPanelController.pointerFrame(mouse: .zero, in: tiny)), "kleiner Bildschirm")
    }
}
