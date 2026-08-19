import Foundation

public enum AttachmentSource: Sendable {
    case base64(String)
    case dataUri(String)
    case filePath(String)
    case bytes(Data)
    case remoteUrl(String)

    public static func detect(_ value: String) -> AttachmentSource? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("data:") { return .dataUri(trimmed) }
        if trimmed.hasPrefix("file://") || trimmed.hasPrefix("/") { return .filePath(trimmed) }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return .remoteUrl(trimmed) }
        if decodeBase64(trimmed) != nil { return .base64(trimmed) }
        return nil
    }

    public static func fromTypeName(_ type: String, value: String) -> AttachmentSource? {
        switch type {
        case "auto": return detect(value)
        case "base64": return .base64(value)
        case "dataUri": return .dataUri(value)
        case "file", "contentUri": return .filePath(value)
        case "url": return .remoteUrl(value)
        default: return nil
        }
    }

    static func decodeBase64(_ value: String) -> Data? {
        let compact = value.filter { !$0.isWhitespace }
        if compact.isEmpty { return nil }
        if let data = Data(base64Encoded: compact) { return data }
        var urlSafe = compact
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while urlSafe.count % 4 != 0 { urlSafe.append("=") }
        return Data(base64Encoded: urlSafe)
    }
}

public struct AttachmentRequest: Sendable {
    public let source: AttachmentSource
    public let name: String
    public let mimeType: String?
    public let declaredSize: Int64?
    public let metadata: [String: String]

    public init(
        source: AttachmentSource,
        name: String,
        mimeType: String? = nil,
        declaredSize: Int64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.source = source
        self.name = name
        self.mimeType = mimeType
        self.declaredSize = declaredSize
        self.metadata = metadata
    }
}
