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
    public let underlying: NSError?

    public init(
        type: ChatErrorType,
        message: String,
        recoverable: Bool,
        code: String? = nil,
        underlying: Error? = nil
    ) {
        self.type = type
        self.message = message
        self.recoverable = recoverable
        self.code = code
        self.underlying = underlying.map { $0 as NSError }
    }

    public var description: String {
        var s = "LiveAndAiChatError(type: \(type.rawValue), message: \"\(message)\", recoverable: \(recoverable)"
        if let code { s += ", code: \(code)" }
        s += ")"
        return s
    }
}
