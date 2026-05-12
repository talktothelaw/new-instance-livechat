import Foundation

/// Transport-level connection state. Mirrors the Android / web enum so the
/// host UI can render identical "Online / Connecting… / Reconnecting… /
/// Offline" labels across platforms.
public enum ConnectionState: String, Codable, Sendable {
    case idle
    case connecting
    case connected
    case disconnected
    case offline
}

/// High-level conversation flow state — derived from the server-reported
/// `Conversation.status` and the current `Assignment` (see `ChatStore.derive`).
public enum FlowState: String, Codable, Sendable {
    case idle
    case collectingInfo = "collecting_info"
    case botConversation = "bot_conversation"
    case handoffPending = "handoff_pending"
    case liveChat = "live_chat"
    case ended
    case error
}

/// Coarse SDK lifecycle exposed to the host so it can drive its own
/// open-chat button (loading / disabled / "retry" labels) without combining
/// multiple state flows by hand. Matches `ChatSdkLifecycle` on Android.
public enum ChatSdkLifecycle: String, Codable, Sendable {
    case notStarted = "not_started"
    case initializing
    case ready
    case unavailable
    case failed
}
