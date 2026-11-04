import XCTest
@testable import LiveAndAiChat

@MainActor
final class RatingStoreTests: XCTestCase {
    private let ended = Conversation(
        id: "conv-1",
        status: .resolved,
        assignedAgentId: "agent-1",
        assignedAgentName: "Sam",
        lastCustomerMessageAt: "2026-11-04T10:00:00.000Z"
    )

    private func store(
        enabled: Bool = true,
        conversation: Conversation? = nil,
        rate: @escaping (String, Int?, String?, Bool) async throws -> Void = { _, _, _, _ in },
        fetch: ((String) async throws -> Conversation?)? = nil
    ) -> ChatStore {
        let resolved = conversation ?? ended
        let s = ChatStore(
            fetchConversation: fetch ?? { _ in resolved },
            rate: rate,
            clearDelayMs: 20
        )
        s.ratingsEnabled = enabled
        return s
    }

    private func refusal(_ code: String?) -> LiveAndAiChatError {
        LiveAndAiChatError(type: .system, message: "refused", recoverable: false, code: code)
    }

    private func gate() -> (wait: @Sendable () async -> Void, open: @Sendable () -> Void) {
        let box = GateBox()
        return ({ await box.wait() }, { box.open() })
    }

    func testKeepsPendingRatingAfterSessionCleared() async {
        let s = store()
        await s.capturePendingRating(conversationId: "conv-1")
        s.setConversation(Conversation(id: "conv-2"), assignment: nil)
        XCTAssertEqual(s.pendingRating, PendingRating(conversationId: "conv-1", agentName: "Sam", status: .idle))
    }

    func testNoPendingRatingWhenRatingsOff() async {
        let s = store(enabled: false)
        await s.capturePendingRating(conversationId: "conv-1")
        XCTAssertNil(s.pendingRating)
    }

    func testNoPendingRatingWhenAlreadyRated() async {
        let rated = Conversation(
            id: "conv-1", status: .closed, lastCustomerMessageAt: "2026-11-04T10:00:00.000Z",
            rating: ConversationRating(score: 4, skipped: false)
        )
        let s = store(conversation: rated)
        await s.capturePendingRating(conversationId: "conv-1")
        XCTAssertNil(s.pendingRating)
    }

    func testNoPendingRatingWhenCustomerNeverWrote() async {
        let s = store(conversation: Conversation(id: "conv-1", status: .closed))
        await s.capturePendingRating(conversationId: "conv-1")
        XCTAssertNil(s.pendingRating)
    }

    func testNoPendingRatingWhenNotEnded() async {
        let s = store(conversation: Conversation(id: "conv-1", status: .active, lastCustomerMessageAt: "x"))
        await s.capturePendingRating(conversationId: "conv-1")
        XCTAssertNil(s.pendingRating)
    }

    func testNoAgentNameWhenNoAgentAssigned() async {
        let s = store(conversation: Conversation(
            id: "conv-1", status: .closed, assignedAgentId: nil, assignedAgentName: "Sam",
            lastCustomerMessageAt: "x"
        ))
        await s.capturePendingRating(conversationId: "conv-1")
        XCTAssertNil(s.pendingRating?.agentName)
        XCTAssertNotNil(s.pendingRating)
    }

    func testClearsSilentlyOnRatingNotAllowed() async {
        let s = store(rate: { _, _, _, _ in throw LiveAndAiChatError(type: .auth, message: "no", recoverable: false, code: "RATING_NOT_ALLOWED") })
        await s.capturePendingRating(conversationId: "conv-1")
        await s.submitRating(score: 3, comment: nil)
        XCTAssertNil(s.pendingRating)
    }

    func testRatingsOffRefusalTurnsRatingsOff() async {
        var refused = refusal(ChatStore.ratingNotAllowed)
        refused.reason = ChatStore.ratingsOff
        let error = refused
        let s = store(rate: { _, _, _, _ in throw error })
        await s.capturePendingRating(conversationId: "conv-1")
        await s.submitRating(score: 3, comment: nil)
        XCTAssertNil(s.pendingRating)
        XCTAssertFalse(s.ratingsEnabled)
        await s.capturePendingRating(conversationId: "conv-2")
        XCTAssertNil(s.pendingRating)
    }

    func testOtherRefusalsKeepRatingsOn() async {
        var refused = refusal(ChatStore.ratingNotAllowed)
        refused.reason = "ALREADY_RATED"
        let error = refused
        let s = store(rate: { _, _, _, _ in throw error })
        await s.capturePendingRating(conversationId: "conv-1")
        await s.submitRating(score: 3, comment: nil)
        XCTAssertNil(s.pendingRating)
        XCTAssertTrue(s.ratingsEnabled)
    }

