import XCTest
@testable import LiveAndAiChat

#if canImport(UIKit)
final class TitleCaseTests: XCTestCase {

    func testCapitalizesFirstLettersAndKeepsTheRestAsTyped() {
        XCTAssertEqual(ChatHeader.titleCase("nwok lawrence"), "Nwok Lawrence")
        XCTAssertEqual(ChatHeader.titleCase("NewInstance support"), "NewInstance Support")
        XCTAssertEqual(ChatHeader.titleCase("AI assistant"), "AI Assistant")
        XCTAssertEqual(ChatHeader.titleCase("iPhone  help"), "IPhone  Help")
    }
}
#endif
