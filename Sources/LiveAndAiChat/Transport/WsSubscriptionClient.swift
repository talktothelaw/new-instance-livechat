import Foundation
import Combine
import os.log

/// WebSocket transport logger, mirrors `SseLog` so the host can
/// surface a unified diagnostic stream regardless of transport.
enum WsLog {
    private static let logger = OSLog(subsystem: "liveandaichat", category: "ws")

    static func debug(_ message: String) {
        let line = "[LAC/WS] \(message)"
        print(line)
        os_log("%{public}@", log: logger, type: .error, line)
        LACDiagnosticLog.emit(line)
    }

    static func warn(_ message: String) {
        let line = "[LAC/WS WARN] \(message)"
        print(line)
        os_log("%{public}@", log: logger, type: .error, line)
        LACDiagnosticLog.emit(line)
    }
}

/// graphql-ws sub-protocol client over `URLSessionWebSocketTask`. Same
/// public surface and reconnect/heartbeat semantics as the SSE client.
///
/// Wire protocol (graphql-ws/v0.13+):
///   - client → server: connection_init, subscribe, complete, ping
///   - server → client: connection_ack, next, error, complete, ping, pong
final class WsSubscriptionClient: NSObject, SubscriptionClient {

    private let _connectionState = CurrentValueSubject<ConnectionState, Never>(.idle)
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> {
        _connectionState.eraseToAnyPublisher()
    }

    private let endpoint: URL
    let credential: ChatCredential
    private let reconnect: ReconnectPolicy
    private let heartbeatTimeoutMs: Int
    private let session: URLSession
    var onAuthFailure: ((String) -> Void)?

