import AppCore
import AppKit
import HermesKit
import SwiftUI

private enum HermesDeskRenderPerformanceLog {
    static func append(_ message: String) {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let directoryURL = supportURL.appending(path: "HermesDesk", directoryHint: .isDirectory)
        let fileURL = directoryURL.appending(path: "run-events-debug.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) == false {
                try Data(line.utf8).write(to: fileURL)
            } else if let handle = try? FileHandle(forWritingTo: fileURL) {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            }
        } catch {
            return
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppStateStore

    @State private var listScope: WorkspaceListScope = .active
    @State private var taskFilter: WorkspaceTaskFilter = .all
    @State private var transcriptDisplayMode: HermesWorkspaceTranscriptMode = .full
    @State private var inspectorTab: WorkspaceInspectorTab = .overview
    @State private var composerTitleDraft = ""
    @State private var composerPromptDraft = ""
    @State private var composerError: String?
    @State private var isComposerExpanded = false
    @State private var autoLoadingOlderTaskID: Task.ID?
    @State private var automaticOlderLoadingEnabledTaskID: Task.ID?
    @State private var workspaceScrollMetrics = WorkspaceScrollMetrics()
    @State private var workspaceScrollCommand: WorkspaceScrollCommand?
    @State private var shouldAutoScrollSelectedTask = true
    @State private var pendingForcedAutoScrollTaskID: Task.ID?
    @State private var expandedInspectorEventIDs: Set<String> = []
    @State private var selectedTaskSnapshot: Task?
    @State private var selectedTaskEntriesSnapshot: [WorkspaceFeedEntry] = []
    @FocusState private var composerIsFocused: Bool

    var body: some View {
        HSplitView {
            navigationColumn
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            workspaceColumn
                .frame(minWidth: 540, idealWidth: 720)

            inspectorColumn
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(appState.text(zh: "Hermes Desk", en: "Hermes Desk"))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    prepareComposerForNewTask()
                } label: {
                    Label(appState.text(zh: "新建任务", en: "New Task"), systemImage: "square.and.pencil")
                }

                Button {
                    Swift.Task {
                        await appState.refreshWorkspace()
                    }
                } label: {
                    Label(appState.text(zh: "刷新", en: "Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)

                if appState.interruptedFeedCount > 0 {
                    Button {
                        appState.reconnectInterruptedFeeds()
                    } label: {
                        Label(appState.text(zh: "重连实时流", en: "Reconnect Feeds"), systemImage: "bolt.horizontal.circle")
                    }
                }

                SettingsLink {
                    Label(appState.text(zh: "连接与诊断", en: "Connection & Diagnostics"), systemImage: "stethoscope")
                }
            }
        }
        .task {
            syncSelectionToScope()
            refreshSelectedTaskSnapshot()
        }
        .onChange(of: listScope) {
            taskFilter = .all
            syncSelectionToScope()
        }
        .onChange(of: taskFilter) {
            syncSelectionToScope()
        }
        .onChange(of: appState.selectedAgentID) { oldValue, newValue in
            HermesDeskPerformanceLog.selection(
                "dashboard agent old=\(oldValue ?? "nil") new=\(newValue ?? "nil") visibleTasks=\(displayedTasks.count)"
            )
        }
        .onChange(of: appState.selectedTaskID) { oldValue, newValue in
            let transcriptCount = appState.selectedTask.map { appState.transcriptMessages(for: $0).count } ?? 0
            HermesDeskPerformanceLog.selection(
                "dashboard task old=\(oldValue ?? "nil") new=\(newValue ?? "nil") transcript=\(transcriptCount) visibleTasks=\(displayedTasks.count)"
            )
        }
        .onChange(of: selectedTaskSnapshotKey) { _, _ in
            refreshSelectedTaskSnapshot()
        }
    }

    private var navigationColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.text(zh: "工作区", en: "Workspace"))
                            .font(.title3.weight(.semibold))
                        Text(appState.localizedConnectionTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        headerIconButton(systemImage: "square.and.pencil") {
                            prepareComposerForNewTask()
                        }
                        .help(appState.text(zh: "新建任务", en: "New task"))

                        headerIconButton(systemImage: appState.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise") {
                            Swift.Task {
                                await appState.refreshWorkspace()
                            }
                        }
                        .disabled(appState.isRefreshing)
                        .help(appState.text(zh: "刷新会话", en: "Refresh sessions"))
                    }
                }

