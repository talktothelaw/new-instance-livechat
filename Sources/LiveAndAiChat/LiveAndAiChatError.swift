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
public enum ChatErrorCode {
    public static let invalidPublicKey = "INVALID_PUBLIC_KEY"
    public static let missingWidgetKey = "MISSING_WIDGET_KEY"
    public static let chatConfigUnavailable = "CHAT_CONFIG_UNAVAILABLE"
    public static let chatDisabled = "CHAT_DISABLED"
    public static let configFetchFailed = "CONFIG_FETCH_FAILED"
    public static let invalidIdentityToken = "INVALID_IDENTITY_TOKEN"
    public static let networkError = "NETWORK_ERROR"
    public static let transportError = "TRANSPORT_ERROR"
    public static let chatInitializationFailed = "CHAT_INITIALIZATION_FAILED"
    public static let messageSendFailed = "MESSAGE_SEND_FAILED"
    public static let attachmentFailed = "ATTACHMENT_FAILED"
    public static let serverError = "SERVER_ERROR"
}

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

    public func sdkCode(usingIdentityToken: Bool = false) -> String {
        switch type {
        case .auth:
            return usingIdentityToken ? ChatErrorCode.invalidIdentityToken : ChatErrorCode.invalidPublicKey
        case .network:
            return ChatErrorCode.networkError
        case .validation:
            return ChatErrorCode.serverError
        case .system:
            return ChatErrorCode.chatInitializationFailed
        }
    }

    public var description: String {
        var s = "LiveAndAiChatError(type: \(type.rawValue), message: \"\(message)\", recoverable: \(recoverable)"
        if let code { s += ", code: \(code)" }
        if conversationClosed { s += ", conversationClosed: true" }
        s += ")"
        return s
    }
}
