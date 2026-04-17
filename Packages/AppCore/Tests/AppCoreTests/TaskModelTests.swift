import Foundation
import HermesKit
import XCTest
@testable import AppCore

final class TaskModelTests: XCTestCase {
    func testWorkspaceMarkdownRenderModeUsesMarkdownForHeadingsAndPlainTextWhileStreaming() {
        XCTAssertEqual(
            WorkspaceMarkdownRenderMode.resolve(for: "### 标题\n\n- 列表项", isStreaming: false),
            .markdown
        )
        XCTAssertEqual(
            WorkspaceMarkdownRenderMode.resolve(for: "### 标题\n\n- 列表项", isStreaming: true),
            .markdown
        )
        XCTAssertEqual(
            WorkspaceMarkdownRenderMode.resolve(for: "```python\nprint('hi')", isStreaming: true),
            .plainText
        )
        XCTAssertEqual(
            WorkspaceMarkdownRenderMode.resolve(for: "普通文本，没有 markdown", isStreaming: false),
            .plainText
        )
    }

    func testWorkspaceMarkdownPreviewFormatterRemovesCommonMarkdownSyntax() {
        let source = """
        # Markdown 校验文本

        这是 **加粗** 内容，还有 [OpenAI 官网](https://openai.com)。

        ```python
        print("hello")
        ```
        """

        XCTAssertEqual(
            WorkspaceMarkdownPreviewFormatter.plainText(source)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "Markdown 校验文本 这是 加粗 内容，还有 OpenAI 官网。 print(\"hello\")"
        )
    }

    func testWorkspaceMarkdownSourceFormatterDedentsAccidentallyIndentedMarkdownBlock() {
        let source = """
        当然，下面是一段 Markdown 示例文本：

            # 这是一级标题

            ## 这是二级标题

            - 苹果
            - 香蕉
            - 橙子

            ```python
            print("Hello")
            ```

        链接示例
        """

        let normalized = WorkspaceMarkdownSourceFormatter.normalized(source)

        XCTAssertTrue(normalized.contains("\n# 这是一级标题"))
        XCTAssertTrue(normalized.contains("\n## 这是二级标题"))
        XCTAssertTrue(normalized.contains("\n- 苹果"))
        XCTAssertTrue(normalized.contains("\n```python"))
        XCTAssertFalse(normalized.contains("\n    # 这是一级标题"))
    }

    func testWorkspaceMarkdownSourceFormatterUnwrapsOuterMarkdownExampleFence() {
        let source = """
        当然，下面是一段 Markdown 示例文本：

        ```markdown
        # 这是一级标题

        ### 代码示例

        ```python
        def hello():
            print("Hello, Markdown!")
        ```

        ### 链接示例

        [点击访问 OpenAI](https://openai.com)
        ```

        如果你愿意，我也可以直接给你：
        1. **更短的 Markdown 示例**
        """

        let normalized = WorkspaceMarkdownSourceFormatter.normalized(source)

        XCTAssertFalse(normalized.contains("```markdown"))
        XCTAssertTrue(normalized.contains("# 这是一级标题"))
        XCTAssertTrue(normalized.contains("```python"))
        XCTAssertTrue(normalized.contains("### 链接示例"))
        XCTAssertTrue(normalized.contains("1. **更短的 Markdown 示例**"))
    }

    func testSortedForOverviewPrioritizesPendingWork() {
        let now = Date()
        let tasks = [
            makeTask(id: "recent", state: .succeeded, updatedAt: now.addingTimeInterval(-300)),
            makeTask(id: "running", state: .running, updatedAt: now.addingTimeInterval(-60)),
            makeTask(id: "failed", state: .failed, updatedAt: now.addingTimeInterval(-120)),
            makeTask(id: "waiting", state: .waitingUser, updatedAt: now)
        ]

        let sortedIDs = tasks.sortedForOverview().map(\.taskID)

        XCTAssertEqual(sortedIDs, ["waiting", "failed", "running", "recent"])
    }

    func testTaskStateTerminalFlagMatchesProtocolExpectations() {
        XCTAssertTrue(TaskState.succeeded.isTerminal)
        XCTAssertTrue(TaskState.failed.isTerminal)
        XCTAssertTrue(TaskState.cancelled.isTerminal)
        XCTAssertFalse(TaskState.running.isTerminal)
        XCTAssertFalse(TaskState.waitingUser.isTerminal)
    }

