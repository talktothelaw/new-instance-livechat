import XCTest
import Combine
@testable import LiveAndAiChat

@MainActor
final class StateForwardingTests: XCTestCase {
    func testObjectWillChangeStillFiresAfterTeardownAndResubscribe() throws {
        let sdk = try LiveAndAiChat.Builder()
            .config(LiveAndAiChatConfig(customerToken: makeJwt(sub: "cust-1", nonce: "a"), baseUrl: "http://127.0.0.1:9"))
            .build()
        defer {
            sdk.session.clear()
            sdk.destroy()
        }
        sdk.session.clear()
        sdk.subscriptionClient = FakeSubscriptionClient()
        sdk.session.conversationId = "conv-1"

        try sdk.setUserToken(makeJwt(sub: "cust-1", nonce: "b"))
        XCTAssertNotNil(sdk.subscriptionClient)

        var fired = 0
        let observation = sdk.objectWillChange.sink { fired += 1 }
        defer { observation.cancel() }

        sdk.store.updateDraft("hello")
        XCTAssertEqual(fired, 1)

        sdk.attachmentQueue.clear()
        XCTAssertEqual(fired, 2)
    }
}