    init(
        endpoint: URL,
        credential: ChatCredential,
        reconnect: ReconnectPolicy = ReconnectPolicy(),
        heartbeatTimeoutMs: Int = 30_000,
        urlSessionConfig: URLSessionConfiguration = .ephemeral
    ) {
        self.endpoint = endpoint
        self.credential = credential
        self.reconnect = reconnect
        self.heartbeatTimeoutMs = heartbeatTimeoutMs
        let cfg = urlSessionConfig
        cfg.timeoutIntervalForRequest = 0
        cfg.timeoutIntervalForResource = 0
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    private let queue = DispatchQueue(label: "cloud.newinstance.liveandaichat.ws", qos: .utility)
    private var stopped = false
    private(set) var authFailed = false
    private var connectTask: Task<Void, Never>?
    private var task: URLSessionWebSocketTask?
    private var watchdogTimer: DispatchSourceTimer?
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
            self.task?.cancel(with: .normalClosure, reason: nil)
            self.task = nil
            self.opsLock.lock()
            for (_, op) in self.operations { op.subject.send(completion: .finished) }
            self.operations.removeAll()
            self.opsLock.unlock()
            self._connectionState.send(.idle)
        }
    }

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
        while !stopped && !authFailed {
            _connectionState.send(.connecting)
            openWs()
            // Wait for the task to disconnect.
            while !stopped, task != nil {
                try? await Task.sleep(nanoseconds: 500 * 1_000_000)
            }
            if stopped || authFailed { break }
            attempts += 1
            if attempts > reconnect.maxAttempts {
                _connectionState.send(.disconnected)
                return
            }
            let delay = Backoff.delayMillis(policy: reconnect, attempt: attempts - 1)
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
        }
    }

    func upgradeRequest() -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.allHTTPHeaderFields = credential.headers()
        req.setValue("graphql-transport-ws", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        req.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        return req
    }

    static let connectionInitFrame: [String: Any] = ["type": "connection_init", "payload": [String: Any]()]

    private func openWs() {
        let t = session.webSocketTask(with: upgradeRequest())
        task = t
        WsLog.debug("WS open → \(endpoint.absoluteString)")
        t.resume()
        sendFrame(Self.connectionInitFrame)
        receiveLoop()
    }

    private func receiveLoop() {
        guard let t = task else { return }
        t.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                let status = (t.response as? HTTPURLResponse)?.statusCode
                if status == 401 || status == 403 || t.closeCode.rawValue == 4401 || t.closeCode.rawValue == 4403 {
                    self.failAuth("WebSocket rejected the credential")
                }
                self.handleClose()
                return
            case .success(let message):
                self.lastEventAt = Date()
                self.handleMessage(message)
                self.receiveLoop()
            }
        }
    }

    func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else { return }

        let type = obj["type"] as? String
        switch type {
        case "connection_ack":
            attempts = 0
            _connectionState.send(.connected)
            opsLock.lock()
            let snapshot = operations
            opsLock.unlock()
            WsLog.debug("WS connection_ack — replaying \(snapshot.count) subscription(s)")
            for (id, op) in snapshot { sendSubscribe(opId: id, request: op.request) }
            armWatchdog()
        case "ping":
            sendFrame(["type": "pong"])
        case "next", "error", "complete":
            guard let opId = obj["id"] as? String else { return }
            opsLock.lock()
            let op = operations[opId]
            opsLock.unlock()
            if let message = unauthenticatedMessage(inGraphQLErrors: type == "error" ? obj["payload"] : (obj["payload"] as? [String: Any])?["errors"]) {
                failAuth(message)
                task?.cancel(with: .normalClosure, reason: nil)
                task = nil
                watchdogTimer?.cancel()
                watchdogTimer = nil
                return
            }
            switch type {
            case "next":
                if let payload = obj["payload"] as? [String: Any],
                   let dataField = payload["data"] as? [String: Any] {
                    WsLog.debug("WS next opId=\(opId.suffix(8)) keys=\(Array(dataField.keys))")
                    op?.subject.send(dataField)
                }
            case "complete":
                opsLock.lock()
                operations.removeValue(forKey: opId)
                opsLock.unlock()
                WsLog.debug("WS complete opId=\(opId.suffix(8))")
                op?.subject.send(completion: .finished)
            case "error":
                WsLog.warn("WS error opId=\(opId.suffix(8)) payload=\(obj["payload"] ?? "?")")
                op?.subject.send(completion: .finished)
            default: break
            }
        default:
            WsLog.debug("WS message type=\(type ?? "<nil>")")
        }
    }

    private func handleClose() {
        WsLog.debug("WS closed (stopped=\(stopped))")
        task = nil
        if !stopped && !authFailed { _connectionState.send(.disconnected) }
    }

    private func failAuth(_ message: String) {
        if authFailed || stopped { return }
        authFailed = true
        WsLog.warn("WS auth rejected, not reconnecting until the credential changes")
        _connectionState.send(.disconnected)
        onAuthFailure?(message)
    }

    private func sendFrame(_ frame: [String: Any]) {
        guard let t = task,
              let data = try? JSONSerialization.data(withJSONObject: frame, options: []),
              let text = String(data: data, encoding: .utf8)
        else { return }
        t.send(.string(text)) { _ in }
    }

    private func sendSubscribe(opId: String, request: SubscriptionRequest) {
        var payload: [String: Any] = ["query": request.query]
        if let v = request.variables { payload["variables"] = v }
        if let n = request.operationName { payload["operationName"] = n }
        sendFrame([
            "id": opId,
            "type": "subscribe",
            "payload": payload,
        ])
    }

    private func sendComplete(opId: String) {
        sendFrame(["id": opId, "type": "complete"])
    }

    private func armWatchdog() {
        watchdogTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = max(1, heartbeatTimeoutMs / 2)
        timer.schedule(deadline: .now() + .milliseconds(interval), repeating: .milliseconds(interval))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let elapsed = Int(Date().timeIntervalSince(self.lastEventAt) * 1000)
            if elapsed > self.heartbeatTimeoutMs {
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self._connectionState.send(.disconnected)
                self.watchdogTimer?.cancel()
                self.watchdogTimer = nil
            }
        }
        watchdogTimer = timer
        timer.resume()
    }
}
