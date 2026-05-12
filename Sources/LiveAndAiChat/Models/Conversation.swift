import Foundation

public enum ConversationStatus: String, Codable, Sendable {
    case botActive = "BOT_ACTIVE"
    case waiting = "WAITING"
    case active = "ACTIVE"
    case closed = "CLOSED"
    case resolved = "RESOLVED"
}

public struct Conversation: Codable, Equatable, Sendable {
    public let id: String
    public let status: ConversationStatus
    public let assignedAgentId: String?
    public let assignedAgentName: String?
    public let customerName: String?
    public let customerEmail: String?
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        id: String,
        status: ConversationStatus = .botActive,
        assignedAgentId: String? = nil,
        assignedAgentName: String? = nil,
        customerName: String? = nil,
        customerEmail: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.status = status
        self.assignedAgentId = assignedAgentId
        self.assignedAgentName = assignedAgentName
        self.customerName = customerName
        self.customerEmail = customerEmail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decodeIfPresent(ConversationStatus.self, forKey: .status) ?? .botActive
        assignedAgentId = try c.decodeIfPresent(String.self, forKey: .assignedAgentId)
        assignedAgentName = try c.decodeIfPresent(String.self, forKey: .assignedAgentName)
        customerName = try c.decodeIfPresent(String.self, forKey: .customerName)
        customerEmail = try c.decodeIfPresent(String.self, forKey: .customerEmail)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

public enum AssignmentStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case assigned = "ASSIGNED"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case expired = "EXPIRED"
}

public struct Assignment: Codable, Equatable, Sendable {
    public let id: String
    public let status: AssignmentStatus
    public let agentId: String?
    public let agentName: String?
    public let queuePosition: Int?
    public let estimatedWaitTime: Int?
    public let createdAt: String?

    public init(
        id: String,
        status: AssignmentStatus = .pending,
        agentId: String? = nil,
        agentName: String? = nil,
        queuePosition: Int? = nil,
        estimatedWaitTime: Int? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.status = status
        self.agentId = agentId
        self.agentName = agentName
        self.queuePosition = queuePosition
        self.estimatedWaitTime = estimatedWaitTime
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decodeIfPresent(AssignmentStatus.self, forKey: .status) ?? .pending
        // Server returns either {agentId, agentName} or {assignedAgentId,
        // assignedAgentName} depending on the operation — accept both.
        if let v = try c.decodeIfPresent(String.self, forKey: .agentId) {
            agentId = v
        } else {
            agentId = try c.decodeIfPresent(String.self, forKey: .assignedAgentId)
        }
        if let v = try c.decodeIfPresent(String.self, forKey: .agentName) {
            agentName = v
        } else {
            agentName = try c.decodeIfPresent(String.self, forKey: .assignedAgentName)
        }
        queuePosition = try c.decodeIfPresent(Int.self, forKey: .queuePosition)
        estimatedWaitTime = try c.decodeIfPresent(Int.self, forKey: .estimatedWaitTime)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(agentId, forKey: .agentId)
        try c.encodeIfPresent(agentName, forKey: .agentName)
        try c.encodeIfPresent(queuePosition, forKey: .queuePosition)
        try c.encodeIfPresent(estimatedWaitTime, forKey: .estimatedWaitTime)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, status, agentId, agentName, queuePosition, estimatedWaitTime, createdAt
        case assignedAgentId, assignedAgentName
    }
}
