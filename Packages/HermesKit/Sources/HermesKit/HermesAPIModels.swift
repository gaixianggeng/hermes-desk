import Foundation

public struct HermesEndpoint: Codable, Equatable, Sendable {
    public var scheme: String
    public var host: String
    public var port: Int

    public init(scheme: String = "http", host: String = "127.0.0.1", port: Int = 8642) {
        self.scheme = scheme
        self.host = host
        self.port = port
    }

    public var baseURL: URL? {
        URL(string: "\(scheme)://\(host):\(port)")
    }

    public var displayName: String {
        "\(scheme)://\(host):\(port)"
    }

    public static let defaultLocal = HermesEndpoint()
}

public struct HermesLocalServerConfiguration: Equatable, Sendable {
    public var endpoint: HermesEndpoint
    public var apiKey: String?
    public var hermesHomePath: String
    public var environmentFilePath: String
    public var environmentFileExists: Bool

    public init(
        endpoint: HermesEndpoint = .defaultLocal,
        apiKey: String? = nil,
        hermesHomePath: String? = nil,
        environmentFilePath: String? = nil,
        environmentFileExists: Bool = false
    ) {
        let resolvedHermesHome = hermesHomePath?.nilIfBlank
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appending(path: ".hermes", directoryHint: .isDirectory)
                .path
        self.endpoint = endpoint
        self.apiKey = apiKey?.nilIfBlank
        self.hermesHomePath = resolvedHermesHome
        self.environmentFilePath = environmentFilePath?.nilIfBlank
            ?? URL(fileURLWithPath: resolvedHermesHome, isDirectory: true)
                .appending(path: ".env")
                .path
        self.environmentFileExists = environmentFileExists
    }

    public static func discover(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> HermesLocalServerConfiguration {
        let defaultHermesHomePath = homeDirectory
            .appending(path: ".hermes", directoryHint: .isDirectory)
            .path
        let hermesHomePath = processEnvironment["HERMES_HOME"]?.nilIfBlank
            ?? defaultHermesHomePath
        let environment = HermesEnvironmentFile.load(
            hermesHomePath: hermesHomePath,
            fileManager: fileManager
        )
        let sharedEnvironment = hermesHomePath == defaultHermesHomePath
            ? environment
            : HermesEnvironmentFile.load(
                hermesHomePath: defaultHermesHomePath,
                fileManager: fileManager
            )

        let scheme = processEnvironment["API_SERVER_SCHEME"]
            ?? environment["API_SERVER_SCHEME"]
            ?? sharedEnvironment["API_SERVER_SCHEME"]
            ?? HermesEndpoint.defaultLocal.scheme
        let host = processEnvironment["API_SERVER_HOST"]
            ?? environment["API_SERVER_HOST"]
            ?? sharedEnvironment["API_SERVER_HOST"]
            ?? HermesEndpoint.defaultLocal.host
        let port = Int(
            processEnvironment["API_SERVER_PORT"]
                ?? environment["API_SERVER_PORT"]
                ?? sharedEnvironment["API_SERVER_PORT"]
                ?? String(HermesEndpoint.defaultLocal.port)
        ) ?? HermesEndpoint.defaultLocal.port
        let apiKey = processEnvironment["API_SERVER_KEY"]
            ?? environment["API_SERVER_KEY"]
            ?? sharedEnvironment["API_SERVER_KEY"]

        return HermesLocalServerConfiguration(
            endpoint: HermesEndpoint(scheme: scheme, host: host, port: port),
            apiKey: apiKey,
            hermesHomePath: hermesHomePath,
            environmentFilePath: environment.filePath,
            environmentFileExists: environment.exists
        )
    }
}

public struct HermesHealth: Codable, Equatable, Sendable {
    public var statusSummary: String
    public var version: String?
    public var detail: String?
    public var rawStatus: String?
    public var checkedAt: Date

