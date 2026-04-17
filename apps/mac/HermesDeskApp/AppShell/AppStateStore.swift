import AppCore
import AppKit
import HermesKit
import SwiftUI

struct HermesDeskTaskCacheStore {
    struct State: Codable, Equatable {
        struct TranscriptEntry: Codable, Equatable {
            let runtimeProfileID: String
            let sessionID: String
            let messages: [HermesConversationMessage]
            let hasMoreBefore: Bool
        }

        struct PendingEntry: Codable, Equatable {
            struct Message: Codable, Equatable {
                let id: UUID
                let sessionID: String
                let content: String
                let timestamp: Date
            }

            let taskID: String
            let messages: [Message]
        }

        let tasks: [Task]
        let taskRuntimeProfileIDs: [String: String]
        let transcriptEntries: [TranscriptEntry]
        let pendingEntries: [PendingEntry]
    }

    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    static func defaultForEnvironment(
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> HermesDeskTaskCacheStore {
        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return HermesDeskTaskCacheStore(fileURL: nil)
        }

        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let fileURL = supportURL
            .appending(path: "HermesDesk", directoryHint: .isDirectory)
            .appending(path: "task-cache.json")
        return HermesDeskTaskCacheStore(fileURL: fileURL)
    }

    func load() -> State? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        do {
            return try JSONDecoder.hermesDeskCacheDecoder.decode(State.self, from: data)
        } catch {
            return nil
        }
    }

    func save(_ state: State) {
        guard let fileURL else {
            return
        }

        do {
            let data = try JSONEncoder.hermesDeskCacheEncoder.encode(state)
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

extension JSONEncoder {
    static var hermesDeskCacheEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.hermesDeskFractionalISO8601.string(from: date))
        }
        return encoder
    }

    static var hermesDeskFractionalISO8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

extension JSONDecoder {
    static var hermesDeskCacheDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = JSONEncoder.hermesDeskFractionalISO8601.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date string: \(value)")
        }
        return decoder
    }
}

@MainActor
final class AppStateStore: ObservableObject {
    private struct TranscriptCacheKey: Hashable {
        var runtimeProfileID: String
        var sessionID: String
    }

    struct PendingOutgoingMessage: Equatable, Sendable, Identifiable {
        let id: UUID
        let sessionID: String
        let content: String
        let timestamp: Date
    }

    private struct PendingOutgoingFingerprint: Hashable {
        let sessionID: String
        let normalizedContent: String
    }

    private struct WorkspaceMessageFingerprint: Hashable {
        let sessionID: String
        let role: HermesConversationRole
        let normalizedContent: String
        let second: Int
    }

    @Published var languagePreference: HermesDeskLanguagePreference {
        didSet {
            UserDefaults.standard.set(languagePreference.rawValue, forKey: HermesDeskL10n.defaultsKey)
        }
    }
    @Published private(set) var connectionState: HermesConnectionState
    @Published private(set) var isRefreshing = false
    @Published private(set) var isStartingRun = false
    @Published private(set) var agents: [HermesAgentDescriptor] = []
    @Published var selectedAgentID: String? {
        didSet {
            guard oldValue != selectedAgentID else { return }
            if let selectedTask, selectedTask.agentID != selectedAgentID {
                selectedTaskID = nil
            }
            selectDefaultTaskIfNeeded()
            scheduleAgentReload(reason: .healthRefresh)
        }
    }
    @Published var tasks: [Task] = [] {
        didSet {
            if let selectedTaskID, tasks.contains(where: { $0.taskID == selectedTaskID }) == false {
                self.selectedTaskID = nil
            }
            pendingOutgoingMessagesByTaskID = pendingOutgoingMessagesByTaskID.filter { taskID, _ in
                tasks.contains(where: { $0.taskID == taskID })
            }
            stableWorkspaceEntryIDsByTaskID = stableWorkspaceEntryIDsByTaskID.filter { taskID, _ in
                tasks.contains(where: { $0.taskID == taskID })
            }
            selectDefaultTaskIfNeeded()
        }
    }
    @Published private(set) var selectedTaskID: Task.ID?
    @Published var runLaunchError: String?
    @Published var taskActionFeedback: String?
    @Published private(set) var workspaceMessagesByTaskID: [Task.ID: [HermesConversationMessage]] = [:]
    @Published private(set) var pendingOutgoingMessagesByTaskID: [Task.ID: [PendingOutgoingMessage]] = [:]
    private var transcriptMessagesByCacheKey: [TranscriptCacheKey: [HermesConversationMessage]] = [:]
    private var transcriptHasOlderByCacheKey: [TranscriptCacheKey: Bool] = [:]
    private var stableWorkspaceEntryIDsByTaskID: [Task.ID: [WorkspaceMessageFingerprint: String]] = [:]
    private var transcriptLoadingTaskIDs: Set<Task.ID> = []
    private var transcriptLoadingOlderTaskIDs: Set<Task.ID> = []

    private static let pendingActionTimeout: TimeInterval = 20
    private static let pendingActionReconcileInterval: Duration = .seconds(5)
    private static let defaultRuntimeProfileID = "__default_runtime__"

    private let taskCacheStore: HermesDeskTaskCacheStore
    private let defaultBackend: any AgentBackend
    private var localBackendsByRuntimeProfileID: [String: any AgentBackend] = [:]
    private var taskRuntimeProfileIDs: [Task.ID: String] = [:]
    private var runEventTasks: [String: Swift.Task<Void, Never>] = [:]
    private var runEventSessionTokens: [String: UUID] = [:]
    private var liveActionRequestTokens: [Task.ID: UUID] = [:]
    private var pendingActionMonitorTask: Swift.Task<Void, Never>?
    private var transcriptReconcileMonitorTask: Swift.Task<Void, Never>?
    private var agentReloadTask: Swift.Task<Void, Never>?
    private var transcriptRefreshTask: Swift.Task<Void, Never>?
    private var nextLocalTranscriptMessageID: Int64 = -1

    init(
        backend: any AgentBackend = HermesLocalAdapter(),
        initialAgents: [HermesAgentDescriptor]? = nil,
        initialBackendsByRuntimeProfileID: [String: any AgentBackend]? = nil,
        taskCacheStore: HermesDeskTaskCacheStore = .defaultForEnvironment()
    ) {
        self.taskCacheStore = taskCacheStore
        self.defaultBackend = backend
        self.languagePreference = HermesDeskL10n.currentPreference
        self.connectionState = .starting(message: HermesDeskL10n.text(preference: HermesDeskL10n.currentPreference, zh: "等待首次探测 Hermes…", en: "Waiting for first Hermes probe…"))

        if let initialAgents {
            self.agents = initialAgents
            self.localBackendsByRuntimeProfileID = initialBackendsByRuntimeProfileID ?? [:]
            self.localBackendsByRuntimeProfileID[Self.defaultRuntimeProfileID] = backend
            self._selectedAgentID = Published(initialValue: initialAgents.first?.agentID)
        } else {
            configureAgents()
        }
        restorePersistedClientState()
        startPendingActionMonitor()
        startTranscriptReconcileMonitor()
        if agents.isEmpty {
            scheduleAgentReload(reason: .appLaunch)
        }
    }

    deinit {
        runEventTasks.values.forEach { $0.cancel() }
        pendingActionMonitorTask?.cancel()
        transcriptReconcileMonitorTask?.cancel()
        agentReloadTask?.cancel()
        transcriptRefreshTask?.cancel()
        runEventSessionTokens.removeAll()
    }

    nonisolated static func managedSessionPrefix(forAgentID agentID: String) -> String {
        "hermes-desk-\(agentID)-"
    }

    nonisolated static func legacyManagedSessionPrefix(forAgentID agentID: String) -> String {
        "agent-hub-\(agentID)-"
    }

    nonisolated static func managedSessionPrefixes(forAgentID agentID: String) -> [String] {
        [
            managedSessionPrefix(forAgentID: agentID),
            legacyManagedSessionPrefix(forAgentID: agentID)
        ]
    }

    nonisolated static func managedAgentID(
        fromRootSessionID rootSessionID: String,
        agents: [HermesAgentDescriptor]
    ) -> String? {
        agents.first {
            managedSessionPrefixes(forAgentID: $0.agentID).contains { prefix in
                rootSessionID.hasPrefix(prefix)
            }
        }?.agentID
    }

    nonisolated static func isManagedWorkspaceSession(
        rootSessionID: String,
        source: String?,
        agentID: String
    ) -> Bool {
        guard source?.lowercased() == "api_server" else {
            return false
        }
        return managedSessionPrefixes(forAgentID: agentID).contains { prefix in
            rootSessionID.hasPrefix(prefix)
        }
    }

    nonisolated static func isManagedWorkspaceTask(_ task: Task) -> Bool {
        guard let rootSessionID = task.rootSessionID ?? task.effectiveSessionID else {
            return false
        }
        return isManagedWorkspaceSession(
            rootSessionID: rootSessionID,
            source: task.sessionSource,
            agentID: task.agentID
        )
    }

    private func resolvedRuntimeProfileID(forAgentID agentID: String?) -> String {
        guard let agent = agentDescriptor(for: agentID) else {
            return Self.defaultRuntimeProfileID
        }
        let agentBackend = localBackendsByRuntimeProfileID[agent.runtimeProfileID]
        if agent.runtimeProfile.hermesHomePath != defaultBackend.diagnostics.hermesHomePath,
           agentBackend?.endpoint == defaultBackend.endpoint {
            return Self.defaultRuntimeProfileID
        }
        return agent.runtimeProfileID
    }

    private func backend(forAgentID agentID: String?) -> any AgentBackend {
        let runtimeProfileID = resolvedRuntimeProfileID(forAgentID: agentID)
        guard runtimeProfileID != Self.defaultRuntimeProfileID,
              let localBackend = localBackendsByRuntimeProfileID[runtimeProfileID] else {
            return defaultBackend
        }
        return localBackend
    }

    private func backend(forTaskID taskID: Task.ID) -> (any AgentBackend)? {
        guard let task = tasks.first(where: { $0.taskID == taskID }) else {
            return nil
        }
        let runtimeProfileID = taskRuntimeProfileIDs[taskID] ?? resolvedRuntimeProfileID(forAgentID: task.agentID)
        return backend(forRuntimeProfileID: runtimeProfileID, agentID: task.agentID)
    }

