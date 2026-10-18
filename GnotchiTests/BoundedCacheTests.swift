import XCTest
@testable import Gnotchi

/// Begrenzter Zwischenspeicher für App-Symbole (Review 18.10.).
final class BoundedCacheTests: XCTestCase {

    func testStoresAndReturns() {
        var c = BoundedCache<String, Int>(limit: 2)
        c.insert(1, for: "a")
        XCTAssertEqual(c["a"], 1)
        XCTAssertNil(c["b"])
    }

    func testEvictsOldestBeyondLimit() {
        var c = BoundedCache<String, Int>(limit: 2)
        c.insert(1, for: "a")
        c.insert(2, for: "b")
        c.insert(3, for: "c")
        XCTAssertNil(c["a"])
        XCTAssertEqual(c["b"], 2)
        XCTAssertEqual(c["c"], 3)
        XCTAssertEqual(c.count, 2)
    }

    func testOverwriteDoesNotGrow() {
        var c = BoundedCache<String, Int>(limit: 2)
        c.insert(1, for: "a")
        c.insert(5, for: "a")
        c.insert(2, for: "b")
        XCTAssertEqual(c["a"], 5)
        XCTAssertEqual(c.count, 2)
    }

    /// Fehlende App wird auch gemerkt (Wert nil), sonst fragte jede Darstellung LaunchServices erneut.
    func testRemembersMiss() {
        var c = BoundedCache<String, Int?>(limit: 2)
        c.insert(nil, for: "x")
        XCTAssertNotNil(c["x"] as Int??)
        XCTAssertNil(c["y"] as Int??)
    }
}
