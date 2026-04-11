import AppCore
import HermesKit
import SwiftUI

@MainActor
final class AppStateStore: ObservableObject {
    @Published private(set) var connectionState: HermesConnectionState = .starting(message: "Waiting for first Hermes probe…")
    @Published private(set) var isRefreshing = false
    @Published private(set) var isStartingRun = false
    @Published var tasks: [Task] = Task.previewTasks
    @Published private(set) var selectedTaskID: Task.ID?
    @Published var runLaunchError: String?

    let backend: any AgentBackend
    private var runEventTasks: [String: Swift.Task<Void, Never>] = [:]

    init(backend: any AgentBackend = HermesLocalAdapter()) {
        self.backend = backend
        selectDefaultTaskIfNeeded()

        Swift.Task {
            await refreshHealth()
        }
    }

    deinit {
        runEventTasks.values.forEach { $0.cancel() }
    }

    var endpoint: HermesEndpoint {
        backend.endpoint
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
            return "Run a real Hermes task from the dashboard. Until then, sample tasks show the shape of the task workspace."
        }

        return "Live Hermes runs are driving the task board and detail pane."
    }

    var liveTasks: [Task] {
        tasks
            .filter { $0.isPreview == false }
            .sortedForOverview()
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
            .filter { $0.state == .running }
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
    var queuedCount: Int { queuedTasks.count }
    var inboxCount: Int { inboxTasks.count }
    var recentCount: Int { recentTasks.count }
    var cancelledCount: Int { cancelledTasks.count }

    func selectTask(_ task: Task?) {
        selectedTaskID = task?.taskID
    }

    func selectTask(id: Task.ID?) {
        selectedTaskID = id
    }

    func selectDefaultTaskIfNeeded() {
        guard selectedTask == nil else { return }
        selectedTaskID = prioritizedTasks.first?.taskID
    }

    func refreshHealth() async {
        guard isRefreshing == false else { return }

        isRefreshing = true
        connectionState = .starting(message: "Checking \(endpoint.displayName)…")
        connectionState = await backend.health()
        isRefreshing = false
    }

    func startHermesTask(title: String?, prompt: String) async throws {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.isEmpty == false else {
            throw RunLaunchValidationError.emptyPrompt
        }

        guard isStartingRun == false else {
            throw RunLaunchValidationError.alreadyStarting
        }

        isStartingRun = true
        runLaunchError = nil
        defer { isStartingRun = false }

        let sessionID = "agent-hub-\(UUID().uuidString)"
        do {
            let response = try await backend.startRun(
                input: trimmedPrompt,
                sessionID: sessionID,
                instructions: nil
            )

            let task = Task.liveHermesTask(
                title: resolvedTaskTitle(customTitle: title, prompt: trimmedPrompt),
                input: trimmedPrompt,
                runID: response.runID,
                sessionID: sessionID
            )
            upsertTask(task)
            selectedTaskID = task.taskID
            connectRunEvents(taskID: task.taskID, runID: response.runID)
        } catch {
            let message = error.localizedDescription
            runLaunchError = message
            throw error
        }
    }

    private var overviewTasks: [Task] {
        liveTasks.isEmpty ? previewTasks : liveTasks
    }

    private var prioritizedTasks: [Task] {
        overviewTasks
    }

    private func connectRunEvents(taskID: String, runID: String) {
        runEventTasks[taskID]?.cancel()
        runEventTasks[taskID] = Swift.Task { [weak self] in
            guard let self else { return }

            do {
                for try await event in backend.runEvents(for: runID) {
                    await self.apply(event: event, toTaskID: taskID)
                }
            } catch {
                await self.markStreamFailure(forTaskID: taskID, message: error.localizedDescription)
            }
        }
    }

    private func apply(event: HermesRunEvent, toTaskID taskID: String) {
        guard let index = tasks.firstIndex(where: { $0.taskID == taskID }) else {
            return
        }

        tasks[index].apply(hermesEvent: event)
        if tasks[index].state.isTerminal {
            runEventTasks[taskID]?.cancel()
            runEventTasks[taskID] = nil
        }
    }

    private func markStreamFailure(forTaskID taskID: String, message: String) {
        guard let task = tasks.first(where: { $0.taskID == taskID }), task.state.isTerminal == false else {
            return
        }

        apply(
            event: HermesRunEvent(
                type: .runFailed,
                runID: task.runID ?? taskID,
                timestamp: .now,
                failureMessage: message
            ),
            toTaskID: taskID
        )
    }

    private func upsertTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.taskID == task.taskID }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    private func resolvedTaskTitle(customTitle: String?, prompt: String) -> String {
        if let customTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), customTitle.isEmpty == false {
            return customTitle
        }

        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstLine, firstLine.isEmpty == false {
            if firstLine.count <= 72 {
                return firstLine
            }
            return String(firstLine.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }

        return "Hermes Task"
    }
}

private enum RunLaunchValidationError: LocalizedError {
    case emptyPrompt
    case alreadyStarting

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Enter a task for Hermes before starting the run."
        case .alreadyStarting:
            return "Hermes is already starting another task."
        }
    }
}