    func testSortedForOverviewKeepsQueuedWorkAheadOfResultsAndCancelledLast() {
        let now = Date()
        let tasks = [
            makeTask(id: "cancelled", state: .cancelled, updatedAt: now.addingTimeInterval(-30)),
            makeTask(id: "succeeded", state: .succeeded, updatedAt: now.addingTimeInterval(-60)),
            makeTask(id: "paused", state: .paused, updatedAt: now.addingTimeInterval(-90)),
            makeTask(id: "queued", state: .queued, updatedAt: now)
        ]

        let sortedIDs = tasks.sortedForOverview().map(\.taskID)

        XCTAssertEqual(sortedIDs, ["queued", "paused", "succeeded", "cancelled"])
    }

    func testSortedForOverviewPrioritizesLiveTasksAheadOfPreviewSamplesWithinSameState() {
        let now = Date()
        let tasks = [
            makeTask(id: "preview-running", state: .running, updatedAt: now, isPreview: true),
            makeTask(id: "live-running", state: .running, updatedAt: now.addingTimeInterval(-60), isPreview: false)
        ]

        let sortedIDs = tasks.sortedForOverview().map(\.taskID)

        XCTAssertEqual(sortedIDs, ["live-running", "preview-running"])
    }

    func testStatusContextLinePrefersPendingAction() {
        let now = Date()
        let task = makeTask(id: "live-running", state: .running, updatedAt: now, pendingAction: .stop)

        XCTAssertEqual(task.statusContextLine, "🛑 Stop requested — waiting for Hermes to finish the action.")
    }

    func testStatusContextLineDescribesRecoveryChain() {
        let now = Date()
        let task = makeTask(id: "failed", state: .failed, updatedAt: now, retryChildTaskID: "run_retry_123")

        XCTAssertEqual(task.statusContextLine, "🔁 Replacement run: run_retry_123")
    }

    func testTaskStateStatusIndicatorMatchesExpectedTrafficLightStyle() {
        XCTAssertEqual(TaskState.running.statusIndicator, "🟢")
        XCTAssertEqual(TaskState.succeeded.statusIndicator, "✅")
        XCTAssertEqual(TaskState.failed.statusIndicator, "🔴")
    }

    func testStatusContextLineShowsObservationReconnectStateBeforeRecoveryChain() {
        let now = Date()
        var task = makeTask(id: "run-1", state: .running, updatedAt: now, retryChildTaskID: "run_retry_123")
        task.runState.observationState = .reconnecting
        task.runState.observationMessage = "Reconnecting to Hermes live updates (attempt 2 of 3)."

        XCTAssertEqual(task.statusContextLine, "🟠 Reconnecting to Hermes live updates (attempt 2 of 3).")
    }

    func testSortedForAttentionPrioritizesFailedApprovalAndReconnectAheadOfRunning() {
        let now = Date()
        var reconnecting = makeTask(id: "reconnecting", state: .running, updatedAt: now.addingTimeInterval(-30))
        reconnecting.runState.observationState = .disconnected
        reconnecting.runState.observationMessage = "Live feed disconnected"

        let tasks = [
            makeTask(id: "running", state: .running, updatedAt: now),
            reconnecting,
            makeTask(id: "approval", state: .waitingUser, updatedAt: now.addingTimeInterval(-10)),
            makeTask(id: "failed", state: .failed, updatedAt: now.addingTimeInterval(-20))
        ]

        XCTAssertEqual(tasks.sortedForAttention().map(\.taskID), ["failed", "approval", "reconnecting", "running"])
    }

    func testMenuBarInlineActionsExposeFailureRecoveryControls() {
        let now = Date()
        let task = Task(
            taskID: "failed-live",
            title: "failed-live",
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            availableActions: [.retry, .openTerminal, .openWorkspace, .copyResult],
            runState: RunState(
                state: .failed,
                phaseLabel: "failed",
                lastEventAt: now
            )
        )

        XCTAssertEqual(task.menuBarInlineActions, [.retry, .openTerminal, .openWorkspace])
    }

    func testPendingActionTimesOutAfterThreshold() {
        let now = Date()
        let task = makeTask(
            id: "timed-out",
            state: .waitingUser,
            updatedAt: now,
            pendingAction: .approveOnce,
            pendingActionStartedAt: now.addingTimeInterval(-31)
        )

        XCTAssertTrue(task.hasTimedOutPendingAction(asOf: now, timeout: 30))
        XCTAssertFalse(task.hasTimedOutPendingAction(asOf: now, timeout: 60))
    }

