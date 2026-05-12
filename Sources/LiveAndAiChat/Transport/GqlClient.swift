import Foundation

/// Lightweight GraphQL-over-HTTP client. URLSession-based so the SDK has
/// zero third-party dependencies. Returns the `data` payload as a
/// `[String: Any]` dictionary which callers decode into their concrete
/// model types — we deliberately don't generate per-operation result
/// types because the SDK already pins selection sets in ``Operations``.
final class GqlClient {
    private let endpoint: URL
    private let apiKey: String
    private let session: URLSession

    init(endpoint: URL, apiKey: String, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    /// Execute a GraphQL operation. `operationName` is optional and only
    /// used for server-side logging; the SDK does not multiplex multiple
    /// operations into a single document so it's almost always nil.
    @discardableResult
    func execute(
        query: String,
        variables: [String: Any]? = nil,
        operationName: String? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        if let operationName { body["operationName"] = operationName }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlErr as URLError {
            throw LiveAndAiChatError(
                type: .network,
                message: urlErr.localizedDescription,
                recoverable: true,
                underlying: urlErr
            )
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1

        if data.isEmpty {
            throw LiveAndAiChatError(
                type: status >= 500 ? .system : .network,
                message: "Empty response (HTTP \(status))",
                recoverable: status != 401 && status != 403
            )
        }

        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw LiveAndAiChatError(
                type: .system,
                message: "Malformed JSON from server",
                recoverable: true
            )
        }

        if let errors = parsed["errors"] as? [[String: Any]], !errors.isEmpty {
            let first = errors[0]
            let extensions = first["extensions"] as? [String: Any]
            let code = extensions?["code"] as? String
            let message = (first["message"] as? String) ?? "GraphQL error"
            let type: ChatErrorType
            switch code {
            case "UNAUTHENTICATED", "FORBIDDEN":
                type = .auth
            case "BAD_USER_INPUT", "VALIDATION_ERROR":
                type = .validation
            case "INTERNAL_SERVER_ERROR":
                type = .system
            default:
                type = (status >= 500) ? .system : .network
            }
            throw LiveAndAiChatError(
                type: type,
                message: message,
                recoverable: type != .auth,
                code: code
            )
        }

        if status >= 400 {
            let type: ChatErrorType
            if status == 401 || status == 403 { type = .auth }
            else if status >= 500 { type = .system }
            else { type = .network }
            throw LiveAndAiChatError(
                type: type,
                message: "HTTP \(status)",
                recoverable: type != .auth
            )
        }

        guard let payload = parsed["data"] as? [String: Any] else {
            throw LiveAndAiChatError(
                type: .system,
                message: "Response missing data field",
                recoverable: true
            )
        }
        return payload
    }

    /// Convenience helper — re-encodes a JSON-friendly dictionary slice
    /// (e.g. one field of a server response) into a Codable model. Used
    /// instead of writing a per-operation typed wrapper.
    static func decode<T: Decodable>(_ type: T.Type, from any: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: any, options: [])
        return try JSONDecoder().decode(type, from: data)
    }
}
