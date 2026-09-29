import XCTest
@testable import LiveAndAiChat

final class ChatCardLayoutTests: XCTestCase {

    func testLargeScreenPlacesTheWebSizedPanelBottomRight() {
        let frame = ChatCardLayout.frame(in: CGRect(x: 0, y: 0, width: 1024, height: 1366), rightToLeft: false)
        XCTAssertEqual(frame, CGRect(x: 604, y: 726, width: 400, height: 620))
    }

    func testRightToLeftMirrorsThePanelToBottomLeft() {
        let frame = ChatCardLayout.frame(in: CGRect(x: 0, y: 0, width: 1024, height: 1366), rightToLeft: true)
        XCTAssertEqual(frame, CGRect(x: 20, y: 726, width: 400, height: 620))
    }

    func testPanelStaysInsideAnInsetArea() {
        let frame = ChatCardLayout.frame(in: CGRect(x: 0, y: 24, width: 834, height: 1166), rightToLeft: false)
        XCTAssertEqual(frame, CGRect(x: 414, y: 550, width: 400, height: 620))
    }

    func testShortAreaAboveAKeyboardShrinksThePanelHeight() {
        let frame = ChatCardLayout.frame(in: CGRect(x: 0, y: 24, width: 1133, height: 300), rightToLeft: false)
        XCTAssertEqual(frame, CGRect(x: 713, y: 44, width: 400, height: 260))
    }

    func testNarrowAreaShrinksThePanelWidth() {
        let frame = ChatCardLayout.frame(in: CGRect(x: 0, y: 0, width: 320, height: 1000), rightToLeft: false)
        XCTAssertEqual(frame, CGRect(x: 20, y: 360, width: 280, height: 620))
    }
}
