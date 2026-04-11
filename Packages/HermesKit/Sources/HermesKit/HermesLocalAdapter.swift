import Foundation

public struct HermesLocalAdapter: AgentBackend, Sendable {
    public let endpoint: HermesEndpoint
    private let healthClient: HealthClient
    private let runClient: RunClient

    public init(
        configuration: HermesLocalServerConfiguration = .discover(),
        session: any HTTPSession = URLSession.shared,
        streamSession: URLSession = .shared,
        timeout: TimeInterval = 60
    ) {
        endpoint = configuration.endpoint
        healthClient = HealthClient(
            endpoint: configuration.endpoint,
            apiKey: configuration.apiKey,
            session: session,
            timeout: min(timeout, 5)
        )
        runClient = RunClient(
            endpoint: configuration.endpoint,
            apiKey: configuration.apiKey,
            session: session,
            streamSession: streamSession,
            timeout: timeout
        )
    }

    public func health() async -> HermesConnectionState {
        await healthClient.checkConnection()
    }

    public func startRun(
        input: String,
        sessionID: String?,
        instructions: String?
    ) async throws -> HermesRunStartResponse {
        try await runClient.startRun(
            HermesRunRequest(input: input, sessionID: sessionID, instructions: instructions)
        )
    }

    public func runEvents(for runID: String) -> AsyncThrowingStream<HermesRunEvent, Error> {
        runClient.runEvents(for: runID)
    }
}
