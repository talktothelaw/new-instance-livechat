import Foundation
import Combine

/// GraphQL-over-SSE single-connection client. Wire protocol per
/// `graphql-sse` PROTOCOL.md (and matches the Android implementation
/// in `SseSubscriptionClient.kt`):
///
///   1. **Reservation**:  `PUT  {endpoint}`       → 201 + token in body
///   2. **Stream**:       `GET  {endpoint}`       + `X-GraphQL-Event-Stream-Token: <token>` header
///   3. **Subscribe**:    `POST {endpoint}` body  `{query, variables, extensions: {operationId: <uuid>}}`
///   4. **Complete**:     `DELETE {endpoint}?operationId=<uuid>`
///
/// Stream events:
///   - `event: next`     `data: {id: "<opId>", payload: ExecutionResult}`
///   - `event: complete` `data: {id: "<opId>"}`
///
/// Reconnect: exponential backoff (`Backoff`) with ±50% jitter.
/// Heartbeat: any inbound event resets `lastEventAt`. A watchdog
/// force-reconnects if no event arrives within `heartbeatTimeoutMs`.
final class SseSubscriptionClient: NSObject, SubscriptionClient {

    // MARK: - Public surface

    private let _connectionState = CurrentValueSubject<ConnectionState, Never>(.idle)
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> {
        _connectionState.eraseToAnyPublisher()
    }

    // MARK: - Construction

    private let endpoint: URL
    private let apiKey: String
    private let reconnect: ReconnectPolicy
    private let heartbeatTimeoutMs: Int
    private let session: URLSession

    init(
        endpoint: URL,
        apiKey: String,
        reconnect: ReconnectPolicy = ReconnectPolicy(),
        heartbeatTimeoutMs: Int = 30_000,
        urlSessionConfig: URLSessionConfiguration = .ephemeral
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.reconnect = reconnect
        self.heartbeatTimeoutMs = heartbeatTimeoutMs
        // Ephemeral session + zero timeout so the long-lived GET stream
        // doesn't expire on the first idle minute (URLSession's default
        // timeoutIntervalForRequest is 60s).
        let cfg = urlSessionConfig
        cfg.timeoutIntervalForRequest = 0  // 0 = no per-request timeout
        cfg.timeoutIntervalForResource = 0
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    // MARK: - Lifecycle

    private let queue = DispatchQueue(label: "com.cinstance.liveandaichat.sse", qos: .utility)
    private var stopped = false
    private var connectTask: Task<Void, Never>?
    private var watchdogTimer: DispatchSourceTimer?
    private var streamTask: URLSessionDataTask?
    private var streamDelegate: SseStreamDelegate?
    private var token: String?
    private var lastEventAt = Date()
    private var attempts = 0

    private struct LiveOp {
        let request: SubscriptionRequest
        let subject: PassthroughSubject<[String: Any], Never>
    }
    private var operations: [String: LiveOp] = [:]
    private let opsLock = NSLock()

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.stopped { return }
            if self.connectTask != nil { return }
            self.connectTask = Task.detached { [weak self] in
                await self?.connectLoop()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.connectTask?.cancel()
            self.connectTask = nil
            self.watchdogTimer?.cancel()
            self.watchdogTimer = nil
            self.streamTask?.cancel()
            self.streamTask = nil
            self.streamDelegate = nil
            self.token = nil
            self.opsLock.lock()
            for (_, op) in self.operations { op.subject.send(completion: .finished) }
            self.operations.removeAll()
            self.opsLock.unlock()
            self._connectionState.send(.idle)
        }
    }

    // MARK: - Subscribe

    func subscribe(_ request: SubscriptionRequest) -> AnyPublisher<[String: Any], Never> {
        let opId = UUID().uuidString
        let subject = PassthroughSubject<[String: Any], Never>()
        opsLock.lock()
        operations[opId] = LiveOp(request: request, subject: subject)
        opsLock.unlock()
        if _connectionState.value == .connected {
            sendSubscribe(opId: opId, request: request)
        }
        return subject
            .handleEvents(receiveCancel: { [weak self] in
                guard let self else { return }
                self.opsLock.lock()
                self.operations.removeValue(forKey: opId)
                self.opsLock.unlock()
                self.sendComplete(opId: opId)
            })
            .eraseToAnyPublisher()
    }

    // MARK: - Connect loop

    private func connectLoop() async {
        while !stopped {
            _connectionState.send(.connecting)
            let ok = await reserveToken()
            if !ok {
                _connectionState.send(.disconnected)
            } else {
                openStream()
                // Wait until the stream task ends.
                while !stopped, streamTask != nil {
                    try? await Task.sleep(nanoseconds: 500 * 1_000_000)
                }
            }
            if stopped { break }
            attempts += 1
            if attempts > reconnect.maxAttempts {
                _connectionState.send(.disconnected)
                return
            }
            let delay = Backoff.delayMillis(policy: reconnect, attempt: attempts - 1)
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
        }
    }

