import Foundation
import XCTest
@testable import HermesKit

final class HermesProfileTaskStoreTests: XCTestCase {
    func testSnapshotWithConversationContentIsDisplayableWorkspaceTask() {
        let snapshot = HermesRootSessionTaskSnapshot(
            profileID: "kunce",
            rootSessionID: "root",
            currentSessionID: "root",
            rootSession: HermesSessionDescriptor(sessionID: "root", source: "feishu"),
            currentSession: HermesSessionDescriptor(sessionID: "root", source: "feishu"),
            lineage: [HermesSessionDescriptor(sessionID: "root", source: "feishu")],
            initialUserMessage: "请帮我复盘 Hermes Desk",
            latestConversationMessage: "已经定位了 session 状态问题",
            lastActivityAt: Date()
        )

        XCTAssertTrue(snapshot.shouldDisplayInWorkspaceTaskList)
    }

    func testEmptyShellSnapshotDoesNotDisplayEvenForCliOrGatewaySources() {
        let snapshot = HermesRootSessionTaskSnapshot(
            profileID: "kunce",
            rootSessionID: "root",
            currentSessionID: "root",
            rootSession: HermesSessionDescriptor(sessionID: "root", source: "cli"),
            currentSession: HermesSessionDescriptor(sessionID: "root", source: "cli"),
            lineage: [HermesSessionDescriptor(sessionID: "root", source: "cli")],
            initialUserMessage: nil,
            latestConversationMessage: nil,
            lastActivityAt: Date()
        )

        XCTAssertFalse(snapshot.shouldDisplayInWorkspaceTaskList)
    }

    func testApiServerSnapshotsStayHiddenFromWorkspaceTaskList() {
        let snapshot = HermesRootSessionTaskSnapshot(
            profileID: "kunce",
            rootSessionID: "root",
            currentSessionID: "root",
            rootSession: HermesSessionDescriptor(sessionID: "root", source: "api_server"),
            currentSession: HermesSessionDescriptor(sessionID: "root", source: "api_server"),
            lineage: [HermesSessionDescriptor(sessionID: "root", source: "api_server")],
            initialUserMessage: "Reply with JSON only",
            latestConversationMessage: "{\"ok\":true}",
            lastActivityAt: Date()
        )

        XCTAssertFalse(snapshot.shouldDisplayInWorkspaceTaskList)
    }
}