    public init(
        statusSummary: String,
        version: String? = nil,
        detail: String? = nil,
        rawStatus: String? = nil,
        checkedAt: Date = .now
    ) {
        self.statusSummary = statusSummary
        self.version = version
        self.detail = detail
        self.rawStatus = rawStatus
        self.checkedAt = checkedAt
    }
}

public enum HermesConnectionState: Equatable, Sendable {
    case online(HermesHealth)
    case starting(message: String)
    case disconnected(message: String)
    case configurationError(message: String)

    public var title: String {
        switch self {
        case .online:
            return "Hermes online"
        case .starting:
            return "Checking Hermes"
        case .disconnected:
            return "Hermes offline"
        case .configurationError:
            return "Hermes misconfigured"
        }
    }

    public var detail: String {
        switch self {
        case let .online(health):
            let versionPart = health.version.map { " · v\($0)" } ?? ""
            let detailPart = health.detail.map { " · \($0)" } ?? ""
            return "\(health.statusSummary)\(versionPart)\(detailPart)"
        case let .starting(message), let .disconnected(message), let .configurationError(message):
            return message
        }
    }

    public var isHealthy: Bool {
        if case .online = self {
            return true
        }

        return false
    }
}

public enum HealthCheckError: Error, LocalizedError, Equatable, Sendable {
    case invalidEndpoint(String)
    case invalidResponse
    case unauthorized
    case unexpectedStatus(Int)
    case timedOut
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(endpoint):
            return "Invalid Hermes endpoint: \(endpoint)"
        case .invalidResponse:
            return "Hermes returned an invalid response."
        case .unauthorized:
            return "Hermes rejected the request (401)."
        case let .unexpectedStatus(statusCode):
            return "Hermes returned HTTP \(statusCode)."
        case .timedOut:
            return "Hermes health check timed out."
        case let .transport(message):
            return message
        }
    }
}

public struct HermesRunRequest: Equatable, Sendable {
    public var input: String
    public var sessionID: String?
    public var instructions: String?
    public var conversationHistory: [HermesConversationHistoryMessage]?

    public init(
        input: String,
        sessionID: String? = nil,
        instructions: String? = nil,
        conversationHistory: [HermesConversationHistoryMessage]? = nil
    ) {
        self.input = input
        self.sessionID = sessionID?.nilIfBlank
        self.instructions = instructions?.nilIfBlank
        self.conversationHistory = conversationHistory?.isEmpty == false ? conversationHistory : nil
    }

    public init(input: String, sessionID: String? = nil, instructions: String? = nil) {
        self.init(
            input: input,
            sessionID: sessionID,
            instructions: instructions,
            conversationHistory: nil
        )
    }
}

public struct HermesConversationHistoryMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct HermesRunStartResponse: Codable, Equatable, Sendable {
    public var runID: String
    public var status: String

    public init(runID: String, status: String) {
        self.runID = runID
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
    }
}

public struct HermesRunUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, totalTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

public enum HermesRunAction: String, Codable, Equatable, Sendable, CaseIterable {
    case approveOnce = "approve_once"
    case approveForTask = "approve_for_task"
    case reject
    case retry
    case stop
}

public struct HermesRunActionRequest: Encodable, Equatable, Sendable {
    public var action: HermesRunAction
    public var approvalID: String?

    public init(action: HermesRunAction, approvalID: String? = nil) {
        self.action = action
        self.approvalID = approvalID?.nilIfBlank
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case approvalID = "approval_id"
    }
}

public struct HermesRunActionResponse: Codable, Equatable, Sendable {
    public var runID: String
    public var status: String
    public var approvalID: String?
    public var decision: String?

    public init(runID: String, status: String, approvalID: String? = nil, decision: String? = nil) {
        self.runID = runID
        self.status = status
        self.approvalID = approvalID?.nilIfBlank
        self.decision = decision?.nilIfBlank
    }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
        case approvalID = "approval_id"
        case decision
    }
}

