import Foundation

public struct AgentBackendDiagnostics: Equatable, Sendable {
    public var adapterName: String
    public var hermesHomePath: String?
    public var environmentFilePath: String?
    public var environmentFileExists: Bool
    public var apiKeyConfigured: Bool

    public init(
        adapterName: String,
        hermesHomePath: String? = nil,
        environmentFilePath: String? = nil,
        environmentFileExists: Bool = false,
        apiKeyConfigured: Bool = false
    ) {
        self.adapterName = adapterName
        self.hermesHomePath = hermesHomePath
        self.environmentFilePath = environmentFilePath
        self.environmentFileExists = environmentFileExists
        self.apiKeyConfigured = apiKeyConfigured
    }
}

public protocol AgentBackend: Sendable {
    var endpoint: HermesEndpoint { get }
    var diagnostics: AgentBackendDiagnostics { get }
    func health() async -> HermesConnectionState
    func startRun(
        input: String,
        sessionID: String?,
        instructions: String?,
        conversationHistory: [HermesConversationHistoryMessage]?
    ) async throws -> HermesRunStartResponse
    func performRunAction(
        runID: String,
        request: HermesRunActionRequest
    ) async throws -> HermesRunActionResponse
    func runEvents(for runID: String) -> AsyncThrowingStream<HermesRunEvent, Error>
    func fetchSessionMessages(sessionID: String) async throws -> [HermesConversationMessage]
    func fetchSessionMessagesPage(
        sessionID: String,
        limit: Int,
        before: HermesConversationPageCursor?
    ) async throws -> HermesConversationPage
    func fetchSessionBinding(preferredSessionID: String, rootSessionID: String?) async throws -> HermesSessionBinding?
}
