import Foundation

public enum ChatCloseReason: String, Sendable {
    case closeButton = "close_button"
    case backNavigation = "back_navigation"
    case gesture = "gesture"
    case programmatic = "programmatic"
    case sessionEnded = "session_ended"
    case hostNavigation = "host_navigation"
}

public enum ChatCloseInitiator: String, Sendable {
    case user
    case host
    case sdk
}

public struct ChatCloseEvent: Sendable {
    public let reason: ChatCloseReason
    public let initiator: ChatCloseInitiator
    public let timestamp: Int64
    public let conversationId: String?
    public let assignmentId: String?
    public let channel: String
    public let previousState: String
    public let unreadCount: Int
    public let hasDraft: Bool
    public let pendingAttachmentCount: Int
    public let metadata: [String: String]
}

final class CloseEmissionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false

    func arm() {
        lock.lock()
        armed = true
        lock.unlock()
    }

    func tryClaim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !armed { return false }
        armed = false
        return true
    }

    var isArmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return armed
    }
}