public enum HermesRunEventType: String, Codable, Equatable, Sendable, CaseIterable {
    case toolStarted = "tool.started"
    case toolCompleted = "tool.completed"
    case reasoningAvailable = "reasoning.available"
    case messageDelta = "message.delta"
    case approvalRequested = "approval.requested"
    case approvalResolved = "approval.resolved"
    case observationReconnecting = "observation.reconnecting"
    case observationDisconnected = "observation.disconnected"
    case runInterrupted = "run.interrupted"
    case runCompleted = "run.completed"
    case runFailed = "run.failed"
}

public struct HermesRunEvent: Codable, Equatable, Sendable, Identifiable {
    public var type: HermesRunEventType
    public var runID: String
    public var timestamp: Date
    public var toolName: String?
    public var preview: String?
    public var reasoning: String?
    public var delta: String?
    public var output: String?
    public var duration: TimeInterval?
    public var isToolError: Bool
    public var failureMessage: String?
    public var usage: HermesRunUsage?
    public var approvalID: String?
    public var command: String?
    public var eventDescription: String?
    public var allowPermanent: Bool?
    public var decision: String?
    public var message: String?

    public init(
        type: HermesRunEventType,
        runID: String,
        timestamp: Date,
        toolName: String? = nil,
        preview: String? = nil,
        reasoning: String? = nil,
        delta: String? = nil,
        output: String? = nil,
        duration: TimeInterval? = nil,
        isToolError: Bool = false,
        failureMessage: String? = nil,
        usage: HermesRunUsage? = nil,
        approvalID: String? = nil,
        command: String? = nil,
        eventDescription: String? = nil,
        allowPermanent: Bool? = nil,
        decision: String? = nil,
        message: String? = nil
    ) {
        self.type = type
        self.runID = runID
        self.timestamp = timestamp
        self.toolName = toolName?.nilIfBlank
        self.preview = preview?.nilIfBlank
        self.reasoning = reasoning?.nilIfBlank
        self.delta = delta?.nilIfEmptyPreservingWhitespace
        self.output = output?.nilIfBlank
        self.duration = duration
        self.isToolError = isToolError
        self.failureMessage = failureMessage?.nilIfBlank
        self.usage = usage
        self.approvalID = approvalID?.nilIfBlank
        self.command = command?.nilIfBlank
        self.eventDescription = eventDescription?.nilIfBlank
        self.allowPermanent = allowPermanent
        self.decision = decision?.nilIfBlank
        self.message = message?.nilIfBlank
    }

    public var id: String {
        "\(runID)-\(type.rawValue)-\(timestamp.timeIntervalSince1970)"
    }

    public var timelineSummary: String {
        switch type {
        case .toolStarted:
            return "Started tool: \(toolName ?? "tool")"
        case .toolCompleted:
            return isToolError ? "Tool reported an error: \(toolName ?? "tool")" : "Completed tool: \(toolName ?? "tool")"
        case .reasoningAvailable:
            return "Reasoning updated"
        case .messageDelta:
            return "Streaming output"
        case .approvalRequested:
            return "Approval requested"
        case .approvalResolved:
            return decision == "deny" ? "Approval rejected" : "Approval granted"
        case .observationReconnecting:
            return "Reconnecting live feed"
        case .observationDisconnected:
            return "Live feed disconnected"
        case .runInterrupted:
            return "Run interrupted"
        case .runCompleted:
            return "Run completed"
        case .runFailed:
            return "Run failed"
        }
    }

    public var timelineDetail: String? {
        switch type {
        case .toolStarted:
            return preview
        case .toolCompleted:
            guard let duration else {
                return nil
            }
            return "Duration: \(duration.formatted(.number.precision(.fractionLength(0 ... 3))))s"
        case .reasoningAvailable:
            return reasoning
        case .messageDelta:
            return delta
        case .approvalRequested:
            return [eventDescription, command].compactMap { $0 }.joined(separator: "\n")
        case .approvalResolved:
            return decision
        case .observationReconnecting, .observationDisconnected:
            return message
        case .runInterrupted:
            return message
        case .runCompleted:
            return output
        case .runFailed:
            return failureMessage
        }
    }

