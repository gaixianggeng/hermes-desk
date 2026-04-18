import Foundation
import HermesKit

public enum TaskSource: String, Codable, Sendable, CaseIterable {
    case manual
    case shortcut
    case scheduled
    case restored
}

public enum TaskState: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case waitingUser = "waiting_user"
    case paused
    case failed
    case succeeded
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

public enum TaskAction: String, Codable, Sendable, CaseIterable {
    case approveOnce = "approve_once"
    case approveForTask = "approve_for_task"
    case reject
    case retry
    case resume
    case pause
    case stop
    case openTerminal = "open_terminal"
    case openWorkspace = "open_workspace"
    case copyResult = "copy_result"
}

public enum FailureCategory: String, Codable, Sendable, CaseIterable {
    case connectionError = "connection_error"
    case toolError = "tool_error"
    case approvalRejected = "approval_rejected"
    case approvalExpired = "approval_expired"
    case validationError = "validation_error"
    case dependencyError = "dependency_error"
    case unknownError = "unknown_error"
}

public enum RunObservationState: String, Codable, Equatable, Sendable, CaseIterable {
    case live
    case reconnecting
    case disconnected
}

public enum TaskSessionStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case running
    case open
    case archived
}

public struct RunState: Codable, Equatable, Sendable {
    public var state: TaskState
    public var phaseLabel: String
    public var lastEventAt: Date
    public var progressHint: String?
    public var failureCategory: FailureCategory?
    public var failureMessage: String?
    public var waitingReason: String?
    public var approvalID: String?
    public var observationState: RunObservationState
    public var observationMessage: String?

    public init(
        state: TaskState,
        phaseLabel: String,
        lastEventAt: Date,
        progressHint: String? = nil,
        failureCategory: FailureCategory? = nil,
        failureMessage: String? = nil,
        waitingReason: String? = nil,
        approvalID: String? = nil,
        observationState: RunObservationState = .live,
        observationMessage: String? = nil
    ) {
        self.state = state
        self.phaseLabel = phaseLabel
        self.lastEventAt = lastEventAt
        self.progressHint = progressHint
        self.failureCategory = failureCategory
        self.failureMessage = failureMessage
        self.waitingReason = waitingReason
        self.approvalID = approvalID
        self.observationState = observationState
        self.observationMessage = observationMessage
    }
}

public struct Task: Codable, Equatable, Sendable, Identifiable {
    public var taskID: String
    public var title: String
    public var source: TaskSource
    public var agentID: String
    public var sessionID: String?
    public var rootSessionID: String?
    public var currentSessionID: String?
    public var sessionSource: String?
    public var sessionLineage: [HermesSessionDescriptor]
    public var runID: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var requestText: String?
    public var currentSummary: String
    public var output: String
    public var taskEvents: [TaskEvent]
    public var availableActions: [TaskAction]
    public var capabilities: AgentCapability
    public var runState: RunState
    public var artifact: Artifact?
    public var pendingAction: TaskAction?
    public var pendingActionStartedAt: Date?
    public var retryParentTaskID: String?
    public var retryChildTaskID: String?
    public var isPreview: Bool

    public init(
        taskID: String,
        title: String,
        source: TaskSource = .manual,
        agentID: String = "hermes",
        sessionID: String? = nil,
        rootSessionID: String? = nil,
        currentSessionID: String? = nil,
        sessionSource: String? = nil,
        sessionLineage: [HermesSessionDescriptor] = [],
        runID: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        requestText: String? = nil,
        currentSummary: String,
        output: String = "",
        taskEvents: [TaskEvent] = [],
        availableActions: [TaskAction] = [],
        capabilities: AgentCapability = AgentCapability(),
        runState: RunState,
        artifact: Artifact? = nil,
        pendingAction: TaskAction? = nil,
        pendingActionStartedAt: Date? = nil,
        retryParentTaskID: String? = nil,
        retryChildTaskID: String? = nil,
        isPreview: Bool = false
    ) {
        self.taskID = taskID
        self.title = title
        self.source = source
        self.agentID = agentID
        self.sessionID = sessionID
        self.rootSessionID = rootSessionID ?? sessionID
        self.currentSessionID = currentSessionID ?? sessionID
        let trimmedSessionSource = sessionSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionSource = trimmedSessionSource?.isEmpty == false ? trimmedSessionSource : nil
        self.sessionLineage = sessionLineage
        self.runID = runID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.requestText = requestText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentSummary = currentSummary
        self.output = output
        self.taskEvents = taskEvents
        self.availableActions = availableActions
        self.capabilities = capabilities
        self.runState = runState
        self.artifact = artifact
        self.pendingAction = pendingAction
        self.pendingActionStartedAt = pendingActionStartedAt
        self.retryParentTaskID = retryParentTaskID
        self.retryChildTaskID = retryChildTaskID
        self.isPreview = isPreview
    }

