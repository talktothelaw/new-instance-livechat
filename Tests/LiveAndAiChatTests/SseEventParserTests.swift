import XCTest
@testable import LiveAndAiChat

final class SseEventParserTests: XCTestCase {
    func testParsesSingleEvent() {
        let parser = SseEventParser()
        let chunk = "event: next\ndata: {\"id\":\"op1\",\"payload\":{\"data\":{}}}\n\n".data(using: .utf8)!
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "next")
        XCTAssertTrue(events[0].data.contains("\"id\":\"op1\""))
    }

    func testHandlesSplitChunks() {
        let parser = SseEventParser()
        let part1 = "event: next\ndata: {\"id\":\"op1\",\"payload\":{".data(using: .utf8)!
        let part2 = "\"data\":{}}}\n\n".data(using: .utf8)!
        XCTAssertTrue(parser.feed(part1).isEmpty)
        let events = parser.feed(part2)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "next")
    }

    func testIgnoresCommentsAndCRLF() {
        let parser = SseEventParser()
        let chunk = ": heartbeat\r\nevent: complete\r\ndata: {\"id\":\"op1\"}\r\n\r\n".data(using: .utf8)!
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "complete")
    }

    func testMultilineDataConcatenates() {
        let parser = SseEventParser()
        let chunk = "data: line1\ndata: line2\n\n".data(using: .utf8)!
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "line1\nline2")
    }
}
