import Foundation
import XCTest
@testable import HermesKit

private struct MockRunHTTPSession: HTTPSession {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

private func makeRunResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

final class RunClientTests: XCTestCase {
    func testStartRunAddsAuthorizationAndParsesAcceptedResponse() async throws {
        let endpoint = HermesEndpoint(host: "localhost", port: 8642)
        let url = try XCTUnwrap(endpoint.baseURL?.appending(path: "v1/runs"))
        let session = MockRunHTTPSession { request in
            XCTAssertEqual(request.url, url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-dev-key")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["input"] as? String, "Ship it")
            XCTAssertEqual(json["session_id"] as? String, "session-1")
            XCTAssertEqual(json["instructions"] as? String, "Stay brief")

            let response = #"{"run_id":"run_123","status":"started"}"#.data(using: .utf8) ?? Data()
            return (response, makeRunResponse(url: url, statusCode: 202))
        }

        let client = RunClient(endpoint: endpoint, apiKey: "local-dev-key", session: session)
        let response = try await client.startRun(HermesRunRequest(
            input: "Ship it",
            sessionID: "session-1",
            instructions: "Stay brief"
        ))

        XCTAssertEqual(response.runID, "run_123")
        XCTAssertEqual(response.status, "started")
    }

    func testParseStartRunResponseMapsUnauthorizedStatus() throws {
        let endpoint = HermesEndpoint(host: "localhost", port: 8642)
        let client = RunClient(endpoint: endpoint)
        let url = try XCTUnwrap(endpoint.baseURL?.appending(path: "v1/runs"))

        XCTAssertThrowsError(
            try client.parseStartRunResponse(from: Data(), response: makeRunResponse(url: url, statusCode: 401))
        ) { error in
            XCTAssertEqual(error as? HermesRunClientError, .unauthorized)
        }
    }

    func testEventParserConsumesCommentsAndMultipleDataFrames() throws {
        var parser = HermesRunEventStreamParser()
        let lines = [
            ": keepalive",
            "data: {\"event\":\"message.delta\",",
            "data: \"run_id\":\"run_123\",\"timestamp\":1710000000.0,\"delta\":\"hello\"}",
            "",
            "data: {\"event\":\"run.completed\",\"run_id\":\"run_123\",\"timestamp\":1710000001.0,\"output\":\"hello\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}",
            "",
            ": stream closed"
        ]

        var events: [HermesRunEvent] = []
        for line in lines {
            if let event = try parser.consume(line: line) {
                events.append(event)
            }
        }
        if let event = try parser.finish() {
            events.append(event)
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.type, .messageDelta)
        XCTAssertEqual(events.first?.delta, "hello")
        XCTAssertEqual(events.last?.type, .runCompleted)
        XCTAssertEqual(events.last?.usage?.totalTokens, 3)
    }
}
