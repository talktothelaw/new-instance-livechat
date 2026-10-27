import XCTest
@testable import LiveAndAiChat

private let selection = "elicitation { id mode message requestedSchema url status }"

private func stepMessage(_ status: ElicitationStatus, mode: ElicitationMode = .form) -> ChatMessage {
    ChatMessage(
        id: "m1",
        conversationId: "conv-1",
        content: "Please confirm",
        type: .ai,
        seq: 1,
        elicitation: Elicitation(id: "e1", mode: mode, message: "Please confirm", requestedSchema: nil, url: nil, status: status)
    )
}

private func requestJSON(_ request: URLRequest) -> [String: Any]? {
    guard let body = request.httpBody ?? request.httpBodyStream.map(readAll) else { return nil }
    return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
}

private func readAll(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

private func aiReply(_ text: String, content: String) -> ChatMessage {
    ChatMessage(id: "ai-\(text)", conversationId: "conv-1", content: content, type: .ai)
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    var tries = 0
    while !condition() && tries < 300 {
        tries += 1
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condition())
}

private final class MessageCounter: LiveAndAiChatDelegate {
    var received: [ChatMessage] = []
    func didReceiveMessage(_ message: ChatMessage) { received.append(message) }
}

final class ElicitationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset { _ in (200, Data(#"{"data":{"answerCsElicitation":true}}"#.utf8)) }
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testSelectsElicitationEverywhere() {
        for doc in [Operations.initChat, Operations.getMessages, Operations.subMessageReceived] {
            XCTAssertEqual(doc.components(separatedBy: selection).count - 1, 1)
        }
        XCTAssertEqual(Operations.sendMessage.components(separatedBy: selection).count - 1, 2)
        XCTAssertTrue(Operations.answerElicitation.contains(
            "mutation AnswerCsElicitation($conversationId: ID!, $elicitationId: ID!, $action: CsElicitationAction!, $content: JSONObject) { answerCsElicitation(conversationId: $conversationId, elicitationId: $elicitationId, action: $action, content: $content) }"
        ))
    }

    func testDecodesElicitationWithSchema() throws {
        let node: [String: Any] = [
            "id": "m1", "conversationId": "c1", "content": "Confirm", "type": "AI", "status": "SENT",
            "elicitation": [
                "id": "e1", "mode": "FORM", "message": "Confirm", "url": NSNull(), "status": "PENDING",
                "requestedSchema": [
                    "type": "object",
                    "properties": ["amount": ["type": "integer", "title": "Amount", "default": 5], "ok": ["type": "boolean"]],
                    "required": ["amount"],
                ],
            ],
        ]
        let msg = try GqlClient.decode(ChatMessage.self, from: node)
        let step = try XCTUnwrap(msg.elicitation)
        XCTAssertEqual(step.id, "e1")
        XCTAssertEqual(step.mode, .form)
        XCTAssertEqual(step.status, .pending)
        XCTAssertNil(step.url)
        XCTAssertEqual(step.requestedSchema, .object([
            "type": .string("object"),
            "properties": .object([
                "amount": .object(["type": .string("integer"), "title": .string("Amount"), "default": .number(5)]),
                "ok": .object(["type": .string("boolean")]),
            ]),
            "required": .array([.string("amount")]),
        ]))

        let plain = try GqlClient.decode(ChatMessage.self, from: ["id": "m2", "conversationId": "c1", "type": "AI"])
        XCTAssertNil(plain.elicitation)
        let unknown = try GqlClient.decode(ChatMessage.self, from: [
            "id": "m3", "conversationId": "c1", "type": "AI", "content": "hi",
            "elicitation": ["id": "e9", "mode": "SOMETHING_NEW", "status": "PENDING"],
        ])
        XCTAssertNil(unknown.elicitation)
        XCTAssertEqual(unknown.content, "hi")
    }

    @MainActor
    func testResentMessageDoesNotBumpUnread() throws {
        let store = ChatStore()
        XCTAssertTrue(store.mergeMessage(stepMessage(.pending)))
        XCTAssertFalse(store.mergeMessage(stepMessage(.answered)))
        XCTAssertEqual(store.unreadCount, 1)
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertEqual(store.messages[0].elicitation?.status, .answered)

        let sdk = try LiveAndAiChat.Builder().config(LiveAndAiChatConfig(apiKey: "sk_live_k:secret")).build()
        defer { sdk.destroy() }
        let counter = MessageCounter()
        sdk.addDelegate(counter)
        sdk.receive(stepMessage(.pending))
        sdk.receive(stepMessage(.answered))
        XCTAssertEqual(counter.received.map { $0.elicitation?.status }, [.pending])
        XCTAssertEqual(sdk.unreadCount, 1)
        XCTAssertEqual(sdk.messages.first?.elicitation?.status, .answered)
    }

    @MainActor
    func testAnswersFormWithContentAndDeclineWithout() async throws {
        let sdk = try LiveAndAiChat.Builder().config(LiveAndAiChatConfig(apiKey: "sk_live_k:secret")).build()
        defer {
            sdk.session.clear()
            sdk.destroy()
        }
        sdk.session.conversationId = "conv-1"
        sdk.store.setInitialMessages([stepMessage(.pending)])

        try await sdk.answerElicitation(messageId: "m1", action: .accept, content: ["name": .string("Ada"), "count": .number(2), "ok": .bool(true)])
        try await sdk.answerElicitation(messageId: "m1", action: .decline, content: ["name": .string("Ada")])

        let answers = StubURLProtocol.requests.compactMap(answerVariables)
        XCTAssertEqual(answers.count, 2)
        XCTAssertEqual(answers[0]["conversationId"] as? String, "conv-1")
        XCTAssertEqual(answers[0]["elicitationId"] as? String, "e1")
        XCTAssertEqual(answers[0]["action"] as? String, "ACCEPT")
        let content = try XCTUnwrap(answers[0]["content"] as? [String: Any])
        XCTAssertEqual(content["name"] as? String, "Ada")
        XCTAssertEqual(content["count"] as? Int, 2)
        XCTAssertEqual(content["ok"] as? Bool, true)
        XCTAssertEqual(answers[1]["action"] as? String, "DECLINE")
        XCTAssertNil(answers[1]["content"])

        StubURLProtocol.reset { _ in (200, Data(#"{"errors":[{"message":"nope","extensions":{"code":"BAD_USER_INPUT"}}]}"#.utf8)) }
        do {
            try await sdk.answerElicitation(messageId: "m1", action: .decline)
            XCTFail("expected the answer to fail")
        } catch {
            XCTAssertEqual((error as? LiveAndAiChatError)?.message, "nope")
        }
    }

    @MainActor
    func testAiReplySignalsOnceWhicheverCopyArrivesFirst() async throws {
        StubURLProtocol.reset { request in
            guard let json = requestJSON(request),
                  (json["query"] as? String)?.contains("SendCsCustomerMessage") == true,
                  let vars = json["variables"] as? [String: Any],
                  let text = vars["content"] as? String
            else { return (200, Data(#"{"data":{"ok":true}}"#.utf8)) }
            let payload: [String: Any] = ["data": ["sendCsCustomerMessage": [
                "success": true,
                "customerMessage": [
                    "id": "cust-\(text)", "clientId": vars["clientId"] ?? "", "conversationId": "conv-1",
                    "content": text, "type": "CUSTOMER",
                ],
                "aiResponse": ["id": "ai-\(text)", "conversationId": "conv-1", "content": "http", "type": "AI"],
            ]]]
            return (200, try! JSONSerialization.data(withJSONObject: payload))
        }
        let sdk = try LiveAndAiChat.Builder().config(LiveAndAiChatConfig(apiKey: "sk_live_k:secret")).build()
        defer {
            sdk.session.clear()
            sdk.destroy()
        }
        sdk.session.conversationId = "conv-1"
        var signals = 0
        sdk.inboundSignal = { _ in signals += 1 }
        let counter = MessageCounter()
        sdk.addDelegate(counter)

        sdk.sendMessage("one")
        try await waitUntil { sdk.messages.contains { $0.id == "ai-one" } }
        XCTAssertEqual(signals, 1)
        sdk.receive(aiReply("one", content: "subscription"))
        XCTAssertEqual(signals, 1)

        sdk.receive(aiReply("two", content: "subscription"))
        XCTAssertEqual(signals, 2)
        sdk.sendMessage("two")
        try await waitUntil { sdk.messages.first { $0.id == "ai-two" }?.content == "http" }
        XCTAssertEqual(signals, 2)
        XCTAssertEqual(counter.received.map(\.id), ["ai-one", "ai-two"])
    }

    func testNumberFieldsAcceptLocaleDecimalSeparator() {
        let fields = ElicitationForm.fields(from: .object(["properties": .object([
            "ratio": .object(["type": .string("number")]),
            "count": .object(["type": .string("integer")]),
        ])]))
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(
            ElicitationForm.answer(fields, texts: ["ratio": "1,5", "count": "2,0"], toggles: [:], locale: german).content,
            ["ratio": .number(1.5), "count": .number(2)]
        )
        XCTAssertEqual(ElicitationForm.answer(fields, texts: ["ratio": "1.5"], toggles: [:], locale: german).content, ["ratio": .number(1.5)])
        XCTAssertEqual(ElicitationForm.answer(fields, texts: ["count": "2,5"], toggles: [:], locale: german).problems, ["count": "Enter a whole number."])
        XCTAssertEqual(
            ElicitationForm.answer(fields, texts: ["ratio": "1,5"], toggles: [:], locale: Locale(identifier: "en_US")).problems,
            ["ratio": "Enter a number."]
        )
    }

    func testBuildsFieldsFromSchemaAndSkipsUnsupportedTypes() {
        let schema: JSONValue = .object([
            "properties": .object([
                "name": .object(["type": .string("string"), "title": .string("Your name"), "description": .string("As on your card")]),
                "plan": .object(["type": .string("string"), "enum": .array([.string("basic"), .string("pro")])]),
                "amount": .object(["type": .string("integer"), "default": .number(5)]),
                "ratio": .object(["type": .string("number")]),
                "agree": .object(["type": .string("boolean"), "default": .bool(true)]),
                "tags": .object(["type": .string("array")]),
                "address": .object(["type": .string("object")]),
            ]),
            "required": .array([.string("name"), .string("plan")]),
        ])
        let fields = ElicitationForm.fields(from: schema)
        XCTAssertEqual(fields.map(\.key), ["agree", "amount", "name", "plan", "ratio"])
        let byKey = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })
        XCTAssertEqual(byKey["name"], ElicitationField(key: "name", label: "Your name", helper: "As on your card", kind: .text, required: true, initialText: "", initialOn: false))
        XCTAssertEqual(byKey["plan"]?.kind, .choice(["basic", "pro"]))
        XCTAssertEqual(byKey["plan"]?.label, "plan")
        XCTAssertEqual(byKey["plan"]?.initialText, "")
        XCTAssertEqual(byKey["amount"]?.kind, .number(integer: true))
        XCTAssertEqual(byKey["amount"]?.initialText, "5")
        XCTAssertEqual(byKey["ratio"]?.kind, .number(integer: false))
        XCTAssertEqual(byKey["agree"]?.kind, .toggle)
        XCTAssertEqual(byKey["agree"]?.initialOn, true)
        XCTAssertEqual(ElicitationForm.fields(from: nil), [])
        XCTAssertEqual(ElicitationForm.fields(from: .object(["properties": .string("bad")])), [])
    }

    func testValidatesAnswers() {
        let fields = ElicitationForm.fields(from: .object([
            "properties": .object([
                "name": .object(["type": .string("string")]),
                "plan": .object(["type": .string("string"), "enum": .array([.string("basic"), .string("pro")])]),
                "amount": .object(["type": .string("integer")]),
                "ratio": .object(["type": .string("number")]),
                "note": .object(["type": .string("string")]),
                "agree": .object(["type": .string("boolean")]),
            ]),
            "required": .array([.string("name"), .string("plan")]),
        ]))

        let blocked = ElicitationForm.answer(fields, texts: ["name": "   ", "amount": "2.5", "ratio": "abc"], toggles: [:])
        XCTAssertEqual(blocked.problems, [
            "name": "This field is required.",
            "plan": "This field is required.",
            "amount": "Enter a whole number.",
            "ratio": "Enter a number.",
        ])

        let sent = ElicitationForm.answer(fields, texts: ["name": "  Ada ", "plan": "pro", "amount": "3", "ratio": "-1.5"], toggles: ["agree": true])
        XCTAssertEqual(sent.problems, [:])
        XCTAssertEqual(sent.content, [
            "name": .string("Ada"),
            "plan": .string("pro"),
            "amount": .number(3),
            "ratio": .number(-1.5),
            "agree": .bool(true),
        ])
    }

    func testStatusLines() {
        XCTAssertNil(ElicitationForm.statusLine(.pending))
        XCTAssertEqual(ElicitationForm.statusLine(.answered), "Sent")
        XCTAssertEqual(ElicitationForm.statusLine(.declined), "Declined")
        XCTAssertEqual(ElicitationForm.statusLine(.cancelled), "Cancelled")
        XCTAssertEqual(ElicitationForm.statusLine(.expired), "This step expired")
        XCTAssertEqual(ElicitationForm.statusLine(.completed), "Done")
    }

    func testRefusesNonHttpsStepUrl() {
        for raw in [nil, "", "http://pay.example.com/step", "javascript:alert(1)", "not a url", "https://", "ftp://pay.example.com"] {
            XCTAssertNil(ElicitationForm.secureUrl(raw), raw ?? "nil")
        }
        let url = ElicitationForm.secureUrl("https://pay.example.com/step?id=1")
        XCTAssertEqual(url?.absoluteString, "https://pay.example.com/step?id=1")
        XCTAssertEqual(url.map(ElicitationForm.hostLabel), "pay.example.com")
        XCTAssertEqual(ElicitationForm.secureUrl("HTTPS://pay.example.com:8443/x").map(ElicitationForm.hostLabel), "pay.example.com:8443")
    }

    func testSendsIos050Header() {
        XCTAssertEqual(LiveAndAiChat.version, "0.5.0")
        let headers = ChatCredential(.apiKey("sk_live_k:secret")).headers()
        XCTAssertEqual(headers["x-newinstance-sdk"], "ios/0.5.0")
        XCTAssertEqual(headers["User-Agent"], "LiveAndAiChat-iOS/0.5.0")
    }

    private func answerVariables(_ request: URLRequest) -> [String: Any]? {
        guard let json = requestJSON(request),
              (json["query"] as? String)?.contains("AnswerCsElicitation") == true
        else { return nil }
        return json["variables"] as? [String: Any]
    }
}
