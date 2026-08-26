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
/// Stable diagnostic codes carried on ``LiveAndAiChatError/code``. The same
/// strings are used by the Android, web, React Native and Flutter SDKs, so a
/// support conversation about "code CHAT_DISABLED" means the same thing on
/// every platform.
public enum ChatErrorCode {
    /// The API key was rejected: wrong key, wrong environment, revoked, or expired.
    public static let invalidPublicKey = "INVALID_PUBLIC_KEY"
    /// No API key was supplied.
    public static let missingWidgetKey = "MISSING_WIDGET_KEY"
    /// The key is valid but no chat configuration exists for the organization.
    public static let chatConfigUnavailable = "CHAT_CONFIG_UNAVAILABLE"
    /// The key and config are fine, but chat is switched off in the dashboard.
    public static let chatDisabled = "CHAT_DISABLED"
    /// Remote configuration could not be fetched; the built-in theme is in use.
    public static let configFetchFailed = "CONFIG_FETCH_FAILED"
    /// The chat identity token was malformed, expired, or signed for another organization.
    public static let invalidIdentityToken = "INVALID_IDENTITY_TOKEN"
    /// A request could not reach the backend at all.
    public static let networkError = "NETWORK_ERROR"
    /// The realtime transport dropped and could not be re-established.
    public static let transportError = "TRANSPORT_ERROR"
    /// Starting a conversation failed.
    public static let chatInitializationFailed = "CHAT_INITIALIZATION_FAILED"
    /// A message could not be delivered.
    public static let messageSendFailed = "MESSAGE_SEND_FAILED"
    /// An attachment could not be uploaded.
    public static let attachmentFailed = "ATTACHMENT_FAILED"
    /// The backend answered, but not with anything the SDK could use.
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

    /// Normalise this error onto the cross-platform ``ChatErrorCode``
    /// vocabulary. `code` on its own carries the raw GraphQL/transport code
    /// (for example `UNAUTHENTICATED`), which differs per layer; `sdkCode` is
    /// the stable value to branch on and to quote in a support request.
    ///
    /// An auth failure cannot tell on its own whether the API key or the chat
    /// identity token was rejected, so pass `usingIdentityToken: true` when the
    /// SDK was configured with a token.
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
