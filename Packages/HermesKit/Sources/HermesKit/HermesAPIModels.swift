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

    public init(endpoint: HermesEndpoint = .defaultLocal, apiKey: String? = nil) {
        self.endpoint = endpoint
        self.apiKey = apiKey?.nilIfBlank
    }

    public static func discover() -> HermesLocalServerConfiguration {
        let environment = HermesEnvironmentFile.loadDefault()
        let processEnvironment = ProcessInfo.processInfo.environment

        let scheme = processEnvironment["API_SERVER_SCHEME"]
            ?? environment["API_SERVER_SCHEME"]
            ?? HermesEndpoint.defaultLocal.scheme
        let host = processEnvironment["API_SERVER_HOST"]
            ?? environment["API_SERVER_HOST"]
            ?? HermesEndpoint.defaultLocal.host
        let port = Int(
            processEnvironment["API_SERVER_PORT"]
                ?? environment["API_SERVER_PORT"]
                ?? String(HermesEndpoint.defaultLocal.port)
        ) ?? HermesEndpoint.defaultLocal.port
        let apiKey = processEnvironment["API_SERVER_KEY"]
            ?? environment["API_SERVER_KEY"]

        return HermesLocalServerConfiguration(
            endpoint: HermesEndpoint(scheme: scheme, host: host, port: port),
            apiKey: apiKey
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

    public init(input: String, sessionID: String? = nil, instructions: String? = nil) {
        self.input = input
        self.sessionID = sessionID?.nilIfBlank
        self.instructions = instructions?.nilIfBlank
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

public enum HermesRunEventType: String, Codable, Equatable, Sendable, CaseIterable {
    case toolStarted = "tool.started"
    case toolCompleted = "tool.completed"
    case reasoningAvailable = "reasoning.available"
    case messageDelta = "message.delta"
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
        usage: HermesRunUsage? = nil
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
        case .toolStarted, .toolCompleted, .runFailed:
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
            debugDescription: "Hermes run event is missing a valid timestamp."
        )
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

    subscript(key: String) -> String? {
        values[key]?.nilIfBlank
    }

    static func loadDefault(fileManager: FileManager = .default) -> HermesEnvironmentFile {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let candidate = homeDirectory
            .appending(path: ".hermes", directoryHint: .isDirectory)
            .appending(path: ".env")

        guard fileManager.fileExists(atPath: candidate.path),
              let contents = try? String(contentsOf: candidate, encoding: .utf8) else {
            return HermesEnvironmentFile(values: [:])
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

        return HermesEnvironmentFile(values: values)
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