    func testLiveHermesTaskPreservesOriginalRequestText() {
        let task = Task.liveHermesTask(
            title: "Review auth flow",
            input: "Please review the auth flow and explain the failures.",
            runID: "run_123",
            sessionID: "session-1"
        )

        XCTAssertEqual(task.requestText, "Please review the auth flow and explain the failures.")
        XCTAssertEqual(task.currentSummary, "Please review the auth flow and explain the failures.")
    }

    func testLiveHermesTaskSeedsRootAndCurrentSessionBinding() {
        let task = Task.liveHermesTask(
            title: "Review auth flow",
            input: "Please review the auth flow and explain the failures.",
            runID: "run_123",
            sessionID: "session-1"
        )

        XCTAssertEqual(task.rootSessionID, "session-1")
        XCTAssertEqual(task.currentSessionID, "session-1")
        XCTAssertEqual(task.effectiveSessionID, "session-1")
        XCTAssertEqual(task.sessionBindingSummary, "Current: session-1")
        XCTAssertEqual(task.sessionLineage.map(\.sessionID), ["session-1"])
        XCTAssertEqual(task.sessionLineageSummary, "session-1")
    }

    func testEffectiveSessionPrefersCurrentOverLegacyAndRoot() {
        let now = Date()
        let task = Task(
            taskID: "binding",
            title: "binding",
            sessionID: "legacy-session",
            rootSessionID: "root-session",
            currentSessionID: "current-session",
            sessionLineage: [
                HermesSessionDescriptor(sessionID: "root-session"),
                HermesSessionDescriptor(sessionID: "current-session", parentSessionID: "root-session")
            ],
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            runState: RunState(
                state: .running,
                phaseLabel: "phase",
                lastEventAt: now
            )
        )

        XCTAssertEqual(task.effectiveSessionID, "current-session")
        XCTAssertEqual(task.sessionBindingSummary, "Current: current-session · Root: root-session")
        XCTAssertEqual(task.sessionLineageSummary, "root-session → current-session")
    }

    func testSummarizedWorkspaceTitleBuildsShortChineseTaskTitle() {
        let title = Task.summarizedWorkspaceTitle(
            from: "我希望在左侧任务列表栏，可以展示当前执行的任务介绍，有点像问 chatgpt 之后会自动总结标题一样"
        )

        XCTAssertEqual(title, "左侧任务列表栏展示当前执行的任务介绍")
    }

    func testGenericWorkspaceTitleDetectionRecognizesPresetFallbacks() {
        XCTAssertTrue(Task.isGenericWorkspaceTitle("Hermes task"))
        XCTAssertTrue(Task.isGenericWorkspaceTitle("Review with Hermes"))
        XCTAssertFalse(Task.isGenericWorkspaceTitle("Fix mac workspace streaming UI"))
    }

    func testRefreshedWorkspaceTitleUsesResultWhenCurrentTitleWasAutoGenerated() {
        let title = Task.refreshedWorkspaceTitle(
            currentTitle: "左侧任务列表栏展示当前执行的任务介绍",
            requestText: "我希望在左侧任务列表栏，可以展示当前执行的任务介绍，有点像问 chatgpt 之后会自动总结标题一样",
            resultText: "已完成左侧任务列表重构，并补上类似 ChatGPT 的标题自动总结"
        )

        XCTAssertEqual(title, "已完成左侧任务列表重构")
    }

    func testRefreshedWorkspaceTitleDoesNotOverrideManualTitle() {
        let title = Task.refreshedWorkspaceTitle(
            currentTitle: "SuZhou Factory AI Workspace",
            requestText: "帮我优化左侧任务列表",
            resultText: "已完成左侧任务列表重构，并补上类似 ChatGPT 的标题自动总结"
        )

        XCTAssertNil(title)
    }

    func testSessionStatusIsArchivedWhenRootSessionEnded() {
        let now = Date()
        let task = Task(
            taskID: "archived",
            title: "archived",
            sessionID: "session-1",
            rootSessionID: "session-1",
            currentSessionID: "session-1",
            sessionLineage: [
                HermesSessionDescriptor(sessionID: "session-1", endedAt: now)
            ],
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            runState: RunState(state: .succeeded, phaseLabel: "Archived", lastEventAt: now)
        )

        XCTAssertEqual(task.sessionStatus, .archived)
    }

    func testSessionStatusIsRunningWhenLiveRunIdentifierExists() {
        let now = Date()
        let task = Task(
            taskID: "running",
            title: "running",
            sessionID: "session-1",
            rootSessionID: "session-1",
            currentSessionID: "session-1",
            sessionLineage: [
                HermesSessionDescriptor(sessionID: "session-1")
            ],
            runID: "run_123",
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            runState: RunState(state: .running, phaseLabel: "Running", lastEventAt: now)
        )

        XCTAssertEqual(task.sessionStatus, .running)
    }