    private func backend(forRuntimeProfileID runtimeProfileID: String, agentID: String?) -> any AgentBackend {
        if runtimeProfileID == Self.defaultRuntimeProfileID {
            return defaultBackend
        }
        return localBackendsByRuntimeProfileID[runtimeProfileID] ?? defaultBackend
    }

    private var selectedBackend: any AgentBackend {
        if let selectedAgentID {
            return backend(forAgentID: selectedAgentID)
        }
        if let firstAgentID = agents.first?.agentID {
            return backend(forAgentID: firstAgentID)
        }
        return defaultBackend
    }

    var endpoint: HermesEndpoint {
        selectedBackend.endpoint
    }

    var backendDiagnostics: AgentBackendDiagnostics {
        selectedBackend.diagnostics
    }

    private func agentDescriptor(for agentID: String?) -> HermesAgentDescriptor? {
        guard let agentID else { return nil }
        return agents.first { $0.agentID == agentID }
    }

    var selectedAgent: HermesAgentDescriptor? {
        agentDescriptor(for: selectedAgentID)
    }

    var selectedAgentDisplayName: String {
        selectedAgent?.displayName ?? text(zh: "Hermes Agent", en: "Hermes Agent")
    }

    var selectedRuntimeProfileID: String? {
        selectedAgentID.map { resolvedRuntimeProfileID(forAgentID: $0) }
    }

    var selectedRuntimeProfileDisplayName: String {
        selectedRuntimeProfileID ?? text(zh: "默认运行时", en: "Default runtime")
    }

    var selectedAgentRoleSummary: String? {
        selectedAgent?.roleSummary
    }

    func displayName(forAgentID agentID: String) -> String {
        agentDescriptor(for: agentID)?.displayName ?? agentID
    }

    var selectedAgentTasks: [Task] {
        tasks
            .filter { $0.isPreview == false && (selectedAgentID == nil || $0.agentID == selectedAgentID) }
            .sortedForOverview()
    }

    var allLiveTasks: [Task] {
        tasks
            .filter { $0.isPreview == false }
            .sortedForOverview()
    }

    var endpointDisplayAgentLabel: String {
        text(zh: "当前 Agent", en: "Current Agent")
    }

    var localizedConnectionTitle: String {
        switch connectionState {
        case .online:
            return text(zh: "Hermes 在线", en: "Hermes online")
        case .starting:
            return text(zh: "正在连接 Hermes", en: "Checking Hermes")
        case .disconnected:
            return text(zh: "Hermes 离线", en: "Hermes offline")
        case .configurationError:
            return text(zh: "Hermes 配置异常", en: "Hermes misconfigured")
        }
    }

    var localizedConnectionDetail: String {
        switch connectionState {
        case let .online(health):
            if let detail = health.detail, detail.isEmpty == false {
                return text(zh: "本地接口可用 · \(detail)", en: "Local API reachable · \(detail)")
            }
            return text(zh: "本地接口可用", en: "Local API reachable")
        case let .starting(message), let .disconnected(message), let .configurationError(message):
            return message
        }
    }

    func text(zh: String, en: String) -> String {
        HermesDeskL10n.text(preference: languagePreference, zh: zh, en: en)
    }

