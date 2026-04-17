import Foundation
import XCTest
@testable import HermesDesk
import AppCore
import HermesKit

@MainActor
final class AppStateStoreTests: XCTestCase {
    func testTaskCacheStoreUsesEphemeralModeForXcodeHostedLaunches() {
        XCTAssertTrue(
            HermesDeskTaskCacheStore.shouldUseEphemeralStore(
                environment: ["XCTestSessionIdentifier": "session-1"],
                arguments: []
            )
        )
        XCTAssertTrue(
            HermesDeskTaskCacheStore.shouldUseEphemeralStore(
                environment: [:],
                arguments: ["-NSDocumentRevisionsDebugMode", "YES"]
            )
        )
        XCTAssertFalse(
            HermesDeskTaskCacheStore.shouldUseEphemeralStore(
                environment: [:],
                arguments: []
            )
        )
    }

    func testHoldingSelectionForNewTaskPreventsAutoSwitchToAnotherLiveTask() {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        store.tasks = [
            Task.liveHermesTask(
                taskID: "alpha01:existing-running",
                title: "Existing task",
                input: "old",
                runID: "run_existing",
                sessionID: "hermes-desk-alpha01-existing",
                agentID: "alpha01"
            )
        ]

        store.holdSelectionForNewTask()
        XCTAssertTrue(store.isHoldingNewTaskSelection)
        XCTAssertNil(store.selectedTask)

        var refreshedTasks = store.tasks
        refreshedTasks[0].updatedAt = Date().addingTimeInterval(5)
        refreshedTasks[0].currentSummary = "Streaming output from Hermes"
        store.tasks = refreshedTasks

        XCTAssertTrue(store.isHoldingNewTaskSelection)
        XCTAssertNil(store.selectedTask)
    }

    func testManagedAgentIDUsesSessionPrefixInsteadOfPromptText() {
        let agents = [
            HermesAgentDescriptor(
                agentID: "alpha01",
                displayName: "Alpha",
                roleSummary: nil,
                runtimeProfileID: "alpha01",
                runtimeProfile: HermesProfileDescriptor(
                    profileID: "alpha01",
                    displayName: "alpha01",
                    hermesHomePath: "/tmp/alpha01",
                    environmentFilePath: "/tmp/alpha01/.env",
                    environmentFileExists: false
                )
            ),
            HermesAgentDescriptor(
                agentID: "beta01",
                displayName: "Beta",
                roleSummary: nil,
                runtimeProfileID: "beta01",
                runtimeProfile: HermesProfileDescriptor(
                    profileID: "beta01",
                    displayName: "beta01",
                    hermesHomePath: "/tmp/beta01",
                    environmentFilePath: "/tmp/beta01/.env",
                    environmentFileExists: false
                )
            )
        ]

        XCTAssertEqual(AppStateStore.managedAgentID(fromRootSessionID: "hermes-desk-alpha01-task-a", agents: agents), "alpha01")
        XCTAssertEqual(AppStateStore.managedAgentID(fromRootSessionID: "hermes-desk-beta01-task-b", agents: agents), "beta01")
        XCTAssertEqual(AppStateStore.managedAgentID(fromRootSessionID: "agent-hub-alpha01-task-a", agents: agents), "alpha01")
        XCTAssertNil(AppStateStore.managedAgentID(fromRootSessionID: "20260413_224005_40517084", agents: agents))
    }

    func testManagedWorkspaceSessionRequiresHermesDeskPrefixAndAPIServerSource() {
        XCTAssertTrue(
            AppStateStore.isManagedWorkspaceSession(
                rootSessionID: "hermes-desk-alpha01-task-a",
                source: "api_server",
                agentID: "alpha01"
            )
        )
        XCTAssertTrue(
            AppStateStore.isManagedWorkspaceSession(
                rootSessionID: "agent-hub-alpha01-task-a",
                source: "api_server",
                agentID: "alpha01"
            )
        )
        XCTAssertFalse(
            AppStateStore.isManagedWorkspaceSession(
                rootSessionID: "20260414_114320_c236e0d1",
                source: "feishu",
                agentID: "taiyi"
            )
        )
        XCTAssertFalse(
            AppStateStore.isManagedWorkspaceSession(
                rootSessionID: "random-api-server-session",
                source: "api_server",
                agentID: "alpha01"
            )
        )
    }