    private func reserveToken() async -> Bool {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "PUT"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = Data()  // empty body
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if body.isEmpty { return false }
            token = body
            return true
        } catch {
            return false
        }
    }

    private func openStream() {
        guard let t = token else { return }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(t, forHTTPHeaderField: "X-GraphQL-Event-Stream-Token")

        let delegate = SseStreamDelegate(
            onOpen: { [weak self] in self?.onStreamOpened() },
            onEvent: { [weak self] event in self?.onStreamEvent(event) },
            onCompleted: { [weak self] _ in self?.onStreamClosed() }
        )
        streamDelegate = delegate
        let streamSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        let task = streamSession.dataTask(with: req)
        streamTask = task
        task.resume()
    }

    private func onStreamOpened() {
        attempts = 0
        lastEventAt = Date()
        _connectionState.send(.connected)
        opsLock.lock()
        let snapshot = operations
        opsLock.unlock()
        for (id, op) in snapshot {
            sendSubscribe(opId: id, request: op.request)
        }
        armWatchdog()
    }

    private func onStreamEvent(_ event: SseEvent) {
        lastEventAt = Date()
        guard !event.data.isEmpty else { return }
        guard let data = event.data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let opId = obj["id"] as? String
        else { return }

        switch event.name {
        case "next":
            opsLock.lock()
            let op = operations[opId]
            opsLock.unlock()
            if let payload = obj["payload"] as? [String: Any],
               let data = payload["data"] as? [String: Any] {
                op?.subject.send(data)
            }
        case "complete":
            opsLock.lock()
            let op = operations.removeValue(forKey: opId)
            opsLock.unlock()
            op?.subject.send(completion: .finished)
        default:
            // Unknown event type — emit anyway so we don't silently drop.
            opsLock.lock()
            let op = operations[opId]
            opsLock.unlock()
            if let payload = obj["payload"] as? [String: Any],
               let data = payload["data"] as? [String: Any] {
                op?.subject.send(data)
            }
        }
    }

    private func onStreamClosed() {
        streamTask = nil
        streamDelegate = nil
        if !stopped { _connectionState.send(.disconnected) }
    }

    // MARK: - Watchdog

    private func armWatchdog() {
        watchdogTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = max(1, heartbeatTimeoutMs / 2)
        timer.schedule(deadline: .now() + .milliseconds(interval), repeating: .milliseconds(interval))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let elapsed = Int(Date().timeIntervalSince(self.lastEventAt) * 1000)
            if elapsed > self.heartbeatTimeoutMs {
                self.streamTask?.cancel()
                self.streamTask = nil
                self.streamDelegate = nil
                self._connectionState.send(.disconnected)
                self.watchdogTimer?.cancel()
                self.watchdogTimer = nil
            }
        }
        watchdogTimer = timer
        timer.resume()
    }

    // MARK: - Subscribe / complete

    private func sendSubscribe(opId: String, request: SubscriptionRequest) {
        guard let t = token else { return }
        var body: [String: Any] = ["query": request.query]
        if let v = request.variables { body["variables"] = v }
        if let n = request.operationName { body["operationName"] = n }
        body["extensions"] = ["operationId": opId]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(t, forHTTPHeaderField: "X-GraphQL-Event-Stream-Token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        session.dataTask(with: req).resume()
    }

    private func sendComplete(opId: String) {
        guard let t = token else { return }
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "operationId", value: opId))
        comps.queryItems = items
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(t, forHTTPHeaderField: "X-GraphQL-Event-Stream-Token")
        session.dataTask(with: req).resume()
    }
}

// MARK: - URLSession data delegate that streams SSE bytes

/// URLSession delegate that lives only as long as one stream attempt.
/// The SSE client creates a fresh delegate (and `URLSession`) per
/// reservation so cancelling one attempt can't race with the next.
final class SseStreamDelegate: NSObject, URLSessionDataDelegate {
    private let parser = SseEventParser()
    private let onOpen: () -> Void
    private let onEvent: (SseEvent) -> Void
    private let onCompleted: (Error?) -> Void
    private var opened = false

    init(
        onOpen: @escaping () -> Void,
        onEvent: @escaping (SseEvent) -> Void,
        onCompleted: @escaping (Error?) -> Void
    ) {
        self.onOpen = onOpen
        self.onEvent = onEvent
        self.onCompleted = onCompleted
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            completionHandler(.cancel)
            onCompleted(URLError(.badServerResponse))
            return
        }
        if !opened {
            opened = true
            onOpen()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let events = parser.feed(data)
        for ev in events { onEvent(ev) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onCompleted(error)
    }
}
