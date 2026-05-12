import Foundation

/// Three-step presigned upload helper. Mirrors the Android `FileUploader`
/// and web `core/fileUpload.ts`:
///   1. `requestPresignedUpload(files: [{originalName, mimeType, size, folder, visibility}])` → `{fileId, uploadUrl}`
///   2. `PUT` bytes to `uploadUrl` with the matching `Content-Type`
///   3. `confirmFileUpload(fileId)` → `{fileId, publicUrl}`
///
/// Constraints (matching web + Android):
///   - Allowed: image/png, image/jpeg, image/webp, image/gif, application/pdf
///   - Max: 25 MB
final class FileUploader {

    enum Constants {
        static let maxBytes: Int64 = 25 * 1024 * 1024
        static let defaultFolder = "cs-chat-attachments"
        static let allowedMime: Set<String> = [
            "image/png", "image/jpeg", "image/jpg", "image/webp", "image/gif",
            "application/pdf",
        ]
    }

    private let gql: GqlClient
    private let session: URLSession

    init(gql: GqlClient, session: URLSession = .shared) {
        self.gql = gql
        self.session = session
    }

    func upload(
        data: Data,
        name: String,
        mimeType: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> String {
        if Int64(data.count) > Constants.maxBytes {
            throw LiveAndAiChatError(
                type: .validation,
                message: "File exceeds 25 MB limit",
                recoverable: true
            )
        }
        if !Constants.allowedMime.contains(mimeType) {
            throw LiveAndAiChatError(
                type: .validation,
                message: "Unsupported file type: \(mimeType)",
                recoverable: true
            )
        }

        onProgress?(0.0)
        let presigned = try await gql.execute(
            query: Operations.requestPresignedUpload,
            variables: [
                "files": [[
                    "originalName": name,
                    "mimeType": mimeType,
                    "size": data.count,
                    "folder": Constants.defaultFolder,
                    "visibility": "PUBLIC",
                ]]
            ]
        )
        guard let arr = presigned["requestPresignedUpload"] as? [[String: Any]],
              let first = arr.first,
              let fileId = first["fileId"] as? String,
              let uploadUrl = first["uploadUrl"] as? String,
              let url = URL(string: uploadUrl)
        else {
            throw LiveAndAiChatError(
                type: .system,
                message: "Presign payload missing",
                recoverable: true
            )
        }

        onProgress?(0.1)
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: req, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LiveAndAiChatError(
                type: .network,
                message: "Upload failed",
                recoverable: true
            )
        }
        onProgress?(0.85)

        let confirm = try await gql.execute(
            query: Operations.confirmFileUpload,
            variables: ["fileId": fileId]
        )
        guard let payload = confirm["confirmFileUpload"] as? [String: Any],
              let publicUrl = payload["publicUrl"] as? String
        else {
            throw LiveAndAiChatError(
                type: .system,
                message: "Confirm missing publicUrl",
                recoverable: true
            )
        }
        onProgress?(1.0)
        return publicUrl
    }
}
