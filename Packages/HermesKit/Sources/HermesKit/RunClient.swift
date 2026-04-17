import Foundation

public struct HermesRunEventStreamParser {
    private var bufferedDataLines: [String] = []

    public init() {}

    public mutating func consume(line: String) throws -> HermesRunEvent? {
        if line.isEmpty {
            return try flush()
        }

        if line.hasPrefix(":") {
            return nil
        }

        guard line.hasPrefix("data:") else {
            return nil
        }

        var dataLine = String(line.dropFirst(5))
        if dataLine.first == " " {
            dataLine.removeFirst()
        }
        bufferedDataLines.append(dataLine)
        return nil
    }

    public mutating func finish() throws -> HermesRunEvent? {
        try flush()
    }

    private mutating func flush() throws -> HermesRunEvent? {
        guard bufferedDataLines.isEmpty == false else {
            return nil
        }

        let payload = bufferedDataLines.joined(separator: "\n")
        bufferedDataLines.removeAll(keepingCapacity: true)

        guard let data = payload.data(using: .utf8) else {
            throw HermesRunClientError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(HermesRunEvent.self, from: data)
        } catch {
            // Keep the SSE stream alive when the server emits an unexpected frame.
            // A single malformed event should not prevent later run.completed output
            // from reaching the workspace.
            return nil
        }
    }
}

public struct RunClient: Sendable {
    public let endpoint: HermesEndpoint
    private let apiKey: String?
    private let session: any HTTPSession
    private let streamSession: URLSession
    private let timeout: TimeInterval

    public init(
        endpoint: HermesEndpoint = .defaultLocal,
        apiKey: String? = nil,
        session: any HTTPSession = URLSession.shared,
        streamSession: URLSession = .shared,
        timeout: TimeInterval = 60
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? apiKey : nil
        self.session = session
        self.streamSession = streamSession
        self.timeout = timeout
    }

    public func startRun(_ request: HermesRunRequest) async throws -> HermesRunStartResponse {
        guard let url = endpoint.baseURL?.appending(path: "v1/runs") else {
            throw HermesRunClientError.invalidEndpoint(endpoint.displayName)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorizationHeader(to: &urlRequest)
        urlRequest.httpBody = try JSONEncoder().encode(StartRunRequestBody(request: request))

        do {
            let (data, response) = try await session.data(for: urlRequest)
            return try parseStartRunResponse(from: data, response: response)
        } catch let error as HermesRunClientError {
            throw error
        } catch let error as URLError {
            throw HermesRunClientError.transport(error.localizedDescription)
        } catch {
            throw HermesRunClientError.transport(error.localizedDescription)
        }
    }

    public func performRunAction(
        runID: String,
        request: HermesRunActionRequest
    ) async throws -> HermesRunActionResponse {
        guard let url = endpoint.baseURL?.appending(path: "v1/runs/\(runID)/actions") else {
            throw HermesRunClientError.invalidEndpoint(endpoint.displayName)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorizationHeader(to: &urlRequest)
        urlRequest.httpBody = try JSONEncoder().encode(request)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            return try parseRunActionResponse(from: data, response: response)
        } catch let error as HermesRunClientError {
            throw error
        } catch let error as URLError {
            throw HermesRunClientError.transport(error.localizedDescription)
        } catch {
            throw HermesRunClientError.transport(error.localizedDescription)
        }
    }

    public func runEvents(for runID: String) -> AsyncThrowingStream<HermesRunEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let url = endpoint.baseURL?.appending(path: "v1/runs/\(runID)/events") else {
                continuation.finish(throwing: HermesRunClientError.invalidEndpoint(endpoint.displayName))
                return
            }

            let streamTask = Task {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "GET"
                urlRequest.timeoutInterval = timeout
                urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                applyAuthorizationHeader(to: &urlRequest)

                do {
                    let (bytes, response) = try await streamSession.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw HermesRunClientError.invalidResponse
                    }

                    switch httpResponse.statusCode {
                    case 200 ..< 300:
                        break
                    case 401:
                        throw HermesRunClientError.unauthorized
                    default:
                        throw HermesRunClientError.unexpectedStatus(httpResponse.statusCode, nil)
                    }

                    var parser = HermesRunEventStreamParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if let event = try parser.consume(line: line) {
                            continuation.yield(event)
                        }
                    }

                    if let finalEvent = try parser.finish() {
                        continuation.yield(finalEvent)
                    }
                    continuation.finish()
                } catch let error as HermesRunClientError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: HermesRunClientError.transport(error.localizedDescription))
                } catch {
                    continuation.finish(throwing: HermesRunClientError.transport(error.localizedDescription))
                }
            }

            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }

    public func parseStartRunResponse(from data: Data, response: URLResponse) throws -> HermesRunStartResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesRunClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            do {
                return try JSONDecoder().decode(HermesRunStartResponse.self, from: data)
            } catch {
                throw HermesRunClientError.invalidResponse
            }
        case 401:
            throw HermesRunClientError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8)
            throw HermesRunClientError.unexpectedStatus(httpResponse.statusCode, body)
        }
    }

    public func parseRunActionResponse(from data: Data, response: URLResponse) throws -> HermesRunActionResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HermesRunClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            do {
                return try JSONDecoder().decode(HermesRunActionResponse.self, from: data)
            } catch {
                throw HermesRunClientError.invalidResponse
            }
        case 401:
            throw HermesRunClientError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8)
            throw HermesRunClientError.unexpectedStatus(httpResponse.statusCode, body)
        }
    }

    private func applyAuthorizationHeader(to request: inout URLRequest) {
        guard let apiKey, apiKey.isEmpty == false else {
            return
        }

        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
}

private struct StartRunRequestBody: Encodable {
    let input: String
    let sessionID: String?
    let instructions: String?
    let conversationHistory: [HermesConversationHistoryMessage]?

    init(request: HermesRunRequest) {
        input = request.input
        sessionID = request.sessionID
        instructions = request.instructions
        conversationHistory = request.conversationHistory
    }

    private enum CodingKeys: String, CodingKey {
        case input
        case sessionID = "session_id"
        case instructions
        case conversationHistory = "conversation_history"
    }
}
