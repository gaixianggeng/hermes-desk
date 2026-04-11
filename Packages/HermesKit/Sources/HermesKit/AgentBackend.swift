import Foundation

public protocol AgentBackend: Sendable {
    var endpoint: HermesEndpoint { get }
    func health() async -> HermesConnectionState
}
