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

#if canImport(UIKit)
final class ScrollIntentPreferenceTests: XCTestCase {

    func testWrittenValuesSurviveSiblingsThatWriteNothing() {
        var bottom = BottomVisibilityKey.defaultValue
        BottomVisibilityKey.reduce(value: &bottom) { BottomVisibility(frame: CGRect(x: 0, y: -120, width: 370, height: 900)) }
        BottomVisibilityKey.reduce(value: &bottom) { BottomVisibilityKey.defaultValue }
        XCTAssertEqual(bottom.frame.minY, -120)

        var height = ScrollContainerHeightKey.defaultValue
        ScrollContainerHeightKey.reduce(value: &height) { ScrollContainerHeightKey.defaultValue }
        ScrollContainerHeightKey.reduce(value: &height) { 635 }
        ScrollContainerHeightKey.reduce(value: &height) { ScrollContainerHeightKey.defaultValue }
        XCTAssertEqual(height, 635)
    }

    func testBackgroundImageLoadsOnlyEnabledWebUrlsAndMapsSizeAndPosition() {
        var bg = OrgAppearanceBackgroundImage()
        bg.url = "https://cdn.example/bg.png"
        XCTAssertNil(ChatBackgroundImage.url(for: bg))
        bg.enabled = true
        XCTAssertEqual(ChatBackgroundImage.url(for: bg)?.absoluteString, "https://cdn.example/bg.png")
        for bad in ["", "   ", "file:///etc/hosts", "data:image/png;base64,AAAA", "javascript:alert(1)", "https://"] {
            bg.url = bad
            XCTAssertNil(ChatBackgroundImage.url(for: bg), bad)
        }

        let natural = CGSize(width: 100, height: 50)
        let box = CGSize(width: 400, height: 800)
        XCTAssertEqual(ChatBackgroundImage.scale(size: "cover", natural: natural, box: box), 16)
        XCTAssertEqual(ChatBackgroundImage.scale(size: "contain", natural: natural, box: box), 4)
        XCTAssertEqual(ChatBackgroundImage.scale(size: "auto", natural: natural, box: box), 1)
        XCTAssertEqual(ChatBackgroundImage.anchor("center"), CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(ChatBackgroundImage.anchor("top"), CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(ChatBackgroundImage.anchor("right"), CGPoint(x: 1, y: 0.5))
        XCTAssertEqual(ChatBackgroundImage.anchor("bottom left"), CGPoint(x: 0, y: 1))
    }
}
#endif
