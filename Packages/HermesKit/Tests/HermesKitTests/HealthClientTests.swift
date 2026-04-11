import Foundation
import XCTest
@testable import HermesKit

private struct MockHTTPSession: HTTPSession {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

private func makeResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

final class HealthClientTests: XCTestCase {
    func testFetchHealthParsesSuccessfulJSONPayload() async throws {
        let endpoint = HermesEndpoint(host: "localhost", port: 9999)
        let url = try XCTUnwrap(endpoint.baseURL?.appending(path: "health"))
        let session = MockHTTPSession { request in
            XCTAssertEqual(request.url, url)

            let body = #"{"status":"ok","version":"0.2.0","message":"ready"}"#.data(using: .utf8) ?? Data()
            return (body, makeResponse(url: url, statusCode: 200))
        }

        let client = HealthClient(endpoint: endpoint, session: session)
        let health = try await client.fetchHealth()

        XCTAssertEqual(health.statusSummary, "ok")
        XCTAssertEqual(health.version, "0.2.0")
        XCTAssertEqual(health.detail, "ready")
    }

    func testCheckConnectionMapsUnauthorizedIntoDisconnectedState() async {
        let endpoint = HermesEndpoint(host: "localhost", port: 9999)
        let url = endpoint.baseURL?.appending(path: "health")
        let session = MockHTTPSession { _ in
            (Data(), makeResponse(url: url!, statusCode: 401))
        }

        let state = await HealthClient(endpoint: endpoint, session: session).checkConnection()

        guard case let .disconnected(message) = state else {
            return XCTFail("Expected disconnected state, got \(state)")
        }

        XCTAssertTrue(message.contains("401"))
    }

    func testCheckConnectionMapsTimeoutIntoDisconnectedState() async {
        let endpoint = HermesEndpoint(host: "localhost", port: 9999)
        let session = MockHTTPSession { _ in
            throw URLError(.timedOut)
        }

        let state = await HealthClient(endpoint: endpoint, session: session).checkConnection()

        guard case let .disconnected(message) = state else {
            return XCTFail("Expected disconnected state, got \(state)")
        }

        XCTAssertTrue(message.localizedCaseInsensitiveContains("timed out"))
    }

}