    func testSelectingTaskAcrossAgentsDoesNotTriggerBackendHealthRefresh() async throws {
        let alphaBackend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/alpha",
                environmentFilePath: "/tmp/alpha/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let betaBackend = StubBackend(
            endpoint: HermesEndpoint(port: 9642),
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/beta",
                environmentFilePath: "/tmp/beta/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agents = [
            HermesAgentDescriptor(
                agentID: "alpha01",
                displayName: "Alpha",
                roleSummary: nil,
                runtimeProfileID: "alpha01",
                runtimeProfile: HermesProfileDescriptor(
                    profileID: "alpha01",
                    displayName: "alpha01",
                    hermesHomePath: "/tmp/alpha",
                    environmentFilePath: "/tmp/alpha/.env",
                    environmentFileExists: true
                )
            ),
            HermesAgentDescriptor(
                agentID: "beta01",
                displayName: "Beta",
                roleSummary: nil,
                runtimeProfileID: "beta01",
                runtimeProfile: HermesProfileDescriptor(
                    profileID: "beta01",
                    displayName: "beta01",
                    hermesHomePath: "/tmp/beta",
                    environmentFilePath: "/tmp/beta/.env",
                    environmentFileExists: true
                )
            )
        ]
        let store = AppStateStore(
            backend: alphaBackend,
            initialAgents: agents,
            initialBackendsByRuntimeProfileID: [
                "alpha01": alphaBackend,
                "beta01": betaBackend
            ]
        )
        let alphaTask = Task.liveHermesTask(
            taskID: "alpha01:session-1",
            title: "Alpha task",
            input: "alpha",
            runID: "run_alpha",
            sessionID: "hermes-desk-alpha01-session-1",
            agentID: "alpha01"
        )
        let betaTask = Task.liveHermesTask(
            taskID: "beta01:session-1",
            title: "Beta task",
            input: "beta",
            runID: "run_beta",
            sessionID: "hermes-desk-beta01-session-1",
            agentID: "beta01"
        )
        store.tasks = [alphaTask, betaTask]

