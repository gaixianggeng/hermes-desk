import Foundation

public protocol AgentBackend: Sendable {
    var endpoint: HermesEndpoint { get }
    func health() async -> HermesConnectionState
    func startRun(
        input: String,
        sessionID: String?,
        instructions: String?
    ) async throws -> HermesRunStartResponse
    func runEvents(for runID: String) -> AsyncThrowingStream<HermesRunEvent, Error>
}
