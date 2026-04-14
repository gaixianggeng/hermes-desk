import Foundation
import XCTest
@testable import HermesKit

final class HermesAgentDiscoveryTests: XCTestCase {
    func testDiscoverAgentsBuildsDisplayNameFromSoulMarkdown() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let profileRoot = tempRoot
            .appendingPathComponent(".hermes/profiles/alpha01", isDirectory: true)
        try FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        try """
        你是「Alpha 全栈产品开发代理」，负责产品设计、应用开发与技术交付。
        """.write(to: profileRoot.appendingPathComponent("SOUL.md"), atomically: true, encoding: .utf8)
        try """
        agent:
          system_prompt: "你是产品设计与应用开发代理。"
        """.write(to: profileRoot.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        let agents = HermesAgentDiscovery.discoverAgents(homeDirectory: tempRoot)

        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents.first?.agentID, "alpha01")
        XCTAssertEqual(agents.first?.displayName, "Alpha 全栈产品开发代理")
        XCTAssertEqual(agents.first?.runtimeProfileID, "alpha01")
    }

    func testDiscoverAgentsFallsBackToProfileNameWhenSoulMarkdownMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let profileRoot = tempRoot
            .appendingPathComponent(".hermes/profiles/beta01", isDirectory: true)
        try FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        try """
        agent:
          system_prompt: "你是执行 / 交付代理。"
        """.write(to: profileRoot.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        let agents = HermesAgentDiscovery.discoverAgents(homeDirectory: tempRoot)

        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents.first?.displayName, "beta01")
        XCTAssertEqual(agents.first?.roleSummary, "你是执行 / 交付代理。")
    }
}
