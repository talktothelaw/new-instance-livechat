import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

enum AttachmentSourceResolver {

    struct Resolved {
        let data: Data
        let mimeType: String
        let name: String
    }

    static func resolve(
        request: AttachmentRequest,
        allowRemote: Bool,
        maxBytes: Int64,
        allowedMime: Set<String>
    ) async throws -> Resolved {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw validation("Attachment name is required") }

        var sourceMime: String?
        let data: Data
        switch request.source {
        case .bytes(let bytes):
            data = bytes
        case .base64(let value):
            guard let decoded = AttachmentSource.decodeBase64(value) else {
                throw validation("Invalid base64 attachment data")
            }
            data = decoded
        case .dataUri(let uri):
            guard let parsed = parseDataUri(uri) else { throw validation("Invalid data URI") }
            sourceMime = parsed.mime
            data = parsed.data
        case .filePath(let path):
            data = try readFile(path: path, maxBytes: maxBytes)
        case .remoteUrl(let urlString):
            if !allowRemote {
                throw validation("Remote URL attachments are disabled — enable allowRemoteAttachmentUrls to use them")
            }
            data = try await fetchRemote(urlString: urlString, maxBytes: maxBytes)
        }

        if data.isEmpty { throw validation("Attachment is empty") }
        if Int64(data.count) > maxBytes { throw sizeError(maxBytes) }
        if let declared = request.declaredSize, declared != Int64(data.count) {
            throw validation("Attachment size mismatch: declared \(declared) bytes, got \(data.count) — the file may be corrupted")
        }

        guard let mime = normalizeMime(request.mimeType ?? sourceMime ?? mimeFromName(name)) else {
            throw validation("Could not determine the attachment MIME type — pass mimeType explicitly")
        }
        if !allowedMime.contains(mime) { throw validation("Unsupported file type: \(mime)") }
        if let extMime = normalizeMime(mimeFromName(name)), allowedMime.contains(extMime), extMime != mime {
            throw validation("File extension does not match MIME type (\(extMime) vs \(mime))")
        }

        return Resolved(data: data, mimeType: mime, name: name)
    }

    static func parseDataUri(_ uri: String) -> (mime: String?, data: Data)? {
        guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
        let header = String(uri[uri.index(uri.startIndex, offsetBy: 5)..<comma])
        guard header.hasSuffix(";base64") else { return nil }
        let mimePart = String(header.dropLast(";base64".count))
        let mime = mimePart.isEmpty ? nil : mimePart
        guard let data = AttachmentSource.decodeBase64(String(uri[uri.index(after: comma)...])) else { return nil }
        return (mime, data)
    }

    static func normalizeMime(_ mime: String?) -> String? {
        guard let value = mime?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        return value == "image/jpg" ? "image/jpeg" : value
    }

    static func mimeFromName(_ name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return nil }
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        default:
            #if canImport(UniformTypeIdentifiers)
            if #available(iOS 14.0, macOS 11.0, *) {
                return UTType(filenameExtension: ext)?.preferredMIMEType
            }
            #endif
            return nil
        }
    }

    private static func readFile(path: String, maxBytes: Int64) throws -> Data {
        let url: URL
        if path.hasPrefix("file://"), let parsed = URL(string: path) {
            url = parsed
        } else {
            url = URL(fileURLWithPath: path)
        }
        guard url.isFileURL else { throw validation("Not a file URL") }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) > maxBytes {
            throw sizeError(maxBytes)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw validation("File not found or unreadable: \(url.lastPathComponent)")
        }
    }

    private static func fetchRemote(urlString: String, maxBytes: Int64) async throws -> Data {
        guard let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else {
            throw validation("Invalid remote attachment URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw validation("Remote attachment fetch failed (HTTP \(code))")
        }
        if Int64(data.count) > maxBytes { throw sizeError(maxBytes) }
        return data
    }

    private static func validation(_ message: String) -> LiveAndAiChatError {
        LiveAndAiChatError(type: .validation, message: message, recoverable: true)
    }

    private static func sizeError(_ maxBytes: Int64) -> LiveAndAiChatError {
        validation("File exceeds \(maxBytes / (1024 * 1024)) MB limit")
    }
}
