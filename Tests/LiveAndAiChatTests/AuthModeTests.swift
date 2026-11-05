import XCTest
import Combine
@testable import LiveAndAiChat

final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _requests: [URLRequest] = []
    private static var _handler: (URLRequest) -> (Int, Data) = { _ in (200, Data(#"{"data":{"ok":true}}"#.utf8)) }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    static func reset(_ handler: @escaping (URLRequest) -> (Int, Data) = { _ in (200, Data(#"{"data":{"ok":true}}"#.utf8)) }) {
        lock.lock()
        _requests = []
        _handler = handler
        lock.unlock()
    }

    static func configuration() -> URLSessionConfiguration {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return cfg
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._requests.append(request)
        let handler = Self._handler
        Self.lock.unlock()
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class FakeSubscriptionClient: SubscriptionClient {
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> { Just(.connected).eraseToAnyPublisher() }
    var onAuthFailure: ((String) -> Void)?
    private(set) var stopped = false
    func start() {}
    func stop() { stopped = true }
    func subscribe(_ request: SubscriptionRequest) -> AnyPublisher<[String: Any], Never> {
        Empty().eraseToAnyPublisher()
    }
}

final class LogCapture {
    private let lock = NSLock()
    private var lines: [String] = []

    init() {
        LACDiagnosticLog.setHandler { [weak self] line in self?.append(line) }
    }

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func stop() { LACDiagnosticLog.setHandler(nil) }
}

func makeJwt(sub: String, nonce: String) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: ["sub": sub, "nonce": nonce])
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
    return "eyJhbGciOiJIUzI1NiJ9.\(encoded).signature\(nonce)"
}

let unauthenticatedNext = #"{"id":"op1","payload":{"errors":[{"message":"Session expired","extensions":{"code":"UNAUTHENTICATED"}}]}}"#

final class AuthHeaderTests: XCTestCase {
    private let secretKey = "sk_live_keyid:TOPSECRETVALUE"
    private let endpoint = URL(string: "https://chat.example.com/service")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testKeyModeSendsOnlyFullApiKey() async throws {
        let gql = GqlClient(
            endpoint: endpoint,
            credential: ChatCredential(.apiKey(secretKey)),
            session: URLSession(configuration: StubURLProtocol.configuration())
        )
        try await gql.execute(query: "query { ok }")
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), secretKey)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-newinstance-sdk"), "ios/0.7.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "LiveAndAiChat-iOS/0.7.0")
    }

    func testJwtModeSendsOnlyBearer() async throws {
        let token = makeJwt(sub: "cust-1", nonce: "a")
        let gql = GqlClient(
            endpoint: endpoint,
            credential: ChatCredential(.customerToken(token)),
            session: URLSession(configuration: StubURLProtocol.configuration())
        )
        try await gql.execute(query: "query { ok }")
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-newinstance-sdk"), "ios/0.7.0")
    }

    func testCredentialSwapAppliesToLaterRequests() async throws {
        let first = makeJwt(sub: "cust-1", nonce: "a")
        let second = makeJwt(sub: "cust-1", nonce: "b")
        let credential = ChatCredential(.customerToken(first))
        let gql = GqlClient(
            endpoint: endpoint,
            credential: credential,
            session: URLSession(configuration: StubURLProtocol.configuration())
        )
        try await gql.execute(query: "query { ok }")
        credential.setCustomerToken(second)
        try await gql.execute(query: "query { ok }")
        let auth = StubURLProtocol.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        XCTAssertEqual(auth, ["Bearer \(first)", "Bearer \(second)"])
    }

    func testUnauthenticatedResponseMapsToAuthError() async {
        StubURLProtocol.reset { _ in
            (401, Data(#"{"errors":[{"message":"jwt expired","extensions":{"code":"UNAUTHENTICATED"}}]}"#.utf8))
        }
        let gql = GqlClient(
            endpoint: endpoint,
            credential: ChatCredential(.customerToken(makeJwt(sub: "c", nonce: "a"))),
            session: URLSession(configuration: StubURLProtocol.configuration())
        )
        do {
            try await gql.execute(query: "query { ok }")
            XCTFail("expected an auth error")
        } catch let error as LiveAndAiChatError {
            XCTAssertEqual(error.type, .auth)
            XCTAssertFalse(error.recoverable)
            XCTAssertEqual(error.sdkCode(usingIdentityToken: true), ChatErrorCode.invalidIdentityToken)
            XCTAssertEqual(error.sdkCode(usingIdentityToken: false), ChatErrorCode.invalidPublicKey)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testBare401MapsToAuthError() async {
        StubURLProtocol.reset { _ in (401, Data()) }
        let gql = GqlClient(
            endpoint: endpoint,
            credential: ChatCredential(.apiKey(secretKey)),
            session: URLSession(configuration: StubURLProtocol.configuration())
        )
        do {
            try await gql.execute(query: "query { ok }")
            XCTFail("expected an auth error")
        } catch {
            XCTAssertEqual((error as? LiveAndAiChatError)?.type, .auth)
        }
    }

    func testSseRequestsCarryCredentialHeaders() {
        let token = makeJwt(sub: "cust-1", nonce: "a")
        let jwtClient = SseSubscriptionClient(
            endpoint: URL(string: "https://chat.example.com/graphql/stream")!,
            credential: ChatCredential(.customerToken(token))
        )
        let streamHeaders = jwtClient.requestHeaders(streamToken: "stream-token")
        XCTAssertEqual(streamHeaders["Authorization"], "Bearer \(token)")
        XCTAssertNil(streamHeaders["x-api-key"])
        XCTAssertEqual(streamHeaders["x-newinstance-sdk"], "ios/0.7.0")
        XCTAssertEqual(streamHeaders["User-Agent"], "LiveAndAiChat-iOS/0.7.0")
        XCTAssertEqual(streamHeaders["X-GraphQL-Event-Stream-Token"], "stream-token")

        let keyClient = SseSubscriptionClient(
            endpoint: URL(string: "https://chat.example.com/graphql/stream")!,
            credential: ChatCredential(.apiKey(secretKey))
        )
        let keyHeaders = keyClient.requestHeaders()
        XCTAssertEqual(keyHeaders["x-api-key"], secretKey)
        XCTAssertNil(keyHeaders["Authorization"])
        XCTAssertEqual(keyHeaders["x-newinstance-sdk"], "ios/0.7.0")
    }

    func testSseReserveSendsCredential() {
        let reserved = expectation(description: "reserve PUT")
        StubURLProtocol.reset { request in
            if request.httpMethod == "PUT" { reserved.fulfill() }
            return (500, Data("no".utf8))
        }
        let client = SseSubscriptionClient(
            endpoint: URL(string: "https://chat.example.com/graphql/stream")!,
            credential: ChatCredential(.apiKey(secretKey)),
            reconnect: ReconnectPolicy(initialDelayMs: 60_000, maxDelayMs: 60_000),
            urlSessionConfig: StubURLProtocol.configuration()
        )
        client.start()
        wait(for: [reserved], timeout: 5)
        client.stop()
        let put = StubURLProtocol.requests.first { $0.httpMethod == "PUT" }
        XCTAssertEqual(put?.value(forHTTPHeaderField: "x-api-key"), secretKey)
        XCTAssertNil(put?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(put?.value(forHTTPHeaderField: "x-newinstance-sdk"), "ios/0.7.0")
    }

    func testWsUpgradeCarriesCredentialAndInitHasNoCredential() throws {
        let token = makeJwt(sub: "cust-1", nonce: "a")
        let jwtClient = WsSubscriptionClient(
            endpoint: URL(string: "wss://chat.example.com/graphql/ws")!,
            credential: ChatCredential(.customerToken(token))
        )
        let jwtRequest = jwtClient.upgradeRequest()
        XCTAssertEqual(jwtRequest.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertNil(jwtRequest.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertEqual(jwtRequest.value(forHTTPHeaderField: "x-newinstance-sdk"), "ios/0.7.0")
        XCTAssertEqual(jwtRequest.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"), "graphql-transport-ws")

        let keyClient = WsSubscriptionClient(
            endpoint: URL(string: "wss://chat.example.com/graphql/ws")!,
            credential: ChatCredential(.apiKey(secretKey))
        )
        let keyRequest = keyClient.upgradeRequest()
        XCTAssertEqual(keyRequest.value(forHTTPHeaderField: "x-api-key"), secretKey)
        XCTAssertNil(keyRequest.value(forHTTPHeaderField: "Authorization"))

        let frame = try JSONSerialization.data(withJSONObject: WsSubscriptionClient.connectionInitFrame)
        XCTAssertEqual(String(data: frame, encoding: .utf8)?.contains(#""payload":{}"#), true)
    }
}

final class SubscriptionAuthFailureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testSseReserve401EmitsAuthFailureOnceAndDoesNotRetry() {
        StubURLProtocol.reset { _ in (401, Data()) }
        let failed = expectation(description: "auth failure")
        var messages: [String] = []
        let client = SseSubscriptionClient(
            endpoint: URL(string: "https://chat.example.com/graphql/stream")!,
            credential: ChatCredential(.customerToken(makeJwt(sub: "c", nonce: "a"))),
            reconnect: ReconnectPolicy(initialDelayMs: 5, maxDelayMs: 5),
            urlSessionConfig: StubURLProtocol.configuration()
        )
        client.onAuthFailure = { message in
            messages.append(message)
            failed.fulfill()
        }
        client.start()
        wait(for: [failed], timeout: 5)
        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        client.stop()
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.httpMethod == "PUT" }.count, 1)
    }

    func testSseUnauthenticatedNextEmitsAuthFailureAndDoesNotReconnect() {
        var messages: [String] = []
        let client = SseSubscriptionClient(
            endpoint: URL(string: "https://chat.example.com/graphql/stream")!,
            credential: ChatCredential(.customerToken(makeJwt(sub: "c", nonce: "a"))),
            reconnect: ReconnectPolicy(initialDelayMs: 5, maxDelayMs: 5),
            urlSessionConfig: StubURLProtocol.configuration()
        )
        client.onAuthFailure = { messages.append($0) }
        client.onStreamEvent(name: "next", data: unauthenticatedNext)
        client.onStreamEvent(name: "next", data: unauthenticatedNext)
        XCTAssertEqual(messages, ["Session expired"])
        XCTAssertTrue(client.authFailed)
        client.start()
        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        client.stop()
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testWsUnauthenticatedFramesEmitAuthFailureAndDoNotReconnect() {
        let client = WsSubscriptionClient(
            endpoint: URL(string: "wss://chat.example.com/graphql/ws")!,
            credential: ChatCredential(.customerToken(makeJwt(sub: "c", nonce: "a")))
        )
        var messages: [String] = []
        var states: [ConnectionState] = []
        let bag = client.connectionStatePublisher.sink { states.append($0) }
        client.onAuthFailure = { messages.append($0) }
        client.handleMessage(.string(#"{"type":"next","id":"op1","payload":{"errors":[{"message":"Session expired","extensions":{"code":"UNAUTHENTICATED"}}]}}"#))
        client.handleMessage(.string(#"{"type":"error","id":"op2","payload":[{"message":"again","extensions":{"code":"UNAUTHENTICATED"}}]}"#))
        XCTAssertEqual(messages, ["Session expired"])
        XCTAssertTrue(client.authFailed)
        states.removeAll()
        client.start()
        let settle = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        XCTAssertFalse(states.contains(.connecting))
        client.stop()
        bag.cancel()
    }

    func testWsErrorFrameAloneIsDetected() {
        let client = WsSubscriptionClient(
            endpoint: URL(string: "wss://chat.example.com/graphql/ws")!,
            credential: ChatCredential(.apiKey("sk_live_k:secret"))
        )
        var messages: [String] = []
        client.onAuthFailure = { messages.append($0) }
        client.handleMessage(.string(#"{"type":"error","id":"op2","payload":[{"message":"bad key","extensions":{"code":"UNAUTHENTICATED"}}]}"#))
        XCTAssertEqual(messages, ["bad key"])
    }
}

@MainActor
final class SetUserTokenTests: XCTestCase {
    private func makeSdk(_ config: LiveAndAiChatConfig, user: ChatUser? = nil) throws -> LiveAndAiChat {
        let builder = LiveAndAiChat.Builder().config(config)
        if let user { _ = builder.user(user) }
        let sdk = try builder.build()
        sdk.session.clear()
        return sdk
    }

    private func jwtConfig(_ token: String) throws -> LiveAndAiChatConfig {
        try LiveAndAiChatConfig(customerToken: token, baseUrl: "http://127.0.0.1:9", initialMessage: "hello")
    }

    func testSetUserTokenThrowsInKeyMode() throws {
        let sdk = try makeSdk(LiveAndAiChatConfig(apiKey: "sk_live_k:secret"))
        defer { sdk.destroy() }
        XCTAssertThrowsError(try sdk.setUserToken(makeJwt(sub: "c", nonce: "a"))) { error in
            let e = error as? LiveAndAiChatError
            XCTAssertEqual(e?.code, "E_CONFIG")
            XCTAssertEqual(e?.type, .validation)
            XCTAssertEqual(e?.recoverable, false)
            XCTAssertEqual(e?.message, "setUserToken is only available when the SDK is configured with customerToken")
        }
    }

    func testSetUserTokenRejectsBlankToken() throws {
        let sdk = try makeSdk(jwtConfig(makeJwt(sub: "c", nonce: "a")))
        defer { sdk.destroy() }
        XCTAssertThrowsError(try sdk.setUserToken("  ")) { error in
            let e = error as? LiveAndAiChatError
            XCTAssertEqual(e?.code, "E_CONFIG")
            XCTAssertEqual(e?.message, "customerToken must not be blank")
        }
    }

    func testSetUserTokenSwapsHeaderAndRebuildsSubscriptionClient() throws {
        let first = makeJwt(sub: "cust-1", nonce: "a")
        let second = makeJwt(sub: "cust-1", nonce: "b")
        let sdk = try makeSdk(jwtConfig(first))
        defer {
            sdk.session.clear()
            sdk.destroy()
        }
        let fake = FakeSubscriptionClient()
        sdk.subscriptionClient = fake
        sdk.session.conversationId = "conv-1"

        try sdk.setUserToken(second)

        XCTAssertEqual(sdk.credential.headers()["Authorization"], "Bearer \(second)")
        XCTAssertNil(sdk.credential.headers()["x-api-key"])
        XCTAssertTrue(fake.stopped)
        let rebuilt = try XCTUnwrap(sdk.subscriptionClient as? SseSubscriptionClient)
        XCTAssertFalse(rebuilt === fake)
        XCTAssertEqual(rebuilt.requestHeaders()["Authorization"], "Bearer \(second)")
        XCTAssertNotNil(rebuilt.onAuthFailure)
        XCTAssertEqual(sdk.session.conversationId, "conv-1")
    }

    func testSetUserTokenForDifferentSubjectClearsConversation() throws {
        let sdk = try makeSdk(jwtConfig(makeJwt(sub: "cust-1", nonce: "a")))
        defer {
            sdk.session.clear()
            sdk.destroy()
        }
        let fake = FakeSubscriptionClient()
        sdk.subscriptionClient = fake
        sdk.session.conversationId = "conv-1"
        sdk.session.identityKey = "cust-1"

        try sdk.setUserToken(makeJwt(sub: "cust-2", nonce: "b"))

        XCTAssertTrue(fake.stopped)
        XCTAssertNil(sdk.session.conversationId)
        XCTAssertNil(sdk.subscriptionClient)
    }

    func testJwtInitInputCarriesNoCustomerFields() throws {
        let sdk = try makeSdk(
            jwtConfig(makeJwt(sub: "cust-1", nonce: "a")),
            user: ChatUser(customerName: "Ada", customerId: "u1", customerEmail: "ada@example.com")
        )
        defer { sdk.destroy() }
        sdk.setUser(ChatUser(customerName: "Grace", customerId: "u2", customerEmail: "grace@example.com"))
        let input = sdk.initChatInput()
        XCTAssertEqual(Set(input.keys), ["initialMessage"])
        XCTAssertEqual(input["initialMessage"] as? String, "hello")
    }

    func testKeyInitInputCarriesSetUserFields() throws {
        let sdk = try makeSdk(LiveAndAiChatConfig(apiKey: "sk_live_k:secret"))
        defer { sdk.destroy() }
        sdk.setUser(ChatUser(customerName: "Ada", customerId: "u1", customerEmail: "ada@example.com"))
        let input = sdk.initChatInput()
        XCTAssertEqual(input["customerName"] as? String, "Ada")
        XCTAssertEqual(input["customerId"] as? String, "u1")
        XCTAssertEqual(input["customerEmail"] as? String, "ada@example.com")
        XCTAssertNil(input["customerToken"])
    }
}

@MainActor
final class SecretRedactionTests: XCTestCase {
    private let secret = "TOPSECRETVALUE42"

    func testConfigDescriptionsRedactSecretAndToken() throws {
        let keyConfig = try LiveAndAiChatConfig(apiKey: "sk_live_keyid:\(secret)")
        let token = makeJwt(sub: "cust-1", nonce: "leak")
        let jwtConfig = try LiveAndAiChatConfig(customerToken: token)
        for config in [keyConfig, jwtConfig] {
            var dumped = ""
            dump(config, to: &dumped)
            let rendered = [
                config.description,
                config.debugDescription,
                String(describing: config),
                String(reflecting: config),
                "\(config)",
                dumped,
            ].joined(separator: "\n")
            XCTAssertFalse(rendered.contains(secret))
            XCTAssertFalse(rendered.contains(token))
            XCTAssertFalse(rendered.contains("signatureleak"))
        }
        XCTAssertTrue(keyConfig.description.contains("sk_live_keyid:***"))
        XCTAssertTrue(jwtConfig.description.contains("customerToken: ***"))
    }

    func testNothingSensitiveIsLogged() throws {
        let capture = LogCapture()
        defer { capture.stop() }
        let key = "sk_live_keyid:\(secret)"
        let token = makeJwt(sub: "cust-1", nonce: "leak")
        let fresh = makeJwt(sub: "cust-1", nonce: "leak2")

        StubURLProtocol.reset { _ in
            (401, Data(#"{"errors":[{"message":"rejected","extensions":{"code":"UNAUTHENTICATED"}}]}"#.utf8))
        }
        for credential in [ChatCredential(.apiKey(key)), ChatCredential(.customerToken(token))] {
            let gql = GqlClient(
                endpoint: URL(string: "https://chat.example.com/service")!,
                credential: credential,
                session: URLSession(configuration: StubURLProtocol.configuration())
            )
            let executed = expectation(description: "gql")
            Task.detached {
                do { try await gql.execute(query: "query { ok }") } catch { capture.append("\(error)") }
                executed.fulfill()
            }

            let failed = expectation(description: "auth failure")
            let sse = SseSubscriptionClient(
                endpoint: URL(string: "https://chat.example.com/graphql/stream")!,
                credential: credential,
                reconnect: ReconnectPolicy(initialDelayMs: 5, maxDelayMs: 5),
                urlSessionConfig: StubURLProtocol.configuration()
            )
            sse.onAuthFailure = { capture.append($0); failed.fulfill() }
            sse.start()
            wait(for: [executed, failed], timeout: 5)
            sse.stop()

            let ws = WsSubscriptionClient(endpoint: URL(string: "wss://chat.example.com/graphql/ws")!, credential: credential)
            ws.onAuthFailure = { capture.append($0) }
            ws.handleMessage(.string(#"{"type":"next","id":"op1","payload":{"data":{"x":1}}}"#))
            ws.handleMessage(.string(unauthenticatedNext.replacingOccurrences(of: #"{"id""#, with: #"{"type":"next","id""#)))
        }

        let sdk = try LiveAndAiChat.Builder()
            .config(LiveAndAiChatConfig(customerToken: token, baseUrl: "http://127.0.0.1:9"))
            .build()
        sdk.subscriptionClient = FakeSubscriptionClient()
        sdk.session.conversationId = "conv-log"
        try sdk.setUserToken(fresh)
        do { try sdk.setUserToken(" ") } catch { capture.append("\(error)") }
        sdk.session.clear()
        sdk.destroy()

        let everything = capture.text
        XCTAssertTrue(everything.contains("Session expired"))
        XCTAssertTrue(everything.contains("customerToken must not be blank"))
        XCTAssertFalse(everything.contains(secret))
        XCTAssertFalse(everything.contains(token))
        XCTAssertFalse(everything.contains(fresh))
        XCTAssertFalse(everything.contains("signatureleak"))
    }
}