        store.selectTask(betaTask)
        try await Swift.Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.selectedTaskID, betaTask.taskID)
        XCTAssertEqual(store.selectedAgentID, betaTask.agentID)
        XCTAssertEqual(alphaBackend.healthCallCount, 0)
        XCTAssertEqual(betaBackend.healthCallCount, 0)
    }

    func testLocalBenchmarkSwitchingAgentsWhileHiddenTaskStreams() async throws {
        let alphaBackend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/alpha",
                environmentFilePath: "/tmp/alpha/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let betaBackend = StubBackend(
            endpoint: HermesEndpoint(port: 9642),
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/beta",
                environmentFilePath: "/tmp/beta/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let gammaBackend = StubBackend(
            endpoint: HermesEndpoint(port: 10642),
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/gamma",
                environmentFilePath: "/tmp/gamma/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agents = [
            HermesAgentDescriptor(
                agentID: "alpha01",
                displayName: "Alpha",
                roleSummary: nil,
                runtimeProfileID: "alpha01",
                runtimeProfile: HermesProfileDescriptor(
                    profileID: "alpha01",
                    displayName: "alpha01",
                    hermesHomePath: "/tmp/alpha",
                    environmentFilePath: "/tmp/alpha/.env",
                    environmentFileExists: true
                )
            ),
            HermesAgentDescriptor(
                agentID: "beta01",
                displayName: "Beta",
                roleSummary: nil,
                runtimeProfileID: "beta01",
                runtimeProfile: HermesProfileDescriptor(
                    profileID: "beta01",
                    displayName: "beta01",
                    hermesHomePath: "/tmp/beta",
                    environmentFilePath: "/tmp/beta/.env",
                    environmentFileExists: true
                )
            ),
            HermesAgentDescriptor(
                agentID: "gamma01",
                displayName: "Gamma",
                roleSummary: nil,
                runtimeProfileID: "gamma01",
                runtimeProfile: HermesProfileDescriptor(
                    profileID: "gamma01",
                    displayName: "gamma01",
                    hermesHomePath: "/tmp/gamma",
                    environmentFilePath: "/tmp/gamma/.env",
                    environmentFileExists: true
                )
            )
        ]
        let store = AppStateStore(
            backend: alphaBackend,
            initialAgents: agents,
            initialBackendsByRuntimeProfileID: [
                "alpha01": alphaBackend,
                "beta01": betaBackend,
                "gamma01": gammaBackend
            ]
        )

        let now = Date()
        let alphaTask = Task.liveHermesTask(
            taskID: "alpha01:session-1",
            title: "Alpha task",
            input: "alpha",
            runID: "run_alpha",
            sessionID: "hermes-desk-alpha01-session-1",
            agentID: "alpha01"
        )
        let betaTask = Task.liveHermesTask(
            taskID: "beta01:session-1",
            title: "Beta task",
            input: "beta",
            runID: "run_beta",
            sessionID: "hermes-desk-beta01-session-1",
            agentID: "beta01"
        )
        let gammaTask = Task.liveHermesTask(
            taskID: "gamma01:session-1",
            title: "Gamma task",
            input: "gamma",
            runID: "run_gamma",
            sessionID: "hermes-desk-gamma01-session-1",
            agentID: "gamma01"
        )
        store.tasks = [alphaTask, betaTask, gammaTask]
        store.selectTask(betaTask)

        let start = DispatchTime.now().uptimeNanoseconds
        for index in 0..<200 {
            let selectedTask = index.isMultiple(of: 2) ? betaTask : gammaTask
            store.selectTask(selectedTask)
            store.applyRunEventForTesting(
                taskID: alphaTask.taskID,
                event: HermesRunEvent(
                    type: .messageDelta,
                    runID: "run_alpha",
                    timestamp: now.addingTimeInterval(Double(index) * 0.01),
                    delta: " chunk-\(index)"
                )
            )
        }
        store.flushBufferedStreamingDeltaForTesting(taskID: alphaTask.taskID)
        store.selectTask(alphaTask)
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        let hiddenTask = try XCTUnwrap(store.tasks.first(where: { $0.taskID == alphaTask.taskID }))
        XCTAssertTrue(hiddenTask.output.contains("chunk-199"))
        XCTAssertFalse(store.transcriptMessages(for: hiddenTask).isEmpty)
        XCTAssertLessThan(elapsedMS, 2_000)
        print("LOCAL_BENCH hidden-stream-switch elapsed_ms=\(String(format: "%.2f", elapsedMS))")
    }

    func testStartHermesTaskContinuesExistingTaskUsingItsSessionID() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        let existingTask = Task(
            taskID: "alpha01:hermes-desk-alpha01-existing-session",
            title: "Existing",
            agentID: "alpha01",
            sessionID: "hermes-desk-alpha01-existing-session",
            rootSessionID: "hermes-desk-alpha01-existing-session",
            currentSessionID: "hermes-desk-alpha01-existing-session",
            sessionSource: "api_server",
            sessionLineage: [HermesSessionDescriptor(sessionID: "hermes-desk-alpha01-existing-session", source: "api_server")],
            createdAt: .now,
            updatedAt: .now,
            requestText: "hello",
            currentSummary: "hello",
            runState: RunState(state: .running, phaseLabel: "Conversation active", lastEventAt: .now)
        )
        store.tasks = [existingTask]

        try await store.startHermesTask(title: nil, prompt: "继续", continuingTaskID: existingTask.taskID)

        XCTAssertEqual(backend.startedRunRequests.last?.sessionID, "hermes-desk-alpha01-existing-session")
    }

    func testStartHermesTaskIncludesWorkspaceConversationHistoryWhenContinuingTask() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        let sessionID = "hermes-desk-alpha01-existing-session"
        let existingTask = Task(
            taskID: "alpha01:\(sessionID)",
            title: "Existing",
            agentID: "alpha01",
            sessionID: sessionID,
            rootSessionID: sessionID,
            currentSessionID: sessionID,
            sessionSource: "api_server",
            sessionLineage: [HermesSessionDescriptor(sessionID: sessionID, source: "api_server")],
            createdAt: .now,
            updatedAt: .now,
            requestText: "关于我你了解多少",
            currentSummary: "关于我你了解多少",
            runState: RunState(state: .running, phaseLabel: "Conversation active", lastEventAt: .now)
        )
        store.tasks = [existingTask]
        store.materializeAssistantReplyForTesting(taskID: existingTask.taskID, content: "我目前只知道你在这个工作区里发给我的消息。")

        try await store.startHermesTask(title: nil, prompt: "我问你的第一句话是什么", continuingTaskID: existingTask.taskID)

        XCTAssertEqual(
            backend.startedRunRequests.last?.conversationHistory,
            [
                HermesConversationHistoryMessage(role: "user", content: "关于我你了解多少"),
                HermesConversationHistoryMessage(role: "assistant", content: "我目前只知道你在这个工作区里发给我的消息。")
            ]
        )
    }

    func testStartHermesTaskRejectsContinuingExternalConversation() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "taiyi",
            displayName: "太一",
            roleSummary: nil,
            runtimeProfileID: "taiyi",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "taiyi",
                displayName: "taiyi",
                hermesHomePath: "/tmp/taiyi",
                environmentFilePath: "/tmp/taiyi/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        let existingTask = Task(
            taskID: "taiyi:feishu-session",
            title: "External",
            agentID: "taiyi",
            sessionID: "feishu-session",
            rootSessionID: "feishu-session",
            currentSessionID: "feishu-session",
            sessionSource: "feishu",
            sessionLineage: [HermesSessionDescriptor(sessionID: "feishu-session", source: "feishu")],
            createdAt: .now,
            updatedAt: .now,
            requestText: "hello",
            currentSummary: "hello",
            runState: RunState(state: .running, phaseLabel: "Conversation active", lastEventAt: .now)
        )
        store.tasks = [existingTask]

        do {
            try await store.startHermesTask(title: nil, prompt: "我发的第一句话是什么", continuingTaskID: existingTask.taskID)
            XCTFail("Expected continuing an external conversation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Only conversations created by Hermes Desk can continue inside this app."
            )
        }
        XCTAssertTrue(backend.startedRunRequests.isEmpty)
    }

    func testStartHermesTaskCreatesDistinctSessionsForNewTasks() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])

        try await store.startHermesTask(title: nil, prompt: "first", continuingTaskID: nil)
        try await store.startHermesTask(title: nil, prompt: "second", continuingTaskID: nil)

        let sessionIDs = backend.startedRunRequests.compactMap(\.sessionID)
        XCTAssertEqual(sessionIDs.count, 2)
        XCTAssertNotEqual(sessionIDs[0], sessionIDs[1])
        XCTAssertTrue(sessionIDs.allSatisfy { $0.hasPrefix("hermes-desk-alpha01-") })
    }

    func testStartHermesTaskKeepsPendingMessageWithoutTranscriptQueries() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])

        try await store.startHermesTask(title: nil, prompt: "整体检查下这个项目目前的进展", continuingTaskID: nil)

        let task = try XCTUnwrap(store.tasks.first)
        XCTAssertFalse(store.isTranscriptLoading(for: task))
        XCTAssertEqual(store.pendingOutgoingMessages(for: task).map(\.content), ["整体检查下这个项目目前的进展"])
        XCTAssertEqual(store.transcriptMessages(for: task).map(\.displayText), ["整体检查下这个项目目前的进展"])
    }

    func testStartHermesTaskSecondSendUsesSameSessionForSameTask() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])

        try await store.startHermesTask(title: nil, prompt: "你好", continuingTaskID: nil)
        let createdTaskID = store.tasks.first?.taskID
        try await store.startHermesTask(title: nil, prompt: "苏州天气", continuingTaskID: createdTaskID)

        let sessionIDs = backend.startedRunRequests.compactMap(\.sessionID)
        XCTAssertEqual(sessionIDs.count, 2)
        XCTAssertEqual(sessionIDs[0], sessionIDs[1])
    }

    func testConversationTaskKeepsStableTitleAndNoArtifactAfterReplies() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        try await store.startHermesTask(title: nil, prompt: "周杰伦今年多大", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        store.materializeAssistantReplyForTesting(
            taskID: taskID,
            content: "周杰伦出生于 1979 年 1 月 18 日，按今年 2026 年算，47 岁。",
            timestamp: Date(timeIntervalSince1970: 1_776_097_850)
        )

        let task = try XCTUnwrap(store.tasks.first)
        XCTAssertEqual(store.transcriptMessages(for: task).count, 2)
        XCTAssertEqual(task.title, Task.summarizedWorkspaceTitle(from: "周杰伦今年多大"))
        XCTAssertNil(task.artifact)
        XCTAssertEqual(task.requestText, "周杰伦今年多大")
    }

    func testRefreshWorkspaceKeepsTaskFromClientCache() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let cacheStore = HermesDeskTaskCacheStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        let store = AppStateStore(
            backend: backend,
            initialAgents: [agent],
            initialBackendsByRuntimeProfileID: [:],
            taskCacheStore: cacheStore
        )
        backend.runEventsByRunID["run_1"] = [
            HermesRunEvent(type: .runCompleted, runID: "run_1", timestamp: .now, output: "hi")
        ]

        try await store.startHermesTask(title: nil, prompt: "hello", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        try await Swift.Task.sleep(nanoseconds: 50_000_000)
        await store.refreshWorkspace()

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.taskID, taskID)
        XCTAssertEqual(store.selectedTaskID, taskID)
    }

    func testRunCompletedEventMaterializesFinalReplyWithoutTranscriptHydration() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        backend.runEventsByRunID["run_1"] = [
            HermesRunEvent(type: .runCompleted, runID: "run_1", timestamp: .now, output: "苏州今天多云，26°C。")
        ]

        try await store.startHermesTask(title: nil, prompt: "苏州今天的问题", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        try await Swift.Task.sleep(nanoseconds: 50_000_000)

        let task = try XCTUnwrap(store.tasks.first(where: { $0.taskID == taskID }))
        XCTAssertNil(task.runID)
        XCTAssertEqual(task.output, "苏州今天多云，26°C。")
        XCTAssertEqual(task.currentSummary, "苏州今天多云，26°C。")
        XCTAssertEqual(task.runState.phaseLabel, "Conversation updated")
        XCTAssertNil(task.artifact)
        XCTAssertEqual(store.transcriptMessages(for: task).map(\.displayText), ["苏州今天的问题", "苏州今天多云，26°C。"])
    }

    func testRunClosureWithoutVisibleReplyDoesNotEnterTranscriptSyncState() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        backend.runEventsByRunID["run_1"] = []
        backend.keepsUnconfiguredRunStreamsOpen = false

        try await store.startHermesTask(title: nil, prompt: "给我一个状态", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        try await Swift.Task.sleep(nanoseconds: 50_000_000)

        let task = try XCTUnwrap(store.tasks.first(where: { $0.taskID == taskID }))
        XCTAssertNil(task.runID)
        XCTAssertEqual(task.runState.phaseLabel, "Run finished")
        XCTAssertNil(task.runState.progressHint)
        XCTAssertTrue(store.transcriptMessages(for: task).map(\.displayText).contains("给我一个状态"))
    }

    func testPendingOutgoingClearsAfterPersistedUserMessage() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        backend.runEventsByRunID["run_1"] = [
            HermesRunEvent(type: .runCompleted, runID: "run_1", timestamp: .now, output: "hi")
        ]

        try await store.startHermesTask(title: nil, prompt: "hello", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        let taskBeforePersist = try XCTUnwrap(store.tasks.first(where: { $0.taskID == taskID }))
        XCTAssertEqual(store.pendingOutgoingMessages(for: taskBeforePersist).map(\.content), ["hello"])
        let pendingMessage = try XCTUnwrap(store.pendingOutgoingMessages(for: taskBeforePersist).first)
        let optimisticEntryID = store.stableWorkspaceEntryID(for: pendingMessage, taskID: taskID)
        try await Swift.Task.sleep(nanoseconds: 50_000_000)
        await store.refreshWorkspaceStateForTesting(taskID: taskID)

        let taskAfterPersist = try XCTUnwrap(store.tasks.first(where: { $0.taskID == taskID }))
        XCTAssertTrue(store.pendingOutgoingMessages(for: taskAfterPersist).isEmpty)
        XCTAssertEqual(store.transcriptMessages(for: taskAfterPersist).count, 2)
        let persistedUserMessage = try XCTUnwrap(store.transcriptMessages(for: taskAfterPersist).first(where: { $0.role == .user }))
        XCTAssertEqual(store.stableWorkspaceEntryID(for: persistedUserMessage, taskID: taskID), optimisticEntryID)
    }

    func testFollowUpTranscriptRemovesOptimisticDuplicateAndKeepsSameSession() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let store = AppStateStore(backend: backend, initialAgents: [agent], initialBackendsByRuntimeProfileID: [:])
        try await store.startHermesTask(title: nil, prompt: "你好", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        store.materializeAssistantReplyForTesting(taskID: taskID, content: "你好！我在。")
        try await store.startHermesTask(title: nil, prompt: "苏州天气", continuingTaskID: taskID)
        store.materializeAssistantReplyForTesting(taskID: taskID, content: "苏州当前天气：晴。")

        let task = try XCTUnwrap(store.tasks.first(where: { $0.taskID == taskID }))
        let transcript = store.transcriptMessages(for: task)
        XCTAssertNil(task.runID)
        XCTAssertEqual(transcript.filter { $0.role == .user && $0.displayText == "苏州天气" }.count, 1)
        XCTAssertTrue(store.pendingOutgoingMessages(for: task).isEmpty)
        XCTAssertEqual(transcript.map(\.displayText), ["你好", "你好！我在。", "苏州天气", "苏州当前天气：晴。"])
        XCTAssertEqual(Set(backend.startedRunRequests.compactMap(\.sessionID)).count, 1)
    }

    func testRefreshWorkspaceStateReconcilesAPIServerAssistantReplyEvenWhenItLooksLikeProgress() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let cacheStore = HermesDeskTaskCacheStore(fileURL: cacheURL)
        let sessionID = "hermes-desk-alpha01-session-1"
        let now = Date(timeIntervalSince1970: 1_776_000_000)
        let assistantReply = """
        ## 当前状态
        status: connected
        phase: preparing answer
        payload: 已收到你的消息，正在继续排查并汇总结果。
        """
        let task = Task(
            taskID: "alpha01:\(sessionID)",
            title: "排查流式显示",
            agentID: "alpha01",
            sessionID: sessionID,
            rootSessionID: sessionID,
            currentSessionID: sessionID,
            sessionSource: "api_server",
            sessionLineage: [HermesSessionDescriptor(sessionID: sessionID, source: "api_server")],
            runID: "run_1",
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            requestText: "帮我看看为什么消息没展示",
            currentSummary: "Sent a follow-up to Hermes. Waiting for the next run to respond.",
            runState: RunState(state: .running, phaseLabel: "Follow-up queued", lastEventAt: now)
        )
        cacheStore.save(
            .init(
                tasks: [task],
                taskRuntimeProfileIDs: [task.taskID: "alpha01"],
                workspaceEntries: [
                    .init(
                        taskID: task.taskID,
                        messages: [
                            HermesConversationMessage(
                                id: 1,
                                sessionID: sessionID,
                                role: .user,
                                content: "帮我看看为什么消息没展示",
                                timestamp: now
                            ),
                            HermesConversationMessage(
                                id: 2,
                                sessionID: sessionID,
                                role: .assistant,
                                content: assistantReply,
                                timestamp: now.addingTimeInterval(1)
                            )
                        ]
                    )
                ],
                pendingEntries: []
            )
        )

        let store = AppStateStore(
            backend: backend,
            initialAgents: [agent],
            initialBackendsByRuntimeProfileID: [:],
            taskCacheStore: cacheStore
        )
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)

        await store.refreshWorkspaceStateForTesting(taskID: taskID)

        let updatedTask = try XCTUnwrap(store.tasks.first(where: { $0.taskID == taskID }))
        XCTAssertNil(updatedTask.runID)
        XCTAssertEqual(updatedTask.output, assistantReply)
        XCTAssertEqual(updatedTask.currentSummary, assistantReply)
        XCTAssertEqual(updatedTask.runState.phaseLabel, "Conversation updated")
    }

    func testRestoresTasksAndTranscriptFromClientOwnedCache() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let cacheStore = HermesDeskTaskCacheStore(fileURL: cacheURL)
        let firstStore = AppStateStore(
            backend: backend,
            initialAgents: [agent],
            initialBackendsByRuntimeProfileID: [:],
            taskCacheStore: cacheStore
        )
        try await firstStore.startHermesTask(title: nil, prompt: "restore me", continuingTaskID: nil)
        let firstTaskID = try XCTUnwrap(firstStore.tasks.first?.taskID)
        firstStore.materializeAssistantReplyForTesting(taskID: firstTaskID, content: "restored reply")

        let restoredStore = AppStateStore(
            backend: backend,
            initialAgents: [agent],
            initialBackendsByRuntimeProfileID: [:],
            taskCacheStore: cacheStore
        )

        let restoredTask = try XCTUnwrap(restoredStore.tasks.first)
        XCTAssertEqual(restoredTask.requestText, "restore me")
        XCTAssertEqual(restoredStore.transcriptMessages(for: restoredTask).map(\.displayText), ["restore me", "restored reply"])
    }

    func testRestoresRunningTaskFromLightweightClientOwnedState() async throws {
        let backend = StubBackend(
            diagnostics: AgentBackendDiagnostics(
                adapterName: "Hermes",
                hermesHomePath: "/tmp/default",
                environmentFilePath: "/tmp/default/.env",
                environmentFileExists: true,
                apiKeyConfigured: true
            )
        )
        let agent = HermesAgentDescriptor(
            agentID: "alpha01",
            displayName: "Alpha",
            roleSummary: nil,
            runtimeProfileID: "alpha01",
            runtimeProfile: HermesProfileDescriptor(
                profileID: "alpha01",
                displayName: "alpha01",
                hermesHomePath: "/tmp/profile",
                environmentFilePath: "/tmp/profile/.env",
                environmentFileExists: false
            )
        )
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let cacheStore = HermesDeskTaskCacheStore(fileURL: cacheURL)
        let firstStore = AppStateStore(
            backend: backend,
            initialAgents: [agent],
            initialBackendsByRuntimeProfileID: [:],
            taskCacheStore: cacheStore
        )
        try await firstStore.startHermesTask(title: nil, prompt: "苏州今天的问题", continuingTaskID: nil)
        let taskID = try XCTUnwrap(firstStore.tasks.first?.taskID)

        let restoredStore = AppStateStore(
            backend: backend,
            initialAgents: [agent],
            initialBackendsByRuntimeProfileID: [:],
            taskCacheStore: cacheStore
        )

        let restoredTask = try XCTUnwrap(restoredStore.tasks.first(where: { $0.taskID == taskID }))
        XCTAssertEqual(restoredTask.runID, "run_1")
        XCTAssertEqual(restoredStore.pendingOutgoingMessages(for: restoredTask).map(\.content), ["苏州今天的问题"])
        XCTAssertEqual(restoredStore.transcriptMessages(for: restoredTask).map(\.displayText), ["苏州今天的问题"])
        XCTAssertEqual(restoredStore.selectedTaskID, taskID)
    }

    func testLegacyCacheSchemaIsDeletedInsteadOfRestored() throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let legacyPayload = """
        {
          "tasks": [],
          "taskRuntimeProfileIDs": {},
          "transcriptEntries": [],
          "pendingEntries": []
        }
        """
        try legacyPayload.data(using: .utf8)?.write(to: cacheURL)

        let cacheStore = HermesDeskTaskCacheStore(fileURL: cacheURL)
        XCTAssertNil(cacheStore.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

}

