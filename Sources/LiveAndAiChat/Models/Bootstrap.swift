import Foundation

public struct ReconnectPolicy: Codable, Equatable, Sendable {
    public var initialDelayMs: Int
    public var maxDelayMs: Int
    /// Use `Int.max` to mean "unbounded". Encoded/decoded as raw Int so
    /// the JSON contract matches Android (`Long.MAX_VALUE`) and web.
    public var maxAttempts: Int

    public init(initialDelayMs: Int = 1000, maxDelayMs: Int = 30_000, maxAttempts: Int = .max) {
        self.initialDelayMs = initialDelayMs
        self.maxDelayMs = maxDelayMs
        self.maxAttempts = maxAttempts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        initialDelayMs = (try c.decodeIfPresent(Int.self, forKey: .initialDelayMs)) ?? 1000
        maxDelayMs = (try c.decodeIfPresent(Int.self, forKey: .maxDelayMs)) ?? 30_000
        maxAttempts = (try c.decodeIfPresent(Int.self, forKey: .maxAttempts)) ?? .max
    }
}

public struct LiveChatBootstrap: Codable, Equatable, Sendable {
    public var transport: TransportMode
    public var ssePath: String
    public var wsPath: String
    public var reconnect: ReconnectPolicy
    public var eventReplayWindowSeconds: Int
    public var heartbeatIntervalMs: Int
    public var heartbeatTimeoutMs: Int

    public init(
        transport: TransportMode = .sse,
        ssePath: String = "/graphql/stream",
        wsPath: String = "/graphql/ws",
        reconnect: ReconnectPolicy = ReconnectPolicy(),
        eventReplayWindowSeconds: Int = 60,
        heartbeatIntervalMs: Int = 10_000,
        heartbeatTimeoutMs: Int = 30_000
    ) {
        self.transport = transport
        self.ssePath = ssePath
        self.wsPath = wsPath
        self.reconnect = reconnect
        self.eventReplayWindowSeconds = eventReplayWindowSeconds
        self.heartbeatIntervalMs = heartbeatIntervalMs
        self.heartbeatTimeoutMs = heartbeatTimeoutMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = LiveChatBootstrap()
        if let v = try c.decodeIfPresent(TransportMode.self, forKey: .transport) { d.transport = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .ssePath) { d.ssePath = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .wsPath) { d.wsPath = v }
        if let v = try c.decodeIfPresent(ReconnectPolicy.self, forKey: .reconnect) { d.reconnect = v }
        if let v = try c.decodeIfPresent(Int.self, forKey: .eventReplayWindowSeconds) { d.eventReplayWindowSeconds = v }
        if let v = try c.decodeIfPresent(Int.self, forKey: .heartbeatIntervalMs) { d.heartbeatIntervalMs = v }
        if let v = try c.decodeIfPresent(Int.self, forKey: .heartbeatTimeoutMs) { d.heartbeatTimeoutMs = v }
        self = d
    }
}