    public var streamedText: String? {
        switch type {
        case .messageDelta:
            return delta
        case .reasoningAvailable:
            return reasoning
        case .runCompleted:
            return output
        case .toolStarted, .toolCompleted, .approvalRequested, .approvalResolved, .observationReconnecting, .observationDisconnected, .runInterrupted, .runFailed:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type = "event"
        case runID = "run_id"
        case timestamp
        case toolName = "tool"
        case preview
        case reasoning = "text"
        case delta
        case output
        case duration
        case error
        case usage
        case approvalID = "approval_id"
        case command
        case eventDescription = "description"
        case allowPermanent = "allow_permanent"
        case decision
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(HermesRunEventType.self, forKey: .type)
        runID = try container.decode(String.self, forKey: .runID)
        timestamp = try HermesRunEvent.decodeTimestamp(from: container)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)?.nilIfBlank
        preview = try container.decodeIfPresent(String.self, forKey: .preview)?.nilIfBlank
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)?.nilIfBlank
        delta = try container.decodeIfPresent(String.self, forKey: .delta)?.nilIfEmptyPreservingWhitespace
        output = try container.decodeIfPresent(String.self, forKey: .output)?.nilIfBlank
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        usage = try container.decodeIfPresent(HermesRunUsage.self, forKey: .usage)
        approvalID = try container.decodeIfPresent(String.self, forKey: .approvalID)?.nilIfBlank
        command = try container.decodeIfPresent(String.self, forKey: .command)?.nilIfBlank
        eventDescription = try container.decodeIfPresent(String.self, forKey: .eventDescription)?.nilIfBlank
        allowPermanent = try container.decodeIfPresent(Bool.self, forKey: .allowPermanent)
        decision = try container.decodeIfPresent(String.self, forKey: .decision)?.nilIfBlank
        message = try container.decodeIfPresent(String.self, forKey: .message)?.nilIfBlank

        if let boolError = try container.decodeIfPresent(Bool.self, forKey: .error) {
            isToolError = boolError
            failureMessage = nil
        } else if let stringError = try container.decodeIfPresent(String.self, forKey: .error)?.nilIfBlank {
            isToolError = false
            failureMessage = stringError
        } else {
            isToolError = false
            failureMessage = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(runID, forKey: .runID)
        try container.encode(timestamp.timeIntervalSince1970, forKey: .timestamp)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(delta, forKey: .delta)
        try container.encodeIfPresent(output, forKey: .output)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(approvalID, forKey: .approvalID)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(eventDescription, forKey: .eventDescription)
        try container.encodeIfPresent(allowPermanent, forKey: .allowPermanent)
        try container.encodeIfPresent(decision, forKey: .decision)
        try container.encodeIfPresent(message, forKey: .message)
        switch type {
        case .toolCompleted:
            try container.encode(isToolError, forKey: .error)
        case .runFailed:
            try container.encodeIfPresent(failureMessage, forKey: .error)
        default:
            break
        }
        try container.encodeIfPresent(usage, forKey: .usage)
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>) throws -> Date {
        if let seconds = try container.decodeIfPresent(Double.self, forKey: .timestamp) {
            return Date(timeIntervalSince1970: seconds)
        }

        if let seconds = try container.decodeIfPresent(Int.self, forKey: .timestamp) {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }

        if let seconds = try container.decodeIfPresent(String.self, forKey: .timestamp),
           let value = Double(seconds) {
            return Date(timeIntervalSince1970: value)
        }

        throw DecodingError.dataCorruptedError(
            forKey: .timestamp,
            in: container,
            debugDescription: "Expected unix timestamp as Double, Int, or String"
        )
    }
}

public enum HermesConversationRole: String, Codable, Equatable, Sendable, CaseIterable {
    case user
    case assistant
    case tool
    case system
    case sessionMeta = "session_meta"
    case unknown

    public init(rawRole: String) {
        self = HermesConversationRole(rawValue: rawRole) ?? .unknown
    }

    public var isVisibleInWorkspace: Bool {
        switch self {
        case .sessionMeta:
            return false
        case .user, .assistant, .tool, .system, .unknown:
            return true
        }
    }
}

