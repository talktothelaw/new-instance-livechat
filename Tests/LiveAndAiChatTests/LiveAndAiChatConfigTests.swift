import XCTest
@testable import LiveAndAiChat

final class LiveAndAiChatConfigTests: XCTestCase {
    func testEndpointsDeriveCorrectly() throws {
        // Debug builds (this is the test target) accept the override —
        // mirrors the Android `endpoints derive correctly` test.
        let cfg = try LiveAndAiChatConfig(
            apiKey: "sk_live_k:secret",
            baseUrl: "https://chat.example.com"
        )
        XCTAssertEqual(cfg.gqlEndpoint.absoluteString, "https://chat.example.com/service")
        XCTAssertEqual(cfg.sseEndpoint.absoluteString, "https://chat.example.com/graphql/stream")
        XCTAssertEqual(cfg.wsEndpoint.absoluteString, "wss://chat.example.com/graphql/ws")
    }

    func testHttpBaseProducesWsNotWss() throws {
        let cfg = try LiveAndAiChatConfig(apiKey: "sk_live_k:secret", baseUrl: "http://localhost:8010")
        XCTAssertEqual(cfg.wsEndpoint.absoluteString, "ws://localhost:8010/graphql/ws")
    }

    func testDefaultBaseUrlIsProductionService() throws {
        let cfg = try LiveAndAiChatConfig(apiKey: "sk_live_k:secret")
        XCTAssertEqual(cfg.baseUrl, "https://service.newinstance.cloud")
        XCTAssertEqual(cfg.gqlEndpoint.absoluteString, "https://service.newinstance.cloud/service")
        XCTAssertEqual(cfg.wsEndpoint.absoluteString, "wss://service.newinstance.cloud/graphql/ws")
    }

    func testBlankApiKeyRejected() {
        assertConfigError(LiveAndAiChatConfig.exclusiveModeMessage) {
            try LiveAndAiChatConfig(apiKey: "", baseUrl: "https://chat.example.com")
        }
    }

    func testNonHttpBaseRejected() {
        XCTAssertThrowsError(try LiveAndAiChatConfig(apiKey: "sk_live_k:secret", baseUrl: "ftp://chat.example.com"))
    }

    func testFullKeyIsKeptWhole() throws {
        let cfg = try LiveAndAiChatConfig(apiKey: "  sk_live_k:secret \n", baseUrl: "https://chat.example.com")
        XCTAssertEqual(cfg.auth, .apiKey("sk_live_k:secret"))
        XCTAssertEqual(cfg.authMode, .apiKey)
    }

    func testCustomerTokenSelectsJwtMode() throws {
        let cfg = try LiveAndAiChatConfig(customerToken: " a.b.c ")
        XCTAssertEqual(cfg.auth, .customerToken("a.b.c"))
        XCTAssertEqual(cfg.authMode, .customerToken)
    }

    func testBothModesRejected() {
        assertConfigError(LiveAndAiChatConfig.exclusiveModeMessage) {
            try LiveAndAiChatConfig(apiKey: "sk_live_k:secret", customerToken: "a.b.c")
        }
    }

    func testNeitherModeRejected() {
        assertConfigError(LiveAndAiChatConfig.exclusiveModeMessage) { try LiveAndAiChatConfig() }
        assertConfigError(LiveAndAiChatConfig.exclusiveModeMessage) {
            try LiveAndAiChatConfig(apiKey: "  ", customerToken: "\n")
        }
    }

    func testKeyIdWithoutSecretRejected() {
        for key in ["sk_live_k", "sk_live_k:", ":secret", " : "] {
            assertConfigError(LiveAndAiChatConfig.malformedApiKeyMessage) { try LiveAndAiChatConfig(apiKey: key) }
        }
    }

    func testConfigMessagesAreExact() {
        XCTAssertEqual(LiveAndAiChatConfig.exclusiveModeMessage, "pass either apiKey (keyId:secret) or customerToken")
        XCTAssertEqual(LiveAndAiChatConfig.malformedApiKeyMessage, "apiKey must be keyId:secret, or use customerToken")
        XCTAssertEqual(
            LiveAndAiChatConfig.setUserTokenInKeyModeMessage,
            "setUserToken is only available when the SDK is configured with customerToken"
        )
        XCTAssertEqual(LiveAndAiChatConfig.blankCustomerTokenMessage, "customerToken must not be blank")
    }

    private func assertConfigError(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> LiveAndAiChatConfig
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            let e = error as? LiveAndAiChatError
            XCTAssertEqual(e?.type, .validation, file: file, line: line)
            XCTAssertEqual(e?.code, "E_CONFIG", file: file, line: line)
            XCTAssertEqual(e?.recoverable, false, file: file, line: line)
            XCTAssertEqual(e?.message, message, file: file, line: line)
        }
    }
}
