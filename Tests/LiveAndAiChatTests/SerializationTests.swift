import XCTest
@testable import LiveAndAiChat

final class SerializationTests: XCTestCase {
    func testChatMessageRoundtrip() throws {
        let json = """
        {
          "id": "msg-1",
          "clientId": "c-1",
          "conversationId": "conv-1",
          "content": "hello",
          "type": "AI",
          "status": "DELIVERED",
          "seq": 7
        }
        """.data(using: .utf8)!
        let msg = try JSONDecoder().decode(ChatMessage.self, from: json)
        XCTAssertEqual(msg.id, "msg-1")
        XCTAssertEqual(msg.type, .ai)
        XCTAssertEqual(msg.status, .delivered)
        XCTAssertEqual(msg.seq, 7)
    }

    func testConversationIgnoresExtraFields() throws {
        let json = """
        {
          "id": "c1",
          "status": "ACTIVE",
          "assignedAgentId": "agent-1",
          "assignedAgentName": "Ada",
          "extraField": "should-be-ignored"
        }
        """.data(using: .utf8)!
        let conv = try JSONDecoder().decode(Conversation.self, from: json)
        XCTAssertEqual(conv.status, .active)
        XCTAssertEqual(conv.assignedAgentId, "agent-1")
    }

    func testAssignmentDecodesStatuses() throws {
        let json = #"{"id":"a1","status":"PENDING","queuePosition":3}"#.data(using: .utf8)!
        let a = try JSONDecoder().decode(Assignment.self, from: json)
        XCTAssertEqual(a.status, .pending)
        XCTAssertEqual(a.queuePosition, 3)
    }

    func testTransportModeDecodesLowercase() throws {
        let sse = try JSONDecoder().decode(TransportMode.self, from: "\"sse\"".data(using: .utf8)!)
        let ws = try JSONDecoder().decode(TransportMode.self, from: "\"ws\"".data(using: .utf8)!)
        XCTAssertEqual(sse, .sse)
        XCTAssertEqual(ws, .ws)
    }

    func testAppearanceDecodesWithMissingFields() throws {
        // Tests the lenient decoder: every missing field falls back to the
        // spec default. Server returning only `version` should still
        // produce a fully-populated `OrgAppearance`.
        let json = #"{"version":1}"#.data(using: .utf8)!
        let appearance = try JSONDecoder().decode(OrgAppearance.self, from: json)
        XCTAssertEqual(appearance.version, 1)
        XCTAssertEqual(appearance.colors.headerBackground, "#9333EA")
        XCTAssertEqual(appearance.colors.chatBackground, "#F7F7FB")
        XCTAssertFalse(appearance.backgroundImage.enabled)
    }

    func testAppearanceBackgroundImageRepeatKey() throws {
        // The GraphQL field is `repeat` (a Swift keyword), exposed as
        // `repeatStyle` on the model. Verify the mapping survives JSON.
        let json = """
        {"enabled":true,"url":"https://x","opacity":0.8,"position":"center","size":"cover","repeat":"no-repeat","overlayColor":"#000000","overlayOpacity":0.2}
        """.data(using: .utf8)!
        let bg = try JSONDecoder().decode(OrgAppearanceBackgroundImage.self, from: json)
        XCTAssertTrue(bg.enabled)
        XCTAssertEqual(bg.url, "https://x")
        XCTAssertEqual(bg.repeatStyle, "no-repeat")
        XCTAssertEqual(bg.overlayOpacity, 0.2, accuracy: 0.0001)
    }
}
