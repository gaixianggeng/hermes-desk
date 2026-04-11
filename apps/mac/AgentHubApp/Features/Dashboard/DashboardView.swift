import AppCore
import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppStateStore

    @State private var isPresentingRunSheet = false
    @State private var runTitleDraft = ""
    @State private var runPromptDraft = ""
    @State private var runSheetError: String?

    private let detailColumns = [GridItem(.adaptive(minimum: 120), spacing: 8)]
    private let statColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            HSplitView {
                overviewColumn
                    .frame(minWidth: 560, idealWidth: 700)

                detailPane
                    .frame(minWidth: 340, idealWidth: 380, maxWidth: 420)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            .navigationTitle("Agent Hub")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        presentRunSheet()
                    } label: {
                        Label("Run Hermes Task", systemImage: "sparkles.rectangle.stack")
                    }

                    Button {
                        Swift.Task {
                            await appState.refreshHealth()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(appState.isRefreshing)

                    SettingsLink {
                        Label("Connection & Diagnostics", systemImage: "stethoscope")
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingRunSheet) {
            runTaskSheet
        }
        .task {
            await appState.refreshHealth()
        }
    }

    private var overviewColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroCard

                taskPanel(
                    title: "Action Required",
                    subtitle: "Approvals, failures, and other items that need a person before work can continue.",
                    tasks: appState.inboxTasks,
                    emptyTitle: "All clear",
                    emptyMessage: "Nothing is waiting on your input."
                )
                taskPanel(
                    title: "Running",
                    subtitle: "Tasks Hermes is actively working on right now.",
                    tasks: appState.runningTasks,
                    emptyTitle: "No active task",
                    emptyMessage: "Start a Hermes task to see live output here."
                )
                taskPanel(
                    title: "Queued & Paused",
                    subtitle: "Tasks that are lined up to start later or are waiting to be resumed.",
                    tasks: appState.queuedTasks,
                    emptyTitle: "No queued work",
                    emptyMessage: "There are no queued or paused tasks right now."
                )
                taskPanel(
                    title: "Recent Results",
                    subtitle: "Completed work that still has useful outputs or files to revisit.",
                    tasks: appState.recentTasks,
                    emptyTitle: "No recent result",
                    emptyMessage: "Completed Hermes runs will land here with their latest result summary."
                )

                if appState.cancelledTasks.isEmpty == false {
                    taskPanel(
                        title: "Stopped",
                        subtitle: "Cancelled work is kept separate so it does not read like a finished result.",
                        tasks: appState.cancelledTasks,
                        emptyTitle: "",
                        emptyMessage: ""
                    )
                }
            }
            .padding(24)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.connectionState.title)
                        .font(.title2.weight(.semibold))
                    Text(appState.connectionState.detail)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    presentRunSheet()
                } label: {
                    Label("Run Hermes Task", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isStartingRun)
            }

            Label(appState.taskFeedSummary, systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: statColumns, alignment: .leading, spacing: 12) {
                statCard(title: "Needs input", value: appState.inboxCount, tint: .orange)
                statCard(title: "Running", value: appState.runningCount, tint: .blue)
                statCard(title: "Queued", value: appState.queuedCount, tint: .purple)
                statCard(title: "Results", value: appState.recentCount, tint: .green)

                if appState.cancelledCount > 0 {
                    statCard(title: "Stopped", value: appState.cancelledCount, tint: .red)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func taskPanel(
        title: String,
        subtitle: String,
        tasks: [Task],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                if emptyTitle.isEmpty == false {
                    ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyMessage))
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: Task) -> some View {
        let isSelected = appState.selectedTaskID == task.taskID

        return Button {
            appState.selectTask(task)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(task.currentSummary)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text(task.runState.phaseLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(task.state.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(task.state.tint.opacity(0.12), in: Capsule())

                        sourceBadge(task)
                    }
                }

                if let output = task.latestOutputSummary, output.isEmpty == false {
                    Text(output)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else if let artifact = task.artifact {
                    Text(artifact.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let task = appState.selectedTask {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailHeader(task)

                    detailCard(title: "Status", systemImage: task.state.symbolName) {
                        VStack(alignment: .leading, spacing: 10) {
                            statusLine(label: "Task state", value: task.state.displayTitle)
                            statusLine(label: "Current phase", value: task.runState.phaseLabel)
                            statusLine(label: "Last update", value: task.updatedAt.formatted(date: .abbreviated, time: .shortened))

                            if let progressHint = task.runState.progressHint {
                                statusLine(label: "Progress", value: progressHint)
                            }

                            if let waitingReason = task.runState.waitingReason {
                                statusLine(label: "Waiting on", value: waitingReason)
                            }

                            if let failureMessage = task.runState.failureMessage {
                                statusLine(label: "Issue", value: failureMessage)
                            }
                        }
                    }

                    detailCard(title: "Latest output", systemImage: "text.alignleft") {
                        if let output = task.latestOutputSummary {
                            Text(output)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(task.isPreview ? "Preview tasks do not stream live Hermes output." : "Hermes has not emitted output for this task yet.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    detailCard(title: "Recent events", systemImage: "timeline.selection") {
                        if task.taskEvents.isEmpty {
                            Text(task.isPreview ? "Preview tasks do not carry a live Hermes event timeline." : "Waiting for Hermes events…")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(task.taskEvents.suffix(8).reversed())) { event in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(event.summary)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer(minLength: 8)
                                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let detail = event.detail, detail.isEmpty == false {
                                            Text(detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .padding(.bottom, 6)

                                    if event.id != task.taskEvents.suffix(8).first?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    if let artifact = task.artifact {
                        detailCard(title: "Result", systemImage: "shippingbox") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(artifact.summary)
                                    .foregroundStyle(.secondary)

                                if artifact.keyOutputs.isEmpty == false {
                                    detailList(title: "Key outputs", items: artifact.keyOutputs)
                                }

                                if artifact.files.isEmpty == false {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Files")
                                            .font(.subheadline.weight(.semibold))
                                        ForEach(artifact.files) { file in
                                            Text(file.path)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                if artifact.nextActions.isEmpty == false {
                                    detailList(title: "Suggested follow-up", items: artifact.nextActions)
                                }
                            }
                        }
                    }

                    if task.availableActions.isEmpty == false {
                        detailCard(title: "Available actions", systemImage: "slider.horizontal.3") {
                            LazyVGrid(columns: detailColumns, alignment: .leading, spacing: 8) {
                                ForEach(task.availableActions, id: \.rawValue) { action in
                                    Text(action.displayTitle)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.08), in: Capsule())
                                }
                            }
                        }
                    }

                    detailCard(title: "Metadata", systemImage: "info.circle") {
                        VStack(alignment: .leading, spacing: 10) {
                            statusLine(label: "Task ID", value: task.taskID)
                            statusLine(label: "Agent", value: task.agentID)
                            statusLine(label: "Feed", value: task.isPreview ? "Preview sample" : "Live Hermes run")
                            statusLine(label: "Source", value: task.source.displayTitle)
                            statusLine(label: "Created", value: task.createdAt.formatted(date: .abbreviated, time: .shortened))

                            if let sessionID = task.sessionID {
                                statusLine(label: "Session", value: sessionID)
                            }

                            if let runID = task.runID {
                                statusLine(label: "Run", value: runID)
                            }
                        }
                    }
                }
                .padding(24)
            }
        } else {
            ContentUnavailableView(
                "Choose a task",
                systemImage: "list.bullet.rectangle.portrait",
                description: Text("Pick a task from the overview to inspect its latest context, output, and event timeline.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private func detailHeader(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.title2.weight(.semibold))
                    Text(task.currentSummary)
                        .foregroundStyle(.secondary)
                    sourceBadge(task)
                }

                Spacer(minLength: 0)

                Label(task.state.displayTitle, systemImage: task.state.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(task.state.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(task.state.tint.opacity(0.12), in: Capsule())
            }
        }
    }

    private func detailCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func statCard(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sourceBadge(_ task: Task) -> some View {
        Text(task.isPreview ? "Preview" : "Live")
            .font(.caption.weight(.medium))
            .foregroundStyle(task.isPreview ? Color.secondary : Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((task.isPreview ? Color.secondary : Color.green).opacity(0.14), in: Capsule())
    }

    private var runTaskSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Run Hermes Task")
                .font(.title2.weight(.semibold))
            Text("Start a real Hermes run without turning Agent Hub into a chat shell. Give the task a short label if you want, then write the work request below.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Task title (optional)")
                    .font(.subheadline.weight(.medium))
                TextField("e.g. Review the latest failing build", text: $runTitleDraft)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Hermes task")
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $runPromptDraft)
                    .font(.body)
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            if let runSheetError {
                Label(runSheetError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresentingRunSheet = false
                }
                Button {
                    submitRunSheet()
                } label: {
                    if appState.isStartingRun {
                        Label("Starting…", systemImage: "hourglass")
                    } else {
                        Label("Start Run", systemImage: "play.fill")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(appState.isStartingRun || runPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 380)
    }

    private func presentRunSheet() {
        runSheetError = nil
        appState.runLaunchError = nil
        isPresentingRunSheet = true
    }

    private func submitRunSheet() {
        runSheetError = nil
        Swift.Task {
            do {
                try await appState.startHermesTask(title: runTitleDraft, prompt: runPromptDraft)
                await MainActor.run {
                    runTitleDraft = ""
                    runPromptDraft = ""
                    isPresentingRunSheet = false
                }
            } catch {
                await MainActor.run {
                    runSheetError = error.localizedDescription
                }
            }
        }
    }
}

private extension TaskState {
    var displayTitle: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .waitingUser:
            return "Needs input"
        case .paused:
            return "Paused"
        case .failed:
            return "Failed"
        case .succeeded:
            return "Completed"
        case .cancelled:
            return "Stopped"
        }
    }

    var symbolName: String {
        switch self {
        case .queued:
            return "clock"
        case .running:
            return "bolt.fill"
        case .waitingUser:
            return "hand.raised.fill"
        case .paused:
            return "pause.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .queued:
            return .purple
        case .running:
            return .blue
        case .waitingUser:
            return .orange
        case .paused:
            return .yellow
        case .failed:
            return .red
        case .succeeded:
            return .green
        case .cancelled:
            return .secondary
        }
    }
}

private extension TaskAction {
    var displayTitle: String {
        switch self {
        case .approveOnce:
            return "Approve once"
        case .approveForTask:
            return "Approve for task"
        case .reject:
            return "Reject"
        case .retry:
            return "Retry"
        case .resume:
            return "Resume"
        case .pause:
            return "Pause"
        case .stop:
            return "Stop"
        case .openTerminal:
            return "Open terminal"
        case .openWorkspace:
            return "Open workspace"
        case .copyResult:
            return "Copy result"
        }
    }
}

private extension TaskSource {
    var displayTitle: String {
        switch self {
        case .manual:
            return "Manual"
        case .shortcut:
            return "Shortcut"
        case .scheduled:
            return "Scheduled"
        case .restored:
            return "Restored"
        }
    }
}
