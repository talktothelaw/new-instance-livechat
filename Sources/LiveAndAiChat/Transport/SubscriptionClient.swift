import Foundation
import Combine

/// Request shape passed to ``SubscriptionClient/subscribe(_:)``. Mirrors the
/// Android `SubscriptionRequest` data class.
struct SubscriptionRequest {
    let query: String
    let variables: [String: Any]?
    let operationName: String?

    init(query: String, variables: [String: Any]? = nil, operationName: String? = nil) {
        self.query = query
        self.variables = variables
        self.operationName = operationName
    }
}

/// Common interface that the SSE and WebSocket subscription clients
/// implement. Each call to ``subscribe(_:)`` returns a Combine publisher
/// of the operation's `data` payloads (one element per server-pushed
/// event); cancelling the subscription unsubscribes on the wire.
///
/// The client owns its own reconnect loop, so consumers see a continuous
/// publisher even across transport flaps.
protocol SubscriptionClient: AnyObject {
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> { get }
    func start()
    func stop()
    func subscribe(_ request: SubscriptionRequest) -> AnyPublisher<[String: Any], Never>
}