    func testGqlClientReadsTheRefusalReason() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"errors":[{"message":"no","extensions":{"code":"RATING_NOT_ALLOWED","reason":"RATINGS_OFF"}}]}"#.utf8))
        }
        let gql = GqlClient(
            endpoint: URL(string: "https://chat.example.com/service")!,
            credential: ChatCredential(.apiKey("sk_live_keyid:secret")),
            session: URLSession(configuration: StubURLProtocol.configuration())
        )
        do {
            try await gql.execute(query: Operations.rateConversation, variables: ["conversationId": "conv-1", "score": 3])
            XCTFail("expected a refusal")
        } catch let error as LiveAndAiChatError {
            XCTAssertEqual(error.code, ChatStore.ratingNotAllowed)
            XCTAssertEqual(error.reason, ChatStore.ratingsOff)
        }
    }

    func testKeepsCardOnNetworkError() async {
        let s = store(rate: { _, _, _, _ in throw LiveAndAiChatError(type: .network, message: "down", recoverable: true) })
        await s.capturePendingRating(conversationId: "conv-1")
        await s.submitRating(score: 3, comment: nil)
        XCTAssertEqual(s.pendingRating?.status, .error)
        await s.submitRating(score: 3, comment: nil)
        XCTAssertEqual(s.pendingRating?.status, .error)
    }

    func testSuccessShowsSentThenClears() async throws {
        let s = store()
        await s.capturePendingRating(conversationId: "conv-1")
        let task = Task { await s.submitRating(score: 5, comment: nil) }
        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertEqual(s.pendingRating?.status, .sent)
        await task.value
        XCTAssertNil(s.pendingRating)
    }

    func testBlankCommentSentAsNilAndLongCommentCut() async {
        var sent: [(Int?, String?, Bool)] = []
        let s = store(rate: { _, score, comment, skip in sent.append((score, comment, skip)) })
        await s.capturePendingRating(conversationId: "conv-1")
        await s.submitRating(score: 4, comment: "   ")
        await s.capturePendingRating(conversationId: "conv-1")
        await s.submitRating(score: 4, comment: String(repeating: "a", count: 1500))
        XCTAssertNil(sent[0].1)
        XCTAssertEqual(sent[1].1?.count, 1000)
    }

    func testRejectsScoresOutsideOneToFive() async {
        var calls = 0
        let s = store(rate: { _, _, _, _ in calls += 1 })
        await s.capturePendingRating(conversationId: "conv-1")
        await s.submitRating(score: 0, comment: nil)
        await s.submitRating(score: 6, comment: nil)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(s.pendingRating?.status, .idle)
    }

    func testSkipClearsAtOnce() async {
        var skipped = false
        let s = store(rate: { _, _, _, skip in skipped = skip })
        await s.capturePendingRating(conversationId: "conv-1")
        await s.skipRating()
        XCTAssertTrue(skipped)
        XCTAssertNil(s.pendingRating)
    }

    func testConcurrentCapturesFetchOnce() async {
        let g = gate()
        var fetched = 0
        let s = store(fetch: { _ in fetched += 1; await g.wait(); return self.ended })
        async let a: Void = s.capturePendingRating(conversationId: "conv-1")
        async let b: Void = s.capturePendingRating(conversationId: "conv-1")
        try? await Task.sleep(nanoseconds: 20_000_000)
        g.open()
        _ = await (a, b)
        XCTAssertEqual(fetched, 1)
    }

    func testLateFetchDoesNotResetSendingOrErrorCard() async {
        let g = gate()
        var calls = 0
        let s = store(
            rate: { _, _, _, _ in throw LiveAndAiChatError(type: .network, message: "down", recoverable: true) },
            fetch: { _ in
                calls += 1
                if calls == 2 { await g.wait() }
                return self.ended
            }
        )
        await s.capturePendingRating(conversationId: "conv-1")
        async let late: Void = s.capturePendingRating(conversationId: "conv-1")
        try? await Task.sleep(nanoseconds: 20_000_000)
        await s.submitRating(score: 2, comment: nil)
        XCTAssertEqual(s.pendingRating?.status, .error)
        g.open()
        await late
        XCTAssertEqual(s.pendingRating?.status, .error)
    }

    func testDiscardClearsCardAndInvalidatesInFlightCapture() async {
        let g = gate()
        let s = store(fetch: { _ in await g.wait(); return self.ended })
        async let capture: Void = s.capturePendingRating(conversationId: "conv-1")
        try? await Task.sleep(nanoseconds: 20_000_000)
        s.discardPendingRating()
        g.open()
        await capture
        XCTAssertNil(s.pendingRating)
    }

    func testDiscardedCaptureDoesNotBlockNewCaptureForSameId() async {
        let g = gate()
        var calls = 0
        let s = store(fetch: { _ in
            calls += 1
            if calls == 1 { await g.wait() }
            return self.ended
        })
        async let first: Void = s.capturePendingRating(conversationId: "conv-1")
        try? await Task.sleep(nanoseconds: 20_000_000)
        s.discardPendingRating()
        await s.capturePendingRating(conversationId: "conv-1")
        XCTAssertNotNil(s.pendingRating)
        g.open()
        await first
        XCTAssertEqual(calls, 2)
        XCTAssertNotNil(s.pendingRating)
    }

    func testResetDiscardsPendingRating() async {
        let s = store()
        await s.capturePendingRating(conversationId: "conv-1")
        s.reset()
        XCTAssertNil(s.pendingRating)
    }

    func testOperationsSelectRatingFields() throws {
        XCTAssertTrue(Operations.getCsConfig.contains("ratingsEnabled"))
        XCTAssertTrue(Operations.getConversationState.contains("lastCustomerMessageAt"))
        XCTAssertTrue(Operations.rateConversation.contains("rateCsConversation"))
        let json = #"{"settings":{"ratingsEnabled":true}}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(OrgChatConfig.self, from: json)
        XCTAssertTrue(cfg.settings.ratingsEnabled)
    }
}

private final class GateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if opened { lock.unlock(); cont.resume() } else { waiters.append(cont); lock.unlock() }
        }
    }

    func open() {
        lock.lock()
        opened = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

final class RatingCopyTests: XCTestCase {
    func testTitleNamesTheAgentOnlyWhenThereIsOne() {
        XCTAssertEqual(RatingCopy.title(agentName: "Sam"), "How was your chat with Sam?")
        XCTAssertEqual(RatingCopy.title(agentName: nil), "How was your chat?")
        XCTAssertEqual(RatingCopy.title(agentName: "  "), "How was your chat?")
    }

    func testStarLabels() {
        XCTAssertEqual(RatingCopy.starLabel(1), "1 star")
        XCTAssertEqual(RatingCopy.starLabel(5), "5 stars")
    }
}