    var diagnosticsSummary: String {
        let logsPath = backendDiagnostics.hermesHomePath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appending(path: "logs", directoryHint: .isDirectory)
                .path
        } ?? "Unavailable"
        let selectedTaskSummary = selectedTask?.taskID ?? "None"
        return [
            "Agent: \(selectedAgentDisplayName)",
            "Runtime profile: \(selectedRuntimeProfileDisplayName)",
            "Adapter: \(backendDiagnostics.adapterName)",
            "Endpoint: \(endpoint.displayName)",
            "Status: \(connectionState.title)",
            "Status detail: \(connectionState.detail)",
            "Hermes home: \(backendDiagnostics.hermesHomePath ?? "Unavailable")",
            "Environment file: \(backendDiagnostics.environmentFilePath ?? "Unavailable")",
            "Environment file exists: \(backendDiagnostics.environmentFileExists ? "yes" : "no")",
            "API key configured: \(backendDiagnostics.apiKeyConfigured ? "yes" : "no")",
            "Logs directory: \(logsPath)",
            "Live tasks: \(liveTasks.count)",
            "Preview tasks: \(previewTasks.count)",
            "Inbox / Running / Open / Archived: \(inboxCount) / \(runningCount) / \(openCount) / \(archivedCount)",
            "Selected task: \(selectedTaskSummary)"
        ].joined(separator: "\n")
    }

    var menuBarSymbolName: String {
        switch connectionState {
        case .online:
            return "bolt.circle.fill"
        case .starting:
            return "bolt.circle"
        case .disconnected:
            return "exclamationmark.triangle.fill"
        case .configurationError:
            return "gear.badge.xmark"
        }
    }

    var taskFeedSummary: String {
        if liveTasks.isEmpty {
            return text(
                zh: "你可以从下方输入区为当前 Agent 发起新任务。任务会按 Agent 与 Task 组织，而不是混在一个全局聊天列表里。",
                en: "Start a new task for the current agent from the composer below. Work stays organized by agent and task instead of one global chat list."
            )
        }

        if interruptedFeedCount > 0 {
            return text(
                zh: "当前 Agent 下有 \(interruptedFeedCount) 条实时任务流等待重连。",
                en: "The current agent has \(interruptedFeedCount) live task feed\(interruptedFeedCount == 1 ? " waiting" : "s waiting") to reconnect."
            )
        }

        return text(
            zh: "当前 Agent 的任务列表、中间对话区和右侧进展面板都围绕同一个 Task 工作台展开。",
            en: "The current agent's task list, conversation pane, and progress inspector are all centered on the same task workspace."
        )
    }

    var liveTasks: [Task] {
        selectedAgentTasks
    }

    var previewTasks: [Task] {
        tasks
            .filter(\.isPreview)
            .sortedForOverview()
    }

    var inboxTasks: [Task] {
        overviewTasks
            .filter { $0.state == .waitingUser || $0.state == .failed }
            .sortedForOverview()
    }

    var runningTasks: [Task] {
        overviewTasks
            .filter { $0.sessionStatus == .running }
            .sortedForOverview()
    }

    var openTasks: [Task] {
        overviewTasks
            .filter { $0.sessionStatus == .open }
            .sortedForOverview()
    }

    var queuedTasks: [Task] {
        overviewTasks
            .filter { $0.state == .queued || $0.state == .paused }
            .sortedForOverview()
    }

    var recentTasks: [Task] {
        overviewTasks
            .filter { $0.state == .succeeded }
            .sortedForOverview()
    }

    var cancelledTasks: [Task] {
        overviewTasks
            .filter { $0.state == .cancelled }
            .sortedForOverview()
    }

    var selectedTask: Task? {
        guard let selectedTaskID else { return nil }
        return tasks.first { $0.taskID == selectedTaskID }
    }

    var runningCount: Int { runningTasks.count }
    var openCount: Int { openTasks.count }
    var queuedCount: Int { queuedTasks.count }
    var inboxCount: Int { inboxTasks.count }
    var recentCount: Int { recentTasks.count }
    var cancelledCount: Int { cancelledTasks.count }
    var archivedCount: Int { liveTasks.filter { $0.sessionStatus == .archived }.count }
    var interruptedFeedCount: Int {
        liveTasks.filter {
            $0.isPreview == false &&
            $0.state.isTerminal == false &&
            $0.runState.observationState != .live
        }.count
    }
    var priorityAttentionTask: Task? {
        liveTasks.sortedForAttention().first
    }
    var priorityAttentionLabel: String {
        guard let task = priorityAttentionTask else {
            return text(zh: "打开主面板", en: "Open Dashboard")
        }

        if task.state == .failed {
            return text(zh: "打开失败任务", en: "Open Failed Task")
        }
        if task.state == .waitingUser {
            return text(zh: "打开待确认任务", en: "Open Approval Task")
        }
        if task.state.isTerminal == false, task.runState.observationState != .live {
            return text(zh: "打开待重连任务", en: "Open Reconnect Task")
        }
        if task.state == .running {
            return text(zh: "打开进行中任务", en: "Open Running Task")
        }
        return text(zh: "打开主面板", en: "Open Dashboard")
    }
    var priorityAttentionSymbolName: String {
        guard let task = priorityAttentionTask else {
            return "macwindow"
        }

        if task.state == .failed {
            return "exclamationmark.triangle.fill"
        }
        if task.state == .waitingUser {
            return "hand.raised.fill"
        }
        if task.state.isTerminal == false, task.runState.observationState != .live {
            return "bolt.horizontal.circle"
        }
        if task.state == .running {
            return "bolt.fill"
        }
        return "macwindow"
    }

    func selectTask(_ task: Task?) {
        if let task {
            selectedAgentID = task.agentID
        }
        selectedTaskID = task?.taskID
        taskActionFeedback = nil
        guard let task else { return }
        beginTranscriptLoadIfNeeded(for: task)
    }

    func selectTask(id: Task.ID?) {
        selectedTaskID = id
        taskActionFeedback = nil
        guard let id, let task = tasks.first(where: { $0.taskID == id }) else { return }
        selectedAgentID = task.agentID
        beginTranscriptLoadIfNeeded(for: task)
    }

    private func beginTranscriptLoadIfNeeded(for task: Task, force: Bool = false) {
        guard task.isPreview == false else { return }
        let cacheKeys = taskTranscriptCacheKeys(for: task)
        guard cacheKeys.isEmpty == false else { return }

        let shouldRebuild = force || cacheKeys.contains { transcriptMessagesByCacheKey[$0] != nil }
        guard shouldRebuild else { return }

        rebuildWorkspaceMessagesCache(for: task)
        refreshTaskTitleIfNeeded(forTaskID: task.taskID)
    }

    func selectDefaultTaskIfNeeded() {
        guard selectedTask == nil else { return }
        guard let task = prioritizedTasks.first else {
            selectedTaskID = nil
            return
        }
        selectedTaskID = task.taskID
        beginTranscriptLoadIfNeeded(for: task)
    }

    private func configureAgents() {
        let discoveredAgents = HermesAgentDiscovery.discoverAgents()
        agents = discoveredAgents
        localBackendsByRuntimeProfileID = Dictionary(uniqueKeysWithValues: discoveredAgents.map { agent in
            let profile = agent.runtimeProfile
            var processEnvironment = ProcessInfo.processInfo.environment
            processEnvironment["HERMES_HOME"] = profile.hermesHomePath
            let configuration = HermesLocalServerConfiguration.discover(processEnvironment: processEnvironment)
            return (agent.runtimeProfileID, HermesLocalAdapter(configuration: configuration))
        })
        localBackendsByRuntimeProfileID[Self.defaultRuntimeProfileID] = defaultBackend

        let preferredAgentID = discoveredAgents.first(where: { agent in
            agent.runtimeProfile.hermesHomePath == defaultBackend.diagnostics.hermesHomePath
        })?.agentID

        if let selectedAgentID,
           discoveredAgents.contains(where: { $0.agentID == selectedAgentID }) {
            self.selectedAgentID = selectedAgentID
        } else {
            self.selectedAgentID = preferredAgentID ?? discoveredAgents.first?.agentID
        }
    }

    private func restorePersistedClientState(availableAgents: [HermesAgentDescriptor]? = nil) {
        guard let persistedState = taskCacheStore.load() else {
            nextLocalTranscriptMessageID = -1
            return
        }

        let visibleAgents = availableAgents ?? agents
        let visibleAgentIDs = Set(visibleAgents.map(\.agentID))
        let filteredTasks = persistedState.tasks
            .filter { $0.isPreview == false && visibleAgentIDs.contains($0.agentID) }
            .sortedForOverview()
        let validTaskIDs = Set(filteredTasks.map(\.taskID))

        tasks = filteredTasks
        taskRuntimeProfileIDs = persistedState.taskRuntimeProfileIDs.filter { validTaskIDs.contains($0.key) }

        transcriptMessagesByCacheKey = Dictionary(
            uniqueKeysWithValues: persistedState.transcriptEntries.map { entry in
                (
                    TranscriptCacheKey(runtimeProfileID: entry.runtimeProfileID, sessionID: entry.sessionID),
                    entry.messages
                )
            }
        )
        transcriptHasOlderByCacheKey = Dictionary(
            uniqueKeysWithValues: persistedState.transcriptEntries.map { entry in
                (
                    TranscriptCacheKey(runtimeProfileID: entry.runtimeProfileID, sessionID: entry.sessionID),
                    entry.hasMoreBefore
                )
            }
        )
        pendingOutgoingMessagesByTaskID = Dictionary(
            uniqueKeysWithValues: persistedState.pendingEntries.compactMap { entry in
                guard validTaskIDs.contains(entry.taskID) else {
                    return nil
                }
                let messages = entry.messages.map { message in
                    PendingOutgoingMessage(
                        id: message.id,
                        sessionID: message.sessionID,
                        content: message.content,
                        timestamp: message.timestamp
                    )
                }
                return (entry.taskID, messages)
            }
        )
        stableWorkspaceEntryIDsByTaskID = [:]
        transcriptLoadingTaskIDs = []
        transcriptLoadingOlderTaskIDs = []
        workspaceMessagesByTaskID = Dictionary(
            uniqueKeysWithValues: filteredTasks.map { task in
                (task.taskID, buildWorkspaceMessages(for: task))
            }
        )

        let minimumLocalID = transcriptMessagesByCacheKey
            .values
            .flatMap { $0 }
            .map(\.id)
            .filter { $0 < 0 }
            .min() ?? 0
        nextLocalTranscriptMessageID = minimumLocalID < 0 ? minimumLocalID - 1 : -1
    }

    private func persistClientState() {
        let persistedTasks = tasks.filter { $0.isPreview == false }
        let taskIDs = Set(persistedTasks.map(\.taskID))
        let validCacheKeys = Set(persistedTasks.flatMap(taskTranscriptCacheKeys(for:)))
        let state = HermesDeskTaskCacheStore.State(
            tasks: persistedTasks,
            taskRuntimeProfileIDs: taskRuntimeProfileIDs.filter { taskIDs.contains($0.key) },
            transcriptEntries: transcriptMessagesByCacheKey.compactMap { cacheKey, messages in
                guard validCacheKeys.contains(cacheKey) else {
                    return nil
                }
                return HermesDeskTaskCacheStore.State.TranscriptEntry(
                    runtimeProfileID: cacheKey.runtimeProfileID,
                    sessionID: cacheKey.sessionID,
                    messages: messages,
                    hasMoreBefore: transcriptHasOlderByCacheKey[cacheKey] ?? false
                )
            },
            pendingEntries: pendingOutgoingMessagesByTaskID.compactMap { taskID, messages in
                guard taskIDs.contains(taskID) else {
                    return nil
                }
                return HermesDeskTaskCacheStore.State.PendingEntry(
                    taskID: taskID,
                    messages: messages.map { message in
                        HermesDeskTaskCacheStore.State.PendingEntry.Message(
                            id: message.id,
                            sessionID: message.sessionID,
                            content: message.content,
                            timestamp: message.timestamp
                        )
                    }
                )
            }
        )
        taskCacheStore.save(state)
    }

    private func nextLocalMessageID() -> Int64 {
        defer { nextLocalTranscriptMessageID -= 1 }
        return nextLocalTranscriptMessageID
    }

    private func scheduleAgentReload(reason: SubscriptionRestoreReason) {
        agentReloadTask?.cancel()
        transcriptRefreshTask?.cancel()
        let availableAgents = agents
        agentReloadTask = Swift.Task { [weak self] in
            await self?.reloadTasksForAgents(availableAgents)
            guard Swift.Task.isCancelled == false else { return }
            await self?.refreshHealth(using: reason)
        }
    }

    private func reloadTasksForAgents(_ availableAgents: [HermesAgentDescriptor]) async {
        guard availableAgents.isEmpty == false else {
            tasks = []
            taskRuntimeProfileIDs = [:]
            transcriptMessagesByCacheKey = [:]
            transcriptHasOlderByCacheKey = [:]
            transcriptLoadingTaskIDs = []
            transcriptLoadingOlderTaskIDs = []
            workspaceMessagesByTaskID = [:]
            pendingOutgoingMessagesByTaskID = [:]
            stableWorkspaceEntryIDsByTaskID = [:]
            persistClientState()
            return
        }
        restorePersistedClientState(availableAgents: availableAgents)
        if let selectedTaskID,
           tasks.contains(where: { $0.taskID == selectedTaskID && (selectedAgentID == nil || $0.agentID == selectedAgentID) }) == false {
            self.selectedTaskID = nil
        }
        selectDefaultTaskIfNeeded()
        transcriptLoadingTaskIDs = []
        transcriptLoadingOlderTaskIDs = []
        if let selectedTask {
            rebuildWorkspaceMessagesCache(for: selectedTask)
        }
    }

    func transcriptMessages(for task: Task) -> [HermesConversationMessage] {
        if let cachedMessages = workspaceMessagesByTaskID[task.taskID] {
            return cachedMessages
        }
        return buildWorkspaceMessages(for: task)
    }

    func pendingOutgoingMessages(for task: Task) -> [PendingOutgoingMessage] {
        pendingOutgoingMessagesByTaskID[task.taskID] ?? []
    }

    func isTranscriptLoading(for task: Task) -> Bool {
        transcriptLoadingTaskIDs.contains(task.taskID)
    }

    func isLoadingOlderMessages(for task: Task) -> Bool {
        transcriptLoadingOlderTaskIDs.contains(task.taskID)
    }

    func canLoadOlderMessages(for task: Task) -> Bool {
        false
    }

    func loadOlderMessages(for taskID: Task.ID) {
        transcriptLoadingOlderTaskIDs.remove(taskID)
    }

    private func buildWorkspaceMessages(for task: Task) -> [HermesConversationMessage] {
        let combinedMessages = taskTranscriptCacheKeys(for: task).flatMap { transcriptMessagesByCacheKey[$0] ?? [] }
        let deduplicatedMessages = Dictionary(grouping: combinedMessages, by: workspaceMessageFingerprint(for:))
            .values
            .compactMap { groupedMessages in
                groupedMessages.max { lhs, rhs in
                    if (lhs.id >= 0) != (rhs.id >= 0) {
                        return lhs.id < rhs.id
                    }
                    if lhs.timestamp != rhs.timestamp {
                        return lhs.timestamp < rhs.timestamp
                    }
                    return lhs.id < rhs.id
                }
            }
        return deduplicatedMessages
            .filter { $0.role.isVisibleInWorkspace && $0.displayText.isEmpty == false }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.id < rhs.id
            }
    }

    private func rebuildWorkspaceMessagesCache(for task: Task) {
        var nextCache = workspaceMessagesByTaskID
        nextCache[task.taskID] = buildWorkspaceMessages(for: task)
        workspaceMessagesByTaskID = nextCache
    }

    private func startPendingActionMonitor() {
        pendingActionMonitorTask?.cancel()
        pendingActionMonitorTask = Swift.Task { [weak self] in
            while Swift.Task.isCancelled == false {
                try? await Swift.Task.sleep(for: Self.pendingActionReconcileInterval)
                guard Swift.Task.isCancelled == false else { return }
                self?.reconcileTimedOutPendingActions()
            }
        }
    }

    private func startTranscriptReconcileMonitor() {
        transcriptReconcileMonitorTask?.cancel()
        transcriptReconcileMonitorTask = Swift.Task { [weak self] in
            while Swift.Task.isCancelled == false {
                try? await Swift.Task.sleep(for: .seconds(2))
                guard Swift.Task.isCancelled == false else { return }
                await self?.reconcileVisibleLiveTranscripts()
            }
        }
    }

    private func reconcileVisibleLiveTranscripts() async {
        let candidateTaskIDs = Set(
            ([selectedTaskID].compactMap { $0 } + pendingOutgoingMessagesByTaskID.keys)
                .compactMap { taskID in
                    tasks.first(where: {
                        $0.taskID == taskID
                            && $0.isPreview == false
                            && ($0.runID != nil || (pendingOutgoingMessagesByTaskID[taskID]?.isEmpty == false))
                    })?.taskID
                }
        )

        guard candidateTaskIDs.isEmpty == false else {
            return
        }

        for taskID in candidateTaskIDs {
            await refreshTranscripts(forTaskID: taskID, force: true)
        }
    }

    private func reconcileTimedOutPendingActions(now: Date = .now) {
        var reconciledTaskIDs: [Task.ID] = []

        for index in tasks.indices {
            guard tasks[index].hasTimedOutPendingAction(asOf: now, timeout: Self.pendingActionTimeout),
                  let action = tasks[index].pendingAction else {
                continue
            }

            tasks[index].pendingAction = nil
            tasks[index].pendingActionStartedAt = nil
            liveActionRequestTokens[tasks[index].taskID] = nil
            tasks[index].updatedAt = now
            tasks[index].runState.progressHint = timedOutPendingActionMessage(for: action, task: tasks[index])
            appendLocalEvent(
                to: &tasks[index],
                type: .error,
                timestamp: now,
                summary: "Hermes Desk stopped waiting on \(pendingActionReconcileTitle(for: action))",
                detail: tasks[index].runState.progressHint
            )
            reconciledTaskIDs.append(tasks[index].taskID)
        }

        if reconciledTaskIDs.isEmpty == false {
            taskActionFeedback = reconciledTaskIDs.count == 1
                ? "Hermes has not confirmed the last action yet. Hermes Desk released the blocked action state for \(reconciledTaskIDs[0])."
                : "Hermes has not confirmed \(reconciledTaskIDs.count) pending actions yet. Hermes Desk released their blocked action states."
            persistClientState()
        }
    }

    private func preloadVisibleTranscripts() async {
        let taskIDs = [selectedTaskID ?? liveTasks.first?.taskID].compactMap { $0 }
        for taskID in taskIDs {
            await refreshTranscripts(forTaskID: taskID)
        }
    }

    private func runtimeProfileID(for task: Task) -> String {
        taskRuntimeProfileIDs[task.taskID] ?? resolvedRuntimeProfileID(forAgentID: task.agentID)
    }

    private func taskSessionIDs(for task: Task) -> [String] {
        let orderedSessionIDs = task.sessionLineage.map(\.sessionID)
        return orderedSessionIDs.isEmpty
            ? task.effectiveSessionID.map { [$0] } ?? []
            : orderedSessionIDs
    }

    private func taskTranscriptCacheKeys(for task: Task) -> [TranscriptCacheKey] {
        let sessionIDs = taskSessionIDs(for: task)
        guard sessionIDs.isEmpty == false else {
            return []
        }

        var runtimeProfileIDs = [runtimeProfileID(for: task)]
        if task.normalizedSessionSource != "api_server",
           runtimeProfileIDs.contains(Self.defaultRuntimeProfileID) == false {
            runtimeProfileIDs.append(Self.defaultRuntimeProfileID)
        }

        var keys: [TranscriptCacheKey] = []
        keys.reserveCapacity(runtimeProfileIDs.count * sessionIDs.count)
        for runtimeProfileID in runtimeProfileIDs {
            for sessionID in sessionIDs {
                keys.append(TranscriptCacheKey(runtimeProfileID: runtimeProfileID, sessionID: sessionID))
            }
        }
        return keys
    }

    private func mergeTranscriptMessages(
        _ incomingMessages: [HermesConversationMessage],
        into cacheKey: TranscriptCacheKey
    ) {
        let existingMessages = transcriptMessagesByCacheKey[cacheKey] ?? []
        // Retain ALL existing messages — positive-ID (server-fetched) and negative-ID (locally
        // created during streaming). Discarding negative-ID messages here would wipe assistant
        // streaming messages whenever a new user message is materialized.
        let retainedExistingMessages = existingMessages

        let merged = (retainedExistingMessages + incomingMessages)
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.id < rhs.id
            }

        var deduplicated: [HermesConversationMessage] = []
        deduplicated.reserveCapacity(merged.count)
        var seenIDs: Set<Int64> = []
        for message in merged where seenIDs.insert(message.id).inserted {
            deduplicated.append(message)
        }

        transcriptMessagesByCacheKey[cacheKey] = deduplicated
    }

    private func primaryTranscriptCacheKey(for task: Task, sessionID: String? = nil) -> TranscriptCacheKey? {
        let resolvedSessionID = sessionID ?? task.effectiveSessionID
        guard let resolvedSessionID,
              resolvedSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return TranscriptCacheKey(
            runtimeProfileID: runtimeProfileID(for: task),
            sessionID: resolvedSessionID
        )
    }

    private func appendTranscriptMessageIfNeeded(_ message: HermesConversationMessage, for task: Task) {
        guard let cacheKey = primaryTranscriptCacheKey(for: task, sessionID: message.sessionID) else {
            return
        }

        let existingMessages = transcriptMessagesByCacheKey[cacheKey] ?? []
        let fingerprint = workspaceMessageFingerprint(for: message)
        if existingMessages.contains(where: { workspaceMessageFingerprint(for: $0) == fingerprint }) {
            return
        }

        mergeTranscriptMessages([message], into: cacheKey)
        transcriptHasOlderByCacheKey[cacheKey] = false
    }

    private func materializePendingOutgoingMessages(for taskID: Task.ID) {
        guard let task = tasks.first(where: { $0.taskID == taskID }) else {
            return
        }

        for pendingMessage in pendingOutgoingMessages(for: task) {
            appendTranscriptMessageIfNeeded(
                HermesConversationMessage(
                    id: nextLocalMessageID(),
                    sessionID: pendingMessage.sessionID,
                    role: .user,
                    content: pendingMessage.content,
                    timestamp: pendingMessage.timestamp
                ),
                for: task
            )
        }
    }

    private func upsertStreamingAssistantMessage(
        for taskID: Task.ID,
        sessionID: String,
        content: String,
        timestamp: Date
    ) {
        guard let task = tasks.first(where: { $0.taskID == taskID }),
              let cacheKey = primaryTranscriptCacheKey(for: task, sessionID: sessionID) else {
            return
        }

        var messages = transcriptMessagesByCacheKey[cacheKey] ?? []
        let adjustedTimestamp: Date
        if let lastTimestamp = messages.last?.timestamp, timestamp <= lastTimestamp {
            adjustedTimestamp = lastTimestamp.addingTimeInterval(0.001)
        } else {
            adjustedTimestamp = timestamp
        }
        if let lastMessage = messages.last,
           lastMessage.role == .assistant,
           lastMessage.id < 0,
           lastMessage.sessionID == sessionID {
            messages[messages.count - 1] = HermesConversationMessage(
                id: lastMessage.id,
                sessionID: sessionID,
                role: .assistant,
                content: content,
                timestamp: adjustedTimestamp
            )
        } else {
            messages.append(
                HermesConversationMessage(
                    id: nextLocalMessageID(),
                    sessionID: sessionID,
                    role: .assistant,
                    content: content,
                    timestamp: adjustedTimestamp
                )
            )
        }

        transcriptMessagesByCacheKey[cacheKey] = messages.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id < rhs.id
        }
        transcriptHasOlderByCacheKey[cacheKey] = false
    }

    private func workspaceMessageFingerprint(for message: HermesConversationMessage) -> WorkspaceMessageFingerprint {
        WorkspaceMessageFingerprint(
            sessionID: message.sessionID,
            role: message.role,
            normalizedContent: normalizedPendingOutgoingContent(message.displayText),
            second: Int(message.timestamp.timeIntervalSince1970.rounded(.down))
        )
    }

    private func workspaceMessageFingerprint(for pendingMessage: PendingOutgoingMessage) -> WorkspaceMessageFingerprint {
        WorkspaceMessageFingerprint(
            sessionID: pendingMessage.sessionID,
            role: .user,
            normalizedContent: normalizedPendingOutgoingContent(pendingMessage.content),
            second: Int(pendingMessage.timestamp.timeIntervalSince1970.rounded(.down))
        )
    }

    private func normalizedPendingOutgoingContent(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func stableWorkspaceEntryID(for message: HermesConversationMessage, taskID: Task.ID) -> String {
        let fingerprint = workspaceMessageFingerprint(for: message)
        return stableWorkspaceEntryIDsByTaskID[taskID]?[fingerprint] ?? "session-message-\(message.id)"
    }

    func stableWorkspaceEntryID(for pendingMessage: PendingOutgoingMessage, taskID: Task.ID) -> String {
        let fingerprint = workspaceMessageFingerprint(for: pendingMessage)
        return stableWorkspaceEntryIDsByTaskID[taskID]?[fingerprint] ?? "pending-outgoing-\(pendingMessage.id.uuidString)"
    }

    private func refreshTranscripts(forTaskID taskID: Task.ID, force: Bool = false) async {
        guard let task = tasks.first(where: { $0.taskID == taskID }) else {
            return
        }

        if force {
            materializePendingOutgoingMessages(for: task.taskID)
        }
        reconcilePendingOutgoingMessages(for: task)
        reconcileCompletedConversationFromTranscript(forTaskID: taskID)
        rebuildWorkspaceMessagesCache(for: task)
        refreshTaskTitleIfNeeded(forTaskID: taskID)
        persistClientState()
    }

    private func reconcileCompletedConversationFromTranscript(forTaskID taskID: Task.ID) {
        guard let index = tasks.firstIndex(where: { $0.taskID == taskID }) else {
            return
        }
        guard tasks[index].runID != nil else {
            return
        }

        let transcript = transcriptMessages(for: tasks[index])
        guard let latestUserTimestamp = transcript
            .reversed()
            .first(where: { $0.role == .user })?
            .timestamp,
              let latestAssistantMessage = transcript
            .reversed()
            .first(where: { $0.role == .assistant && tasks[index].shouldDisplayMessageInWorkspaceConversation($0) }),
              latestAssistantMessage.timestamp >= latestUserTimestamp else {
            return
        }

        let finalText = latestAssistantMessage.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard finalText.isEmpty == false else {
            return
        }

        tasks[index].runID = nil
        tasks[index].pendingAction = nil
        tasks[index].pendingActionStartedAt = nil
        tasks[index].runState.state = .running
        tasks[index].runState.phaseLabel = text(zh: "对话已更新", en: "Conversation updated")
        tasks[index].runState.progressHint = nil
        tasks[index].runState.observationState = .live
        tasks[index].runState.observationMessage = nil
        tasks[index].currentSummary = finalText.count > 180 ? String(finalText.prefix(180)) + "…" : finalText
        tasks[index].output = finalText
        tasks[index].availableActions = [.openWorkspace]
        tasks[index].artifact = nil
    }

    private func enqueuePendingOutgoingMessage(_ content: String, sessionID: String, taskID: Task.ID) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let message = PendingOutgoingMessage(
            id: UUID(),
            sessionID: sessionID,
            content: trimmed,
            timestamp: .now
        )

        var existing = pendingOutgoingMessagesByTaskID[taskID] ?? []
        existing.append(message)
        let updatedMessages = existing.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.content.localizedCaseInsensitiveCompare(rhs.content) == .orderedAscending
        }
        var nextPendingMessages = pendingOutgoingMessagesByTaskID
        nextPendingMessages[taskID] = updatedMessages
        pendingOutgoingMessagesByTaskID = nextPendingMessages
        let fingerprint = workspaceMessageFingerprint(for: message)
        var stableEntryIDs = stableWorkspaceEntryIDsByTaskID[taskID] ?? [:]
        stableEntryIDs[fingerprint] = "pending-outgoing-\(message.id.uuidString)"
        stableWorkspaceEntryIDsByTaskID[taskID] = stableEntryIDs

        if let task = tasks.first(where: { $0.taskID == taskID }) {
            rebuildWorkspaceMessagesCache(for: task)
        }
        persistClientState()
    }

    private func reconcilePendingOutgoingMessages(for task: Task) {
        let pendingMessages = pendingOutgoingMessagesByTaskID[task.taskID] ?? []
        guard pendingMessages.isEmpty == false else { return }

        let cacheKeys = taskTranscriptCacheKeys(for: task)
        var persistedUserMessages: [HermesConversationMessage] = []
        for cacheKey in cacheKeys {
            let cachedMessages = transcriptMessagesByCacheKey[cacheKey] ?? []
            for message in cachedMessages where message.role == .user {
                persistedUserMessages.append(message)
            }
        }

        var persistedUserFingerprintCounts: [PendingOutgoingFingerprint: Int] = [:]
        var persistedUserMessagesByFingerprint: [PendingOutgoingFingerprint: [HermesConversationMessage]] = [:]
        for message in persistedUserMessages {
            let fingerprint = PendingOutgoingFingerprint(
                sessionID: message.sessionID,
                normalizedContent: normalizedPendingOutgoingContent(message.displayText)
            )
            let nextCount = persistedUserFingerprintCounts[fingerprint, default: 0] + 1
            persistedUserFingerprintCounts[fingerprint] = nextCount
            persistedUserMessagesByFingerprint[fingerprint, default: []].append(message)
        }

        var consumedCounts: [PendingOutgoingFingerprint: Int] = [:]
        var stableEntryIDs = stableWorkspaceEntryIDsByTaskID[task.taskID] ?? [:]
        let unresolvedPendingMessages = pendingMessages.filter { pendingMessage in
            let fingerprint = PendingOutgoingFingerprint(
                sessionID: pendingMessage.sessionID,
                normalizedContent: normalizedPendingOutgoingContent(pendingMessage.content)
            )
            let resolvedCount = persistedUserFingerprintCounts[fingerprint, default: 0]
            let consumedCount = consumedCounts[fingerprint, default: 0]
            guard resolvedCount > consumedCount else {
                return true
            }
            consumedCounts[fingerprint] = consumedCount + 1
            let pendingWorkspaceFingerprint = workspaceMessageFingerprint(for: pendingMessage)
            if let aliasID = stableEntryIDs[pendingWorkspaceFingerprint],
               let resolvedMessage = persistedUserMessagesByFingerprint[fingerprint]?[consumedCount] {
                let persistedWorkspaceFingerprint = workspaceMessageFingerprint(for: resolvedMessage)
                stableEntryIDs[persistedWorkspaceFingerprint] = aliasID
            }
            return false
        }
        stableWorkspaceEntryIDsByTaskID[task.taskID] = stableEntryIDs

        if unresolvedPendingMessages.isEmpty {
            var nextPendingMessages = pendingOutgoingMessagesByTaskID
            nextPendingMessages.removeValue(forKey: task.taskID)
            pendingOutgoingMessagesByTaskID = nextPendingMessages
        } else {
            var nextPendingMessages = pendingOutgoingMessagesByTaskID
            nextPendingMessages[task.taskID] = unresolvedPendingMessages
            pendingOutgoingMessagesByTaskID = nextPendingMessages
        }
        persistClientState()
    }

    private func refreshTaskTitleIfNeeded(forTaskID taskID: Task.ID) {
        guard let index = tasks.firstIndex(where: { $0.taskID == taskID }) else {
            return
        }

        let task = tasks[index]
        guard let requestText = task.requestText?.trimmingCharacters(in: .whitespacesAndNewlines),
              requestText.isEmpty == false else {
            return
        }
        guard Task.shouldAutoRefreshWorkspaceTitle(currentTitle: task.title, requestText: requestText) else {
            return
        }
        let refreshedTitle = Task.summarizedWorkspaceTitle(from: requestText)
        guard refreshedTitle != task.title else {
            return
        }

        tasks[index].title = refreshedTitle
    }

    func refreshHealth() async {
        await refreshHealth(using: .healthRefresh)
    }

    func refreshWorkspace() async {
        guard isRefreshing == false else { return }

        isRefreshing = true
        await reloadTasksForAgents(agents)
        connectionState = .starting(message: "Checking \(endpoint.displayName)…")
        connectionState = await selectedBackend.health()
        isRefreshing = false

        if case .online = connectionState {
            restoreLiveTaskSubscriptions(reason: .healthRefresh)
        }
    }

    private func refreshHealth(using restoreReason: SubscriptionRestoreReason) async {
        guard isRefreshing == false else { return }

        isRefreshing = true
        connectionState = .starting(message: "Checking \(endpoint.displayName)…")
        connectionState = await selectedBackend.health()
        isRefreshing = false

        if case .online = connectionState {
            restoreLiveTaskSubscriptions(reason: restoreReason)
        }
    }

    func startHermesTask(title: String?, prompt: String, continuingTaskID: Task.ID? = nil) async throws {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.isEmpty == false else {
            throw RunLaunchValidationError.emptyPrompt
        }

        guard backendDiagnostics.apiKeyConfigured else {
            throw RunLaunchValidationError.apiKeyMissing
        }

        guard isStartingRun == false else {
            throw RunLaunchValidationError.alreadyStarting
        }

        isStartingRun = true
        runLaunchError = nil
        defer { isStartingRun = false }

        let existingTask = continuingTaskID.flatMap { taskID in
            tasks.first(where: { $0.taskID == taskID })
        }
        if let existingTask, Self.isManagedWorkspaceTask(existingTask) == false {
            throw RunLaunchValidationError.unmanagedConversation
        }

        let targetAgentID = existingTask?.agentID ?? selectedAgentID ?? agents.first?.agentID ?? "hermes"
        let sessionID = existingTask?.effectiveSessionID ?? "hermes-desk-\(targetAgentID)-\(UUID().uuidString)"
        let targetBackend: any AgentBackend
        let targetRuntimeProfileID: String
        if let existingTask {
            targetBackend = backend(forTaskID: existingTask.taskID) ?? defaultBackend
            targetRuntimeProfileID = taskRuntimeProfileIDs[existingTask.taskID] ?? resolvedRuntimeProfileID(forAgentID: targetAgentID)
        } else {
            targetBackend = backend(forAgentID: targetAgentID)
            targetRuntimeProfileID = resolvedRuntimeProfileID(forAgentID: targetAgentID)
        }

        do {
            let response = try await targetBackend.startRun(
                input: trimmedPrompt,
                sessionID: sessionID,
                instructions: nil,
                conversationHistory: nil
            )

            if var existingTask {
                enqueuePendingOutgoingMessage(
                    trimmedPrompt,
                    sessionID: sessionID,
                    taskID: existingTask.taskID
                )
                existingTask.currentSessionID = sessionID
                if existingTask.rootSessionID == nil {
                    existingTask.rootSessionID = sessionID
                }
                if existingTask.sessionLineage.isEmpty {
                    existingTask.sessionLineage = [HermesSessionDescriptor(sessionID: sessionID)]
                }
                existingTask.sessionID = sessionID
                existingTask.runID = response.runID
                existingTask.updatedAt = .now
                existingTask.currentSummary = "Sent a follow-up to Hermes. Waiting for the next run to respond."
                existingTask.output = ""
                existingTask.pendingAction = nil
                existingTask.pendingActionStartedAt = nil
                existingTask.availableActions = [.stop, .openWorkspace]
                existingTask.runState = RunState(
                    state: .running,
                    phaseLabel: "Follow-up queued",
                    lastEventAt: .now,
                    progressHint: "Connecting to Hermes event stream"
                )
                upsertTask(existingTask)
                taskRuntimeProfileIDs[existingTask.taskID] = targetRuntimeProfileID
                selectedTaskID = existingTask.taskID
                selectedAgentID = existingTask.agentID
                taskActionFeedback = nil
                beginTranscriptLoadIfNeeded(for: existingTask, force: true)
                persistClientState()
                connectRunEvents(taskID: existingTask.taskID, runID: response.runID)
            } else {
                let task = Task.liveHermesTask(
                    taskID: "\(targetAgentID):\(sessionID)",
                    title: resolvedTaskTitle(customTitle: title, prompt: trimmedPrompt),
                    input: trimmedPrompt,
                    runID: response.runID,
                    sessionID: sessionID,
                    agentID: targetAgentID
                )
                upsertTask(task)
                taskRuntimeProfileIDs[task.taskID] = targetRuntimeProfileID
                enqueuePendingOutgoingMessage(
                    trimmedPrompt,
                    sessionID: sessionID,
                    taskID: task.taskID
                )
                selectedTaskID = task.taskID
                selectedAgentID = targetAgentID
                taskActionFeedback = nil
                beginTranscriptLoadIfNeeded(for: task, force: true)
                persistClientState()
                connectRunEvents(taskID: task.taskID, runID: response.runID)
            }
        } catch {
            let message = error.localizedDescription
            runLaunchError = message
            throw error
        }
    }

    func performTaskAction(_ action: TaskAction, for taskID: Task.ID) {
        guard let index = tasks.firstIndex(where: { $0.taskID == taskID }) else {
            taskActionFeedback = "The selected task is no longer available."
            return
        }

        taskActionFeedback = nil
        let task = tasks[index]
        let taskDiagnostics = backend(forTaskID: task.taskID)?.diagnostics ?? backend(forAgentID: task.agentID).diagnostics

        switch action {
        case .openWorkspace:
            reveal(path: taskDiagnostics.hermesHomePath)
            taskActionFeedback = "Opened the agent runtime in Finder."

        case .openTerminal:
            if openTerminal(at: taskDiagnostics.hermesHomePath) {
                taskActionFeedback = "Opened Terminal at the agent runtime directory."
            } else {
                taskActionFeedback = "Could not open Terminal for the agent runtime directory."
            }

        case .copyResult:
            let copied = task.artifact?.summary ?? task.latestOutputSummary ?? task.currentSummary
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(copied, forType: .string)
            taskActionFeedback = "Copied the latest task result to the clipboard."

        case .approveOnce, .approveForTask, .reject, .retry, .resume, .pause, .stop:
            if task.isPreview {
                applyPreviewAction(action, toTaskAt: index)
            } else {
                performLiveTaskAction(action, task: task)
            }
        }
    }

    func reconnectLiveFeed(for taskID: Task.ID) {
        guard let index = tasks.firstIndex(where: { $0.taskID == taskID }) else {
            taskActionFeedback = "The selected task is no longer available."
            return
        }

        let task = tasks[index]
        guard task.isPreview == false, task.state.isTerminal == false, let runID = task.runID else {
            taskActionFeedback = "This task does not have a reconnectable live Hermes feed."
            return
        }

        tasks[index].runState.observationState = .reconnecting
        tasks[index].runState.observationMessage = "Manual reconnect requested from Hermes Desk."
        tasks[index].updatedAt = .now
        taskActionFeedback = "Reconnecting the live Hermes feed now."
        persistClientState()
        connectRunEvents(taskID: taskID, runID: runID)
    }

    func reconnectInterruptedFeeds() {
        let reconnectableTasks = liveTasks.filter {
            $0.isPreview == false &&
            $0.state.isTerminal == false &&
            $0.runState.observationState != .live &&
            $0.runID != nil
        }

        guard reconnectableTasks.isEmpty == false else {
            taskActionFeedback = "There are no interrupted live feeds to reconnect right now."
            return
        }

        reconnectableTasks.forEach { task in
            reconnectLiveFeed(for: task.taskID)
        }
        taskActionFeedback = reconnectableTasks.count == 1
            ? "Reconnecting 1 interrupted live feed."
            : "Reconnecting \(reconnectableTasks.count) interrupted live feeds."
    }

    private var overviewTasks: [Task] {
        liveTasks
    }

    private var prioritizedTasks: [Task] {
        overviewTasks
    }

    private func restoreLiveTaskSubscriptions(reason: SubscriptionRestoreReason) {
        guard case .online = connectionState else {
            return
        }

        let tasksToRestore = liveTasks.filter {
            $0.isPreview == false &&
            $0.state.isTerminal == false &&
            $0.runID != nil &&
            (runEventTasks[$0.taskID] == nil || $0.runState.observationState == .disconnected)
        }

        guard tasksToRestore.isEmpty == false else {
            return
        }

        for task in tasksToRestore {
            guard let runID = task.runID,
                  let index = tasks.firstIndex(where: { $0.taskID == task.taskID }) else {
                continue
            }
            tasks[index].runState.observationState = .reconnecting
            tasks[index].runState.observationMessage = reason.statusMessage
            tasks[index].updatedAt = .now
            connectRunEvents(taskID: task.taskID, runID: runID)
        }
    }

    private func connectRunEvents(taskID: String, runID: String) {
        runEventTasks[taskID]?.cancel()
        let sessionToken = UUID()
        runEventSessionTokens[taskID] = sessionToken
        runEventTasks[taskID] = Swift.Task { [weak self] in
            guard let self else { return }
            await observeRunEvents(taskID: taskID, runID: runID, sessionToken: sessionToken)
        }
    }

    private func observeRunEvents(taskID: String, runID: String, sessionToken: UUID) async {
        let maxReconnectAttempts = 3
        var reconnectAttempt = 0

        defer {
            clearRunEventObserver(taskID: taskID, sessionToken: sessionToken)
        }

        while Swift.Task.isCancelled == false {
            guard shouldKeepObserving(taskID: taskID) else {
                return
            }

            do {
                guard let taskBackend = backend(forTaskID: taskID) else {
                    return
                }

                for try await event in taskBackend.runEvents(for: runID) {
                    guard Swift.Task.isCancelled == false else {
                        return
                    }
                    apply(event: event, toTaskID: taskID)
                    reconnectAttempt = 0
                }

                guard shouldKeepObserving(taskID: taskID) else {
                    return
                }

                await finalizeStreamClosure(forTaskID: taskID, runID: runID)
                return
            } catch is CancellationError {
                return
            } catch {
                guard shouldKeepObserving(taskID: taskID) else {
                    return
                }

                if error.localizedDescription.contains("HTTP 404") {
                    await finalizeStreamClosure(forTaskID: taskID, runID: runID)
                    return
                }

                reconnectAttempt += 1
                let shouldRetry = await handleObservationInterruption(
                    forTaskID: taskID,
                    runID: runID,
                    attempt: reconnectAttempt,
                    maxAttempts: maxReconnectAttempts,
                    reason: error.localizedDescription
                )
                if shouldRetry == false {
                    return
                }
            }
        }
    }

    private func finalizeStreamClosure(forTaskID taskID: String, runID: String) async {
        await refreshTranscripts(forTaskID: taskID, force: true)
        guard let index = tasks.firstIndex(where: { $0.taskID == taskID }) else {
            return
        }
        guard tasks[index].state.isTerminal == false else {
            return
        }

        let finalText = (
            transcriptMessages(for: tasks[index])
                .reversed()
                .first(where: { $0.role == .assistant && tasks[index].shouldDisplayMessageInWorkspaceConversation($0) })?
                .displayText
            ?? tasks[index].output
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        tasks[index].runID = nil
        tasks[index].pendingAction = nil
        tasks[index].pendingActionStartedAt = nil
        tasks[index].runState.observationState = .live
        tasks[index].runState.observationMessage = nil

        if finalText.isEmpty == false {
            tasks[index].runState.state = .running
            tasks[index].runState.phaseLabel = text(zh: "对话已更新", en: "Conversation updated")
            tasks[index].runState.progressHint = nil
            tasks[index].currentSummary = finalText.count > 180 ? String(finalText.prefix(180)) + "…" : finalText
            tasks[index].output = finalText
            tasks[index].availableActions = [.openWorkspace]
            tasks[index].artifact = nil
        } else {
            tasks[index].runState.state = .running
            tasks[index].runState.phaseLabel = text(zh: "等待对话同步", en: "Waiting for transcript sync")
            tasks[index].runState.progressHint = text(zh: "Hermes 已结束运行，但最新回复还未同步到本地记录。", en: "Hermes finished the run, but the latest reply has not reached local transcript storage yet.")
            tasks[index].availableActions = [.openWorkspace]
        }
        persistClientState()
    }

    private func handleObservationInterruption(
        forTaskID taskID: String,
        runID: String,
        attempt: Int,
        maxAttempts: Int,
        reason: String
    ) async -> Bool {
        guard shouldKeepObserving(taskID: taskID) else {
            return false
        }

        await refreshTranscripts(forTaskID: taskID, force: true)
        if let task = tasks.first(where: { $0.taskID == taskID }), task.runID == nil {
            return false
        }

        if attempt <= maxAttempts {
            apply(
                event: HermesRunEvent(
                    type: .observationReconnecting,
                    runID: runID,
                    timestamp: .now,
                    message: "Reconnecting to Hermes live updates (attempt \(attempt) of \(maxAttempts)). Last transport error: \(reason)"
                ),
                toTaskID: taskID
            )

            let seconds = UInt64(min(pow(2.0, Double(max(0, attempt - 1))), 4.0))
            do {
                try await Swift.Task.sleep(nanoseconds: seconds * 1_000_000_000)
            } catch {
                return false
            }
            return shouldKeepObserving(taskID: taskID)
        }

        apply(
            event: HermesRunEvent(
                type: .observationDisconnected,
                runID: runID,
                timestamp: .now,
                message: "Live updates paused after \(maxAttempts) reconnect attempts. Last transport error: \(reason)"
            ),
            toTaskID: taskID
        )
        return false
    }

    private func shouldKeepObserving(taskID: String) -> Bool {
        guard let task = tasks.first(where: { $0.taskID == taskID }) else {
            return false
        }
        return task.state.isTerminal == false && task.runID != nil
    }

    private func clearRunEventObserver(taskID: String, sessionToken: UUID) {
        guard runEventSessionTokens[taskID] == sessionToken else {
            return
        }
        runEventTasks[taskID] = nil
        runEventSessionTokens[taskID] = nil
    }

    private func apply(event: HermesRunEvent, toTaskID taskID: String) {
        guard let index = tasks.firstIndex(where: { $0.taskID == taskID }) else {
            return
        }

        let sessionID = tasks[index].effectiveSessionID
        switch event.type {
        case .observationReconnecting, .observationDisconnected:
            break
        default:
            materializePendingOutgoingMessages(for: taskID)
        }

        tasks[index].apply(hermesEvent: event)
        if event.type == .runCompleted || event.type == .runFailed || event.type == .runInterrupted {
            tasks[index].runID = nil
            tasks[index].pendingAction = nil
            tasks[index].pendingActionStartedAt = nil
            tasks[index].runState.observationState = .live
            tasks[index].runState.observationMessage = nil
        }

        if let sessionID {
            switch event.type {
            case .messageDelta:
                let content = tasks[index].output.trimmingCharacters(in: .whitespacesAndNewlines)
                if content.isEmpty == false {
                    upsertStreamingAssistantMessage(
                        for: taskID,
                        sessionID: sessionID,
                        content: content,
                        timestamp: event.timestamp
                    )
                }
            case .runCompleted:
                let content = (event.output ?? tasks[index].output).trimmingCharacters(in: .whitespacesAndNewlines)
                if content.isEmpty == false {
                    upsertStreamingAssistantMessage(
                        for: taskID,
                        sessionID: sessionID,
                        content: content,
                        timestamp: event.timestamp
                    )
                }
            case .runFailed, .runInterrupted:
                break
            case .reasoningAvailable, .toolStarted, .toolCompleted, .approvalRequested, .approvalResolved, .observationReconnecting, .observationDisconnected:
                break
            }
        }

        if tasks[index].pendingAction == nil {
            liveActionRequestTokens[taskID] = nil
        }
        if tasks[index].isPreview == false, event.type == .runCompleted {
            tasks[index].artifact = nil
            tasks[index].availableActions = [.openWorkspace]
        }
        if tasks[index].state.isTerminal {
            liveActionRequestTokens[taskID] = nil
            runEventTasks[taskID]?.cancel()
            runEventTasks[taskID] = nil
            runEventSessionTokens[taskID] = nil
        }

        if sessionID != nil,
           event.type == .runCompleted || event.type == .runFailed || event.type == .runInterrupted {
            Swift.Task { [weak self] in
                await self?.refreshTranscripts(forTaskID: taskID, force: true)
            }
        } else if let task = tasks.first(where: { $0.taskID == taskID }) {
            reconcilePendingOutgoingMessages(for: task)
            rebuildWorkspaceMessagesCache(for: task)
            persistClientState()
        }
    }

    private func performLiveTaskAction(_ action: TaskAction, task: Task) {
        guard let runID = task.runID else {
            taskActionFeedback = "This live task is missing a Hermes run ID."
            return
        }

        let request: HermesRunActionRequest
        switch action {
        case .approveOnce:
            request = HermesRunActionRequest(action: .approveOnce, approvalID: task.runState.approvalID)
        case .approveForTask:
            request = HermesRunActionRequest(action: .approveForTask, approvalID: task.runState.approvalID)
        case .reject:
            request = HermesRunActionRequest(action: .reject, approvalID: task.runState.approvalID)
        case .retry:
            request = HermesRunActionRequest(action: .retry)
        case .stop:
            request = HermesRunActionRequest(action: .stop)
        case .resume, .pause:
            taskActionFeedback = liveActionUnavailableMessage(for: action)
            return
        case .openTerminal, .openWorkspace, .copyResult:
            return
        }

        let requestToken = UUID()
        liveActionRequestTokens[task.taskID] = requestToken
        if let index = tasks.firstIndex(where: { $0.taskID == task.taskID }) {
            tasks[index].pendingAction = action
            tasks[index].pendingActionStartedAt = .now
            tasks[index].updatedAt = .now
        }

        taskActionFeedback = nil
        Swift.Task { [weak self] in
            guard let self else { return }
            do {
                guard let taskBackend = self.backend(forTaskID: task.taskID) else {
                    return
                }
                let response = try await taskBackend.performRunAction(runID: runID, request: request)
                await MainActor.run {
                    guard self.liveActionRequestTokens[task.taskID] == requestToken else { return }
                    self.handleLiveActionResponse(response, action: action, originalTask: task)
                }
            } catch {
                await MainActor.run {
                    guard self.liveActionRequestTokens[task.taskID] == requestToken else { return }
                    self.liveActionRequestTokens[task.taskID] = nil
                    if let index = self.tasks.firstIndex(where: { $0.taskID == task.taskID }) {
                        self.tasks[index].pendingAction = nil
                        self.tasks[index].pendingActionStartedAt = nil
                    }
                    self.taskActionFeedback = error.localizedDescription
                }
            }
        }
    }

    private func handleLiveActionResponse(
        _ response: HermesRunActionResponse,
        action: TaskAction,
        originalTask: Task
    ) {
        switch action {
        case .retry:
            liveActionRequestTokens[originalTask.taskID] = nil
            if let originalIndex = tasks.firstIndex(where: { $0.taskID == originalTask.taskID }) {
                tasks[originalIndex].pendingAction = nil
                tasks[originalIndex].pendingActionStartedAt = nil
                tasks[originalIndex].runID = response.runID
                tasks[originalIndex].runState.state = .running
                tasks[originalIndex].runState.phaseLabel = text(zh: "重试中", en: "Retrying")
                tasks[originalIndex].runState.progressHint = text(zh: "新的运行已在当前任务下启动。", en: "A replacement run was launched within the current task.")
                tasks[originalIndex].currentSummary = text(zh: "已发起重试，继续关注当前任务即可。", en: "Retry requested. Continue following this task.")
                tasks[originalIndex].availableActions = [.stop, .openWorkspace]
                tasks[originalIndex].updatedAt = .now
                selectedTaskID = tasks[originalIndex].taskID
                connectRunEvents(taskID: tasks[originalIndex].taskID, runID: response.runID)
            }
            taskActionFeedback = text(zh: "已在当前任务下启动新的重试运行。", en: "Started a retry run within the current task.")

        case .approveOnce, .approveForTask:
            if let originalIndex = tasks.firstIndex(where: { $0.taskID == originalTask.taskID }) {
                tasks[originalIndex].pendingAction = nil
                tasks[originalIndex].pendingActionStartedAt = nil
                tasks[originalIndex].runState.progressHint = "Approval decision sent to Hermes. Waiting for the run to continue."
                tasks[originalIndex].currentSummary = action == .approveForTask
                    ? "Approval sent for the current task scope."
                    : "Approval sent for one-time execution."
                tasks[originalIndex].updatedAt = .now
            }
            taskActionFeedback = action == .approveForTask
                ? "Approval sent to Hermes for the current task scope."
                : "Approval sent to Hermes for one-time execution."

        case .reject:
            if let originalIndex = tasks.firstIndex(where: { $0.taskID == originalTask.taskID }) {
                tasks[originalIndex].pendingAction = nil
                tasks[originalIndex].pendingActionStartedAt = nil
                tasks[originalIndex].runState.progressHint = "Rejection sent to Hermes. Waiting for the task to settle into a failed state."
                tasks[originalIndex].currentSummary = "Approval rejection sent. Hermes should stop this risky step."
                tasks[originalIndex].updatedAt = .now
            }
            taskActionFeedback = "Rejection sent to Hermes."

        case .stop:
            if let originalIndex = tasks.firstIndex(where: { $0.taskID == originalTask.taskID }) {
                tasks[originalIndex].pendingAction = nil
                tasks[originalIndex].pendingActionStartedAt = nil
                tasks[originalIndex].runState.phaseLabel = "Stopping…"
                tasks[originalIndex].runState.progressHint = "Stop request sent from Hermes Desk. Waiting for Hermes to interrupt the run."
                tasks[originalIndex].availableActions = [.openWorkspace]
                tasks[originalIndex].updatedAt = .now
            }
            taskActionFeedback = "Stop request sent to Hermes."

        case .resume, .pause, .openTerminal, .openWorkspace, .copyResult:
            break
        }
        persistClientState()
    }

    private func applyPreviewAction(_ action: TaskAction, toTaskAt index: Int) {
        var task = tasks[index]
        let timestamp = Date()

        switch action {
        case .approveOnce, .approveForTask:
            task.runState.state = .running
            task.runState.phaseLabel = action == .approveForTask ? "Approval granted for task" : "Approval granted"
            task.runState.progressHint = "Preview task resumed after the approval decision."
            task.runState.failureCategory = nil
            task.runState.failureMessage = nil
            task.runState.waitingReason = nil
            task.currentSummary = "Approval recorded. The preview task is back in motion."
            task.availableActions = [.stop, .openWorkspace]
            taskActionFeedback = action == .approveForTask
                ? "Preview approval granted for the rest of this sample task."
                : "Preview approval granted once."
            appendLocalEvent(
                to: &task,
                type: .confirm,
                timestamp: timestamp,
                summary: action == .approveForTask ? "Approved for task" : "Approved once",
                detail: "Preview-only action. Live Hermes approval resolution is not wired yet."
            )

        case .reject:
            task.runState.state = .failed
            task.runState.phaseLabel = "Approval rejected"
            task.runState.progressHint = nil
            task.runState.failureCategory = .approvalRejected
            task.runState.failureMessage = "You rejected the preview approval request."
            task.runState.waitingReason = nil
            task.currentSummary = "Approval rejected. The preview task is blocked until you retry it."
            task.availableActions = [.retry, .openTerminal, .openWorkspace]
            taskActionFeedback = "Preview approval rejected."
            appendLocalEvent(
                to: &task,
                type: .confirm,
                timestamp: timestamp,
                summary: "Rejected approval request",
                detail: "Preview-only action. Live Hermes approval resolution is not wired yet."
            )

        case .retry:
            task.runState.state = .running
            task.runState.phaseLabel = "Retrying preview task"
            task.runState.progressHint = "Preview retry requested from the task detail panel."
            task.runState.failureCategory = nil
            task.runState.failureMessage = nil
            task.runState.waitingReason = nil
            task.currentSummary = "Retry requested. The preview task is running again."
            task.availableActions = [.stop, .openWorkspace]
            taskActionFeedback = "Preview task moved back into running state."
            appendLocalEvent(
                to: &task,
                type: .stateChange,
                timestamp: timestamp,
                summary: "Retry requested",
                detail: "Preview-only action. Live Hermes retry is not wired yet."
            )

        case .resume:
            task.runState.state = .running
            task.runState.phaseLabel = "Preview task resumed"
            task.runState.progressHint = "Preview task resumed from the paused queue."
            task.runState.waitingReason = nil
            task.currentSummary = "Resume requested. The preview task is active again."
            task.availableActions = [.pause, .stop, .openWorkspace]
            taskActionFeedback = "Preview task resumed."
            appendLocalEvent(
                to: &task,
                type: .stateChange,
                timestamp: timestamp,
                summary: "Resumed task",
                detail: "Preview-only action. Live Hermes resume is not wired yet."
            )

        case .pause:
            task.runState.state = .paused
            task.runState.phaseLabel = "Paused from task detail"
            task.runState.progressHint = nil
            task.runState.waitingReason = "Paused from Hermes Desk preview controls"
            task.currentSummary = "Pause requested. The preview task is waiting to be resumed."
            task.availableActions = [.resume, .openWorkspace]
            taskActionFeedback = "Preview task paused."
            appendLocalEvent(
                to: &task,
                type: .stateChange,
                timestamp: timestamp,
                summary: "Paused task",
                detail: "Preview-only action. Live Hermes pause is not wired yet."
            )

        case .stop:
            task.runState.state = .cancelled
            task.runState.phaseLabel = "Stopped from task detail"
            task.runState.progressHint = nil
            task.runState.waitingReason = nil
            task.currentSummary = "Stop requested. The preview task has been cancelled."
            task.availableActions = [.openWorkspace]
            taskActionFeedback = "Preview task stopped."
            appendLocalEvent(
                to: &task,
                type: .stateChange,
                timestamp: timestamp,
                summary: "Stopped task",
                detail: "Preview-only action. Live Hermes stop is not wired yet."
            )

        case .openTerminal, .openWorkspace, .copyResult:
            return
        }

        task.updatedAt = timestamp
        task.runState.lastEventAt = timestamp
        tasks[index] = task
        persistClientState()
    }

    private func appendLocalEvent(
        to task: inout Task,
        type: EventType,
        timestamp: Date,
        summary: String,
        detail: String?
    ) {
        let nextSequence = (task.taskEvents.last?.seq ?? 0) + 1
        task.taskEvents.append(
            TaskEvent(
                eventID: "\(task.taskID)-local-\(nextSequence)-\(type.rawValue)",
                taskID: task.taskID,
                sessionID: task.sessionID,
                runID: task.runID,
                type: type,
                seq: nextSequence,
                timestamp: timestamp,
                summary: summary,
                detail: detail,
                capabilitySnapshot: task.capabilities
            )
        )
        if task.taskEvents.count > 40 {
            task.taskEvents.removeFirst(task.taskEvents.count - 40)
        }
    }

    private func reveal(path: String?) {
        guard let path, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func openTerminal(at path: String?) -> Bool {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private func liveActionUnavailableMessage(for action: TaskAction) -> String {
        switch action {
        case .resume:
            return "Live Hermes resume is not wired in Hermes Desk yet."
        case .pause:
            return "Live Hermes pause is not wired in Hermes Desk yet."
        case .approveOnce, .approveForTask, .reject, .retry, .stop, .openTerminal, .openWorkspace, .copyResult:
            return ""
        }
    }

    private func timedOutPendingActionMessage(for action: TaskAction, task: Task) -> String {
        switch action {
        case .approveOnce, .approveForTask:
            return "Hermes has not confirmed the approval yet. Reconnect the live feed or reopen the task timeline before deciding whether to send it again."
        case .reject:
            return "Hermes has not confirmed the rejection yet. Reconnect the live feed or reopen the task timeline before retrying the rejection."
        case .retry:
            return "Hermes has not confirmed the replacement run yet. Refresh or retry again if no new run appears."
        case .stop:
            return task.runState.observationState == .live
                ? "Hermes has not confirmed the stop request yet. Refresh the task timeline before sending another stop."
                : "Hermes has not confirmed the stop request yet and the live feed is interrupted. Reconnect the feed before retrying."
        case .resume, .pause, .openTerminal, .openWorkspace, .copyResult:
            return "Hermes has not confirmed the last action yet."
        }
    }

    private func pendingActionReconcileTitle(for action: TaskAction) -> String {
        switch action {
        case .approveOnce:
            return "allow once"
        case .approveForTask:
            return "allow task"
        case .reject:
            return "reject"
        case .retry:
            return "retry"
        case .stop:
            return "stop"
        case .resume:
            return "resume"
        case .pause:
            return "pause"
        case .openTerminal:
            return "open terminal"
        case .openWorkspace:
            return "open workspace"
        case .copyResult:
            return "copy result"
        }
    }

    private func upsertTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.taskID == task.taskID }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        persistClientState()
    }

    private func resolvedTaskTitle(customTitle: String?, prompt: String) -> String {
        if let customTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           customTitle.isEmpty == false,
           Task.isGenericWorkspaceTitle(customTitle) == false {
            return customTitle
        }

        return Task.summarizedWorkspaceTitle(from: prompt)
    }

    #if DEBUG
    func refreshTranscriptsForTesting(taskID: Task.ID, force: Bool = true) async {
        await refreshTranscripts(forTaskID: taskID, force: force)
    }

    func materializeAssistantReplyForTesting(
        taskID: Task.ID,
        content: String,
        timestamp: Date = .now
    ) {
        guard let index = tasks.firstIndex(where: { $0.taskID == taskID }),
              let sessionID = tasks[index].effectiveSessionID,
              let cacheKey = primaryTranscriptCacheKey(for: tasks[index], sessionID: sessionID) else {
            return
        }

        var messages = transcriptMessagesByCacheKey[cacheKey] ?? []
        for pendingMessage in pendingOutgoingMessagesByTaskID[taskID] ?? [] {
            let userMessage = HermesConversationMessage(
                id: nextLocalMessageID(),
                sessionID: pendingMessage.sessionID,
                role: .user,
                content: pendingMessage.content,
                timestamp: pendingMessage.timestamp
            )
            let fingerprint = workspaceMessageFingerprint(for: userMessage)
            if messages.contains(where: { workspaceMessageFingerprint(for: $0) == fingerprint }) == false {
                messages.append(userMessage)
            }
        }

        let lastTimestamp = messages.last?.timestamp
        let adjustedTimestamp: Date
        if let lastTimestamp, timestamp <= lastTimestamp {
            adjustedTimestamp = lastTimestamp.addingTimeInterval(0.001)
        } else {
            adjustedTimestamp = timestamp
        }
        messages.append(
            HermesConversationMessage(
                id: nextLocalMessageID(),
                sessionID: sessionID,
                role: .assistant,
                content: content,
                timestamp: adjustedTimestamp
            )
        )
        transcriptMessagesByCacheKey[cacheKey] = messages.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id < rhs.id
        }
        transcriptHasOlderByCacheKey[cacheKey] = false
        pendingOutgoingMessagesByTaskID.removeValue(forKey: taskID)
        tasks[index].runID = nil
        tasks[index].artifact = nil
        tasks[index].availableActions = [.openWorkspace]
        tasks[index].runState.state = .running
        tasks[index].runState.phaseLabel = text(zh: "对话已更新", en: "Conversation updated")
        tasks[index].runState.progressHint = nil
        tasks[index].runState.observationState = .live
        tasks[index].runState.observationMessage = nil
        tasks[index].currentSummary = content.count > 180 ? String(content.prefix(180)) + "…" : content
        tasks[index].output = content
        rebuildWorkspaceMessagesCache(for: tasks[index])
        refreshTaskTitleIfNeeded(forTaskID: taskID)
        persistClientState()
    }
    #endif
}