private final class StubBackend: AgentBackend, @unchecked Sendable {
    let endpoint: HermesEndpoint
    let diagnostics: AgentBackendDiagnostics
    private(set) var startedRunRequests: [HermesRunRequest] = []
    private(set) var healthCallCount = 0
    var runEventsByRunID: [String: [HermesRunEvent]] = [:]
    var keepsUnconfiguredRunStreamsOpen = true

    init(
        endpoint: HermesEndpoint = .defaultLocal,
        diagnostics: AgentBackendDiagnostics
    ) {
        self.endpoint = endpoint
        self.diagnostics = diagnostics
    }

    func health() async -> HermesConnectionState {
        healthCallCount += 1
        return .online(HermesHealth(statusSummary: "ok"))
    }

    func startRun(
        input: String,
        sessionID: String?,
        instructions: String?,
        conversationHistory: [HermesConversationHistoryMessage]?
    ) async throws -> HermesRunStartResponse {
        startedRunRequests.append(
            HermesRunRequest(
                input: input,
                sessionID: sessionID,
                instructions: instructions,
                conversationHistory: conversationHistory
            )
        )
        return HermesRunStartResponse(runID: "run_\(startedRunRequests.count)", status: "started")
    }

    func performRunAction(
        runID: String,
        request: HermesRunActionRequest
    ) async throws -> HermesRunActionResponse {
        HermesRunActionResponse(runID: runID, status: request.action.rawValue)
    }

    func runEvents(for runID: String) -> AsyncThrowingStream<HermesRunEvent, Error> {
        AsyncThrowingStream { continuation in
            if let events = runEventsByRunID[runID] {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
                return
            }
            if keepsUnconfiguredRunStreamsOpen == false {
                continuation.finish()
            }
        }
    }
}