    func testSessionStatusFallsBackToOpenForConversationOnlyTasks() {
        let now = Date()
        let task = Task(
            taskID: "open",
            title: "open",
            sessionID: "session-1",
            rootSessionID: "session-1",
            currentSessionID: "session-1",
            sessionLineage: [
                HermesSessionDescriptor(sessionID: "session-1")
            ],
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            runState: RunState(state: .running, phaseLabel: "Conversation active", lastEventAt: now)
        )

        XCTAssertEqual(task.sessionStatus, .open)
    }

    func testWorkspaceConversationCanContinueForImportedSessionsWithSessionBinding() {
        let now = Date()
        let apiServerTask = Task(
            taskID: "api-server",
            title: "api-server",
            sessionID: "session-1",
            rootSessionID: "session-1",
            currentSessionID: "session-1",
            sessionSource: "api_server",
            sessionLineage: [HermesSessionDescriptor(sessionID: "session-1", source: "api_server")],
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            runState: RunState(state: .running, phaseLabel: "Conversation active", lastEventAt: now)
        )
        let feishuTask = Task(
            taskID: "feishu",
            title: "feishu",
            sessionID: "session-2",
            rootSessionID: "session-2",
            currentSessionID: "session-2",
            sessionSource: "feishu",
            sessionLineage: [HermesSessionDescriptor(sessionID: "session-2", source: "feishu")],
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            runState: RunState(state: .running, phaseLabel: "Conversation active", lastEventAt: now)
        )

        XCTAssertTrue(apiServerTask.canContinueInWorkspaceConversation)
        XCTAssertTrue(feishuTask.canContinueInWorkspaceConversation)
    }

    func testAPIServerAssistantMessagesStayVisibleInConversationEvenWhenClassifierFlagsProgress() {
        let now = Date()
        let task = Task(
            taskID: "api-server",
            title: "api-server",
            sessionID: "session-1",
            rootSessionID: "session-1",
            currentSessionID: "session-1",
            sessionSource: "api_server",
            sessionLineage: [HermesSessionDescriptor(sessionID: "session-1", source: "api_server")],
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            runState: RunState(state: .running, phaseLabel: "Conversation active", lastEventAt: now)
        )
        let message = HermesConversationMessage(
            id: 42,
            sessionID: "session-1",
            role: .assistant,
            content: """
            ## 当前状态
            status: reconnecting
            phase: checking output
            payload: {\"ok\":true}
            """,
            timestamp: now
        )

        XCTAssertEqual(message.workspaceClassification, .progress)
        XCTAssertFalse(message.shouldDisplayInWorkspaceConversation)
        XCTAssertTrue(task.shouldDisplayMessageInWorkspaceConversation(message))
    }

    func testNonAPIAssistantProgressMessagesRemainHiddenFromConversation() {
        let now = Date()
        let task = Task(
            taskID: "local",
            title: "local",
            sessionID: "session-1",
            rootSessionID: "session-1",
            currentSessionID: "session-1",
            sessionSource: "feishu",
            sessionLineage: [HermesSessionDescriptor(sessionID: "session-1", source: "feishu")],
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            currentSummary: "summary",
            runState: RunState(state: .running, phaseLabel: "Conversation active", lastEventAt: now)
        )
        let message = HermesConversationMessage(
            id: 43,
            sessionID: "session-1",
            role: .assistant,
            content: """
            ## 当前状态
            status: reconnecting
            phase: checking output
            payload: {\"ok\":true}
            """,
            timestamp: now
        )

        XCTAssertFalse(task.shouldDisplayMessageInWorkspaceConversation(message))
    }

    private func makeTask(
        id: String,
        state: TaskState,
        updatedAt: Date,
        isPreview: Bool = false,
        pendingAction: TaskAction? = nil,
        pendingActionStartedAt: Date? = nil,
        retryChildTaskID: String? = nil
    ) -> Task {
        Task(
            taskID: id,
            title: id,
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            requestText: "Original request for \(id)",
            currentSummary: "summary",
            runState: RunState(
                state: state,
                phaseLabel: "phase",
                lastEventAt: updatedAt
            ),
            pendingAction: pendingAction,
            pendingActionStartedAt: pendingActionStartedAt,
            retryChildTaskID: retryChildTaskID,
            isPreview: isPreview
        )
    }
}
