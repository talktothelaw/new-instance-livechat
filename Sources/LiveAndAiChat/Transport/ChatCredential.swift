import Foundation

enum ChatAuth: Equatable, Sendable {
    case apiKey(String)
    case customerToken(String)
}

final class ChatCredential: @unchecked Sendable {
    private let lock = NSLock()
    private var auth: ChatAuth

    init(_ auth: ChatAuth) {
        self.auth = auth
    }

    var current: ChatAuth {
        lock.lock()
        defer { lock.unlock() }
        return auth
    }

    func setCustomerToken(_ token: String) {
        lock.lock()
        auth = .customerToken(token)
        lock.unlock()
    }

    func headers() -> [String: String] {
        var headers = [
            "x-newinstance-sdk": "ios/\(LiveAndAiChat.version)",
            "User-Agent": "LiveAndAiChat-iOS/\(LiveAndAiChat.version)",
        ]
        switch current {
        case .apiKey(let key): headers["x-api-key"] = key
        case .customerToken(let token): headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }
}

func unverifiedTokenSubject(_ token: String) -> String? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sub = object["sub"] as? String,
          !sub.isEmpty else { return nil }
    return sub
}

func unauthenticatedMessage(inGraphQLErrors errors: Any?) -> String? {
    guard let first = (errors as? [[String: Any]])?.first,
          (first["extensions"] as? [String: Any])?["code"] as? String == "UNAUTHENTICATED"
    else { return nil }
    return (first["message"] as? String) ?? "Unauthenticated"
}
