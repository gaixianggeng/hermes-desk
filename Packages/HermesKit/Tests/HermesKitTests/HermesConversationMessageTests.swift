import Foundation
import XCTest
@testable import HermesKit

final class HermesConversationMessageTests: XCTestCase {
    func testUsefulAssistantMessageStaysInWorkspaceConversation() {
        let message = HermesConversationMessage(
            id: 1,
            sessionID: "session-1",
            role: .assistant,
            content: "已完成三栏 Workspace 重构，下一步建议把会话 API 正式接进来。",
            timestamp: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(message.workspaceClassification, .conversation)
        XCTAssertTrue(message.shouldDisplayInWorkspaceConversation)
        XCTAssertFalse(message.shouldRouteToTaskProgress)
    }

    func testToolLikeAssistantLogRoutesToTaskProgress() {
        let message = HermesConversationMessage(
            id: 2,
            sessionID: "session-1",
            role: .assistant,
            content: "📚 skill_view: \"claude-code\"\n💻 terminal: \"xcodebuild -project HermesDesk.xcodeproj\"\n🔀 delegate_task: \"review the workspace\"",
            timestamp: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(message.workspaceClassification, .progress)
        XCTAssertFalse(message.shouldDisplayInWorkspaceConversation)
        XCTAssertTrue(message.shouldRouteToTaskProgress)
    }

    func testMixedAssistantContentStillRoutesToTaskProgressWhenMostlyLogs() {
        let message = HermesConversationMessage(
            id: 3,
            sessionID: "session-1",
            role: .assistant,
            content: "先同步一下当前状态。\n📚 skill_view: \"claude-code\"\n💻 terminal: \"xcodebuild -project HermesDesk.xcodeproj\"",
            timestamp: Date(timeIntervalSince1970: 102)
        )

        XCTAssertEqual(message.workspaceClassification, .progress)
        XCTAssertFalse(message.shouldDisplayInWorkspaceConversation)
        XCTAssertTrue(message.shouldRouteToTaskProgress)
    }

    func testSystemMessageDefaultsToTaskProgress() {
        let message = HermesConversationMessage(
            id: 4,
            sessionID: "session-1",
            role: .system,
            content: "Session resumed from history",
            timestamp: Date(timeIntervalSince1970: 103)
        )

        XCTAssertFalse(message.shouldDisplayInWorkspaceConversation)
        XCTAssertTrue(message.shouldRouteToTaskProgress)
    }

    func testToolRoleAlwaysRoutesToTaskProgress() {
        let message = HermesConversationMessage(
            id: 5,
            sessionID: "session-1",
            role: .tool,
            content: "xcodebuild -project HermesDesk.xcodeproj",
            toolName: "terminal",
            timestamp: Date(timeIntervalSince1970: 104)
        )

        XCTAssertFalse(message.shouldDisplayInWorkspaceConversation)
        XCTAssertTrue(message.shouldRouteToTaskProgress)
    }

    func testSyntheticControlMessageDoesNotRenderAsUserConversation() {
        let message = HermesConversationMessage(
            id: 8,
            sessionID: "session-1",
            role: .user,
            content: "You've reached the maximum number of tool-calling iterations allowed. Please provide a final response summarizing what you've found and accomplished so far, without calling any more tools.",
            timestamp: Date(timeIntervalSince1970: 107)
        )

        XCTAssertTrue(message.isSyntheticControlMessage)
        XCTAssertEqual(message.workspaceClassification, .progress)
        XCTAssertFalse(message.shouldDisplayInWorkspaceConversation)
        XCTAssertTrue(message.shouldRouteToTaskProgress)
    }

    func testReasoningStyleAssistantDraftRoutesToTaskProgress() {
        let message = HermesConversationMessage(
            id: 9,
            sessionID: "session-1",
            role: .assistant,
            content: "Exploring online profiles I'm noticing that an interesting root redirects to an old Google profile. This could suggest some past affiliation. I'm not sure it's necessary to explore that further. I might want to use Junyu Reads as a source.",
            timestamp: Date(timeIntervalSince1970: 108)
        )

        XCTAssertEqual(message.workspaceClassification, .progress)
        XCTAssertFalse(message.shouldDisplayInWorkspaceConversation)
        XCTAssertTrue(message.shouldRouteToTaskProgress)
    }

    func testStructuredStatusDumpRoutesToTaskProgress() {
        let message = HermesConversationMessage(
            id: 10,
            sessionID: "session-1",
            role: .assistant,
            content: """
            ### 当前阶段
            - **阶段**: 发布完成
            - **状态**: 已验收
            reportId: d79243fd09df1a8c8367ed89
            POST http://127.0.0.1:18080/api/v1/reports/import
            https://www.pingwest.com/a/97544
            """,
            timestamp: Date(timeIntervalSince1970: 109)
        )

        XCTAssertEqual(message.workspaceClassification, .progress)
        XCTAssertFalse(message.shouldDisplayInWorkspaceConversation)
        XCTAssertTrue(message.shouldRouteToTaskProgress)
    }

    func testMarkdownRichAnswerStaysInWorkspaceConversation() {
        let message = HermesConversationMessage(
            id: 11,
            sessionID: "session-1",
            role: .assistant,
            content: """
            当然。你可以把**古典音乐**理解成一种长期发展的音乐传统。

            ## 1. 先抓核心
            - **结构**通常更完整
            - **配器**和声更讲究

            ## 2. 入门方式
            先听**巴赫**、**莫扎特**和**德彪西**，比直接啃大部头更容易进入状态。
            """,
            timestamp: Date(timeIntervalSince1970: 110)
        )

        XCTAssertEqual(message.workspaceClassification, .conversation)
        XCTAssertTrue(message.shouldDisplayInWorkspaceConversation)
        XCTAssertFalse(message.shouldRouteToTaskProgress)
    }

    func testFullTranscriptModeShowsToolAndSystemMessages() {
        let toolMessage = HermesConversationMessage(
            id: 6,
            sessionID: "session-1",
            role: .tool,
            content: "xcodebuild -project HermesDesk.xcodeproj",
            toolName: "terminal",
            timestamp: Date(timeIntervalSince1970: 105)
        )
        let systemMessage = HermesConversationMessage(
            id: 7,
            sessionID: "session-1",
            role: .system,
            content: "Session resumed from history",
            timestamp: Date(timeIntervalSince1970: 106)
        )

        XCTAssertTrue(toolMessage.shouldDisplayInWorkspace(mode: .full))
        XCTAssertTrue(systemMessage.shouldDisplayInWorkspace(mode: .full))
        XCTAssertFalse(toolMessage.shouldDisplayInWorkspace(mode: .conversation))
        XCTAssertFalse(systemMessage.shouldDisplayInWorkspace(mode: .conversation))
    }
}
