import Foundation

/// Classification of SDK errors — matches the Android / web `ErrorType`
/// enum so host apps can react consistently across platforms.
public enum ChatErrorType: String, Sendable {
    case network
    case validation
    case auth
    case system
}

/// All public SDK errors. Carries enough context (type + recoverability +
/// optional GraphQL error code) that host apps can decide whether to retry
/// silently, show a banner, or surface a user-actionable message.
public struct LiveAndAiChatError: Error, CustomStringConvertible, Sendable {
    public let type: ChatErrorType
    public let message: String
    public let recoverable: Bool
    public let code: String?
    /// True when the GraphQL response carries
    /// `extensions.conversationClosed: true`. The server emits this on
    /// any mutation against a conversation the agent has closed; the
    /// SDK uses it as the signal to silently start a fresh chat and
    /// resend the customer's message instead of failing the bubble.
    /// Mirrors the Android / web SDK behaviour.
    public let conversationClosed: Bool
    public let underlying: NSError?

    public init(
        type: ChatErrorType,
        message: String,
        recoverable: Bool,
        code: String? = nil,
        conversationClosed: Bool = false,
        underlying: Error? = nil
    ) {
        self.type = type
        self.message = message
        self.recoverable = recoverable
        self.code = code
        self.conversationClosed = conversationClosed
        self.underlying = underlying.map { $0 as NSError }
    }

    public var description: String {
        var s = "LiveAndAiChatError(type: \(type.rawValue), message: \"\(message)\", recoverable: \(recoverable)"
        if let code { s += ", code: \(code)" }
        if conversationClosed { s += ", conversationClosed: true" }
        s += ")"
        return s
    }
}
