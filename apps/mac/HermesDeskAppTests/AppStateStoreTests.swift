import Foundation
import XCTest
@testable import HermesDesk
import AppCore
import HermesKit

@MainActor
final class AppStateStoreTests: XCTestCase {
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

    func testStartHermesTaskImmediatelyMarksTranscriptLoadingAndKeepsPendingMessage() async throws {
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
        backend.fetchSessionMessagesPageHandler = { _, _, _ in
            HermesConversationPage(messages: [], hasMoreBefore: false)
        }

        try await store.startHermesTask(title: nil, prompt: "整体检查下这个项目目前的进展", continuingTaskID: nil)

        let task = try XCTUnwrap(store.tasks.first)
        XCTAssertTrue(store.isTranscriptLoading(for: task))
        XCTAssertEqual(store.pendingOutgoingMessages(for: task).map(\.content), ["整体检查下这个项目目前的进展"])
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

        backend.fetchSessionMessagesPageHandler = { sessionID, _, _ in
            let timestamp = Date(timeIntervalSince1970: 1_776_097_850)
            return HermesConversationPage(
                messages: [
                    HermesConversationMessage(id: 1, sessionID: sessionID, role: .user, content: "周杰伦今年多大", timestamp: timestamp),
                    HermesConversationMessage(id: 2, sessionID: sessionID, role: .assistant, content: "周杰伦出生于 1979 年 1 月 18 日，按今年 2026 年算，47 岁。", timestamp: timestamp)
                ],
                hasMoreBefore: false
            )
        }

        try await store.startHermesTask(title: nil, prompt: "周杰伦今年多大", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        await store.refreshTranscriptsForTesting(taskID: taskID)

        let task = try XCTUnwrap(store.tasks.first)
        XCTAssertEqual(store.transcriptMessages(for: task).count, 2)
        XCTAssertEqual(task.title, Task.summarizedWorkspaceTitle(from: "周杰伦今年多大"))
        XCTAssertNil(task.artifact)
        XCTAssertEqual(task.requestText, "周杰伦今年多大")
    }

    func testInjectedAgentStoreRefreshKeepsTask() async throws {
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

        backend.fetchSessionMessagesPageHandler = { sessionID, _, _ in
            HermesConversationPage(
                messages: [
                    HermesConversationMessage(id: 1, sessionID: sessionID, role: .user, content: "hello", timestamp: .now),
                    HermesConversationMessage(id: 2, sessionID: sessionID, role: .assistant, content: "hi", timestamp: .now)
                ],
                hasMoreBefore: false
            )
        }

        try await store.startHermesTask(title: nil, prompt: "hello", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        await store.refreshTranscriptsForTesting(taskID: taskID)

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.taskID, taskID)
        XCTAssertEqual(store.selectedTaskID, taskID)
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

        backend.fetchSessionMessagesPageHandler = { _, _, _ in
            HermesConversationPage(messages: [], hasMoreBefore: false)
        }

        try await store.startHermesTask(title: nil, prompt: "hello", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        let taskBeforePersist = try XCTUnwrap(store.tasks.first(where: { $0.taskID == taskID }))
        XCTAssertEqual(store.pendingOutgoingMessages(for: taskBeforePersist).map(\.content), ["hello"])
        let pendingMessage = try XCTUnwrap(store.pendingOutgoingMessages(for: taskBeforePersist).first)
        let optimisticEntryID = store.stableWorkspaceEntryID(for: pendingMessage, taskID: taskID)

        let sessionID = try XCTUnwrap(taskBeforePersist.effectiveSessionID)
        backend.fetchSessionMessagesPageHandler = { returnedSessionID, _, _ in
            XCTAssertEqual(returnedSessionID, sessionID)
            return HermesConversationPage(
                messages: [
                    HermesConversationMessage(id: 1, sessionID: returnedSessionID, role: .user, content: "hello", timestamp: .now),
                    HermesConversationMessage(id: 2, sessionID: returnedSessionID, role: .assistant, content: "hi", timestamp: .now)
                ],
                hasMoreBefore: false
            )
        }

        await store.refreshTranscriptsForTesting(taskID: taskID)

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

        backend.fetchSessionMessagesPageHandler = { sessionID, _, _ in
            let baseTimestamp = Date(timeIntervalSince1970: 1_776_092_448)
            if backend.startedRunRequests.count <= 1 {
                return HermesConversationPage(
                    messages: [
                        HermesConversationMessage(id: 1, sessionID: sessionID, role: .user, content: "你好", timestamp: baseTimestamp),
                        HermesConversationMessage(id: 2, sessionID: sessionID, role: .assistant, content: "你好！我在。", timestamp: baseTimestamp)
                    ],
                    hasMoreBefore: false
                )
            }

            let followUpTimestamp = baseTimestamp.addingTimeInterval(10)
            return HermesConversationPage(
                messages: [
                    HermesConversationMessage(id: 1, sessionID: sessionID, role: .user, content: "你好", timestamp: baseTimestamp),
                    HermesConversationMessage(id: 2, sessionID: sessionID, role: .assistant, content: "你好！我在。", timestamp: baseTimestamp),
                    HermesConversationMessage(id: 3, sessionID: sessionID, role: .user, content: "苏州天气", timestamp: followUpTimestamp),
                    HermesConversationMessage(id: 4, sessionID: sessionID, role: .assistant, content: "苏州当前天气：晴。", timestamp: followUpTimestamp)
                ],
                hasMoreBefore: false
            )
        }

        try await store.startHermesTask(title: nil, prompt: "你好", continuingTaskID: nil)
        let taskID = try XCTUnwrap(store.tasks.first?.taskID)
        await store.refreshTranscriptsForTesting(taskID: taskID)
        try await store.startHermesTask(title: nil, prompt: "苏州天气", continuingTaskID: taskID)
        await store.refreshTranscriptsForTesting(taskID: taskID)

        let task = try XCTUnwrap(store.tasks.first(where: { $0.taskID == taskID }))
        let transcript = store.transcriptMessages(for: task)
        XCTAssertNil(task.runID)
        XCTAssertEqual(transcript.filter { $0.role == .user && $0.displayText == "苏州天气" }.count, 1)
        XCTAssertTrue(store.pendingOutgoingMessages(for: task).isEmpty)
        XCTAssertEqual(transcript.map(\.displayText), ["你好", "你好！我在。", "苏州天气", "苏州当前天气：晴。"])
        XCTAssertEqual(Set(backend.startedRunRequests.compactMap(\.sessionID)).count, 1)
    }

}

private final class StubBackend: AgentBackend, @unchecked Sendable {
    let endpoint: HermesEndpoint
    let diagnostics: AgentBackendDiagnostics
    private(set) var startedRunRequests: [HermesRunRequest] = []
    var fetchSessionMessagesHandler: (@Sendable (String) async throws -> [HermesConversationMessage])?
    var fetchSessionMessagesPageHandler: (@Sendable (String, Int, HermesConversationPageCursor?) async throws -> HermesConversationPage)?
    var fetchSessionBindingHandler: (@Sendable (String, String?) async throws -> HermesSessionBinding?)?
    var runEventsByRunID: [String: [HermesRunEvent]] = [:]

    init(
        endpoint: HermesEndpoint = .defaultLocal,
        diagnostics: AgentBackendDiagnostics
    ) {
        self.endpoint = endpoint
        self.diagnostics = diagnostics
    }

    func health() async -> HermesConnectionState {
        .online(HermesHealth(statusSummary: "ok"))
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
            for event in runEventsByRunID[runID] ?? [] {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func fetchSessionMessages(sessionID: String) async throws -> [HermesConversationMessage] {
        if let fetchSessionMessagesHandler {
            return try await fetchSessionMessagesHandler(sessionID)
        }
        return []
    }

    func fetchSessionMessagesPage(
        sessionID: String,
        limit: Int,
        before: HermesConversationPageCursor?
    ) async throws -> HermesConversationPage {
        if let fetchSessionMessagesPageHandler {
            return try await fetchSessionMessagesPageHandler(sessionID, limit, before)
        }
        return HermesConversationPage(messages: [], hasMoreBefore: false)
    }

    func fetchSessionBinding(preferredSessionID: String, rootSessionID: String?) async throws -> HermesSessionBinding? {
        if let fetchSessionBindingHandler {
            return try await fetchSessionBindingHandler(preferredSessionID, rootSessionID)
        }
        return nil
    }
}