extension TaskState {
    var localizedDisplayTitle: String {
        switch self {
        case .queued:
            return HermesDeskL10n.text(zh: "排队中", en: "Queued")
        case .running:
            return HermesDeskL10n.text(zh: "进行中", en: "Running")
        case .waitingUser:
            return HermesDeskL10n.text(zh: "待确认", en: "Waiting User")
        case .paused:
            return HermesDeskL10n.text(zh: "已暂停", en: "Paused")
        case .failed:
            return HermesDeskL10n.text(zh: "失败", en: "Failed")
        case .succeeded:
            return HermesDeskL10n.text(zh: "已完成", en: "Completed")
        case .cancelled:
            return HermesDeskL10n.text(zh: "已停止", en: "Cancelled")
        }
    }
}

extension TaskAction {
    var localizedDisplayTitle: String {
        switch self {
        case .approveOnce:
            return HermesDeskL10n.text(zh: "允许一次", en: "Allow once")
        case .approveForTask:
            return HermesDeskL10n.text(zh: "本任务允许", en: "Allow for task")
        case .reject:
            return HermesDeskL10n.text(zh: "拒绝", en: "Reject")
        case .retry:
            return HermesDeskL10n.text(zh: "重试", en: "Retry")
        case .stop:
            return HermesDeskL10n.text(zh: "停止", en: "Stop")
        case .resume:
            return HermesDeskL10n.text(zh: "继续", en: "Resume")
        case .pause:
            return HermesDeskL10n.text(zh: "暂停", en: "Pause")
        case .openTerminal:
            return HermesDeskL10n.text(zh: "打开终端", en: "Open terminal")
        case .openWorkspace:
            return HermesDeskL10n.text(zh: "打开工作区", en: "Open workspace")
        case .copyResult:
            return HermesDeskL10n.text(zh: "复制结果", en: "Copy result")
        }
    }
}