    public var id: String { taskID }
    public var state: TaskState { runState.state }
    public var effectiveSessionID: String? { currentSessionID ?? sessionID ?? rootSessionID }
    public var normalizedSessionSource: String? { sessionSource?.lowercased() }
    public var canContinueInWorkspaceConversation: Bool {
        effectiveSessionID != nil
    }
    public var sessionBindingSummary: String? {
        guard let effectiveSessionID else {
            return nil
        }
        if let rootSessionID, rootSessionID != effectiveSessionID {
            return "Current: \(effectiveSessionID) · Root: \(rootSessionID)"
        }
        return "Current: \(effectiveSessionID)"
    }
    public var sessionLineageSummary: String? {
        let sessionIDs = sessionLineage.map(\.sessionID)
        guard sessionIDs.isEmpty == false else {
            return effectiveSessionID
        }
        return sessionIDs.joined(separator: " → ")
    }

    public var rootSessionDescriptor: HermesSessionDescriptor? {
        sessionLineage.first
    }

    public var rootSessionEndedAt: Date? {
        rootSessionDescriptor?.endedAt
    }

    public var isArchivedBySession: Bool {
        rootSessionEndedAt != nil
    }

    public var sessionStatus: TaskSessionStatus {
        if isArchivedBySession {
            return .archived
        }
        if runID != nil || pendingAction != nil || state == .waitingUser || runState.observationState != .live {
            return .running
        }
        return .open
    }

