import XCTest
@testable import LiveAndAiChat

@MainActor
final class ChatStoreTests: XCTestCase {
    func testMergeDedupesById() {
        let store = ChatStore()
        let a = msg(id: "1", clientId: "c1", content: "hi")
        let a2 = msg(id: "1", clientId: "c1", content: "hi-edited")
        store.mergeMessage(a)
        store.mergeMessage(a2)
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].content, "hi-edited")
    }

    func testMergeReplacesOptimisticByClientId() {
        let store = ChatStore()
        let temp = msg(id: "temp_c1", clientId: "c1", content: "hi")
        let real = msg(id: "real-1", clientId: "c1", content: "hi", seq: 5)
        store.mergeMessage(temp)
        store.mergeMessage(real)
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].id, "real-1")
        XCTAssertEqual(store.messages[0].seq, 5)
    }

    func testInboundIncrementsUnreadWhileClosed() {
        let store = ChatStore()
        store.mergeMessage(msg(id: "1", clientId: nil, type: .agent))
        store.mergeMessage(msg(id: "2", clientId: nil, type: .ai))
        XCTAssertEqual(store.unreadCount, 2)
    }

    func testUnreadResetWhileOpen() {
        let store = ChatStore()
        store.openWidget()
        store.mergeMessage(msg(id: "1", clientId: nil, type: .agent))
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testFlowStateDerivation() {
        XCTAssertEqual(ChatStore.derive(conversation: conv("c1", .closed), assignment: nil), .ended)
        XCTAssertEqual(ChatStore.derive(conversation: conv("c1", .active), assignment: nil), .liveChat)
        XCTAssertEqual(
            ChatStore.derive(
                conversation: conv("c1", .waiting),
                assignment: Assignment(id: "a1", status: .pending)
            ),
            .handoffPending
        )
        XCTAssertEqual(ChatStore.derive(conversation: conv("c1", .botActive), assignment: nil), .botConversation)
        XCTAssertEqual(ChatStore.derive(conversation: nil, assignment: nil), .idle)
    }

    func testMessagesSortedBySeq() {
        let store = ChatStore()
        store.mergeMessage(msg(id: "a", clientId: nil, seq: 3))
        store.mergeMessage(msg(id: "b", clientId: nil, seq: 1))
        store.mergeMessage(msg(id: "c", clientId: nil, seq: 2))
        XCTAssertEqual(store.messages.map { $0.id }, ["b", "c", "a"])
    }

    func testHighestSeqTracksMax() {
        let store = ChatStore()
        XCTAssertEqual(store.highestSeq, 0)
        store.mergeMessage(msg(id: "a", clientId: nil, seq: 5))
        XCTAssertEqual(store.highestSeq, 5)
        store.mergeMessage(msg(id: "b", clientId: nil, seq: 3))
        XCTAssertEqual(store.highestSeq, 5)  // not lowered
        store.mergeMessage(msg(id: "c", clientId: nil, seq: 12))
        XCTAssertEqual(store.highestSeq, 12)
        store.setInitialMessages([msg(id: "d", clientId: nil, seq: 20)])
        XCTAssertEqual(store.highestSeq, 20)
    }

    func testUpdateMessageTransitionsToFailedInPlace() {
        let store = ChatStore()
        store.mergeMessage(msg(id: "temp_x", clientId: "x", content: "hi"))
        store.updateMessage(messageId: "temp_x") { existing in
            ChatMessage(
                id: existing.id, clientId: existing.clientId, conversationId: existing.conversationId,
                content: existing.content, type: existing.type, status: .failed,
                seq: existing.seq, sender: existing.sender, attachments: existing.attachments,
                createdAt: existing.createdAt, readAt: existing.readAt
            )
        }
        XCTAssertEqual(store.messages.first { $0.id == "temp_x" }?.status, .failed)
    }

    func testResetClearsHighestSeq() {
        let store = ChatStore()
        store.mergeMessage(msg(id: "a", clientId: nil, seq: 99))
        XCTAssertEqual(store.highestSeq, 99)
        store.reset()
        XCTAssertEqual(store.highestSeq, 0)
    }

    // MARK: - helpers

    private func msg(
        id: String,
        clientId: String?,
        content: String = "",
        type: MessageType = .customer,
        seq: Int64? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            clientId: clientId,
            conversationId: "conv",
            content: content,
            type: type,
            seq: seq
        )
    }

    private func conv(_ id: String, _ status: ConversationStatus) -> Conversation {
        Conversation(id: id, status: status)
    }
}