public enum HermesWorkspaceContentClassification: String, Codable, Equatable, Sendable {
    case conversation
    case progress
    case empty
}

public enum HermesWorkspaceTranscriptMode: String, Codable, Equatable, Sendable, CaseIterable {
    case conversation
    case full
}

public struct HermesConversationMessage: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var sessionID: String
    public var role: HermesConversationRole
    public var content: String
    public var toolName: String?
    public var reasoning: String?
    public var timestamp: Date

    public init(
        id: Int64,
        sessionID: String,
        role: HermesConversationRole,
        content: String,
        toolName: String? = nil,
        reasoning: String? = nil,
        timestamp: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.toolName = toolName?.nilIfBlank
        self.reasoning = reasoning?.nilIfBlank
        self.timestamp = timestamp
    }

    public var displayText: String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty == false {
            return trimmedContent
        }
        if let reasoning, reasoning.isEmpty == false {
            return reasoning
        }
        return ""
    }

    public var workspaceClassification: HermesWorkspaceContentClassification {
        HermesWorkspaceContentClassifier.classify(displayText)
    }

    public var isSyntheticControlMessage: Bool {
        HermesWorkspaceContentClassifier.looksLikeSyntheticControlMessage(displayText)
    }

    public func shouldDisplayInWorkspace(mode: HermesWorkspaceTranscriptMode) -> Bool {
        guard displayText.isEmpty == false else {
            return false
        }

        switch mode {
        case .conversation:
            switch role {
            case .user:
                return isSyntheticControlMessage == false
            case .assistant:
                return workspaceClassification == .conversation
            case .tool, .sessionMeta, .system, .unknown:
                return false
            }
        case .full:
            return true
        }
    }

    public var shouldDisplayInWorkspaceConversation: Bool {
        shouldDisplayInWorkspace(mode: .conversation)
    }

    public var shouldRouteToTaskProgress: Bool {
        guard displayText.isEmpty == false else {
            return false
        }

        switch role {
        case .user:
            return isSyntheticControlMessage
        case .assistant:
            return workspaceClassification == .progress
        case .tool, .sessionMeta, .system, .unknown:
            return true
        }
    }
}

public struct HermesConversationPageCursor: Codable, Equatable, Sendable {
    public var id: Int64
    public var timestamp: Date

    public init(id: Int64, timestamp: Date) {
        self.id = id
        self.timestamp = timestamp
    }
}

public struct HermesConversationPage: Codable, Equatable, Sendable {
    public var messages: [HermesConversationMessage]
    public var hasMoreBefore: Bool

    public init(messages: [HermesConversationMessage], hasMoreBefore: Bool) {
        self.messages = messages
        self.hasMoreBefore = hasMoreBefore
    }
}

