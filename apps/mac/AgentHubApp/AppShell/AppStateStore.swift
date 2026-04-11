import AppCore
import HermesKit
import SwiftUI

@MainActor
final class AppStateStore: ObservableObject {
    @Published private(set) var connectionState: HermesConnectionState = .starting(message: "Waiting for first Hermes probe…")
    @Published private(set) var isRefreshing = false
    @Published var tasks: [Task] = Task.previewTasks
    @Published private(set) var selectedTaskID: Task.ID?

    let backend: any AgentBackend

    init(backend: any AgentBackend = HermesLocalAdapter()) {
        self.backend = backend
        selectDefaultTaskIfNeeded()

        Swift.Task {
            await refreshHealth()
        }
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
        "Task lists below are preview samples while Agent Hub only reads Hermes /health."
    }

    var inboxTasks: [Task] {
        tasks
            .filter { $0.state == .waitingUser || $0.state == .failed }
            .sortedForOverview()
    }

    var runningTasks: [Task] {
        tasks
            .filter { $0.state == .running }
            .sortedForOverview()
    }

    var queuedTasks: [Task] {
        tasks
            .filter { $0.state == .queued || $0.state == .paused }
            .sortedForOverview()
    }

    var recentTasks: [Task] {
        tasks
            .filter { $0.state == .succeeded }
            .sortedForOverview()
    }

    var cancelledTasks: [Task] {
        tasks
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

    private var prioritizedTasks: [Task] {
        inboxTasks + runningTasks + queuedTasks + recentTasks + cancelledTasks
    }
}