extension FailureCategory {
    var localizedDisplayTitle: String {
        switch self {
        case .connectionError:
            return HermesDeskL10n.text(zh: "连接异常", en: "Connection issue")
        case .toolError:
            return HermesDeskL10n.text(zh: "工具错误", en: "Tool error")
        case .approvalRejected:
            return HermesDeskL10n.text(zh: "确认被拒绝", en: "Approval rejected")
        case .approvalExpired:
            return HermesDeskL10n.text(zh: "确认已过期", en: "Approval expired")
        case .validationError:
            return HermesDeskL10n.text(zh: "输入校验失败", en: "Validation error")
        case .dependencyError:
            return HermesDeskL10n.text(zh: "依赖异常", en: "Dependency issue")
        case .unknownError:
            return HermesDeskL10n.text(zh: "未知错误", en: "Unknown error")
        }
    }
}

private enum SubscriptionRestoreReason {
    case appLaunch
    case healthRefresh

    var statusMessage: String {
        switch self {
        case .appLaunch:
            return "Restoring the live Hermes feed after Hermes Desk launch."
        case .healthRefresh:
            return "Hermes is back online. Restoring the live task feed."
        }
    }
}

private enum RunLaunchValidationError: LocalizedError {
    case emptyPrompt
    case alreadyStarting
    case apiKeyMissing
    case unmanagedConversation

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Enter a task for Hermes before starting the run."
        case .alreadyStarting:
            return "Hermes is already starting another task."
        case .apiKeyMissing:
            return "The current agent runtime is missing API_SERVER_KEY, so Hermes Desk cannot send runs yet."
        case .unmanagedConversation:
            return "Only conversations created by Hermes Desk can continue inside this app."
        }
    }
}
