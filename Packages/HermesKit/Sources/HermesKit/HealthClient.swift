import Foundation

public protocol HTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {}

public struct HealthClient: Sendable {
    public let endpoint: HermesEndpoint
    private let apiKey: String?
    private let session: any HTTPSession
    private let timeout: TimeInterval

    public init(
        endpoint: HermesEndpoint = .defaultLocal,
        apiKey: String? = nil,
        session: any HTTPSession = URLSession.shared,
        timeout: TimeInterval = 3
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? apiKey : nil
        self.session = session
        self.timeout = timeout
    }

    public func fetchHealth() async throws -> HermesHealth {
        guard let url = endpoint.baseURL?.appending(path: "health") else {
            throw HealthCheckError.invalidEndpoint(endpoint.displayName)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let apiKey, apiKey.isEmpty == false {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HealthCheckError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200 ..< 300:
                return try parseHealth(from: data)
            case 401:
                throw HealthCheckError.unauthorized
            default:
                throw HealthCheckError.unexpectedStatus(httpResponse.statusCode)
            }
        } catch let error as HealthCheckError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw HealthCheckError.timedOut
            default:
                throw HealthCheckError.transport(error.localizedDescription)
            }
        } catch {
            throw HealthCheckError.transport(error.localizedDescription)
        }
    }

    public func checkConnection() async -> HermesConnectionState {
        do {
            let health = try await fetchHealth()
            return .online(health)
        } catch let error as HealthCheckError {
            switch error {
            case .invalidEndpoint:
                return .configurationError(message: error.errorDescription ?? "Invalid endpoint")
            default:
                return .disconnected(message: error.errorDescription ?? "Hermes is unavailable")
            }
        } catch {
            return .disconnected(message: error.localizedDescription)
        }
    }

    private func parseHealth(from data: Data) throws -> HermesHealth {
        if data.isEmpty {
            return HermesHealth(statusSummary: "ok", detail: "Hermes responded with an empty body.")
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let okFlag = object["ok"] as? Bool
            let rawStatus = object["status"] as? String
            let statusSummary = rawStatus ?? (okFlag == true ? "ok" : "online")
            let detail = object["message"] as? String
                ?? object["detail"] as? String
                ?? object["service"] as? String
            let version = object["version"] as? String
                ?? object["server_version"] as? String

            return HermesHealth(
                statusSummary: statusSummary,
                version: version,
                detail: detail,
                rawStatus: rawStatus
            )
        }

        if let rawText = String(data: data, encoding: .utf8), rawText.isEmpty == false {
            return HermesHealth(
                statusSummary: "ok",
                detail: rawText,
                rawStatus: rawText
            )
        }

        throw HealthCheckError.invalidResponse
    }
}
