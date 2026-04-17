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
            XCTAssertNil(json["conversation_history"])

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

    func testStartRunEncodesConversationHistoryWhenProvided() async throws {
        let endpoint = HermesEndpoint(host: "localhost", port: 8642)
        let url = try XCTUnwrap(endpoint.baseURL?.appending(path: "v1/runs"))
        let session = MockRunHTTPSession { request in
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let history = try XCTUnwrap(json["conversation_history"] as? [[String: Any]])
            XCTAssertEqual(history.count, 2)
            XCTAssertEqual(history[0]["role"] as? String, "user")
            XCTAssertEqual(history[0]["content"] as? String, "第一句")
            XCTAssertEqual(history[1]["role"] as? String, "assistant")
            XCTAssertEqual(history[1]["content"] as? String, "第一句的回复")

            let response = #"{"run_id":"run_456","status":"started"}"#.data(using: .utf8) ?? Data()
            return (response, makeRunResponse(url: url, statusCode: 202))
        }

        let client = RunClient(endpoint: endpoint, apiKey: "local-dev-key", session: session)
        let response = try await client.startRun(HermesRunRequest(
            input: "继续这个会话",
            sessionID: "session-1",
            instructions: nil,
            conversationHistory: [
                HermesConversationHistoryMessage(role: "user", content: "第一句"),
                HermesConversationHistoryMessage(role: "assistant", content: "第一句的回复")
            ]
        ))

        XCTAssertEqual(response.runID, "run_456")
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

    func testEventParserParsesApprovalRequestedAndInterruptedEvents() throws {
        var parser = HermesRunEventStreamParser()
        let lines = [
            "data: {\"event\":\"approval.requested\",\"run_id\":\"run_approval\",\"timestamp\":1710000002.0,\"approval_id\":\"approval_1\",\"command\":\"rm -rf /tmp/demo\",\"description\":\"Dangerous command\",\"allow_permanent\":true}",
            "",
            "data: {\"event\":\"run.interrupted\",\"run_id\":\"run_approval\",\"timestamp\":1710000003.0,\"message\":\"Stop requested via API server\"}",
            ""
        ]

        var events: [HermesRunEvent] = []
        for line in lines {
            if let event = try parser.consume(line: line) {
                events.append(event)
            }
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.type, .approvalRequested)
        XCTAssertEqual(events.first?.approvalID, "approval_1")
        XCTAssertEqual(events.first?.command, "rm -rf /tmp/demo")
        XCTAssertEqual(events.last?.type, .runInterrupted)
        XCTAssertEqual(events.last?.message, "Stop requested via API server")
    }

    func testEventParserToleratesStructuredPreviewPayloads() throws {
        var parser = HermesRunEventStreamParser()
        let lines = [
            "data: {\"event\":\"tool.started\",\"run_id\":\"run_structured\",\"timestamp\":1710000004.0,\"tool\":\"browser_navigate\",\"preview\":{\"url\":\"https://example.com\",\"title\":\"Example\"}}",
            "",
            "data: {\"event\":\"reasoning.available\",\"run_id\":\"run_structured\",\"timestamp\":1710000005.0,\"text\":[\"step one\",\"step two\"]}",
            ""
        ]

        var events: [HermesRunEvent] = []
        for line in lines {
            if let event = try parser.consume(line: line) {
                events.append(event)
            }
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.type, .toolStarted)
        XCTAssertEqual(events.first?.toolName, "browser_navigate")
        XCTAssertNotNil(events.first?.preview)
        XCTAssertTrue(events.first?.preview?.contains("\"title\":\"Example\"") == true)
        XCTAssertTrue(events.first?.preview?.contains("\"url\":\"https:\\/\\/example.com\"") == true)
        XCTAssertEqual(events.last?.type, .reasoningAvailable)
        XCTAssertEqual(events.last?.reasoning, "[\"step one\",\"step two\"]")
    }

    func testEventParserSkipsMalformedFramesAndContinuesStreaming() throws {
        var parser = HermesRunEventStreamParser()
        let lines = [
            "data: {\"event\":\"run.unknown\",\"run_id\":\"run_bad\",\"timestamp\":1710000000.0,\"delta\":\"ignored\"}",
            "",
            "data: {\"event\":\"message.delta\",\"run_id\":\"run_bad\",\"timestamp\":1710000001.0,\"delta\":\"hello\"}",
            "",
            "data: {\"event\":\"run.completed\",\"run_id\":\"run_bad\",\"timestamp\":1710000002.0,\"output\":\"hello\"}",
            ""
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
        XCTAssertEqual(events.last?.output, "hello")
    }

    func testRunActionAddsApprovalIDAndParsesResponse() async throws {
        let endpoint = HermesEndpoint(host: "localhost", port: 8642)
        let url = try XCTUnwrap(endpoint.baseURL?.appending(path: "v1/runs/run_123/actions"))
        let session = MockRunHTTPSession { request in
            XCTAssertEqual(request.url, url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-dev-key")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["action"] as? String, "approve_once")
            XCTAssertEqual(json["approval_id"] as? String, "approval_1")

            let response = #"{"run_id":"run_123","status":"approval_resolved","approval_id":"approval_1","decision":"once"}"#.data(using: .utf8) ?? Data()
            return (response, makeRunResponse(url: url, statusCode: 200))
        }

        let client = RunClient(endpoint: endpoint, apiKey: "local-dev-key", session: session)
        let response = try await client.performRunAction(
            runID: "run_123",
            request: HermesRunActionRequest(action: .approveOnce, approvalID: "approval_1")
        )

        XCTAssertEqual(response.runID, "run_123")
        XCTAssertEqual(response.status, "approval_resolved")
        XCTAssertEqual(response.approvalID, "approval_1")
        XCTAssertEqual(response.decision, "once")
    }
}
