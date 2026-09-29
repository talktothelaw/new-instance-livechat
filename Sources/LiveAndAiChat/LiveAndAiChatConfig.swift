import Foundation

/// Transport selection mode. When ``LiveAndAiChatConfig/transport`` is nil
/// the SDK respects the value advertised in the server bootstrap, falling
/// back to ``TransportMode/sse`` if no bootstrap is available.
public enum TransportMode: String, Codable, Sendable {
    case sse
    case ws
}

/// Identity passed to ``LiveAndAiChat/setUser(_:)``. `customerName` is
/// REQUIRED — the backend's `initCsAiChat` rejects blank names and the chat
/// UI cannot attribute the customer's messages without one. `id` and
/// `email` remain optional.
public struct ChatUser: Sendable, Equatable {
    public let customerName: String
    public let customerId: String?
    public let customerEmail: String?

    public init(
        customerName: String,
        customerId: String? = nil,
        customerEmail: String? = nil
    ) {
        precondition(!customerName.isEmpty, "ChatUser.customerName is required and cannot be blank.")
        self.customerName = customerName
        self.customerId = customerId
        self.customerEmail = customerEmail
    }
}

public enum ChatAuthMode: Sendable {
    case apiKey
    case customerToken
}

public struct LiveAndAiChatConfig: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let auth: ChatAuth

    /// Backend base URL. Defaults to ``LiveAndAiChatConfig/defaultBaseUrl``.
    /// Custom values are accepted in debug builds only; release builds throw
    /// at construction time if you try to override this so merchants can't
    /// redirect SDK traffic.
    public let baseUrl: String

    public let gqlPath: String
    public let ssePath: String
    public let wsPath: String

    /// Optional transport override. When `nil`, the SDK uses whatever the
    /// server bootstrap advertises (SSE by default).
    public let transport: TransportMode?

    /// Optional initial message sent on `initCsAiChat`. Web parity.
    public let initialMessage: String?

    public let allowRemoteAttachmentUrls: Bool

    public let theme: ChatThemeOverride?

    public init(
        apiKey: String? = nil,
        customerToken: String? = nil,
        baseUrl: String = LiveAndAiChatConfig.defaultBaseUrl,
        gqlPath: String = "/service",
        ssePath: String = "/graphql/stream",
        wsPath: String = "/graphql/ws",
        transport: TransportMode? = nil,
        initialMessage: String? = nil,
        allowRemoteAttachmentUrls: Bool = false,
        theme: ChatThemeOverride? = nil
    ) throws {
        let key = Self.nonBlank(apiKey)
        let token = Self.nonBlank(customerToken)
        switch (key, token) {
        case let (key?, nil):
            guard let colon = key.firstIndex(of: ":"),
                  !key[..<colon].trimmingCharacters(in: .whitespaces).isEmpty,
                  !key[key.index(after: colon)...].trimmingCharacters(in: .whitespaces).isEmpty
            else { throw Self.configError(Self.malformedApiKeyMessage) }
            self.auth = .apiKey(key)
        case let (nil, token?):
            self.auth = .customerToken(token)
        default:
            throw Self.configError(Self.exclusiveModeMessage)
        }
        guard baseUrl.hasPrefix("http://") || baseUrl.hasPrefix("https://") else {
            throw LiveAndAiChatError(
                type: .validation,
                message: "baseUrl must start with http:// or https://",
                recoverable: false
            )
        }
        if baseUrl != Self.defaultBaseUrl && !Self.isDebugBuild {
            throw LiveAndAiChatError(
                type: .validation,
                message: "baseUrl override is only allowed in debug SDK builds. " +
                    "Shipped (release) builds must use the default \(Self.defaultBaseUrl).",
                recoverable: false
            )
        }
        self.baseUrl = baseUrl
        self.gqlPath = gqlPath
        self.ssePath = ssePath
        self.wsPath = wsPath
        self.transport = transport
        self.initialMessage = initialMessage
        self.allowRemoteAttachmentUrls = allowRemoteAttachmentUrls
        self.theme = theme
    }

    public var authMode: ChatAuthMode {
        switch auth {
        case .apiKey: return .apiKey
        case .customerToken: return .customerToken
        }
    }

    public var description: String {
        let credential: String
        switch auth {
        case .apiKey(let key): credential = "apiKey: \(key.prefix { $0 != ":" }):***"
        case .customerToken: credential = "customerToken: ***"
        }
        return "LiveAndAiChatConfig(authMode: \(authMode), \(credential), baseUrl: \(baseUrl), transport: \(transport?.rawValue ?? "auto"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["description": description], displayStyle: .struct)
    }

    static let exclusiveModeMessage = "pass either apiKey (keyId:secret) or customerToken"
    static let malformedApiKeyMessage = "apiKey must be keyId:secret, or use customerToken"
    static let setUserTokenInKeyModeMessage = "setUserToken is only available when the SDK is configured with customerToken"
    static let blankCustomerTokenMessage = "customerToken must not be blank"

    static func configError(_ message: String) -> LiveAndAiChatError {
        LiveAndAiChatError(type: .validation, message: message, recoverable: false, code: ChatErrorCode.invalidConfig)
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public var gqlEndpoint: URL {
        URL(string: baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + gqlPath)!
    }

    public var sseEndpoint: URL {
        URL(string: baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + ssePath)!
    }

    public var wsEndpoint: URL {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let wsBase: String
        if trimmed.hasPrefix("https://") {
            wsBase = "wss://" + trimmed.dropFirst("https://".count)
        } else if trimmed.hasPrefix("http://") {
            wsBase = "ws://" + trimmed.dropFirst("http://".count)
        } else {
            wsBase = trimmed
        }
        return URL(string: wsBase + wsPath)!
    }

    public static let defaultBaseUrl = "https://service.newinstance.cloud"

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
