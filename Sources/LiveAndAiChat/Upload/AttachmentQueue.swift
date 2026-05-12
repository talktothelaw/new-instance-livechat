import Foundation
import Combine

public enum AttachmentStatus: String, Sendable {
    case queued
    case uploading
    case uploaded
    case failed
}

public struct QueuedAttachment: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var mimeType: String
    public var size: Int64
    public var status: AttachmentStatus
    public var progress: Double
    public var publicUrl: String?
    public var errorReason: String?
    /// Optional local preview source (e.g. an in-memory `UIImage`
    /// or a file URL string) so the composer chip can render the picked
    /// file before the upload completes. The UI is free to use or
    /// ignore this hint.
    public var previewUri: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        mimeType: String,
        size: Int64,
        status: AttachmentStatus = .queued,
        progress: Double = 0,
        publicUrl: String? = nil,
        errorReason: String? = nil,
        previewUri: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.status = status
        self.progress = progress
        self.publicUrl = publicUrl
        self.errorReason = errorReason
        self.previewUri = previewUri
    }
}

/// Observable in-memory queue. Mirrors the Android `AttachmentQueue` —
/// the public `items` flow drives the composer chip strip; ``drainUploaded``
/// pops items in the `.uploaded` state when the user hits send so we
/// build the outbound GraphQL `attachments` array from them.
@MainActor
public final class AttachmentQueue: ObservableObject {
    @Published public private(set) var items: [QueuedAttachment] = []

    public func add(_ item: QueuedAttachment) {
        items.append(item)
    }

    public func update(id: String, _ transform: (QueuedAttachment) -> QueuedAttachment) {
        items = items.map { $0.id == id ? transform($0) : $0 }
    }

    public func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    public func clear() {
        items.removeAll()
    }

    /// Returns drained, fully-uploaded attachments in ``MessageAttachment``
    /// form. Items still uploading or failed remain in the queue so the
    /// user can see them.
    public func drainUploaded() -> [MessageAttachment] {
        var drained: [MessageAttachment] = []
        var remaining: [QueuedAttachment] = []
        for it in items {
            if it.status == .uploaded, let url = it.publicUrl {
                drained.append(MessageAttachment(url: url, name: it.name, type: it.mimeType, size: it.size))
            } else {
                remaining.append(it)
            }
        }
        items = remaining
        return drained
    }
}
