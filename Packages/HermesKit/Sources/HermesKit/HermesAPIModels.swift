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