public enum HermesWorkspaceContentClassifier {
    public static func classify(_ text: String) -> HermesWorkspaceContentClassification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .empty
        }

        if looksLikeSyntheticControlMessage(trimmed) {
            return .progress
        }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard lines.isEmpty == false else {
            return .empty
        }

        let progressPrefixPattern = #"^[^A-Za-z0-9]*(skill_view|todo|terminal|delegate_task|browser_[a-z_]+|read_file|search_files|write_file|patch|execute_code|process|clarify|cronjob|tool_[a-z_]+)\s*:\s*"#
        let progressSentencePattern = #"^(Started tool|Completed tool|Running tool|Tool reported an error|Streaming output)\b"#
        let reasoningSignalPattern = #"(I(?:'m| am)\s+(?:noticing|thinking|considering|wondering)|I\s+(?:might|could|should|want to|need to)\b|This could suggest|I want to make sure|I'm not sure it's necessary)"#
        let machineStatusPattern = #"(?:\b(?:reportId|created|status|phase|payload|headers?)\s*:|HTTP/\d\.\d|\bPOST\s+http|\bGET\s+http|/tmp/|https?://|^#{2,}\s*(?:当前阶段|当前状态|任务进度|执行摘要|progress|status|phase)\b|^\s*(?:[-*]\s+)?\*\*(?:阶段|状态|进度|摘要|Phase|Status|Progress|Summary)\*\*\s*:)"#

        let matchingLines = lines.filter { line in
            line.range(of: progressPrefixPattern, options: [.regularExpression, .caseInsensitive]) != nil
                || line.range(of: progressSentencePattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        if matchingLines.count >= max(1, lines.count - 1) {
            return .progress
        }

        let reasoningSignalCount: Int
        if let expression = try? NSRegularExpression(pattern: reasoningSignalPattern, options: [.caseInsensitive]) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            reasoningSignalCount = expression.numberOfMatches(in: trimmed, options: [], range: range)
        } else {
            reasoningSignalCount = 0
        }

        if reasoningSignalCount >= 2 {
            return .progress
        }

        let machineStatusSignalCount: Int
        if let expression = try? NSRegularExpression(pattern: machineStatusPattern, options: [.caseInsensitive, .anchorsMatchLines]) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            machineStatusSignalCount = expression.numberOfMatches(in: trimmed, options: [], range: range)
        } else {
            machineStatusSignalCount = 0
        }

        if machineStatusSignalCount >= 3 {
            return .progress
        }

        return .conversation
    }

    public static func looksLikeProgressLog(_ text: String) -> Bool {
        classify(text) == .progress
    }

    public static func looksLikeSyntheticControlMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return false
        }

        let controlPatterns = [
            #"You've reached the maximum number of tool-calling iterations allowed"#,
            #"Please provide a final response summarizing what you've found and accomplished so far"#,
            #"^\[System note:"#,
        ]

        return controlPatterns.contains { pattern in
            trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

public struct HermesSessionDescriptor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { sessionID }
    public var sessionID: String
    public var parentSessionID: String?
    public var title: String?
    public var source: String?
    public var startedAt: Date?
    public var endedAt: Date?

    public init(
        sessionID: String,
        parentSessionID: String? = nil,
        title: String? = nil,
        source: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID?.nilIfBlank
        self.title = title?.nilIfBlank
        self.source = source?.nilIfBlank
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct HermesSessionBinding: Codable, Equatable, Sendable {
    public var rootSessionID: String
    public var currentSessionID: String
    public var lineage: [HermesSessionDescriptor]

    public init(rootSessionID: String, currentSessionID: String, lineage: [HermesSessionDescriptor]) {
        self.rootSessionID = rootSessionID
        self.currentSessionID = currentSessionID
        self.lineage = lineage
    }
}

public enum HermesRunClientError: Error, LocalizedError, Equatable, Sendable {
    case invalidEndpoint(String)
    case invalidResponse
    case unauthorized
    case unexpectedStatus(Int, String?)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(endpoint):
            return "Invalid Hermes endpoint: \(endpoint)"
        case .invalidResponse:
            return "Hermes returned an invalid run response."
        case .unauthorized:
            return "Hermes rejected the request (401)."
        case let .unexpectedStatus(statusCode, body):
            if let body, body.isEmpty == false {
                return "Hermes returned HTTP \(statusCode): \(body)"
            }
            return "Hermes returned HTTP \(statusCode)."
        case let .transport(message):
            return message
        }
    }
}

private struct HermesEnvironmentFile {
    private let values: [String: String]
    let filePath: String
    let exists: Bool

    subscript(key: String) -> String? {
        values[key]?.nilIfBlank
    }

    static func load(
        hermesHomePath: String,
        fileManager: FileManager = .default
    ) -> HermesEnvironmentFile {
        let candidate = URL(fileURLWithPath: hermesHomePath, isDirectory: true)
            .appending(path: ".env")

        guard fileManager.fileExists(atPath: candidate.path),
              let contents = try? String(contentsOf: candidate, encoding: .utf8) else {
            return HermesEnvironmentFile(values: [:], filePath: candidate.path, exists: false)
        }

        var values: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.isEmpty == false, line.hasPrefix("#") == false else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }

        return HermesEnvironmentFile(values: values, filePath: candidate.path, exists: true)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfEmptyPreservingWhitespace: String? {
        isEmpty ? nil : self
    }

}
