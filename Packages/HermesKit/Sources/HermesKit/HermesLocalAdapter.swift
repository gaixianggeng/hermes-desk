import Foundation

public struct HermesLocalAdapter: AgentBackend, Sendable {
    public let endpoint: HermesEndpoint
    private let healthClient: HealthClient

    public init(
        endpoint: HermesEndpoint = .defaultLocal,
        session: any HTTPSession = URLSession.shared,
        timeout: TimeInterval = 3
    ) {
        self.endpoint = endpoint
        self.healthClient = HealthClient(
            endpoint: endpoint,
            session: session,
            timeout: timeout
        )
    }

    public func health() async -> HermesConnectionState {
        await healthClient.checkConnection()
    }
}
