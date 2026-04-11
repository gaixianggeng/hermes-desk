import Foundation

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
        case .succeeded, .cancelled:
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

public struct RunState: Codable, Equatable, Sendable {
    public var state: TaskState
    public var phaseLabel: String
    public var lastEventAt: Date
    public var progressHint: String?
    public var failureCategory: FailureCategory?
    public var failureMessage: String?
    public var waitingReason: String?

    public init(
        state: TaskState,
        phaseLabel: String,
        lastEventAt: Date,
        progressHint: String? = nil,
        failureCategory: FailureCategory? = nil,
        failureMessage: String? = nil,
        waitingReason: String? = nil
    ) {
        self.state = state
        self.phaseLabel = phaseLabel
        self.lastEventAt = lastEventAt
        self.progressHint = progressHint
        self.failureCategory = failureCategory
        self.failureMessage = failureMessage
        self.waitingReason = waitingReason
    }
}

public struct Task: Codable, Equatable, Sendable, Identifiable {
    public var taskID: String
    public var title: String
    public var source: TaskSource
    public var agentID: String
    public var sessionID: String?
    public var runID: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var currentSummary: String
    public var availableActions: [TaskAction]
    public var capabilities: AgentCapability
    public var runState: RunState
    public var artifact: Artifact?

    public init(
        taskID: String,
        title: String,
        source: TaskSource = .manual,
        agentID: String = "hermes",
        sessionID: String? = nil,
        runID: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        currentSummary: String,
        availableActions: [TaskAction] = [],
        capabilities: AgentCapability = AgentCapability(),
        runState: RunState,
        artifact: Artifact? = nil
    ) {
        self.taskID = taskID
        self.title = title
        self.source = source
        self.agentID = agentID
        self.sessionID = sessionID
        self.runID = runID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentSummary = currentSummary
        self.availableActions = availableActions
        self.capabilities = capabilities
        self.runState = runState
        self.artifact = artifact
    }

    public var id: String { taskID }
    public var state: TaskState { runState.state }
}

public extension Sequence where Element == Task {
    func sortedForOverview() -> [Task] {
        sorted { lhs, rhs in
            let leftRank = overviewRank(for: lhs.state)
            let rightRank = overviewRank(for: rhs.state)

            if leftRank != rightRank {
                return leftRank < rightRank
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
                )
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
                )
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
                )
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
                )
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
                )
            ),
            Task(
                taskID: "task_result_bootstrap",
                title: "Preview: bootstrap Agent Hub skeleton",
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
                )
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
                )
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