    public var latestOutputSummary: String? {
        guard output.isEmpty == false else {
            return nil
        }

        if output.count <= 320 {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let suffix = String(output.suffix(320)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard suffix.isEmpty == false else {
            return nil
        }
        return "…\(suffix)"
    }

    public func shouldDisplayMessageInWorkspace(
        _ message: HermesConversationMessage,
        mode: HermesWorkspaceTranscriptMode
    ) -> Bool {
        switch mode {
        case .conversation:
            return shouldDisplayMessageInWorkspaceConversation(message)
        case .full:
            return message.shouldDisplayInWorkspace(mode: .full)
        }
    }

    public func shouldDisplayMessageInWorkspaceConversation(_ message: HermesConversationMessage) -> Bool {
        guard message.displayText.isEmpty == false else {
            return false
        }

        if message.role == .assistant {
            // API-backed assistant replies and locally streamed drafts should stay visible in
            // the main conversation even if the generic classifier mistakes them for progress.
            if message.id < 0 || normalizedSessionSource == "api_server" {
                return true
            }
        }

        return message.shouldDisplayInWorkspaceConversation
    }

    public var statusContextLine: String? {
        if let pendingAction {
            return "\(pendingAction.pendingStatusIndicator) \(pendingAction.pendingStatusTitle)"
        }
        if let observationMessage = runState.observationStatusLine {
            return observationMessage
        }
        if let retryChildTaskID, retryChildTaskID.isEmpty == false {
            return "🔁 Replacement run: \(retryChildTaskID)"
        }
        if let retryParentTaskID, retryParentTaskID.isEmpty == false {
            return "↩️ Retried from: \(retryParentTaskID)"
        }
        return nil
    }

    public var menuBarInlineActions: [TaskAction] {
        switch state {
        case .waitingUser:
            return availableActions.filter {
                switch $0 {
                case .approveOnce, .approveForTask, .reject:
                    return true
                default:
                    return false
                }
            }
        case .failed:
            return availableActions.filter {
                switch $0 {
                case .retry, .openTerminal, .openWorkspace:
                    return true
                default:
                    return false
                }
            }
        default:
            return []
        }
    }

    public var supportsMenuBarReconnect: Bool {
        isPreview == false && state.isTerminal == false && runState.observationState != .live
    }

    public func hasTimedOutPendingAction(asOf now: Date = .now, timeout: TimeInterval = 20) -> Bool {
        guard pendingAction != nil, let pendingActionStartedAt else {
            return false
        }

        return now.timeIntervalSince(pendingActionStartedAt) >= timeout
    }
}

public extension Task {
    static func liveHermesTask(
        taskID: String = UUID().uuidString,
        title: String,
        input: String,
        runID: String,
        sessionID: String? = nil,
        agentID: String = "hermes",
        createdAt: Date = .now
    ) -> Task {
        Task(
            taskID: taskID,
            title: title,
            source: .manual,
            agentID: agentID,
            sessionID: sessionID,
            rootSessionID: sessionID,
            currentSessionID: sessionID,
            sessionSource: "api_server",
            sessionLineage: sessionID.map { [HermesSessionDescriptor(sessionID: $0)] } ?? [],
            runID: runID,
            createdAt: createdAt,
            updatedAt: createdAt,
            requestText: input,
            currentSummary: input,
            availableActions: [.stop, .openWorkspace],
            runState: RunState(
                state: .running,
                phaseLabel: "Run started",
                lastEventAt: createdAt,
                progressHint: "Connecting to Hermes event stream"
            )
        )
    }

    static func isGenericWorkspaceTitle(_ title: String) -> Bool {
        let normalized = title.taskTitleSourceText.lowercased()
        return [
            "hermes task",
            "build with hermes",
            "review with hermes",
            "analyze with hermes"
        ].contains(normalized)
    }

    static func summarizedWorkspaceTitle(from prompt: String, fallback: String = "Hermes Task") -> String {
        let normalized = prompt.taskTitleSourceText
        guard normalized.isEmpty == false else {
            return fallback
        }

        var candidate = normalized.removingTaskPolitePrefix()
        if candidate.hasPrefix("在"), candidate.contains("，可以") {
            candidate = String(candidate.dropFirst())
                .replacingOccurrences(of: "，可以", with: "")
        }

        candidate = candidate
            .replacingOccurrences(of: "，请", with: "")
            .replacingOccurrences(of: ", please", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: ", can you", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: ", could you", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentence = candidate.taskLeadingSentence
        var title = sentence

        if title.count > 18, let firstClause = sentence.taskLeadingClause {
            title = firstClause
        }
        if title.count > 22, let leadingEnglishClause = title.taskLeadingEnglishClause {
            title = leadingEnglishClause
        }

        title = title
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .taskTitleSourceText

        if title.count < 4 {
            title = normalized.taskLeadingSentence.taskTitleSourceText
        }
        if title.isEmpty {
            title = fallback
        }

        return title.taskClampedTitle(maxLength: 30, fallback: fallback)
    }

    static func shouldAutoRefreshWorkspaceTitle(currentTitle: String, requestText: String?) -> Bool {
        guard let requestText = requestText?.taskTitleSourceText, requestText.isEmpty == false else {
            return isGenericWorkspaceTitle(currentTitle)
        }

        return isGenericWorkspaceTitle(currentTitle)
            || currentTitle.taskTitleSourceText == summarizedWorkspaceTitle(from: requestText).taskTitleSourceText
    }

    static func refreshedWorkspaceTitle(
        currentTitle: String,
        requestText: String?,
        resultText: String?,
        fallback: String = "Hermes Task"
    ) -> String? {
        guard shouldAutoRefreshWorkspaceTitle(currentTitle: currentTitle, requestText: requestText) else {
            return nil
        }

        let requestTitle = requestText.map { summarizedWorkspaceTitle(from: $0, fallback: fallback) } ?? fallback
        guard let resultText = resultText?.taskTitleSourceText, resultText.isEmpty == false else {
            return requestTitle == currentTitle ? nil : requestTitle
        }

        let refreshed = summarizedWorkspaceTitle(from: resultText, fallback: requestTitle)
        guard refreshed.taskTitleSourceText != currentTitle.taskTitleSourceText else {
            return nil
        }
        return refreshed
    }
}

public extension Sequence where Element == Task {
    func sortedForOverview() -> [Task] {
        sorted { lhs, rhs in
            let leftRank = overviewRank(for: lhs.state)
            let rightRank = overviewRank(for: rhs.state)

            if leftRank != rightRank {
                return leftRank < rightRank
            }

            if lhs.isPreview != rhs.isPreview {
                return lhs.isPreview == false
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func sortedForAttention() -> [Task] {
        sorted { lhs, rhs in
            let leftRank = attentionRank(for: lhs)
            let rightRank = attentionRank(for: rhs)

            if leftRank != rightRank {
                return leftRank < rightRank
            }

            if lhs.isPreview != rhs.isPreview {
                return lhs.isPreview == false
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

public extension Task {
    static var previewTasks: [Task] {
        let now = Date()

        return [
            Task(
                taskID: "task_waiting_docs",
                title: "Preview: review risky git cleanup",
                createdAt: now.addingTimeInterval(-2_400),
                updatedAt: now.addingTimeInterval(-120),
                currentSummary: "Sample approval request for a destructive shell command while live Hermes task feeds are unavailable.",
                availableActions: [.approveOnce, .reject, .openTerminal],
                runState: RunState(
                    state: .waitingUser,
                    phaseLabel: "Approval requested",
                    lastEventAt: now.addingTimeInterval(-120),
                    waitingReason: "Destructive shell command"
                ),
                isPreview: true
            ),
            Task(
                taskID: "task_failed_tests",
                title: "Preview: recover failing build loop",
                createdAt: now.addingTimeInterval(-7_200),
                updatedAt: now.addingTimeInterval(-600),
                currentSummary: "Sample failed run kept in the inbox so retry and investigation flows can be reviewed.",
                availableActions: [.retry, .openTerminal],
                runState: RunState(
                    state: .failed,
                    phaseLabel: "Build failed",
                    lastEventAt: now.addingTimeInterval(-600),
                    failureCategory: .toolError,
                    failureMessage: "Swift build exited with a non-zero status."
                ),
                isPreview: true
            ),
            Task(
                taskID: "task_running_ui",
                title: "Preview: map menu bar UI to task model",
                createdAt: now.addingTimeInterval(-1_800),
                updatedAt: now.addingTimeInterval(-30),
                currentSummary: "Sample active work used to demonstrate in-progress cards and task detail routing.",
                availableActions: [.stop, .openWorkspace],
                runState: RunState(
                    state: .running,
                    phaseLabel: "Reviewing SwiftUI files",
                    lastEventAt: now.addingTimeInterval(-30),
                    progressHint: "Inspecting the app shell structure"
                ),
                isPreview: true
            ),
            Task(
                taskID: "task_queued_detail_panel",
                title: "Preview: prepare task detail panel",
                createdAt: now.addingTimeInterval(-1_500),
                updatedAt: now.addingTimeInterval(-300),
                currentSummary: "Sample queued work waiting behind the active task.",
                availableActions: [.openWorkspace],
                runState: RunState(
                    state: .queued,
                    phaseLabel: "Queued",
                    lastEventAt: now.addingTimeInterval(-300)
                ),
                isPreview: true
            ),
            Task(
                taskID: "task_paused_copy_review",
                title: "Preview: review dashboard copy updates",
                createdAt: now.addingTimeInterval(-3_000),
                updatedAt: now.addingTimeInterval(-900),
                currentSummary: "Sample paused task waiting for a content review before it resumes.",
                availableActions: [.resume, .openWorkspace],
                runState: RunState(
                    state: .paused,
                    phaseLabel: "Paused for review",
                    lastEventAt: now.addingTimeInterval(-900),
                    waitingReason: "Copy review"
                ),
                isPreview: true
            ),
            Task(
                taskID: "task_result_bootstrap",
                title: "Preview: bootstrap Hermes Desk skeleton",
                createdAt: now.addingTimeInterval(-14_400),
                updatedAt: now.addingTimeInterval(-1_200),
                currentSummary: "Sample completed task kept here to show how reusable results will look.",
                availableActions: [.copyResult, .openWorkspace],
                runState: RunState(
                    state: .succeeded,
                    phaseLabel: "Completed",
                    lastEventAt: now.addingTimeInterval(-1_200)
                ),
                artifact: Artifact(
                    summary: "Generated project scaffolding and shared package boundaries.",
                    keyOutputs: [
                        "XcodeGen config",
                        "AppCore models",
                        "Hermes health stub"
                    ],
                    files: [
                        FileReference(path: "project.yml"),
                        FileReference(path: "Packages/AppCore"),
                        FileReference(path: "Packages/HermesKit")
                    ],
                    nextActions: [
                        "Review the generated project in Xcode",
                        "Compare the preview result shape with the upcoming Hermes task feed"
                    ]
                ),
                isPreview: true
            ),
            Task(
                taskID: "task_cancelled_onboarding",
                title: "Preview: discarded onboarding draft",
                createdAt: now.addingTimeInterval(-8_400),
                updatedAt: now.addingTimeInterval(-2_100),
                currentSummary: "Sample cancelled task kept separate from completed results.",
                availableActions: [.openWorkspace],
                runState: RunState(
                    state: .cancelled,
                    phaseLabel: "Cancelled",
                    lastEventAt: now.addingTimeInterval(-2_100)
                ),
                isPreview: true
            )
        ]
    }
}

private func overviewRank(for state: TaskState) -> Int {
    switch state {
    case .waitingUser:
        return 0
    case .failed:
        return 1
    case .running:
        return 2
    case .queued, .paused:
        return 3
    case .succeeded:
        return 4
    case .cancelled:
        return 5
    }
}

private func attentionRank(for task: Task) -> Int {
    if task.state == .failed {
        return 0
    }
    if task.state == .waitingUser {
        return 1
    }
    if task.state.isTerminal == false, task.runState.observationState != .live {
        return 2
    }

    switch task.state {
    case .running:
        return 3
    case .queued, .paused:
        return 4
    case .succeeded:
        return 5
    case .cancelled:
        return 6
    case .waitingUser, .failed:
        return 7
    }
}

public extension TaskState {
    var statusIndicator: String {
        switch self {
        case .queued:
            return "🟣"
        case .running:
            return "🟢"
        case .waitingUser:
            return "🟠"
        case .paused:
            return "🟡"
        case .failed:
            return "🔴"
        case .succeeded:
            return "✅"
        case .cancelled:
            return "⚫️"
        }
    }
}

public extension TaskAction {
    var actionIndicator: String {
        switch self {
        case .approveOnce, .approveForTask:
            return "🟢"
        case .reject:
            return "🔴"
        case .retry:
            return "🔁"
        case .resume:
            return "▶️"
        case .pause:
            return "⏸️"
        case .stop:
            return "🛑"
        case .openTerminal:
            return "💻"
        case .openWorkspace:
            return "📁"
        case .copyResult:
            return "📋"
        }
    }
}

public extension RunState {
    var observationStatusLine: String? {
        guard let observationMessage, observationMessage.isEmpty == false else {
            return nil
        }

        switch observationState {
        case .live:
            return nil
        case .reconnecting:
            return "🟠 \(observationMessage)"
        case .disconnected:
            return "🔌 \(observationMessage)"
        }
    }
}

private extension TaskAction {
    var pendingStatusIndicator: String { actionIndicator }

    var pendingStatusTitle: String {
        switch self {
        case .approveOnce:
            return "Approval sent once — waiting for Hermes to continue."
        case .approveForTask:
            return "Task-scope approval sent — waiting for Hermes to continue."
        case .reject:
            return "Rejection sent — waiting for Hermes to stop this step."
        case .retry:
            return "Retry requested — launching a replacement run."
        case .stop:
            return "Stop requested — waiting for Hermes to finish the action."
        case .resume:
            return "Resume requested — waiting for Hermes to continue."
        case .pause:
            return "Pause requested — waiting for Hermes to acknowledge it."
        case .openTerminal, .openWorkspace, .copyResult:
            return displayTitleFallback
        }
    }

    private var displayTitleFallback: String {
        switch self {
        case .openTerminal:
            return "Open terminal"
        case .openWorkspace:
            return "Open workspace"
        case .copyResult:
            return "Copy result"
        default:
            return rawValue
        }
    }
}

private extension String {
    var taskTitleSourceText: String {
        replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removingTaskPolitePrefix() -> String {
        var result = taskTitleSourceText
        let patterns = [
            #"^(please|pls|can you|could you|would you|help me|i need you to|i want you to|please help me|please review|please summarize)\s+"#,
            #"^(请帮我|帮我|请你|请|麻烦你|麻烦|可以帮我|我希望|我想让你|我想|希望你|希望|现在请|继续|先帮我|先|再|然后|帮忙|帮忙把)\s*"#
        ]

        var didTrim = true
        while didTrim {
            didTrim = false
            for pattern in patterns {
                if let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    result.removeSubrange(range)
                    result = result.taskTitleSourceText
                    didTrim = true
                }
            }
        }
        return result
    }

    var taskLeadingSentence: String {
        let separators = CharacterSet(charactersIn: "\n。！？!?；;")
        let first = components(separatedBy: separators)
            .map(\.taskTitleSourceText)
            .first(where: { $0.isEmpty == false })
        return first ?? taskTitleSourceText
    }

    var taskLeadingClause: String? {
        let clauses = components(separatedBy: CharacterSet(charactersIn: "，,:：|/"))
            .map(\.taskTitleSourceText)
            .filter { $0.count >= 6 }
        return clauses.first
    }

    var taskLeadingEnglishClause: String? {
        let segments = split(separator: " ")
        guard segments.count > 3 else {
            return nil
        }

        let joiners: Set<String> = ["and", "then", "while", "with", "for"]
        var collected: [String] = []
        for segment in segments {
            let token = String(segment)
            if collected.count >= 5, joiners.contains(token.lowercased()) {
                break
            }
            collected.append(token)
            if collected.count >= 7 {
                break
            }
        }
        let title = collected.joined(separator: " ").taskTitleSourceText
        return title.isEmpty ? nil : title
    }

    func taskClampedTitle(maxLength: Int, fallback: String) -> String {
        let normalized = taskTitleSourceText
        guard normalized.isEmpty == false else {
            return fallback
        }
        guard normalized.count > maxLength else {
            return normalized
        }
        return String(normalized.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
