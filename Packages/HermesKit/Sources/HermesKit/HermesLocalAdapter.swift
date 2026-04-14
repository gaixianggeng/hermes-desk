import Foundation

public struct HermesLocalAdapter: AgentBackend, Sendable {
    public let endpoint: HermesEndpoint
    public let diagnostics: AgentBackendDiagnostics
    private let healthClient: HealthClient
    private let runClient: RunClient
    private let transcriptStore: HermesLocalTranscriptStore

    public init(
        configuration: HermesLocalServerConfiguration = .discover(),
        session: any HTTPSession = URLSession.shared,
        streamSession: URLSession = .shared,
        timeout: TimeInterval = 60
    ) {
        endpoint = configuration.endpoint
        diagnostics = AgentBackendDiagnostics(
            adapterName: "Hermes",
            hermesHomePath: configuration.hermesHomePath,
            environmentFilePath: configuration.environmentFilePath,
            environmentFileExists: configuration.environmentFileExists,
            apiKeyConfigured: configuration.apiKey?.isEmpty == false
        )
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
        transcriptStore = HermesLocalTranscriptStore(
            stateDBPath: URL(fileURLWithPath: configuration.hermesHomePath, isDirectory: true)
                .appending(path: "state.db")
                .path
        )
    }

    public func health() async -> HermesConnectionState {
        await healthClient.checkConnection()
    }

    public func startRun(
        input: String,
        sessionID: String?,
        instructions: String?,
        conversationHistory: [HermesConversationHistoryMessage]?
    ) async throws -> HermesRunStartResponse {
        try await runClient.startRun(
            HermesRunRequest(
                input: input,
                sessionID: sessionID,
                instructions: instructions,
                conversationHistory: conversationHistory
            )
        )
    }

    public func performRunAction(
        runID: String,
        request: HermesRunActionRequest
    ) async throws -> HermesRunActionResponse {
        try await runClient.performRunAction(runID: runID, request: request)
    }

    public func runEvents(for runID: String) -> AsyncThrowingStream<HermesRunEvent, Error> {
        runClient.runEvents(for: runID)
    }

    public func fetchSessionMessages(sessionID: String) async throws -> [HermesConversationMessage] {
        do {
            return try transcriptStore.fetchSessionMessages(sessionID: sessionID)
        } catch HermesLocalTranscriptStoreError.databaseMissing {
            return []
        }
    }

    public func fetchSessionMessagesPage(
        sessionID: String,
        limit: Int,
        before: HermesConversationPageCursor?
    ) async throws -> HermesConversationPage {
        do {
            return try transcriptStore.fetchSessionMessagesPage(sessionID: sessionID, limit: limit, before: before)
        } catch HermesLocalTranscriptStoreError.databaseMissing {
            return HermesConversationPage(messages: [], hasMoreBefore: false)
        }
    }

    public func fetchSessionBinding(preferredSessionID: String, rootSessionID: String?) async throws -> HermesSessionBinding? {
        do {
            return try transcriptStore.fetchSessionBinding(preferredSessionID: preferredSessionID, rootSessionID: rootSessionID)
        } catch HermesLocalTranscriptStoreError.databaseMissing {
            return nil
        }
    }
}
