import Foundation
import Combine

enum RatingStatus: Equatable, Sendable { case idle, sending, sent, error }

struct PendingRating: Equatable, Sendable {
    let conversationId: String
    let agentName: String?
    var status: RatingStatus
}

/// In-memory state store for an active chat session. Mirrors the Android
/// `ChatStore.kt` field-for-field — published properties replace Kotlin
/// `StateFlow`. UI layers (SwiftUI views in Phase 2.B) and the SDK
/// callbacks both observe this through Combine.
@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var flowState: FlowState = .idle
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var conversation: Conversation?
    @Published private(set) var assignment: Assignment?
    @Published private(set) var agentTyping: Bool = false
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var draftText: String = ""
    @Published private(set) var pendingRating: PendingRating?

    var ratingsEnabled = false

    static let maxRatingComment = 1000
    static let ratingNotAllowed = "RATING_NOT_ALLOWED"
    static let ratingsOff = "RATINGS_OFF"

    private let fetchConversation: (String) async throws -> Conversation?
    private let rate: (String, Int?, String?, Bool) async throws -> Void
    private let clearDelayMs: UInt64
    private var ratingEpoch = 0
    private var capturesInFlight: Set<String> = []

    init(
        fetchConversation: @escaping (String) async throws -> Conversation? = { _ in nil },
        rate: @escaping (String, Int?, String?, Bool) async throws -> Void = { _, _, _, _ in },
        clearDelayMs: UInt64 = 2000
    ) {
        self.fetchConversation = fetchConversation
        self.rate = rate
        self.clearDelayMs = clearDelayMs
    }

    func discardPendingRating() {
        ratingEpoch += 1
        capturesInFlight.removeAll()
        pendingRating = nil
    }

    func capturePendingRating(conversationId: String) async {
        guard ratingsEnabled else { return }
        if let existing = pendingRating, existing.conversationId == conversationId, existing.status != .idle { return }
        guard capturesInFlight.insert(conversationId).inserted else { return }
        let epoch = ratingEpoch
        let conversation = try? await fetchConversation(conversationId)
        if epoch == ratingEpoch { capturesInFlight.remove(conversationId) }
        guard epoch == ratingEpoch, let conversation else { return }
        if let current = pendingRating, current.conversationId == conversationId, current.status != .idle { return }
        let ended = conversation.status == .resolved || conversation.status == .closed
        guard ended, conversation.rating == nil, conversation.lastCustomerMessageAt != nil else { return }
        pendingRating = PendingRating(
            conversationId: conversationId,
            agentName: conversation.assignedAgentId != nil ? conversation.assignedAgentName : nil,
            status: .idle
        )
    }

    func submitRating(score: Int, comment: String?) async {
        guard (1...5).contains(score) else { return }
        let trimmed = comment?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxRatingComment)
        let cleaned = trimmed.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        await sendRating(score: score, comment: cleaned, skip: false)
    }

    func skipRating() async {
        await sendRating(score: nil, comment: nil, skip: true)
    }

    private func sendRating(score: Int?, comment: String?, skip: Bool) async {
        guard let pending = pendingRating, pending.status == .idle || pending.status == .error else { return }
        let id = pending.conversationId
        let epoch = ratingEpoch
        func setStatus(_ status: RatingStatus) {
            guard epoch == ratingEpoch, pendingRating?.conversationId == id else { return }
            pendingRating?.status = status
        }
        func clear() {
            guard epoch == ratingEpoch, pendingRating?.conversationId == id else { return }
            pendingRating = nil
        }
        setStatus(.sending)
        do {
            try await rate(id, score, comment, skip)
        } catch {
            guard let refusal = error as? LiveAndAiChatError, refusal.code == Self.ratingNotAllowed else {
                setStatus(.error)
                return
            }
            if refusal.reason == Self.ratingsOff { ratingsEnabled = false }
            clear()
            return
        }
        if skip { return clear() }
        setStatus(.sent)
        try? await Task.sleep(nanoseconds: clearDelayMs * 1_000_000)
        clear()
    }

    func updateDraft(_ text: String) {
        draftText = text
    }
    @Published private(set) var widgetOpen: Bool = false
    /// Highest `seq` seen so far. Drives gap-fill on reconnect, mirroring
    /// the web SDK's `highestSeq` and Android `ChatStore.highestSeq`.
    @Published private(set) var highestSeq: Int64 = 0

    func setConversation(_ conversation: Conversation?, assignment: Assignment?) {
        self.conversation = conversation
        self.assignment = assignment
        self.flowState = Self.derive(conversation: conversation, assignment: assignment)
    }

    func setAssignment(_ assignment: Assignment?) {
        self.assignment = assignment
        self.flowState = Self.derive(conversation: conversation, assignment: assignment)
    }

    func setAgentTyping(_ value: Bool) {
        self.agentTyping = value
    }

    func openWidget() {
        widgetOpen = true
        unreadCount = 0
    }

    func closeWidget() {
        widgetOpen = false
    }

    /// Idempotent insert/merge.
    /// - If a message with the same `id` exists → replace.
    /// - Else if a message with the same `clientId` (and clientId not blank) exists → replace.
    /// - Else append.
    /// After insert/replace, re-sort by (`seq` ?? `Int64.max`).
    @discardableResult
    func mergeMessage(_ message: ChatMessage) -> Bool {
        let before = messages.count
        var list = messages
        var action: String
        if let idx = list.firstIndex(where: { $0.id == message.id }) {
            list[idx] = message
            action = "replace-by-id"
        } else if let cid = message.clientId, !cid.isEmpty,
                  let idx = list.firstIndex(where: { $0.clientId == cid }) {
            list[idx] = message
            action = "replace-by-clientId"
        } else {
            list.append(message)
            action = "append"
        }
        list.sort { ($0.seq ?? .max) < ($1.seq ?? .max) }
        messages = list

        if let seq = message.seq { highestSeq = max(highestSeq, seq) }

        let isNew = action == "append"
        let isInbound = message.type == .agent || message.type == .ai
        if isNew && isInbound && !widgetOpen {
            unreadCount += 1
        }
        SseLog.debug("store.mergeMessage \(action) id=\(message.id.suffix(8)) type=\(message.type.rawValue) seq=\(message.seq ?? -1) count: \(before)→\(messages.count)")
        return isNew
    }

    func setInitialMessages(_ messages: [ChatMessage]) {
        let sorted = messages.sorted { ($0.seq ?? .max) < ($1.seq ?? .max) }
        self.messages = sorted
        let maxSeq = messages.compactMap { $0.seq }.max() ?? 0
        highestSeq = max(highestSeq, maxSeq)
    }

    /// Replaces a message in-place if it exists. Used for status
    /// transitions (e.g. `.sent` → `.failed`) without re-running the
    /// merge dedup path.
    func updateMessage(messageId: String, transform: (ChatMessage) -> ChatMessage) {
        messages = messages.map { $0.id == messageId ? transform($0) : $0 }
    }

    func removeMessage(_ messageId: String) {
        messages.removeAll { $0.id == messageId }
    }

    func reset() {
        discardPendingRating()
        draftText = ""
        flowState = .idle
        messages = []
        conversation = nil
        assignment = nil
        agentTyping = false
        unreadCount = 0
        widgetOpen = false
        highestSeq = 0
    }

    /// Pure derivation, exposed for unit tests.
    static func derive(conversation: Conversation?, assignment: Assignment?) -> FlowState {
        guard let c = conversation else { return .idle }
        if c.status == .closed || c.status == .resolved { return .ended }
        if c.status == .active { return .liveChat }
        if c.assignedAgentId != nil { return .liveChat }
        if assignment?.status == .accepted || assignment?.status == .assigned { return .liveChat }
        if c.status == .waiting { return .handoffPending }
        if assignment?.status == .pending { return .handoffPending }
        if c.status == .botActive { return .botConversation }
        return .botConversation
    }
}
