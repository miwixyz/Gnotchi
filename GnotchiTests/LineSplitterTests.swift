import XCTest
@testable import Gnotchi

/// G4: Strom zeilenweise, überlange Zeilen verwerfen statt Speicher fluten.
final class LineSplitterTests: XCTestCase {

    func testSplitsAcrossChunks() {
        var s = LineSplitter(maxLineBytes: 100)
        XCTAssertEqual(s.feed(Data("{\"a\":1}\n{\"b\"".utf8)), [Data("{\"a\":1}".utf8)])
        XCTAssertEqual(s.feed(Data(":2}\n".utf8)), [Data("{\"b\":2}".utf8)])
    }

    func testDropsOverlongLineAndCounts() {
        var s = LineSplitter(maxLineBytes: 5)
        XCTAssertEqual(s.feed(Data("1234567890\nok\n".utf8)), [Data("ok".utf8)])
        XCTAssertEqual(s.dropped, 1)
    }

    func testOverlongAcrossChunksStaysDropped() {
        var s = LineSplitter(maxLineBytes: 5)
        XCTAssertEqual(s.feed(Data("123456".utf8)), [])
        XCTAssertEqual(s.feed(Data("789\nok\n".utf8)), [Data("ok".utf8)])
        XCTAssertEqual(s.dropped, 1)
    }

    func testIgnoresEmptyLines() {
        var s = LineSplitter(maxLineBytes: 10)
        XCTAssertEqual(s.feed(Data("\n\nx\n".utf8)), [Data("x".utf8)])
    }

    func testLineOfExactlyMaxIsKept() {
        var s = LineSplitter(maxLineBytes: 5)
        XCTAssertEqual(s.feed(Data("12345\n".utf8)), [Data("12345".utf8)])
        XCTAssertEqual(s.feed(Data("123456\n".utf8)), [])
        XCTAssertEqual(s.dropped, 1)
    }

    func testLargeLineAcrossManyChunks() {
        let line = Data(repeating: 0x61, count: 2_000_000)
        var input = line
        input.append(0x0A)
        var s = LineSplitter(maxLineBytes: 4_000_000)
        var lines: [Data] = []
        var offset = 0
        while offset < input.count {
            let end = min(offset + 65_536, input.count)
            lines += s.feed(input.subdata(in: offset..<end))
            offset = end
        }
        XCTAssertEqual(lines, [line])
        XCTAssertEqual(s.dropped, 0)
    }

    func testOverlongByAccumulationAcrossChunks() {
        var s = LineSplitter(maxLineBytes: 5)
        XCTAssertEqual(s.feed(Data("123".utf8)), [])
        XCTAssertEqual(s.feed(Data("456\nok\n".utf8)), [Data("ok".utf8)])
        XCTAssertEqual(s.dropped, 1)
    }

    func testNewlineAsFirstByteOfChunk() {
        var s = LineSplitter(maxLineBytes: 10)
        XCTAssertEqual(s.feed(Data("ab".utf8)), [])
        XCTAssertEqual(s.feed(Data("\ncd\n".utf8)), [Data("ab".utf8), Data("cd".utf8)])
    }
}