                Text(appState.localizedConnectionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.agents) { agent in
                        let isSelected = appState.selectedAgentID == agent.agentID
                        VStack(spacing: 8) {
                            Button {
                                appState.selectedAgentID = agent.agentID
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill((isSelected ? Color.accentColor : Color.secondary).opacity(isSelected ? 0.22 : 0.12))
                                            .frame(width: 52, height: 52)
                                        Text(String(agent.displayName.prefix(1)).uppercased())
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    }
                                    Text(agent.displayName)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .frame(width: 76)
                            }
                            .buttonStyle(.plain)

                            Button {
                                appState.selectedAgentID = agent.agentID
                                prepareComposerForNewTask()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(appState.text(zh: "在这个 agent 下新建任务", en: "Start a new task under this agent"))
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            if let agentRoleSummary = appState.selectedAgentRoleSummary {
                Text(agentRoleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 20)
            }

            Picker(appState.text(zh: "任务范围", en: "Task scope"), selection: $listScope) {
                ForEach(WorkspaceListScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            taskFilterStrip
                .padding(.horizontal, 20)

            Divider()
                .padding(.horizontal, 20)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if displayedTasks.isEmpty {
                        ContentUnavailableView(
                            listScope.emptyTitle,
                            systemImage: listScope.emptySymbol,
                            description: Text(listScope.emptyMessage)
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(displayedTasks) { task in
                            taskListRow(task)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func headerIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var taskSummaryStrip: some View {
        HStack(spacing: 10) {
            summaryPill(title: appState.text(zh: "待处理", en: "Needs input"), value: appState.inboxCount, tint: .orange)
            summaryPill(title: appState.text(zh: "进行中", en: "Running"), value: appState.runningCount, tint: .blue)
            summaryPill(title: appState.text(zh: "开放中", en: "Open"), value: appState.openCount, tint: .teal)
            summaryPill(title: appState.text(zh: "已归档", en: "Archived"), value: appState.archivedCount, tint: .green)
        }
    }

    private var taskFilterStrip: some View {
        let filters = availableTaskFilters(for: listScope)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    Button {
                        taskFilter = filter
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(filter.tint)
                                .frame(width: 7, height: 7)
                            Text(filter.title)
                                .font(.caption.weight(.medium))
                            Text("\(taskCount(for: filter))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(filterBackground(for: filter), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func taskListRow(_ task: Task) -> some View {
        WorkspaceTaskListRowView(
            title: workspaceDisplayTitle(for: task),
            introduction: workspaceListIntroduction(for: task),
            statusLine: workspaceListStatusLine(for: task),
            stateTitle: workspaceSessionStatusTitle(for: task),
            stateSymbolName: workspaceSessionStatusSymbol(for: task),
            stateTint: workspaceSessionStatusTint(for: task),
            updatedAtText: task.updatedAt.formatted(date: .abbreviated, time: .shortened),
            isSelected: appState.selectedTaskID == task.taskID,
            showsAttentionDot: task.state == .waitingUser || task.state == .failed,
            onSelect: {
                shouldAutoScrollSelectedTask = true
                pendingForcedAutoScrollTaskID = task.taskID
                appState.selectTask(task)
                composerError = nil
                if appState.selectedTaskID != nil {
                    isComposerExpanded = false
                }
            }
        )
    }

    private var workspaceColumn: some View {
        VStack(spacing: 0) {
            if let task = selectedTaskSnapshot {
                let entries = selectedTaskEntriesSnapshot
                workspaceHeader(task)
                Divider()
                GeometryReader { geometry in
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(spacing: 10) {
                                automaticLoadOlderMessagesSentinel(for: task)
                                let availableFeedWidth = max(geometry.size.width - 16, 320)
                                ForEach(entries) { entry in
                                    workspaceFeedRow(entry, availableWidth: availableFeedWidth)
                                        .id(entry.id)
                                        .transition(workspaceFeedEntryTransition(for: entry))
                                }
                                Color.clear
                                    .frame(height: 1)
                                    .id(workspaceBottomAnchorID(for: task.taskID))
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottomLeading)
                            .animation(.spring(response: 0.46, dampingFraction: 0.90, blendDuration: 0.20), value: workspaceFeedAnimationKey(entries))
                        }
                        .background(
                            WorkspaceScrollObserver(
                                metrics: $workspaceScrollMetrics,
                                command: $workspaceScrollCommand
                            )
                        )
                        .onAppear {
                            shouldAutoScrollSelectedTask = true
                            pendingForcedAutoScrollTaskID = task.taskID
                            queueWorkspaceScrollToBottom(using: scrollProxy, for: task.taskID, force: true)
                        }
                        .onChange(of: task.taskID) { _, _ in
                            autoLoadingOlderTaskID = nil
                            automaticOlderLoadingEnabledTaskID = nil
                            shouldAutoScrollSelectedTask = true
                            pendingForcedAutoScrollTaskID = task.taskID
                            workspaceScrollMetrics = WorkspaceScrollMetrics()
                            queueWorkspaceScrollToBottom(using: scrollProxy, for: task.taskID, force: true)
                        }
                        .onChange(of: workspaceFeedTailAnchor(entries)) { _, _ in
                            if shouldAutoScrollSelectedTask || pendingForcedAutoScrollTaskID == task.taskID {
                                queueWorkspaceScrollToBottom(using: scrollProxy, for: task.taskID)
                            }
                        }
                        .onChange(of: workspaceScrollMetrics) { _, newMetrics in
                            if newMetrics.viewportHeight > 0,
                               newMetrics.contentHeight > 0,
                               pendingForcedAutoScrollTaskID != task.taskID {
                                shouldAutoScrollSelectedTask = newMetrics.isNearBottom
                            }
                            if pendingForcedAutoScrollTaskID == task.taskID, newMetrics.isNearBottom {
                                pendingForcedAutoScrollTaskID = nil
                                shouldAutoScrollSelectedTask = true
                            }
                            if automaticOlderLoadingEnabledTaskID != task.taskID,
                               workspaceScrollCommand == nil,
                               newMetrics.viewportHeight > 0,
                               newMetrics.contentHeight > 0,
                                newMetrics.isNearBottom {
                                automaticOlderLoadingEnabledTaskID = task.taskID
                            }
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        newTaskHero
                    }
                    .padding(24)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            workspaceComposerInset(task: selectedTaskSnapshot)
        }
    }

    private func workspaceComposerInset(task: Task?) -> some View {
        VStack(spacing: 0) {
            if let task, shouldShowWorkspaceRunningStatusBar(for: task) {
                workspaceRunningStatusBar(for: task)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
            }
            Divider()
            workspaceComposer(task: task)
                .padding(20)
                .background(.ultraThinMaterial)
        }
    }

    private func shouldShowWorkspaceRunningStatusBar(for task: Task) -> Bool {
        guard task.sessionStatus == .running else {
            return false
        }

        return workspaceStreamingPreview(for: task) == nil
    }

    private func workspaceRunningStatusBar(for task: Task) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hermes is working")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(task.runState.phaseLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text("See Task progress in Inspector")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func automaticLoadOlderMessagesSentinel(for task: Task) -> some View {
        if appState.canLoadOlderMessages(for: task) || appState.isLoadingOlderMessages(for: task) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        requestOlderMessagesIfNeeded(for: task)
                    }

                if appState.isLoadingOlderMessages(for: task) {
                    Label(
                        appState.text(zh: "加载更早消息中…", en: "Loading earlier messages…"),
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func requestOlderMessagesIfNeeded(for task: Task) {
        guard appState.canLoadOlderMessages(for: task) else {
            return
        }
        guard appState.isLoadingOlderMessages(for: task) == false else {
            return
        }
        guard automaticOlderLoadingEnabledTaskID == task.taskID else {
            return
        }
        guard workspaceScrollMetrics.offsetY <= 24 else {
            return
        }
        guard autoLoadingOlderTaskID != task.taskID else {
            return
        }

        autoLoadingOlderTaskID = task.taskID
        let scrollSnapshot = workspaceScrollMetrics
        appState.loadOlderMessages(for: task.taskID)

        Swift.Task { @MainActor in
            var sawLoadingState = false
            for _ in 0..<40 {
                if appState.isLoadingOlderMessages(for: task) {
                    sawLoadingState = true
                    break
                }
                try? await Swift.Task.sleep(for: .milliseconds(25))
            }

            if sawLoadingState {
                while appState.isLoadingOlderMessages(for: task) {
                    try? await Swift.Task.sleep(for: .milliseconds(25))
                }
            }

            defer {
                if autoLoadingOlderTaskID == task.taskID {
                    autoLoadingOlderTaskID = nil
                }
            }

            guard appState.selectedTaskID == task.taskID else {
                return
            }
            workspaceScrollCommand = .restore(
                previousOffsetY: scrollSnapshot.offsetY,
                previousContentHeight: scrollSnapshot.contentHeight
            )
        }
    }

    private func workspaceHeader(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(workspaceDisplayTitle(for: task))
                            .font(.title2.weight(.semibold))
                        Text(workspaceSessionStatusTitle(for: task))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(workspaceSessionStatusTint(for: task))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(workspaceSessionStatusTint(for: task).opacity(0.12), in: Capsule())
                    }

                    Text(workspaceHeadlineSummary(for: task))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        workspaceMetaPill(systemImage: "person.crop.circle", text: appState.displayName(forAgentID: task.agentID), tint: .accentColor)
                        workspaceMetaPill(systemImage: "calendar", text: task.updatedAt.formatted(date: .abbreviated, time: .shortened), tint: .secondary)
                        if task.isPreview {
                            workspaceMetaPill(systemImage: "sparkles", text: "Preview", tint: .secondary)
                        }
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    transcriptModePicker
                    ForEach(primaryWorkspaceActions(for: task), id: \.rawValue) { action in
                        workspaceHeaderActionButton(action, task: task)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var newTaskHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appState.text(zh: "新建 Agent 任务", en: "New Agent Task"), systemImage: "sparkles.rectangle.stack")
                .font(.title2.weight(.semibold))
            Text(appState.text(
                zh: "从任务而不是聊天收件箱开始。先在左侧选择一个 Agent，再为它创建任务；对话、执行步骤、日志和结果都会挂在这个 Task 下。",
                en: "Start from a task, not a chat inbox. Pick an agent on the left, then create a task for it. Conversation, execution steps, logs, and results all stay attached to that task."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func workspaceStatusStrip(_ task: Task) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                workspaceStatusCard(
                    title: "Phase",
                    value: task.runState.phaseLabel,
                    tint: workspaceSessionStatusTint(for: task),
                    systemImage: workspaceSessionStatusSymbol(for: task)
                )
                workspaceStatusCard(
                    title: "Queue focus",
                    value: workspaceQueueFocusTitle(for: task),
                    tint: workspaceQueueFocusTint(for: task),
                    systemImage: workspaceQueueFocusSymbol(for: task)
                )
                if let streamingSummary = workspaceStreamingPreview(for: task) {
                    workspaceStatusCard(
                        title: "Streaming",
                        value: streamingSummary,
                        tint: .blue,
                        systemImage: "ellipsis.message"
                    )
                } else if task.sessionStatus == .running {
                    workspaceStatusCard(
                        title: "Progress",
                        value: "Hermes is working through the task. Detailed tool, terminal, and agent activity stays in Task progress.",
                        tint: .blue,
                        systemImage: "chart.bar.doc.horizontal"
                    )
                }
                if let observationStatusLine = task.runState.observationStatusLine {
                    workspaceStatusCard(
                        title: "Live feed",
                        value: observationStatusLine,
                        tint: .orange,
                        systemImage: "bolt.horizontal.circle"
                    )
                }
                if task.sessionStatus != .running, let resultSummary = workspaceResultSummary(for: task) {
                    workspaceStatusCard(
                        title: task.state == .succeeded ? "Result" : "Latest useful answer",
                        value: resultSummary,
                        tint: task.state == .succeeded ? .green : .secondary,
                        systemImage: task.state == .succeeded ? "shippingbox" : "text.alignleft"
                    )
                }
            }
        }
    }

    private func workspaceTaskBrief(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label("Task overview", systemImage: "square.text.square")
                    .font(.headline)
                Spacer(minLength: 12)
                Text(workspaceSessionStatusTitle(for: task))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(workspaceSessionStatusTint(for: task))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(workspaceSessionStatusTint(for: task).opacity(0.12), in: Capsule())
            }

            workspaceBriefMetric(
                title: "Goal",
                value: task.requestText ?? task.title,
                tint: .secondary
            )
            workspaceBriefMetric(
                title: "Current",
                value: workspaceCurrentFocusSummary(for: task),
                tint: workspaceSessionStatusTint(for: task)
            )

            if let statusLine = workspaceOverviewStatusLine(for: task) {
                workspaceBriefMetric(
                    title: "Status",
                    value: statusLine,
                    tint: .secondary
                )
            }

            if let sessionBindingSummary = task.sessionBindingSummary {
                Text(sessionBindingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func workspaceBriefMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workspaceOverviewStatusLine(for task: Task) -> String? {
        if let waitingReason = task.runState.waitingReason, waitingReason.isEmpty == false {
            return waitingReason
        }
        if let failureMessage = task.runState.failureMessage, failureMessage.isEmpty == false {
            return failureMessage
        }
        if let progressHint = task.runState.progressHint, progressHint.isEmpty == false {
            return progressHint
        }
        if let observationStatusLine = task.runState.observationStatusLine, observationStatusLine.isEmpty == false {
            return observationStatusLine
        }
        return workspaceResultSummary(for: task)?.workspaceSnippet(maxLength: 180)
    }

    private func workspaceBanner(title: String, body: String, tint: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func workspaceStatusCard(title: String, value: String, tint: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(width: 200, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func workspaceFeedRow(_ entry: WorkspaceFeedEntry, availableWidth: CGFloat) -> some View {
        let palette = workspaceBubblePalette(for: entry)
        let titleColor: Color = entry.alignment == .trailing ? Color.white.opacity(0.96) : entry.tint
        let bodyColor: Color = entry.alignment == .trailing ? Color.white : Color.primary
        let footerColor: Color = entry.alignment == .trailing ? Color.white.opacity(0.74) : Color.secondary
        let progressTint: Color = entry.alignment == .trailing ? Color.white.opacity(0.88) : entry.tint
        let shouldShowHeader = entry.title.isEmpty == false
        let edgePadding = workspaceFeedEdgePadding(for: availableWidth)
        let oppositeInset = workspaceFeedOppositeInset(for: availableWidth)
        let bubbleMaxWidth = workspaceBubbleMaxWidth(
            for: availableWidth,
            oppositeInset: oppositeInset,
            edgePadding: edgePadding
        )
        let bubbleMinWidth = workspaceBubbleMinWidth(for: entry, availableWidth: bubbleMaxWidth)
        let bubbleWidth = workspaceBubbleWidth(
            for: entry,
            bubbleMaxWidth: bubbleMaxWidth,
            minimumWidth: bubbleMinWidth
        )
        let contentWidth = max(bubbleWidth - 32, 120)

        let bubble = VStack(alignment: .leading, spacing: 10) {
                if shouldShowHeader {
                    Text(entry.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(titleColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Group {
                    if entry.monospaced {
                        Text(entry.body)
                            .font(.subheadline.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: contentWidth, alignment: .leading)
                    } else {
                        workspaceBodyView(entry)
                            .frame(width: contentWidth, alignment: .leading)
                    }
                }
                .foregroundStyle(bodyColor)
                .textSelection(.enabled)

                if let footer = entry.footer {
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(footerColor)
                        .frame(
                            maxWidth: .infinity,
                            alignment: entry.alignment == .trailing ? .trailing : .leading
                        )
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .frame(width: bubbleWidth, alignment: .leading)
            .background {
                workspaceFeedBubbleBackground(for: entry, palette: palette)
            }

        return HStack(alignment: .center, spacing: 10) {
            if entry.alignment == .trailing { Spacer(minLength: oppositeInset) }

            if entry.alignment == .trailing, entry.showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(progressTint)
            }

            bubble

            if entry.alignment == .leading { Spacer(minLength: oppositeInset) }
        }
        .padding(.horizontal, edgePadding)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func workspaceFeedBubbleBackground(
        for entry: WorkspaceFeedEntry,
        palette: WorkspaceBubblePalette
    ) -> some View {
        let gradient = LinearGradient(
            colors: [palette.top, palette.bottom],
            startPoint: entry.alignment == .trailing ? .topLeading : .topTrailing,
            endPoint: .bottomTrailing
        )
        let bubbleShape = WorkspaceBubbleShape(alignment: entry.alignment)

        bubbleShape
            .fill(gradient)
            .overlay(
                bubbleShape
                    .stroke(palette.stroke, lineWidth: 0.8)
            )
            .shadow(color: palette.shadow, radius: 3, x: 0, y: 1)
    }

    private func workspaceBubblePalette(for entry: WorkspaceFeedEntry) -> WorkspaceBubblePalette {
        switch entry.bubbleStyle {
        case .automatic:
            if entry.alignment == .trailing {
                return WorkspaceBubblePalette(
                    top: Color(red: 0.00, green: 0.48, blue: 1.00),
                    bottom: Color(red: 0.03, green: 0.50, blue: 1.00),
                    stroke: Color.white.opacity(0.14),
                    shadow: Color.accentColor.opacity(0.035)
                )
            }
            return WorkspaceBubblePalette(
                top: Color.white,
                bottom: Color(red: 0.97, green: 0.97, blue: 0.98),
                stroke: Color.black.opacity(0.055),
                shadow: Color.black.opacity(0.022)
            )
        case .success:
            return WorkspaceBubblePalette(
                top: Color.green.opacity(0.16),
                bottom: Color.green.opacity(0.09),
                stroke: Color.green.opacity(0.16),
                shadow: Color.green.opacity(0.06)
            )
        case .progress:
            return WorkspaceBubblePalette(
                top: Color.blue.opacity(0.14),
                bottom: Color.blue.opacity(0.08),
                stroke: Color.blue.opacity(0.14),
                shadow: Color.blue.opacity(0.05)
            )
        case .tool:
            return WorkspaceBubblePalette(
                top: Color(nsColor: .textBackgroundColor),
                bottom: Color.secondary.opacity(0.08),
                stroke: Color.secondary.opacity(0.14),
                shadow: Color.black.opacity(0.03)
            )
        case .system:
            return WorkspaceBubblePalette(
                top: Color.orange.opacity(0.16),
                bottom: Color.orange.opacity(0.09),
                stroke: Color.orange.opacity(0.15),
                shadow: Color.orange.opacity(0.05)
            )
        }
    }

    private func workspaceComposer(task: Task?) -> some View {
        let placeholder: String
        if task == nil {
            placeholder = appState.text(zh: "给这个 agent 发一个新任务…", en: "Start a new task for this agent…")
        } else {
            placeholder = appState.text(zh: "继续这个任务的对话…", en: "Continue this task…")
        }

        return VStack(alignment: .leading, spacing: 14) {
            TextField(
                placeholder,
                text: $composerPromptDraft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(3 ... 8)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .focused($composerIsFocused)
            .onSubmit {
                submitComposer(for: task)
            }
            .onAppear {
                composerIsFocused = true
            }
            .onChange(of: appState.selectedTaskID) { _, _ in
                composerIsFocused = true
            }

            if let composerError {
                Label(composerError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer(minLength: 12)
                Button {
                    submitComposer(for: task)
                } label: {
                    if appState.isStartingRun {
                        Label("Starting…", systemImage: "hourglass")
                    } else {
                        Label(task == nil ? appState.text(zh: "新建任务", en: "New Task") : appState.text(zh: "发送", en: "Send"), systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isStartingRun || composerPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var inspectorColumn: some View {
        Group {
            if let task = selectedTaskSnapshot {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inspector")
                            .font(.title3.weight(.semibold))
                        Text("Status, steps, logs, and recovery tools for the selected task.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Picker("Inspector tab", selection: $inspectorTab) {
                        ForEach(WorkspaceInspectorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch inspectorTab {
                            case .overview:
                                inspectorOverview(task)
                            case .artifacts:
                                inspectorArtifacts(task)
                            }
                        }
                        .padding(20)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Choose a task",
                    systemImage: "sidebar.right",
                    description: Text("Pick a task from the left to inspect status, steps, logs, and recovery details.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
        }
    }

    private func inspectorOverview(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            inspectorCard(title: "Now / Next", systemImage: task.state.symbolName) {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorLine(label: "Status", value: inspectorStatusValue(for: task))
                    inspectorLine(label: "Current phase", value: inspectorPhaseValue(for: task))
                    inspectorLine(label: "Last update", value: task.updatedAt.formatted(date: .abbreviated, time: .shortened))

                    if let waitingReason = task.runState.waitingReason {
                        inspectorLine(label: "Waiting on", value: waitingReason)
                    }
                    if let pendingAction = task.pendingAction {
                        inspectorLine(label: "Action in flight", value: "\(pendingAction.actionIndicator) \(pendingAction.displayTitle)")
                    }
                    if let observationStatusLine = task.runState.observationStatusLine {
                        inspectorLine(label: "Live feed", value: observationStatusLine)
                    }
                }
            }

            inspectorProgressContent(task)

            if task.state == .waitingUser {
                ConfirmationCardView(
                    task: task,
                    feedback: appState.taskActionFeedback,
                    isActionEnabled: { action in isActionEnabled(action, for: task) },
                    performAction: { action in appState.performTaskAction(action, for: task.taskID) }
                )
            } else if task.state == .failed {
                FailurePanelView(
                    task: task,
                    feedback: appState.taskActionFeedback,
                    isActionEnabled: { action in isActionEnabled(action, for: task) },
                    performAction: { action in appState.performTaskAction(action, for: task.taskID) }
                )
            } else if let observationStatusLine = task.runState.observationStatusLine, task.isPreview == false, task.state.isTerminal == false {
                inspectorCard(title: "Live feed", systemImage: "bolt.horizontal.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(observationStatusLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            appState.reconnectLiveFeed(for: task.taskID)
                        } label: {
                            Label("Reconnect live feed", systemImage: "bolt.horizontal.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let feedback = appState.taskActionFeedback, appState.selectedTaskID == task.taskID {
                inspectorCard(title: "Hermes Desk action", systemImage: "checkmark.message") {
                    Text(feedback)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if supplementalInspectorActions(for: task).isEmpty == false {
                inspectorCard(title: "Quick actions", systemImage: "slider.horizontal.3") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(supplementalInspectorActions(for: task), id: \.rawValue) { action in
                            Button {
                                appState.performTaskAction(action, for: task.taskID)
                            } label: {
                                Label(action.displayTitle, systemImage: action.symbolName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isActionEnabled(action, for: task) == false)
                        }
                    }
                }
            }
        }
    }

    private func inspectorStatusValue(for task: Task) -> String {
        if task.sessionStatus == .open {
            return "🟢 \(appState.text(zh: "开放中", en: "Open"))"
        }
        if task.sessionStatus == .archived {
            return "📦 \(appState.text(zh: "已归档", en: "Archived"))"
        }

        switch task.state {
        case .waitingUser:
            return "🟠 \(appState.text(zh: "待确认", en: "Needs input"))"
        case .failed:
            return "🔴 \(appState.text(zh: "待恢复", en: "Needs recovery"))"
        case .running:
            return "🔵 \(appState.text(zh: "进行中", en: "Running"))"
        case .queued:
            return "🕓 \(appState.text(zh: "排队中", en: "Queued"))"
        case .paused:
            return "⏸️ \(appState.text(zh: "已暂停", en: "Paused"))"
        case .succeeded:
            return "✅ \(appState.text(zh: "已完成", en: "Completed"))"
        case .cancelled:
            return "⏹️ \(appState.text(zh: "已停止", en: "Stopped"))"
        }
    }

    private func inspectorPhaseValue(for task: Task) -> String {
        if task.sessionStatus == .open {
            switch task.runState.phaseLabel {
            case "Conversation updated":
                return appState.text(zh: "可继续追问", en: "Ready for follow-up")
            case "Run finished":
                return appState.text(zh: "等待下一步", en: "Waiting for next step")
            default:
                break
            }
        }

        return task.runState.phaseLabel
    }

    @ViewBuilder
    private func inspectorProgressContent(_ task: Task) -> some View {
        let progressSections = taskProgressSections(for: task)
        let milestoneEvents = taskMilestoneEvents(for: task)

        VStack(alignment: .leading, spacing: 16) {
            inspectorCard(title: "Task progress", systemImage: "list.bullet.rectangle") {
                if progressSections.isEmpty {
                    Text(task.isPreview ? "Preview tasks do not carry detailed live execution activity yet." : "Detailed tool, terminal, and streaming activity will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        let summaryLines = inspectorExecutionSummaryLines(
                            for: task,
                            progressSections: progressSections,
                            milestoneEvents: milestoneEvents
                        )
                        if summaryLines.isEmpty == false {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Execution summary")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(summaryLines, id: \.label) { line in
                                    inspectorLine(label: line.label, value: line.value)
                                }
                            }

                            Divider()
                        }

                        ForEach(progressSections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Label(section.title, systemImage: section.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(section.tint)

                                ForEach(section.events) { event in
                                    inspectorEventRow(event, emphasizeDetail: section.emphasizeDetail || event.type == .log || event.type == .output)
                                    if event.id != section.events.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if shouldShowInspectorLatestAnswer(for: task) {
                inspectorCard(title: task.sessionStatus == .running ? "Latest streamed answer" : "Latest useful answer", systemImage: "text.alignleft") {
                    Text(workspaceResultSummary(for: task) ?? workspaceCurrentFocusSummary(for: task))
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func shouldShowInspectorLatestAnswer(for task: Task) -> Bool {
        guard let resultSummary = workspaceResultSummary(for: task), resultSummary.isEmpty == false else {
            return false
        }

        if task.sessionStatus == .running {
            return workspaceStreamingPreview(for: task) != nil
        }

        let transcriptMessages = appState.transcriptMessages(for: task)
        let hasVisibleAssistantMessage = transcriptMessages.contains { message in
            message.role == .assistant && task.shouldDisplayMessageInWorkspaceConversation(message)
        }
        return hasVisibleAssistantMessage == false
    }

    private func inspectorExecutionSummaryLines(
        for task: Task,
        progressSections: [WorkspaceProgressSection],
        milestoneEvents: [TaskEvent]
    ) -> [(label: String, value: String)] {
        var lines: [(label: String, value: String)] = []

        if let latestMilestone = milestoneEvents.first {
            lines.append((
                label: "Latest milestone",
                value: workspaceEventHeadline(for: latestMilestone)
            ))
        }

        let recentTools = recentProgressToolDisplayNames(for: task)
        if recentTools.isEmpty == false {
            lines.append((
                label: "Recent tools",
                value: recentTools.joined(separator: " • ")
            ))
        }

        let totalUpdates = progressSections.reduce(0) { partialResult, section in
            partialResult + section.events.count
        } + milestoneEvents.count
        if totalUpdates > 0 {
            lines.append((
                label: "Captured updates",
                value: "\(totalUpdates) recent event\(totalUpdates == 1 ? "" : "s")"
            ))
        }

        return lines
    }

    private func recentProgressToolDisplayNames(for task: Task) -> [String] {
        var orderedNames: [String] = []

        for event in task.taskEvents.reversed() {
            guard let toolName = workspaceToolName(for: event) else {
                continue
            }
            let displayName = workspaceDisplayToolName(toolName)
            if orderedNames.contains(displayName) == false {
                orderedNames.append(displayName)
            }
            if orderedNames.count == 3 {
                break
            }
        }

        return orderedNames
    }

    private func inspectorArtifacts(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if task.isPreview, let artifact = task.artifact {
                inspectorCard(title: "Result snapshot", systemImage: "shippingbox") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(artifact.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if artifact.keyOutputs.isEmpty == false {
                            inspectorBulletList(title: "Key outputs", items: Array(artifact.keyOutputs.prefix(3)))
                        }
                        if artifact.files.isEmpty == false {
                            inspectorBulletList(title: "Files", items: Array(artifact.files.prefix(3).map(\.path)))
                        }
                        if artifact.nextActions.isEmpty == false {
                            inspectorBulletList(title: "Next", items: Array(artifact.nextActions.prefix(2)))
                        }
                    }
                }
            } else {
                inspectorCard(title: task.isPreview ? "Result snapshot" : "Conversation source", systemImage: task.isPreview ? "shippingbox" : "ellipsis.message") {
                    Text(task.isPreview ? (task.latestOutputSummary ?? "This task has not emitted a structured artifact yet.") : "This task behaves like a conversation thread. The center transcript is the source of truth, not a separate result snapshot.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if task.retryParentTaskID != nil || task.retryChildTaskID != nil {
                inspectorCard(title: "Linked runs", systemImage: "arrow.triangle.branch") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let retryParentTaskID = task.retryParentTaskID {
                            inspectorLine(label: "Retried from", value: retryParentTaskID)
                        }
                        if let retryChildTaskID = task.retryChildTaskID {
                            inspectorLine(label: "Replacement run", value: retryChildTaskID)
                        }
                    }
                }
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorLine(label: "Task ID", value: task.taskID)
                    inspectorLine(label: "Agent", value: appState.displayName(forAgentID: task.agentID))
                    inspectorLine(label: "Feed", value: task.isPreview ? "Preview sample" : "Live Hermes run")
                    inspectorLine(label: "Source", value: task.source.displayTitle)
                    if let currentSessionID = task.effectiveSessionID {
                        inspectorLine(label: "Session", value: currentSessionID)
                    }
                    if let rootSessionID = task.rootSessionID, rootSessionID != task.effectiveSessionID {
                        inspectorLine(label: "Root session", value: rootSessionID)
                    }
                    if let runID = task.runID {
                        inspectorLine(label: "Run", value: runID)
                    }
                }
            } label: {
                Label("Technical details", systemImage: "info.circle")
                    .font(.headline)
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func inspectorCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func inspectorLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func inspectorBulletList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func workspaceHeaderActionButton(_ action: TaskAction, task: Task) -> some View {
        let button = Button {
            appState.performTaskAction(action, for: task.taskID)
        } label: {
            Label(action.displayTitle, systemImage: action.symbolName)
        }
        .disabled(isActionEnabled(action, for: task) == false)

        switch action {
        case .retry, .approveOnce, .approveForTask:
            button.buttonStyle(.borderedProminent)
        default:
            button.buttonStyle(.bordered)
        }
    }

    private func availableTaskFilters(for scope: WorkspaceListScope) -> [WorkspaceTaskFilter] {
        switch scope {
        case .active:
            return [.all, .needsInput, .running, .open]
        case .archive:
            return [.all, .archived]
        }
    }

    private func taskCount(for filter: WorkspaceTaskFilter) -> Int {
        scopeBaseTasks.count(where: { task in
            switch filter {
            case .all:
                return true
            case .needsInput:
                return task.state == .waitingUser || task.state == .failed
            case .running:
                return task.sessionStatus == .running
            case .open:
                return task.sessionStatus == .open
            case .archived:
                return task.sessionStatus == .archived
            }
        })
    }

    private func filterBackground(for filter: WorkspaceTaskFilter) -> Color {
        taskFilter == filter ? filter.tint.opacity(0.18) : Color.secondary.opacity(0.08)
    }

    private var scopeBaseTasks: [Task] {
        let baseTasks = appState.liveTasks
        switch listScope {
        case .active:
            return baseTasks.filter { $0.isArchivedBySession == false }
        case .archive:
            return baseTasks.filter { $0.isArchivedBySession }
        }
    }

    private func filteredTasks(from tasks: [Task]) -> [Task] {
        tasks.filter { task in
            switch taskFilter {
            case .all:
                return true
            case .needsInput:
                return task.state == .waitingUser || task.state == .failed
            case .running:
                return task.sessionStatus == .running
            case .open:
                return task.sessionStatus == .open
            case .archived:
                return task.sessionStatus == .archived
            }
        }
    }

    private func workspaceQueueFocusTitle(for task: Task) -> String {
        if task.sessionStatus == .open {
            return "Open conversation"
        }
        if task.sessionStatus == .archived {
            return "Archived"
        }
        switch task.state {
        case .waitingUser:
            return "Action Required"
        case .failed:
            return "Recovery Queue"
        case .running:
            return "Running"
        case .queued, .paused:
            return "Queued & Paused"
        case .succeeded:
            return "Recent Result"
        case .cancelled:
            return "Stopped"
        }
    }

    private func workspaceQueueFocusTint(for task: Task) -> Color {
        if task.sessionStatus == .open {
            return .teal
        }
        if task.sessionStatus == .archived {
            return .green
        }
        switch task.state {
        case .waitingUser:
            return .orange
        case .failed:
            return .red
        case .running:
            return .blue
        case .queued, .paused:
            return .purple
        case .succeeded:
            return .green
        case .cancelled:
            return .secondary
        }
    }

    private func workspaceQueueFocusSymbol(for task: Task) -> String {
        if task.sessionStatus == .open {
            return "ellipsis.message"
        }
        if task.sessionStatus == .archived {
            return "archivebox.fill"
        }
        switch task.state {
        case .waitingUser:
            return "hand.raised.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .running:
            return "bolt.fill"
        case .queued, .paused:
            return "clock.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    private func summaryPill(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text("\(title) \(value)")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func workspaceMetaPill(systemImage: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var transcriptModePicker: some View {
        HStack(spacing: 6) {
            ForEach(HermesWorkspaceTranscriptMode.allCases, id: \.rawValue) { mode in
                Button {
                    transcriptDisplayMode = mode
                } label: {
                    Text(mode == .conversation ? appState.text(zh: "对话", en: "Conversation") : appState.text(zh: "完整记录", en: "Full transcript"))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background((transcriptDisplayMode == mode ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08)), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func workspaceBodyView(_ entry: WorkspaceFeedEntry) -> some View {
        WorkspaceMarkdownText(
            entry.body,
            isStreaming: entry.isStreamingMarkdown,
            prefersMarkdown: entry.usesMarkdown
        )
            .textSelection(.enabled)
    }

    private func workspaceFeedTailAnchor(_ entries: [WorkspaceFeedEntry]) -> WorkspaceFeedTailAnchor? {
        guard let lastEntry = entries.last else {
            return nil
        }
        return WorkspaceFeedTailAnchor(
            id: lastEntry.id,
            body: lastEntry.body,
            footer: lastEntry.footer,
            showsProgress: lastEntry.showsProgress
        )
    }

    private func workspaceFeedAnimationKey(_ entries: [WorkspaceFeedEntry]) -> [String] {
        entries.map(\.id)
    }

    private func workspaceFeedEntryTransition(for entry: WorkspaceFeedEntry) -> AnyTransition {
        let insertionEdge: Edge = entry.alignment == .trailing ? .trailing : .leading
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.992, anchor: entry.alignment == .trailing ? .trailing : .leading))
                .combined(with: .offset(x: insertionEdge == .trailing ? 8 : -8, y: 10)),
            removal: .opacity
        )
    }

    private func workspaceBottomAnchorID(for taskID: Task.ID) -> String {
        "workspace-bottom-\(taskID)"
    }

    private func queueWorkspaceScrollToBottom(using scrollProxy: ScrollViewProxy, for taskID: Task.ID, force: Bool = false) {
        if force {
            pendingForcedAutoScrollTaskID = taskID
        }
        DispatchQueue.main.async {
            guard appState.selectedTaskID == taskID else {
                return
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollProxy.scrollTo(workspaceBottomAnchorID(for: taskID), anchor: .bottom)
            }
        }
    }

    private func workspaceSessionStatusTitle(for task: Task) -> String {
        switch task.sessionStatus {
        case .running:
            return appState.text(zh: "运行中", en: "Running")
        case .open:
            return appState.text(zh: "开放中", en: "Open")
        case .archived:
            return appState.text(zh: "已归档", en: "Archived")
        }
    }

    private func workspaceSessionStatusTint(for task: Task) -> Color {
        switch task.sessionStatus {
        case .running:
            return .blue
        case .open:
            return .teal
        case .archived:
            return .green
        }
    }

    private func workspaceSessionStatusSymbol(for task: Task) -> String {
        switch task.sessionStatus {
        case .running:
            return "bolt.fill"
        case .open:
            return "ellipsis.message"
        case .archived:
            return "archivebox.fill"
        }
    }

    private var displayedTasks: [Task] {
        let tasks = filteredTasks(from: scopeBaseTasks)
        switch listScope {
        case .active:
            return tasks.sortedForAttention()
        case .archive:
            return tasks.sortedForOverview()
        }
    }

    private var connectionTint: Color {
        switch appState.connectionState {
        case .online:
            return .green
        case .starting:
            return .orange
        case .disconnected, .configurationError:
            return .red
        }
    }

    private func syncSelectionToScope() {
        let syncStart = DispatchTime.now().uptimeNanoseconds
        guard let selectedTask = appState.selectedTask else {
            if let firstTask = displayedTasks.first {
                appState.selectTask(firstTask)
            }
            HermesDeskPerformanceLog.selection(
                "scope sync selectedTask=nil visibleTasks=\(displayedTasks.count) ms=\(HermesDeskPerformanceLog.formatElapsedMS(since: syncStart))"
            )
            return
        }

        if displayedTasks.contains(where: { $0.taskID == selectedTask.taskID }) == false {
            appState.selectTask(displayedTasks.first)
        }
        HermesDeskPerformanceLog.selection(
            "scope sync selectedTask=\(selectedTask.taskID) visibleTasks=\(displayedTasks.count) ms=\(HermesDeskPerformanceLog.formatElapsedMS(since: syncStart))"
        )
    }

    private var selectedTaskSnapshotKey: SelectedTaskSnapshotKey {
        let selectedTask = appState.selectedTask
        return SelectedTaskSnapshotKey(
            task: selectedTask,
            transcriptCount: selectedTask.map { appState.transcriptMessages(for: $0).count } ?? 0,
            pendingCount: selectedTask.map { appState.pendingOutgoingMessages(for: $0).count } ?? 0,
            transcriptDisplayMode: transcriptDisplayMode,
            taskActionFeedback: selectedTask.map { task in
                appState.selectedTaskID == task.taskID ? appState.taskActionFeedback : nil
            } ?? nil
        )
    }

    private func refreshSelectedTaskSnapshot() {
        guard let selectedTask = appState.selectedTask else {
            selectedTaskSnapshot = nil
            selectedTaskEntriesSnapshot = []
            return
        }

        selectedTaskSnapshot = selectedTask
        selectedTaskEntriesSnapshot = workspaceFeedEntries(for: selectedTask)
    }

    private func prepareComposerForNewTask() {
        composerError = nil
        appState.runLaunchError = nil
        appState.holdSelectionForNewTask()
        composerTitleDraft = ""
        composerPromptDraft = ""
        isComposerExpanded = true
    }


    private func submitComposer(for task: Task?) {
        composerError = nil
        shouldAutoScrollSelectedTask = true
        pendingForcedAutoScrollTaskID = task?.taskID
        let title = resolvedComposerTitle(for: task)
        let continuingTaskID = task?.taskID
        Swift.Task {
            do {
                try await appState.startHermesTask(title: title, prompt: composerPromptDraft, continuingTaskID: continuingTaskID)
                await MainActor.run {
                    composerPromptDraft = ""
                    if task == nil {
                        composerTitleDraft = ""
                    }
                    isComposerExpanded = false
                }
            } catch {
                await MainActor.run {
                    composerError = error.localizedDescription
                }
            }
        }
    }

    private func resolvedComposerTitle(for task: Task?) -> String? {
        let trimmedTitle = composerTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty == false {
            return trimmedTitle
        }
        if let task {
            return task.title
        }
        return nil
    }

    private func workspaceFeedEntries(for task: Task) -> [WorkspaceFeedEntry] {
        let buildStart = DispatchTime.now().uptimeNanoseconds
        let transcriptMessages = appState.transcriptMessages(for: task)
        let pendingEntries = pendingOutgoingEntries(for: task)
        if transcriptMessages.isEmpty, task.isPreview {
            return legacyWorkspaceFeedEntries(for: task)
        }
        if transcriptMessages.isEmpty {
            var entries = pendingEntries.isEmpty ? legacyWorkspaceFeedEntries(for: task) : pendingEntries

            if let streamingEntry = workspaceStreamingEntry(for: task, transcriptMessages: []) {
                entries.append(streamingEntry)
            }
            return entries
        }

        let conversationMessages = transcriptMessages.filter(task.shouldDisplayMessageInWorkspaceConversation)
        let visibleMessages = transcriptMessages.filter { message in
            task.shouldDisplayMessageInWorkspace(message, mode: transcriptDisplayMode)
        }
        let latestConversationAssistantID = conversationMessages
            .reversed()
            .first(where: { $0.role == .assistant })?
            .id

        var entries = visibleMessages.map { message in
            workspaceFeedEntry(for: message, task: task, latestConversationAssistantID: latestConversationAssistantID)
        }
        entries.append(contentsOf: pendingEntries)
        entries = entries.sorted(by: workspaceFeedEntrySort)
        // Show the streaming fallback entry for ALL running tasks (not just preview) when there is
        // no visible assistant message yet. This surfaces "Hermes is working…" while waiting for
        // the first token, and the streaming draft text once tokens arrive.
        let hasVisibleAssistantMessage = visibleMessages.contains { $0.role == .assistant }
        if !hasVisibleAssistantMessage,
           let streamingEntry = workspaceStreamingEntry(for: task, transcriptMessages: visibleMessages) {
            entries.append(streamingEntry)
        }
        if task.isPreview,
           let artifact = task.artifact,
           artifact.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           artifact.summary != conversationMessages.last?.displayText {
            entries.append(
                WorkspaceFeedEntry(
                    id: "artifact-\(task.taskID)",
                    title: "Result snapshot",
                    body: artifact.summary,
                    footer: artifact.keyOutputs.prefix(2).joined(separator: " • "),
                    alignment: .leading,
                    background: Color.green.opacity(0.10),
                    tint: .green,
                    monospaced: false,
                    bubbleStyle: .success
                )
            )
        }
        let buildElapsedMS = Double(DispatchTime.now().uptimeNanoseconds - buildStart) / 1_000_000
        if buildElapsedMS >= 8 {
            HermesDeskPerformanceLog.render(
                "feed build slow task=\(task.taskID) ms=\(String(format: "%.2f", buildElapsedMS)) messages=\(transcriptMessages.count) taskEvents=\(task.taskEvents.count) pending=\(pendingEntries.count) mode=\(transcriptDisplayMode.rawValue)"
            )
        }
        return entries
    }

    private func legacyWorkspaceFeedEntries(for task: Task) -> [WorkspaceFeedEntry] {
        let requestBody = task.requestText ?? task.title
        var entries: [WorkspaceFeedEntry] = [
            WorkspaceFeedEntry(
                id: "task-request-\(task.taskID)",
                title: "You asked Hermes",
                body: requestBody,
                footer: task.createdAt.formatted(date: .abbreviated, time: .shortened),
                alignment: .trailing,
                background: Color.accentColor.opacity(0.16),
                tint: .accentColor,
                monospaced: false
            )
        ]

        if let runtimeEntry = workspaceStreamingEntry(for: task, transcriptMessages: []) {
            entries.append(runtimeEntry)
        } else if let resultSummary = workspaceResultSummary(for: task), resultSummary != requestBody {
            entries.append(
                WorkspaceFeedEntry(
                    id: "task-summary-\(task.taskID)",
                    title: task.state == .succeeded ? "Hermes result" : "Hermes update",
                    body: resultSummary,
                    footer: task.state.localizedDisplayTitle,
                    alignment: .leading,
                    background: Color.secondary.opacity(0.08),
                    tint: task.state.tint,
                    monospaced: false
                )
            )
        }

        if task.isPreview, let artifact = task.artifact {
            entries.append(
                WorkspaceFeedEntry(
                    id: "artifact-\(task.taskID)",
                    title: "Result snapshot",
                    body: artifact.summary,
                    footer: artifact.keyOutputs.prefix(2).joined(separator: " • "),
                    alignment: .leading,
                    background: Color.green.opacity(0.10),
                    tint: .green,
                    monospaced: false
                )
            )
        }

        return entries
    }

    private func workspaceFeedEntry(
        for message: HermesConversationMessage,
        task: Task,
        latestConversationAssistantID: Int64?
    ) -> WorkspaceFeedEntry {
        let isStreamingAssistantMessage =
            message.role == .assistant &&
            message.id < 0 &&
            task.sessionStatus == .running &&
            latestConversationAssistantID == message.id
        let alignment: WorkspaceFeedEntry.Alignment = message.role == .user ? .trailing : .leading
        let background: Color
        let tint: Color
        let title: String
        let bubbleStyle: WorkspaceFeedEntry.BubbleStyle

        switch message.role {
        case .user:
            title = ""
            background = Color.accentColor.opacity(0.16)
            tint = .accentColor
            bubbleStyle = .automatic
        case .assistant:
            let isLatestStableAnswer = task.state.isTerminal && latestConversationAssistantID == message.id
            title = ""
            background = isLatestStableAnswer ? Color.green.opacity(0.08) : Color.secondary.opacity(0.08)
            tint = isLatestStableAnswer ? .green : .secondary
            bubbleStyle = isLatestStableAnswer ? .success : .automatic
        case .tool:
            title = message.toolName.map { "Tool · \($0)" } ?? "Tool output"
            background = Color.secondary.opacity(0.08)
            tint = .secondary
            bubbleStyle = .tool
        case .system:
            title = "System"
            background = Color.orange.opacity(0.08)
            tint = .orange
            bubbleStyle = .system
        case .sessionMeta, .unknown:
            title = "Hermes"
            background = Color.secondary.opacity(0.08)
            tint = .secondary
            bubbleStyle = .automatic
        }

        return WorkspaceFeedEntry(
            id: appState.stableWorkspaceEntryID(for: message, taskID: task.taskID),
            title: title,
            body: message.displayText,
            footer: message.timestamp.formatted(date: .omitted, time: .shortened),
            alignment: alignment,
            background: background,
            tint: tint,
            monospaced: message.role == .tool,
            bubbleStyle: bubbleStyle,
            timestamp: message.timestamp,
            sortPriority: message.role == .assistant ? 2 : 1,
            usesMarkdown: message.role == .assistant,
            isStreamingMarkdown: isStreamingAssistantMessage
        )
    }

    private func workspaceEventFeedEntries(for task: Task) -> [WorkspaceFeedEntry] {
        task.taskEvents.compactMap { event in
            switch event.type {
            case .output, .result:
                return nil
            case .step, .log, .clarify, .stateChange, .confirm, .error:
                return workspaceFeedEntry(for: event)
            }
        }
    }

    private func workspaceFeedEntry(for event: TaskEvent) -> WorkspaceFeedEntry {
        let eventDetail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bubbleStyle: WorkspaceFeedEntry.BubbleStyle = {
            switch event.type {
            case .step:
                return .tool
            case .log, .clarify, .stateChange, .confirm, .error, .output, .result:
                return .system
            }
        }()

        return WorkspaceFeedEntry(
            id: "task-event-\(event.eventID)",
            title: workspaceEventTitle(for: event),
            body: workspaceEventHeadline(for: event),
            footer: [
                eventDetail?.isEmpty == false ? eventDetail : nil,
                event.timestamp.formatted(date: .omitted, time: .shortened)
            ].compactMap { $0 }.joined(separator: " · "),
            alignment: .leading,
            background: workspaceEventBackground(for: event),
            tint: workspaceEventTint(for: event),
            monospaced: event.type == .log || event.type == .clarify,
            showsProgress: event.type == .step || event.type == .stateChange,
            bubbleStyle: bubbleStyle,
            timestamp: event.timestamp,
            sortPriority: 0,
            usesMarkdown: false,
            isStreamingMarkdown: false
        )
    }

    private func workspaceFeedEntrySort(lhs: WorkspaceFeedEntry, rhs: WorkspaceFeedEntry) -> Bool {
        switch (lhs.timestamp, rhs.timestamp) {
        case let (l?, r?):
            if l != r {
                return l < r
            }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        if lhs.sortPriority != rhs.sortPriority {
            return lhs.sortPriority < rhs.sortPriority
        }
        return lhs.id < rhs.id
    }

    private func pendingOutgoingEntries(for task: Task) -> [WorkspaceFeedEntry] {
        let visibleMessageFingerprints = Set(
            appState.transcriptMessages(for: task).map { message in
                PendingOutgoingFingerprint(
                    sessionID: message.sessionID,
                    normalizedContent: normalizedPendingOutgoingContent(message.displayText)
                )
            }
        )

        return appState.pendingOutgoingMessages(for: task).filter { pendingMessage in
            visibleMessageFingerprints.contains(
                PendingOutgoingFingerprint(
                    sessionID: pendingMessage.sessionID,
                    normalizedContent: normalizedPendingOutgoingContent(pendingMessage.content)
                )
            ) == false
        }.map { pendingMessage in
            WorkspaceFeedEntry(
                id: appState.stableWorkspaceEntryID(for: pendingMessage, taskID: task.taskID),
                title: "",
                body: pendingMessage.content,
                footer: pendingMessage.timestamp.formatted(date: .omitted, time: .shortened),
                alignment: .trailing,
                background: Color.accentColor.opacity(0.16),
                tint: .accentColor,
                monospaced: false,
                showsProgress: true,
                bubbleStyle: .automatic,
                timestamp: pendingMessage.timestamp,
                sortPriority: 1,
                usesMarkdown: false,
                isStreamingMarkdown: false
            )
        }
    }

    private struct PendingOutgoingFingerprint: Hashable {
        let sessionID: String
        let normalizedContent: String
    }

    private func normalizedPendingOutgoingContent(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func workspaceStreamingEntry(for task: Task, transcriptMessages: [HermesConversationMessage]) -> WorkspaceFeedEntry? {
        guard task.sessionStatus == .running else {
            return nil
        }

        if let streamingText = workspaceStreamingText(for: task, transcriptMessages: transcriptMessages) {
            return WorkspaceFeedEntry(
                id: "streaming-\(task.taskID)",
                title: "Hermes · draft",
                body: streamingText,
                footer: "Streaming live now · not final yet",
                alignment: .leading,
                background: Color.blue.opacity(0.08),
                tint: .blue,
                monospaced: false,
                showsProgress: true,
                bubbleStyle: .progress
            )
        }
        return nil
    }

    private func workspaceProgressActivityEntry(for task: Task, progressMessages: [HermesConversationMessage]) -> WorkspaceFeedEntry? {
        let progressEvents = taskProgressEvents(for: task)
        let totalUpdates = progressMessages.count + progressEvents.count
        guard totalUpdates > 0 else {
            return nil
        }

        let recentTools = Array(progressMessages.compactMap(\.toolName).suffix(3))
        let footerParts = [
            recentTools.isEmpty ? nil : recentTools.joined(separator: " • "),
            "Open the Progress tab for the full execution trail"
        ].compactMap { $0 }

        return WorkspaceFeedEntry(
            id: "progress-activity-\(task.taskID)-\(totalUpdates)",
            title: "Task progress",
            body: "Captured \(totalUpdates) low-level update\(totalUpdates == 1 ? "" : "s") from tools, terminals, and streaming execution details. Those logs stay in Task progress instead of the main conversation.",
            footer: footerParts.joined(separator: " · "),
            alignment: .leading,
            background: Color.secondary.opacity(0.08),
            tint: .secondary,
            monospaced: false,
            bubbleStyle: .tool
        )
    }

    private func workspaceStreamingText(for task: Task, transcriptMessages: [HermesConversationMessage]) -> String? {
        let streamingText = task.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard streamingText.isEmpty == false else {
            return nil
        }
        guard HermesWorkspaceContentClassifier.looksLikeProgressLog(streamingText) == false else {
            return nil
        }

        // Check ALL assistant messages in the provided transcript (which may include
        // locally-created negative-ID messages shown via the updated visibleMessages filter).
        // If the streaming text is already displayed via the transcript, suppress the streaming
        // entry to avoid showing the same content twice.
        let lastAssistantMessage = transcriptMessages
            .reversed()
            .first(where: { $0.role == .assistant })?
            .displayText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let lastAssistantMessage, lastAssistantMessage == streamingText {
            return nil
        }

        return streamingText
    }

    private func workspaceStreamingPreview(for task: Task) -> String? {
        guard let streamingText = workspaceStreamingText(for: task, transcriptMessages: appState.transcriptMessages(for: task)) else {
            return nil
        }
        return streamingText.workspaceSnippet(maxLength: 220)
    }

    private func workspaceResultSummary(for task: Task) -> String? {
        if task.isPreview,
           let artifactSummary = task.artifact?.summary.trimmingCharacters(in: .whitespacesAndNewlines),
           artifactSummary.isEmpty == false {
            return artifactSummary
        }

        let transcriptMessages = appState.transcriptMessages(for: task)
        if let lastAssistantMessage = transcriptMessages
            .reversed()
            .first(where: { $0.role == .assistant && task.shouldDisplayMessageInWorkspaceConversation($0) })?
            .displayText,
           lastAssistantMessage.isEmpty == false {
            return lastAssistantMessage
        }

        return workspaceStreamingText(for: task, transcriptMessages: transcriptMessages)
    }

    private func workspaceCurrentFocusSummary(for task: Task) -> String {
        if task.state == .waitingUser {
            return (task.runState.waitingReason ?? "Waiting for your decision before Hermes can continue.").workspaceSnippet(maxLength: 180)
        }
        if task.state == .failed {
            return (task.runState.failureMessage ?? "Hermes hit an issue and needs recovery.").workspaceSnippet(maxLength: 180)
        }
        if task.sessionStatus == .running {
            if let streamingText = workspaceStreamingText(for: task, transcriptMessages: appState.transcriptMessages(for: task)) {
                return streamingText.workspaceSnippet(maxLength: 180)
            }
            return "Hermes is working through the task. Detailed tool, terminal, and agent activity stays in Task progress."
        }
        if task.sessionStatus == .open {
            if let resultSummary = workspaceResultSummary(for: task) {
                return resultSummary.workspaceSnippet(maxLength: 180)
            }
            return "This conversation is still open. Continue chatting with Hermes in the current task."
        }
        if let resultSummary = workspaceResultSummary(for: task) {
            return resultSummary.workspaceSnippet(maxLength: 180)
        }
        return (task.requestText ?? task.currentSummary).workspaceSnippet(maxLength: 180)
    }

    private func workspaceDisplayTitle(for task: Task) -> String {
        if task.isPreview == false, let requestText = task.requestText, requestText.isEmpty == false {
            return Task.summarizedWorkspaceTitle(from: requestText)
        }
        if Task.isGenericWorkspaceTitle(task.title), let requestText = task.requestText, requestText.isEmpty == false {
            return Task.summarizedWorkspaceTitle(from: requestText)
        }
        return task.title
    }

    private func workspaceListIntroduction(for task: Task) -> String {
        let introSource = task.requestText?.workspaceSnippet(maxLength: 120) ?? workspaceDisplayTitle(for: task)
        if introSource == workspaceDisplayTitle(for: task) {
            return workspaceCurrentFocusSummary(for: task).workspaceSnippet(maxLength: 120)
        }
        return introSource
    }

    private func workspaceHeadlineSummary(for task: Task) -> String {
        workspaceCurrentFocusSummary(for: task)
    }

    private func workspaceListSummary(for task: Task) -> String {
        workspaceCurrentFocusSummary(for: task).workspaceSnippet(maxLength: 110)
    }

    private func workspaceListStatusLine(for task: Task) -> String? {
        if let statusContextLine = task.statusContextLine, statusContextLine.isEmpty == false {
            return statusContextLine
        }

        let intro = workspaceListIntroduction(for: task)
        let summary = workspaceListSummary(for: task)
        return summary == intro ? nil : summary
    }

    private func taskProgressEvents(for task: Task) -> [TaskEvent] {
        Array(
            task.taskEvents
                .filter { event in
                    switch event.type {
                    case .step, .log, .clarify, .stateChange:
                        return true
                    case .output, .confirm, .error, .result:
                        return false
                    }
                }
                .suffix(10)
                .reversed()
        )
    }

    private func taskProgressSections(for task: Task) -> [WorkspaceProgressSection] {
        let runStatusEvents = recentTaskEvents(for: task, limit: 3) { $0.type == .stateChange }
        let executionEvents = recentTaskEvents(for: task, limit: 6) { $0.type == .step }
        let agentStreamEvents = recentTaskEvents(for: task, limit: 4) { event in
            switch event.type {
            case .log, .clarify:
                return true
            case .output, .step, .stateChange, .confirm, .error, .result:
                return false
            }
        }

        return [
            WorkspaceProgressSection(
                title: "Run status",
                systemImage: "bolt.horizontal.circle",
                tint: .orange,
                events: runStatusEvents,
                emphasizeDetail: false
            ),
            WorkspaceProgressSection(
                title: "Tools & execution",
                systemImage: "hammer",
                tint: .secondary,
                events: executionEvents,
                emphasizeDetail: false
            ),
            WorkspaceProgressSection(
                title: "Agent stream",
                systemImage: "text.alignleft",
                tint: .blue,
                events: agentStreamEvents,
                emphasizeDetail: true
            )
        ].filter { $0.events.isEmpty == false }
    }

    private func recentTaskEvents(
        for task: Task,
        limit: Int,
        matching predicate: (TaskEvent) -> Bool
    ) -> [TaskEvent] {
        Array(
            task.taskEvents
                .filter(predicate)
                .suffix(limit)
                .reversed()
        )
    }

    private func taskMilestoneEvents(for task: Task) -> [TaskEvent] {
        Array(
            task.taskEvents
                .filter { event in
                    switch event.type {
                    case .confirm, .error, .result:
                        return true
                    case .step, .log, .output, .clarify, .stateChange:
                        return false
                    }
                }
                .suffix(6)
                .reversed()
        )
    }

    @ViewBuilder
    private func inspectorEventRow(_ event: TaskEvent, emphasizeDetail: Bool) -> some View {
        let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowsCollapse = inspectorDetailAllowsCollapse(detail, emphasizeDetail: emphasizeDetail)
        let isExpanded = expandedInspectorEventIDs.contains(event.id)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(workspaceEventTitle(for: event))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(workspaceEventTint(for: event))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(workspaceEventBackground(for: event), in: Capsule())

                Text(workspaceEventHeadline(for: event))
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)
                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let detail, detail.isEmpty == false {
                Text(detail)
                    .font(emphasizeDetail ? .callout.monospaced() : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(allowsCollapse && isExpanded == false ? 8 : nil)
                    .textSelection(.enabled)

                if allowsCollapse {
                    Button {
                        toggleInspectorEventExpansion(for: event.id)
                    } label: {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func inspectorDetailAllowsCollapse(_ detail: String?, emphasizeDetail: Bool) -> Bool {
        guard emphasizeDetail, let detail, detail.isEmpty == false else {
            return false
        }

        let lineCount = detail.components(separatedBy: .newlines).count
        return lineCount > 8 || detail.count > 360
    }

    private func toggleInspectorEventExpansion(for eventID: String) {
        if expandedInspectorEventIDs.contains(eventID) {
            expandedInspectorEventIDs.remove(eventID)
        } else {
            expandedInspectorEventIDs.insert(eventID)
        }
    }

    private func workspaceEventTitle(for event: TaskEvent) -> String {
        switch event.type {
        case .confirm:
            return "Approval"
        case .error:
            if let toolName = workspaceToolName(for: event) {
                return "\(workspaceToolCategoryTitle(for: toolName)) error"
            }
            return "Issue"
        case .result:
            return "Result"
        case .output:
            return "Output"
        case .step:
            if let toolName = workspaceToolName(for: event) {
                return workspaceToolCategoryTitle(for: toolName)
            }
            return "Execution"
        case .stateChange:
            return "Run status"
        case .log:
            return "Reasoning"
        case .clarify:
            return "Clarification"
        }
    }

    private func workspaceEventHeadline(for event: TaskEvent) -> String {
        guard let toolName = workspaceToolName(for: event) else {
            return event.summary
        }

        let displayName = workspaceDisplayToolName(toolName)

        switch event.type {
        case .step:
            if event.summary.hasPrefix("Started tool:") {
                return "Started \(displayName)"
            }
            if event.summary.hasPrefix("Completed tool:") {
                return "Completed \(displayName)"
            }
            return displayName
        case .error:
            return "\(displayName) failed"
        case .confirm, .result, .output, .stateChange, .log, .clarify:
            return event.summary
        }
    }

    private func workspaceToolName(for event: TaskEvent) -> String? {
        let prefixes = [
            "Started tool: ",
            "Completed tool: ",
            "Tool reported an error: "
        ]

        for prefix in prefixes where event.summary.hasPrefix(prefix) {
            let toolName = String(event.summary.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return toolName.isEmpty ? nil : toolName
        }

        return nil
    }

    private func workspaceToolCategoryTitle(for toolName: String) -> String {
        let normalized = toolName.lowercased()

        if normalized == "terminal" {
            return "Terminal"
        }
        if normalized == "skill_view" || normalized.hasPrefix("skill_") {
            return "Skill"
        }
        if normalized.hasPrefix("browser_") {
            return "Browser"
        }
        if ["read_file", "write_file", "patch", "search_files"].contains(normalized) {
            return "Files"
        }
        if normalized == "delegate_task" {
            return "Delegation"
        }
        if normalized == "clarify" {
            return "Clarification"
        }
        return "Tool"
    }

    private func workspaceDisplayToolName(_ toolName: String) -> String {
        let normalized = toolName.lowercased()

        switch normalized {
        case "terminal":
            return "Terminal"
        case "skill_view":
            return "Skill view"
        case "delegate_task":
            return "Delegate task"
        case "read_file":
            return "Read file"
        case "write_file":
            return "Write file"
        case "search_files":
            return "Search files"
        default:
            let words = toolName
                .split(separator: "_")
                .map { fragment in
                    fragment.prefix(1).uppercased() + fragment.dropFirst()
                }
            return words.joined(separator: " ")
        }
    }

    private func workspaceEventTint(for event: TaskEvent) -> Color {
        switch event.type {
        case .confirm:
            return .orange
        case .error:
            return .red
        case .result:
            return .green
        case .output:
            return .blue
        case .clarify:
            return .orange
        case .step, .stateChange, .log:
            return .secondary
        }
    }

    private func workspaceEventBackground(for event: TaskEvent) -> Color {
        switch event.type {
        case .confirm:
            return Color.orange.opacity(0.08)
        case .error:
            return Color.red.opacity(0.08)
        case .result:
            return Color.green.opacity(0.08)
        case .output:
            return Color.blue.opacity(0.08)
        case .clarify:
            return Color.orange.opacity(0.08)
        case .step, .stateChange, .log:
            return Color.secondary.opacity(0.08)
        }
    }

    private func primaryWorkspaceActions(for task: Task) -> [TaskAction] {
        let priority: [TaskAction] = {
            switch task.state {
            case .waitingUser:
                return [.approveOnce, .approveForTask, .reject]
            case .failed:
                return [.retry, .openWorkspace, .openTerminal]
            case .running, .queued, .paused:
                return task.sessionStatus == .running ? [.stop, .openWorkspace] : [.openWorkspace]
            case .succeeded:
                return [.copyResult, .openWorkspace]
            case .cancelled:
                return [.openWorkspace]
            }
        }()

        return priority.filter { task.availableActions.contains($0) }
    }

    private func supplementalInspectorActions(for task: Task) -> [TaskAction] {
        let excluded = Set(primaryWorkspaceActions(for: task))
        return task.availableActions.filter { excluded.contains($0) == false }
    }

    private func isActionEnabled(_ action: TaskAction, for task: Task) -> Bool {
        if task.isPreview {
            return true
        }

        if task.pendingAction != nil {
            switch action {
            case .openWorkspace, .openTerminal:
                return true
            default:
                return false
            }
        }

        switch action {
        case .approveOnce, .approveForTask, .reject:
            return task.runState.approvalID != nil
        case .retry, .stop, .openTerminal, .openWorkspace, .copyResult:
            return true
        case .resume, .pause:
            return false
        }
    }

    private func workspaceFeedEdgePadding(for availableWidth: CGFloat) -> CGFloat {
        2
    }

    private func workspaceFeedOppositeInset(for availableWidth: CGFloat) -> CGFloat {
        let adaptiveInset = availableWidth * 0.12
        return min(max(adaptiveInset, 24), 80)
    }

    private func workspaceBubbleMinWidth(for entry: WorkspaceFeedEntry, availableWidth: CGFloat) -> CGFloat {
        switch entry.bubbleStyle {
        case .tool, .system:
            return min(max(availableWidth * 0.34, 220), 340)
        case .progress:
            return min(max(availableWidth * 0.28, 180), 280)
        case .automatic, .success:
            return 0
        }
    }

    private func workspaceBubbleMaxWidth(
        for availableWidth: CGFloat,
        oppositeInset: CGFloat,
        edgePadding: CGFloat
    ) -> CGFloat {
        let proposedWidth = max(availableWidth * 0.76, 280)
        let maxUsableWidth = max(availableWidth - oppositeInset - edgePadding * 2, 260)
        return min(proposedWidth, min(maxUsableWidth, 760))
    }

    private func workspaceBubbleWidth(
        for entry: WorkspaceFeedEntry,
        bubbleMaxWidth: CGFloat,
        minimumWidth: CGFloat
    ) -> CGFloat {
        let horizontalPadding: CGFloat = 32
        let contentMaxWidth = max(bubbleMaxWidth - horizontalPadding, 120)
        let titleWidth = entry.title.isEmpty ? 0 : workspaceMeasuredLineWidth(
            entry.title,
            font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        )
        let bodyWidth = workspaceMeasuredLineWidth(
            entry.body,
            font: entry.monospaced
                ? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        )
        let footerWidth = entry.footer.map {
            workspaceMeasuredLineWidth($0, font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize))
        } ?? 0

        let targetContentWidth = min(
            max(titleWidth, bodyWidth, footerWidth),
            contentMaxWidth
        )

        return max(targetContentWidth + horizontalPadding, minimumWidth)
    }

    private func workspaceMeasuredLineWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let widths = lines.map { line in
            ceil((line as NSString).size(withAttributes: attributes).width)
        }
        return widths.max() ?? 0
    }
}

private enum WorkspaceListScope: String, CaseIterable, Identifiable {
    case active
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return "In Progress"
        case .archive:
            return "Archive"
        }
    }

    var emptyTitle: String {
        switch self {
        case .active:
            return "No active task"
        case .archive:
            return "No archived task"
        }
    }

    var emptyMessage: String {
        switch self {
        case .active:
            return "Pick an agent above and create a new task to start working in this workspace."
        case .archive:
            return "Completed and stopped tasks will land here once they are ready to revisit."
        }
    }

    var emptySymbol: String {
        switch self {
        case .active:
            return "tray"
        case .archive:
            return "archivebox"
        }
    }
}

private enum WorkspaceInspectorTab: String, CaseIterable, Identifiable {
    case overview
    case artifacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Now"
        case .artifacts:
            return "Artifacts"
        }
    }
}

private enum WorkspaceTaskFilter: String, CaseIterable, Identifiable {
    case all
    case needsInput
    case running
    case open
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .needsInput:
            return "Action Required"
        case .running:
            return "Running"
        case .open:
            return "Open"
        case .archived:
            return "Archived"
        }
    }

    var tint: Color {
        switch self {
        case .all:
            return .secondary
        case .needsInput:
            return .orange
        case .running:
            return .blue
        case .open:
            return .teal
        case .archived:
            return .green
        }
    }
}

private enum WorkspaceAgentPreset: String, CaseIterable, Identifiable {
    case hermes
    case builder
    case reviewer
    case analyst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hermes:
            return "Hermes"
        case .builder:
            return "Builder"
        case .reviewer:
            return "Reviewer"
        case .analyst:
            return "Analyst"
        }
    }

    var shortTitle: String {
        switch self {
        case .hermes:
            return "Hermes"
        case .builder:
            return "Build"
        case .reviewer:
            return "Review"
        case .analyst:
            return "Analyze"
        }
    }

    var symbolName: String {
        switch self {
        case .hermes:
            return "bolt.circle.fill"
        case .builder:
            return "hammer.circle.fill"
        case .reviewer:
            return "checkmark.seal.fill"
        case .analyst:
            return "chart.bar.xaxis"
        }
    }

    var tint: Color {
        switch self {
        case .hermes:
            return .blue
        case .builder:
            return .purple
        case .reviewer:
            return .green
        case .analyst:
            return .orange
        }
    }

    var defaultTaskTitle: String {
        switch self {
        case .hermes:
            return "Hermes task"
        case .builder:
            return "Build with Hermes"
        case .reviewer:
            return "Review with Hermes"
        case .analyst:
            return "Analyze with Hermes"
        }
    }
}

private struct WorkspaceFeedEntry: Identifiable {
    enum Alignment {
        case leading
        case trailing
    }

    enum BubbleStyle {
        case automatic
        case success
        case progress
        case tool
        case system
    }

    let id: String
    let title: String
    let body: String
    let footer: String?
    let alignment: Alignment
    let background: Color
    let tint: Color
    let monospaced: Bool
    let showsProgress: Bool
    let bubbleStyle: BubbleStyle
    let timestamp: Date?
    let sortPriority: Int
    let usesMarkdown: Bool
    let isStreamingMarkdown: Bool

    init(
        id: String,
        title: String,
        body: String,
        footer: String? = nil,
        alignment: Alignment,
        background: Color,
        tint: Color,
        monospaced: Bool,
        showsProgress: Bool = false,
        bubbleStyle: BubbleStyle = .automatic,
        timestamp: Date? = nil,
        sortPriority: Int = 0,
        usesMarkdown: Bool = false,
        isStreamingMarkdown: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.footer = footer
        self.alignment = alignment
        self.background = background
        self.tint = tint
        self.monospaced = monospaced
        self.showsProgress = showsProgress
        self.bubbleStyle = bubbleStyle
        self.timestamp = timestamp
        self.sortPriority = sortPriority
        self.usesMarkdown = usesMarkdown
        self.isStreamingMarkdown = isStreamingMarkdown
    }
}

private struct WorkspaceBubblePalette {
    let top: Color
    let bottom: Color
    let stroke: Color
    let shadow: Color
}

private struct SelectedTaskSnapshotKey: Equatable {
    let task: Task?
    let transcriptCount: Int
    let pendingCount: Int
    let transcriptDisplayMode: HermesWorkspaceTranscriptMode
    let taskActionFeedback: String?
}

private struct WorkspaceBubbleShape: InsettableShape {
    let alignment: WorkspaceFeedEntry.Alignment
    private var insetAmount: CGFloat = 0

    init(alignment: WorkspaceFeedEntry.Alignment) {
        self.alignment = alignment
    }

    func path(in rect: CGRect) -> Path {
        let pathRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let trailingPath = trailingBubblePath(in: pathRect)

        if alignment == .trailing {
            return trailingPath
        }

        let transform = CGAffineTransform(translationX: pathRect.midX, y: 0)
            .scaledBy(x: -1, y: 1)
            .translatedBy(x: -pathRect.midX, y: 0)
        return trailingPath.applying(transform)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    private func trailingBubblePath(in rect: CGRect) -> Path {
        // iMessage-like bubble: rounded rect with a small curved tail
        // centered on the side edge instead of hanging off the bottom corner.
        let cr = min(18, rect.height * 0.28, rect.width * 0.12)
        let tailH: CGFloat = 10    // tail vertical span
        let tailW: CGFloat = 6     // how far the tail pokes out to the right
        let bodyRight = rect.maxX - tailW  // main body right edge, leaving room for the tail

        // Tail anchor sits around the middle of the right edge.
        let tailCenterY = rect.midY + min(4, rect.height * 0.06)
        let tailTopY = tailCenterY - tailH * 0.55
        let tailBotY = tailCenterY + tailH * 0.45
        let tailTipY = tailCenterY

        var path = Path()

        // Top-left corner
        path.move(to: CGPoint(x: rect.minX + cr, y: rect.minY))

        // Top edge → top-right corner (body right, not full rect)
        path.addLine(to: CGPoint(x: bodyRight - cr, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: bodyRight, y: rect.minY + cr),
            control: CGPoint(x: bodyRight, y: rect.minY)
        )

        // Right edge of body, down to where tail starts
        path.addLine(to: CGPoint(x: bodyRight, y: tailTopY))

        // Curve outward to form the tail tip
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: tailTipY),
            control1: CGPoint(x: bodyRight, y: tailTopY + tailH * 0.3),
            control2: CGPoint(x: rect.maxX, y: tailTipY - tailH * 0.2)
        )

        // Curve back inward from the tip
        path.addCurve(
            to: CGPoint(x: bodyRight, y: tailBotY),
            control1: CGPoint(x: rect.maxX, y: tailTipY + tailH * 0.3),
            control2: CGPoint(x: bodyRight, y: tailBotY - tailH * 0.15)
        )

        // Continue down the right edge to bottom-right corner
        path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - cr))
        path.addQuadCurve(
            to: CGPoint(x: bodyRight - cr, y: rect.maxY),
            control: CGPoint(x: bodyRight, y: rect.maxY)
        )

        // Bottom edge → bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cr),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        // Left edge → top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cr))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cr, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

private struct WorkspaceFeedTailAnchor: Equatable {
    let id: String
    let body: String
    let footer: String?
    let showsProgress: Bool
}

private struct WorkspaceScrollMetrics: Equatable {
    var offsetY: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    var isNearBottom: Bool {
        offsetY + viewportHeight >= contentHeight - 48
    }
}

private struct WorkspaceScrollCommand {
    enum Kind {
        case restore(previousOffsetY: CGFloat, previousContentHeight: CGFloat)
    }

    let id = UUID()
    let kind: Kind

    static func restore(previousOffsetY: CGFloat, previousContentHeight: CGFloat) -> WorkspaceScrollCommand {
        WorkspaceScrollCommand(kind: .restore(previousOffsetY: previousOffsetY, previousContentHeight: previousContentHeight))
    }
}

private struct WorkspaceScrollObserver: NSViewRepresentable {
    @Binding var metrics: WorkspaceScrollMetrics
    @Binding var command: WorkspaceScrollCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator(metrics: $metrics, command: $command)
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        context.coordinator.metrics = $metrics
        context.coordinator.command = $command
        context.coordinator.attach(to: nsView)
        context.coordinator.applyPendingCommand()
    }

    static func dismantleNSView(_ nsView: ObserverView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.coordinator = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var metrics: Binding<WorkspaceScrollMetrics>
        var command: Binding<WorkspaceScrollCommand?>

        private weak var hostView: NSView?
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?
        private var lastAppliedCommandID: UUID?

        init(metrics: Binding<WorkspaceScrollMetrics>, command: Binding<WorkspaceScrollCommand?>) {
            self.metrics = metrics
            self.command = command
        }

        func attach(to view: NSView) {
            hostView = view
            DispatchQueue.main.async { [weak self] in
                self?.resolveScrollView()
            }
        }

        func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
                self.frameObserver = nil
            }
            scrollView = nil
            hostView = nil
        }

        func applyPendingCommand() {
            guard let command = command.wrappedValue else {
                return
            }
            guard lastAppliedCommandID != command.id else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.apply(command)
            }
        }

        private func resolveScrollView() {
            guard let hostView else {
                return
            }
            guard let enclosingScrollView = hostView.enclosingScrollView else {
                return
            }
            guard scrollView !== enclosingScrollView else {
                captureMetrics()
                return
            }

            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }

            scrollView = enclosingScrollView
            enclosingScrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: enclosingScrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Swift.Task { @MainActor [weak self] in
                    self?.captureMetrics()
                }
            }
            if let documentView = enclosingScrollView.documentView {
                documentView.postsFrameChangedNotifications = true
                frameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self] _ in
                    Swift.Task { @MainActor [weak self] in
                        self?.captureMetrics()
                    }
                }
            }
            captureMetrics()
        }

        private func captureMetrics() {
            guard let scrollView, let documentView = scrollView.documentView else {
                return
            }

            let clipView = scrollView.contentView
            let nextMetrics = WorkspaceScrollMetrics(
                offsetY: clipView.bounds.origin.y,
                contentHeight: documentView.bounds.height,
                viewportHeight: clipView.bounds.height
            )

            if metrics.wrappedValue != nextMetrics {
                metrics.wrappedValue = nextMetrics
            }
        }

        private func apply(_ command: WorkspaceScrollCommand) {
            resolveScrollView()
            guard let scrollView, let documentView = scrollView.documentView else {
                return
            }

            let clipView = scrollView.contentView
            let targetOffsetY: CGFloat
            switch command.kind {
            case let .restore(previousOffsetY, previousContentHeight):
                let delta = documentView.bounds.height - previousContentHeight
                targetOffsetY = max(0, previousOffsetY + delta)
            }

            clipView.scroll(to: CGPoint(x: clipView.bounds.origin.x, y: targetOffsetY))
            scrollView.reflectScrolledClipView(clipView)
            captureMetrics()
            lastAppliedCommandID = command.id
            self.command.wrappedValue = nil
        }
    }

    @MainActor
    final class ObserverView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            coordinator?.attach(to: self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: self)
        }
    }
}

private struct WorkspaceProgressSection: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let events: [TaskEvent]
    let emphasizeDetail: Bool
}

private extension String {
    func workspaceSnippet(maxLength: Int) -> String {
        let collapsed = WorkspaceMarkdownPreviewFormatter.plainText(self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > maxLength else {
            return collapsed
        }
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
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
            return "Open Terminal"
        case .openWorkspace:
            return "Open Workspace"
        case .copyResult:
            return "Copy Result"
        }
    }

    var symbolName: String {
        switch self {
        case .approveOnce, .approveForTask:
            return "checkmark.circle.fill"
        case .reject:
            return "xmark.circle.fill"
        case .retry:
            return "arrow.clockwise.circle.fill"
        case .resume:
            return "play.circle.fill"
        case .pause:
            return "pause.circle.fill"
        case .stop:
            return "stop.circle.fill"
        case .openTerminal:
            return "terminal"
        case .openWorkspace:
            return "rectangle.on.rectangle"
        case .copyResult:
            return "doc.on.doc"
        }
    }
}
