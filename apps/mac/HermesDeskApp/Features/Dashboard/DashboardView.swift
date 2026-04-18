import AppCore
import AppKit
import HermesKit
import SwiftUI

private enum HermesDeskRenderPerformanceLog {
    static func append(_ message: String) {
        guard ProcessInfo.processInfo.environment["HERMES_DESK_DEBUG_LOGS"] == "1" else {
            return
        }
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let directoryURL = supportURL.appending(path: "HermesDesk", directoryHint: .isDirectory)
        let fileURL = directoryURL.appending(path: "run-events-debug.log")
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
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

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppStateStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var listScope: WorkspaceListScope = .active
    @State private var taskFilter: WorkspaceTaskFilter = .all
    @State private var transcriptDisplayMode: HermesWorkspaceTranscriptMode = .full
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
    @State private var expandedInspectorSummaryFieldIDs: Set<String> = []
    @State private var highlightedInspectorSummaryFieldIDs: Set<String> = []
    @State private var lastInspectorSummaryValues: [String: String] = [:]
    @State private var inspectorSummaryHighlightTokens: [String: UUID] = [:]
    @State private var selectedTaskIDSnapshot: Task.ID?
    @State private var selectedTaskDerivedSnapshot: SelectedTaskDerivedSnapshot?
    @State private var selectedTaskEntriesSignature: SelectedTaskEntriesSignature?
    @State private var selectedTaskEntriesSnapshot: [WorkspaceFeedEntry] = []
    @State private var animatedWorkspaceTaskID: Task.ID?
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

    private var selectedTaskViewTask: Task? {
        appState.selectedTask
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

            taskSummaryStrip
                .padding(.horizontal, 20)

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
        ZStack {
            workspaceCanvasBackground

            VStack(spacing: 0) {
                if let task = selectedTaskViewTask {
                    let entries = selectedTaskEntriesSnapshot
                    workspaceHeader(task)
                    Divider()
                        .overlay(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06))
                    GeometryReader { geometry in
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) {
                                    automaticLoadOlderMessagesSentinel(for: task)
                                        .frame(maxWidth: 860)
                                    let availableFeedWidth = max(geometry.size.width - 48, 320)
                                    ForEach(entries) { entry in
                                        workspaceFeedRow(entry, task: task, availableWidth: availableFeedWidth)
                                            .id(entry.id)
                                            .transition(workspaceFeedEntryTransition(for: entry))
                                    }
                                    Color.clear
                                        .frame(height: 1)
                                        .id(workspaceBottomAnchorID(for: task.taskID))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                                .animation(
                                    animatedWorkspaceTaskID == task.taskID
                                        ? .spring(response: 0.46, dampingFraction: 0.90, blendDuration: 0.20)
                                        : nil,
                                    value: workspaceFeedAnimationKey(taskID: task.taskID, entries: entries)
                                )
                            }
                            .background(
                                WorkspaceScrollObserver(
                                    metrics: $workspaceScrollMetrics,
                                    command: $workspaceScrollCommand
                                )
                            )
                            .onAppear {
                                prepareWorkspaceFeedAnimation(for: task.taskID)
                                shouldAutoScrollSelectedTask = true
                                pendingForcedAutoScrollTaskID = task.taskID
                                queueWorkspaceScrollToBottom(using: scrollProxy, for: task.taskID, force: true)
                            }
                            .onChange(of: task.taskID) { _, _ in
                                prepareWorkspaceFeedAnimation(for: task.taskID)
                                autoLoadingOlderTaskID = nil
                                automaticOlderLoadingEnabledTaskID = nil
                                shouldAutoScrollSelectedTask = true
                                pendingForcedAutoScrollTaskID = task.taskID
                                workspaceScrollMetrics = WorkspaceScrollMetrics()
                                queueWorkspaceScrollToBottom(using: scrollProxy, for: task.taskID, force: true)
                            }
                            .onChange(of: workspaceFeedTailAnchor(entries, task: task)) { _, _ in
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
                                .frame(maxWidth: 860)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            workspaceComposerInset(task: selectedTaskViewTask)
        }
    }

    private func workspaceComposerInset(task: Task?) -> some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.black.opacity(colorScheme == .dark ? 0.16 : 0.05))
            workspaceComposer(task: task)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .background(.ultraThinMaterial)
        }
    }

    private func shouldShowWorkspaceRunningStatusBar(for task: Task) -> Bool {
        guard task.sessionStatus == .running else {
            return false
        }

        return workspaceStreamingPreview(for: task) == nil
    }

    private func workspaceHeaderRunStatusPill(for task: Task) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(appState.systemText(task.runState.phaseLabel))
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.10), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
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

    private var workspaceCanvasBackground: some View {
        ZStack {
            LinearGradient(
                colors: workspaceCanvasGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.02 : 0.28))
                .blur(radius: colorScheme == .dark ? 0 : 36)
        }
        .ignoresSafeArea()
    }

    private var workspaceCanvasGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(nsColor: .windowBackgroundColor),
                Color.black.opacity(0.92)
            ]
        }

        return [
            Color(red: 0.98, green: 0.96, blue: 0.89),
            Color(red: 0.97, green: 0.94, blue: 0.86),
            Color(red: 0.95, green: 0.93, blue: 0.87)
        ]
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
                        if shouldShowWorkspaceRunningStatusBar(for: task) {
                            workspaceHeaderRunStatusPill(for: task)
                        }
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
                            workspaceMetaPill(systemImage: "sparkles", text: appState.text(zh: "示例", en: "Preview"), tint: .secondary)
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
        .background(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.38))
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
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06), lineWidth: 1)
        )
    }

    private func workspaceStatusStrip(_ task: Task) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                workspaceStatusCard(
                    title: appState.text(zh: "阶段", en: "Phase"),
                    value: appState.systemText(task.runState.phaseLabel),
                    tint: workspaceSessionStatusTint(for: task),
                    systemImage: workspaceSessionStatusSymbol(for: task)
                )
                workspaceStatusCard(
                    title: appState.text(zh: "当前重点", en: "Queue focus"),
                    value: workspaceQueueFocusTitle(for: task),
                    tint: workspaceQueueFocusTint(for: task),
                    systemImage: workspaceQueueFocusSymbol(for: task)
                )
                if let streamingSummary = workspaceStreamingPreview(for: task) {
                    workspaceStatusCard(
                        title: appState.text(zh: "流式输出", en: "Streaming"),
                        value: streamingSummary,
                        tint: .blue,
                        systemImage: "ellipsis.message"
                    )
                } else if task.sessionStatus == .running {
                    workspaceStatusCard(
                        title: appState.text(zh: "进展", en: "Progress"),
                        value: appState.text(zh: "Hermes 正在处理这个任务。更细的工具、终端和 Agent 活动会显示在“任务进展”里。", en: "Hermes is working through the task. Detailed tool, terminal, and agent activity stays in Task progress."),
                        tint: .blue,
                        systemImage: "chart.bar.doc.horizontal"
                    )
                }
                if let observationStatusLine = task.runState.observationStatusLine {
                    workspaceStatusCard(
                        title: appState.text(zh: "实时流", en: "Live feed"),
                        value: appState.systemText(observationStatusLine),
                        tint: .orange,
                        systemImage: "bolt.horizontal.circle"
                    )
                }
                if task.sessionStatus != .running, let resultSummary = workspaceResultSummary(for: task) {
                    workspaceStatusCard(
                        title: task.state == .succeeded
                            ? appState.text(zh: "结果", en: "Result")
                            : appState.text(zh: "最新有效回复", en: "Latest useful answer"),
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
                Label(appState.text(zh: "任务概览", en: "Task overview"), systemImage: "square.text.square")
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
                title: appState.text(zh: "目标", en: "Goal"),
                value: task.requestText ?? task.title,
                tint: .secondary
            )
            workspaceBriefMetric(
                title: appState.text(zh: "当前", en: "Current"),
                value: workspaceCurrentFocusSummary(for: task),
                tint: workspaceSessionStatusTint(for: task)
            )

            if let statusLine = workspaceOverviewStatusLine(for: task) {
                workspaceBriefMetric(
                    title: appState.text(zh: "状态", en: "Status"),
                    value: statusLine,
                    tint: .secondary
                )
            }

            if let sessionBindingSummary = task.sessionBindingSummary {
                Text(appState.systemText(sessionBindingSummary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(colorScheme == .dark ? 0.14 : 0.06), lineWidth: 1)
        )
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
        if let cached = cachedDerivedSnapshot(for: task) {
            return cached.overviewStatusLine
        }
        return makeWorkspaceOverviewStatusLine(for: task, resultSummary: workspaceResultSummary(for: task))
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
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.22 : 0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func workspaceFeedRow(_ entry: WorkspaceFeedEntry, task: Task, availableWidth: CGFloat) -> some View {
        let palette = workspaceBubblePalette(for: entry)
        let body = workspaceEntryBody(entry, task: task)
        let titleColor: Color = entry.alignment == .trailing ? Color.white.opacity(0.96) : entry.tint
        let bodyColor: Color = entry.alignment == .trailing ? Color.white : Color.primary
        let footerColor: Color = entry.alignment == .trailing ? Color.white.opacity(0.74) : Color.secondary
        let progressTint: Color = entry.alignment == .trailing ? Color.white.opacity(0.88) : entry.tint
        let shouldShowHeader = entry.title.isEmpty == false
        let edgePadding = workspaceFeedEdgePadding(for: availableWidth)
        let oppositeInset = workspaceFeedOppositeInset(for: availableWidth)
        let bubbleContentAlignment: HorizontalAlignment = entry.alignment == .trailing ? .trailing : .leading
        let bubbleMaxWidth = workspaceBubbleMaxWidth(
            for: availableWidth,
            oppositeInset: oppositeInset,
            edgePadding: edgePadding
        )
        let bubbleMinWidth = workspaceBubbleMinWidth(for: entry, availableWidth: bubbleMaxWidth)
        let contentMaxWidth = max(bubbleMaxWidth - 32, 120)

        if workspaceUsesPlainAssistantLayout(for: entry) {
            VStack(alignment: .leading, spacing: 10) {
                if shouldShowHeader {
                    Text(entry.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.tint)
                }

                Group {
                    if entry.monospaced {
                        Text(body)
                            .font(.subheadline.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        workspaceBodyView(entry, task: task)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)

                if let footer = entry.footer {
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, edgePadding + 4)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let bubble = VStack(alignment: bubbleContentAlignment, spacing: 10) {
                if shouldShowHeader {
                    Text(entry.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(titleColor)
                        .frame(
                            maxWidth: entry.alignment == .trailing ? nil : contentMaxWidth,
                            alignment: entry.alignment == .trailing ? .trailing : .leading
                        )
                }

                Group {
                    if entry.monospaced {
                        Text(body)
                            .font(.subheadline.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(
                                maxWidth: entry.alignment == .trailing ? nil : contentMaxWidth,
                                alignment: entry.alignment == .trailing ? .trailing : .leading
                            )
                    } else {
                        workspaceBodyView(entry, task: task)
                            .frame(
                                maxWidth: entry.alignment == .trailing ? nil : contentMaxWidth,
                                alignment: entry.alignment == .trailing ? .trailing : .leading
                            )
                    }
                }
                .foregroundStyle(bodyColor)
                .textSelection(.enabled)

                if let footer = entry.footer {
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(footerColor)
                        .frame(
                            maxWidth: entry.alignment == .trailing ? nil : contentMaxWidth,
                            alignment: entry.alignment == .trailing ? .trailing : .leading
                        )
                }
            }
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .frame(minWidth: bubbleMinWidth > 0 ? bubbleMinWidth : nil, alignment: .leading)
                .background {
                    workspaceFeedBubbleBackground(for: entry, palette: palette)
                }

            HStack(alignment: .center, spacing: 10) {
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
    }

    private func workspaceUsesPlainAssistantLayout(for entry: WorkspaceFeedEntry) -> Bool {
        entry.alignment == .leading && entry.monospaced == false && (entry.usesMarkdown || entry.isStreamingMarkdown)
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
                top: Color(
                    nsColor: colorScheme == .dark ? .controlBackgroundColor : .textBackgroundColor
                ),
                bottom: Color(
                    nsColor: colorScheme == .dark ? .windowBackgroundColor : .controlBackgroundColor
                ),
                stroke: colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055),
                shadow: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.022)
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
                        Label(appState.text(zh: "启动中…", en: "Starting…"), systemImage: "hourglass")
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
            if let task = selectedTaskViewTask {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.text(zh: "检查面板", en: "Inspector"))
                            .font(.title3.weight(.semibold))
                        Text(appState.text(zh: "查看当前所选任务的状态、步骤、日志和恢复工具。", en: "Status, steps, logs, and recovery tools for the selected task."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            inspectorOverview(task)
                        }
                        .padding(20)
                    }
                }
            } else {
                ContentUnavailableView(
                    appState.text(zh: "请选择一个任务", en: "Choose a task"),
                    systemImage: "sidebar.right",
                    description: Text(appState.text(zh: "从左侧选择一个任务，以查看状态、步骤、日志和恢复细节。", en: "Pick a task from the left to inspect status, steps, logs, and recovery details."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
        }
    }

    private func inspectorOverview(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            inspectorTaskSummary(task)

            inspectorCard(title: appState.text(zh: "当前 / 下一步", en: "Now / Next"), systemImage: task.state.symbolName) {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorLine(label: appState.text(zh: "状态", en: "Status"), value: inspectorStatusValue(for: task))
                    inspectorLine(label: appState.text(zh: "最近更新", en: "Last update"), value: task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    inspectorLine(label: appState.text(zh: "建议下一步", en: "Recommended next step"), value: inspectorNextStepValue(for: task))

                    if let waitingReason = task.runState.waitingReason {
                        inspectorLine(label: appState.text(zh: "等待原因", en: "Waiting on"), value: appState.systemText(waitingReason))
                    }
                    if let pendingAction = task.pendingAction {
                        inspectorLine(label: appState.text(zh: "执行中的动作", en: "Action in flight"), value: "\(pendingAction.actionIndicator) \(pendingAction.localizedDisplayTitle)")
                    }
                    if let observationStatusLine = task.runState.observationStatusLine {
                        inspectorLine(label: appState.text(zh: "实时流", en: "Live feed"), value: appState.systemText(observationStatusLine))
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
                inspectorCard(title: appState.text(zh: "实时流", en: "Live feed"), systemImage: "bolt.horizontal.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appState.systemText(observationStatusLine))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            appState.reconnectLiveFeed(for: task.taskID)
                        } label: {
                            Label(appState.text(zh: "重连实时流", en: "Reconnect live feed"), systemImage: "bolt.horizontal.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let feedback = appState.taskActionFeedback, appState.selectedTaskID == task.taskID {
                inspectorCard(title: appState.text(zh: "Hermes Desk 动作反馈", en: "Hermes Desk action"), systemImage: "checkmark.message") {
                    Text(appState.systemText(feedback))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if supplementalInspectorActions(for: task).isEmpty == false {
                inspectorCard(title: appState.text(zh: "快捷动作", en: "Quick actions"), systemImage: "slider.horizontal.3") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(supplementalInspectorActions(for: task), id: \.rawValue) { action in
                            Button {
                                appState.performTaskAction(action, for: task.taskID)
                            } label: {
                                Label(action.localizedDisplayTitle, systemImage: action.symbolName)
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

    private func inspectorTaskSummary(_ task: Task) -> some View {
        inspectorCard(title: appState.text(zh: "任务摘要", en: "Task summary"), systemImage: "square.text.square") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(inspectorSummaryFields(for: task)) { field in
                    inspectorSummaryLine(
                        id: field.id,
                        label: field.label,
                        value: field.value
                    )
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

        return appState.systemText(task.runState.phaseLabel)
    }

    private func inspectorNextStepValue(for task: Task) -> String {
        if let pendingAction = task.pendingAction {
            return appState.text(
                zh: "等待“\(pendingAction.localizedDisplayTitle)”处理完成",
                en: "Waiting for \(pendingAction.localizedDisplayTitle) to settle"
            )
        }

        if task.sessionStatus == .open {
            return appState.text(zh: "可以继续追问或补充上下文", en: "Continue the conversation or add more context")
        }
        if task.sessionStatus == .archived {
            return appState.text(zh: "查看结果、文件或关联运行", en: "Review results, files, or linked runs")
        }

        switch task.state {
        case .waitingUser:
            return appState.text(zh: "先处理确认，再决定是否继续", en: "Resolve the approval request before continuing")
        case .failed:
            return appState.text(zh: "先看失败原因，再决定是恢复还是重试", en: "Review the failure, then recover or retry")
        case .running:
            if task.runState.observationState != .live {
                return appState.text(zh: "先重连实时流，再继续观察执行情况", en: "Reconnect the live feed, then continue monitoring")
            }
            return appState.text(zh: "等待 Hermes 继续执行，必要时查看下方进展", en: "Let Hermes continue running and inspect progress below if needed")
        case .queued:
            return appState.text(zh: "等待前序动作完成", en: "Wait for the preceding work to finish")
        case .paused:
            return appState.text(zh: "恢复任务或继续保持暂停", en: "Resume the task or keep it paused")
        case .succeeded:
            return appState.text(zh: "复查结果，必要时继续追问", en: "Review the result and follow up if needed")
        case .cancelled:
            return appState.text(zh: "如需继续，请发起新任务或查看历史结果", en: "Start a new task or review prior results if work should continue")
        }
    }

    @ViewBuilder
    private func inspectorProgressContent(_ task: Task) -> some View {
        let progressSections = taskProgressSections(for: task)
        let milestoneEvents = taskMilestoneEvents(for: task)

        VStack(alignment: .leading, spacing: 16) {
            inspectorCard(title: appState.text(zh: "任务进展", en: "Task progress"), systemImage: "list.bullet.rectangle") {
                if progressSections.isEmpty {
                    Text(task.isPreview
                        ? appState.text(zh: "示例任务暂时还不携带详细的实时执行活动。", en: "Preview tasks do not carry detailed live execution activity yet.")
                        : appState.text(zh: "更细的工具、终端和流式活动会显示在这里。", en: "Detailed tool, terminal, and streaming activity will appear here."))
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
                                Text(appState.text(zh: "执行摘要", en: "Execution summary"))
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
                inspectorCard(title: task.sessionStatus == .running
                    ? appState.text(zh: "最新流式回复", en: "Latest streamed answer")
                    : appState.text(zh: "最新有效回复", en: "Latest useful answer"), systemImage: "text.alignleft") {
                    Text(workspaceResultSummary(for: task) ?? workspaceCurrentFocusSummary(for: task))
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            inspectorArtifacts(task)
        }
    }

    private func shouldShowInspectorLatestAnswer(for task: Task) -> Bool {
        if let cached = cachedDerivedSnapshot(for: task) {
            return cached.shouldShowInspectorLatestAnswer
        }

        let transcriptMessages = appState.transcriptMessages(for: task)
        return makeShouldShowInspectorLatestAnswer(
            for: task,
            transcriptMessages: transcriptMessages,
            streamingPreview: makeStreamingPreview(
                for: task,
                streamingText: workspaceStreamingText(for: task, transcriptMessages: transcriptMessages)
            ),
            resultSummary: workspaceResultSummary(for: task)
        )
    }

    private func inspectorExecutionSummaryLines(
        for task: Task,
        progressSections: [WorkspaceProgressSection],
        milestoneEvents: [TaskEvent]
    ) -> [(label: String, value: String)] {
        var lines: [(label: String, value: String)] = []

        if let latestMilestone = milestoneEvents.first {
            lines.append((
                label: appState.text(zh: "最新里程碑", en: "Latest milestone"),
                value: workspaceEventHeadline(for: latestMilestone)
            ))
        }

        let recentTools = recentProgressToolDisplayNames(for: task)
        if recentTools.isEmpty == false {
            lines.append((
                label: appState.text(zh: "最近工具", en: "Recent tools"),
                value: recentTools.joined(separator: " • ")
            ))
        }

        let totalUpdates = progressSections.reduce(0) { partialResult, section in
            partialResult + section.events.count
        } + milestoneEvents.count
        if totalUpdates > 0 {
            lines.append((
                label: appState.text(zh: "已捕获更新", en: "Captured updates"),
                value: appState.text(zh: "\(totalUpdates) 条最近事件", en: "\(totalUpdates) recent event\(totalUpdates == 1 ? "" : "s")")
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
                inspectorCard(title: appState.text(zh: "结果快照", en: "Result snapshot"), systemImage: "shippingbox") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appState.systemText(artifact.summary))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if artifact.keyOutputs.isEmpty == false {
                            inspectorBulletList(title: appState.text(zh: "关键产出", en: "Key outputs"), items: Array(artifact.keyOutputs.prefix(3).map(appState.systemText)))
                        }
                        if artifact.files.isEmpty == false {
                            inspectorBulletList(title: appState.text(zh: "文件", en: "Files"), items: Array(artifact.files.prefix(3).map(\.path)))
                        }
                        if artifact.nextActions.isEmpty == false {
                            inspectorBulletList(title: appState.text(zh: "下一步", en: "Next"), items: Array(artifact.nextActions.prefix(2).map(appState.systemText)))
                        }
                    }
                }
            } else {
                inspectorCard(title: task.isPreview
                    ? appState.text(zh: "结果快照", en: "Result snapshot")
                    : appState.text(zh: "对话源", en: "Conversation source"), systemImage: task.isPreview ? "shippingbox" : "ellipsis.message") {
                    Text(task.isPreview
                        ? (task.latestOutputSummary ?? appState.text(zh: "这个任务还没有产出结构化结果。", en: "This task has not emitted a structured artifact yet."))
                        : appState.text(zh: "这个任务的行为更像一条对话线程。中间的对话记录才是事实来源，而不是单独的结果快照。", en: "This task behaves like a conversation thread. The center transcript is the source of truth, not a separate result snapshot."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if task.retryParentTaskID != nil || task.retryChildTaskID != nil {
                inspectorCard(title: appState.text(zh: "关联运行", en: "Linked runs"), systemImage: "arrow.triangle.branch") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let retryParentTaskID = task.retryParentTaskID {
                            inspectorLine(label: appState.text(zh: "重试来源", en: "Retried from"), value: retryParentTaskID)
                        }
                        if let retryChildTaskID = task.retryChildTaskID {
                            inspectorLine(label: appState.text(zh: "替代运行", en: "Replacement run"), value: retryChildTaskID)
                        }
                    }
                }
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorLine(label: appState.text(zh: "任务 ID", en: "Task ID"), value: task.taskID)
                    inspectorLine(label: appState.text(zh: "Agent", en: "Agent"), value: appState.displayName(forAgentID: task.agentID))
                    inspectorLine(label: appState.text(zh: "数据流", en: "Feed"), value: appState.systemText(task.isPreview ? "Preview sample" : "Live Hermes run"))
                    inspectorLine(label: appState.text(zh: "来源", en: "Source"), value: task.source.displayTitle)
                    if let currentSessionID = task.effectiveSessionID {
                        inspectorLine(label: appState.text(zh: "会话", en: "Session"), value: currentSessionID)
                    }
                    if let rootSessionID = task.rootSessionID, rootSessionID != task.effectiveSessionID {
                        inspectorLine(label: appState.text(zh: "根会话", en: "Root session"), value: rootSessionID)
                    }
                    if let runID = task.runID {
                        inspectorLine(label: appState.text(zh: "运行", en: "Run"), value: runID)
                    }
                }
            } label: {
                Label(appState.text(zh: "技术细节", en: "Technical details"), systemImage: "info.circle")
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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(colorScheme == .dark ? 0.12 : 0.05), lineWidth: 1)
        )
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

    private func inspectorSummaryLine(id: String, label: String, value: String) -> some View {
        let allowsCollapse = inspectorSummaryAllowsCollapse(value)
        let isExpanded = expandedInspectorSummaryFieldIDs.contains(id)
        let isHighlighted = highlightedInspectorSummaryFieldIDs.contains(id)

        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(allowsCollapse && isExpanded == false ? 4 : nil)
                .textSelection(.enabled)

            if allowsCollapse {
                Button {
                    toggleInspectorSummaryExpansion(for: id)
                } label: {
                    Text(isExpanded ? appState.text(zh: "收起", en: "Show less") : appState.text(zh: "展开", en: "Show more"))
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(isHighlighted ? 0.14 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(isHighlighted ? 0.22 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 1.4), value: isHighlighted)
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
            Label(action.localizedDisplayTitle, systemImage: action.symbolName)
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
            return appState.text(zh: "开放对话", en: "Open conversation")
        }
        if task.sessionStatus == .archived {
            return appState.text(zh: "已归档", en: "Archived")
        }
        switch task.state {
        case .waitingUser:
            return appState.text(zh: "需要处理", en: "Action Required")
        case .failed:
            return appState.text(zh: "恢复队列", en: "Recovery Queue")
        case .running:
            return appState.text(zh: "进行中", en: "Running")
        case .queued, .paused:
            return appState.text(zh: "排队 / 暂停", en: "Queued & Paused")
        case .succeeded:
            return appState.text(zh: "最近结果", en: "Recent Result")
        case .cancelled:
            return appState.text(zh: "已停止", en: "Stopped")
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
    private func workspaceBodyView(_ entry: WorkspaceFeedEntry, task: Task) -> some View {
        WorkspaceMarkdownText(
            workspaceEntryBody(entry, task: task),
            isStreaming: entry.isStreamingMarkdown,
            prefersMarkdown: entry.usesMarkdown
        )
            .textSelection(.enabled)
    }

    private func workspaceFeedTailAnchor(_ entries: [WorkspaceFeedEntry], task: Task) -> WorkspaceFeedTailAnchor? {
        guard let lastEntry = entries.last else {
            return nil
        }
        return WorkspaceFeedTailAnchor(
            id: lastEntry.id,
            bodyCount: workspaceEntryBody(lastEntry, task: task).count,
            footer: lastEntry.footer,
            showsProgress: lastEntry.showsProgress
        )
    }

    private func workspaceFeedAnimationKey(taskID: Task.ID, entries: [WorkspaceFeedEntry]) -> WorkspaceFeedAnimationKey {
        WorkspaceFeedAnimationKey(taskID: taskID, entryIDs: entries.map(\.id))
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

    private func prepareWorkspaceFeedAnimation(for taskID: Task.ID) {
        guard animatedWorkspaceTaskID != taskID else {
            return
        }

        animatedWorkspaceTaskID = nil
        DispatchQueue.main.async {
            guard appState.selectedTaskID == taskID else {
                return
            }
            animatedWorkspaceTaskID = taskID
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
            taskID: selectedTask?.taskID,
            updatedAt: selectedTask?.updatedAt,
            state: selectedTask?.state,
            sessionStatus: selectedTask?.sessionStatus,
            runID: selectedTask?.runID,
            currentSummary: selectedTask?.currentSummary,
            outputCount: selectedTask?.output.count ?? 0,
            taskEventCount: selectedTask?.taskEvents.count ?? 0,
            availableActionCount: selectedTask?.availableActions.count ?? 0,
            pendingAction: selectedTask?.pendingAction,
            observationState: selectedTask?.runState.observationState,
            observationMessage: selectedTask?.runState.observationMessage,
            artifactSummary: selectedTask?.artifact?.summary,
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
            selectedTaskIDSnapshot = nil
            selectedTaskDerivedSnapshot = nil
            selectedTaskEntriesSignature = nil
            selectedTaskEntriesSnapshot = []
            lastInspectorSummaryValues = [:]
            highlightedInspectorSummaryFieldIDs = []
            inspectorSummaryHighlightTokens = [:]
            return
        }

        let derivedSnapshot = buildSelectedTaskDerivedSnapshot(for: selectedTask)
        let currentSummaryValues = derivedSnapshot.inspectorSummaryValues
        if selectedTaskIDSnapshot != selectedTask.taskID {
            lastInspectorSummaryValues = currentSummaryValues
            highlightedInspectorSummaryFieldIDs = []
            inspectorSummaryHighlightTokens = [:]
        } else {
            for (fieldID, value) in currentSummaryValues where lastInspectorSummaryValues[fieldID] != value {
                triggerInspectorSummaryHighlight(for: fieldID)
            }
            lastInspectorSummaryValues = currentSummaryValues
        }

        selectedTaskIDSnapshot = selectedTask.taskID
        selectedTaskDerivedSnapshot = derivedSnapshot
        let entriesSignature = makeSelectedTaskEntriesSignature(for: selectedTask)
        if selectedTaskEntriesSignature != entriesSignature {
            selectedTaskEntriesSnapshot = workspaceFeedEntries(for: selectedTask)
            selectedTaskEntriesSignature = entriesSignature
        }
    }

    private func cachedDerivedSnapshot(for task: Task) -> SelectedTaskDerivedSnapshot? {
        guard selectedTaskDerivedSnapshot?.taskID == task.taskID else {
            return nil
        }
        return selectedTaskDerivedSnapshot
    }

    private func buildSelectedTaskDerivedSnapshot(for task: Task) -> SelectedTaskDerivedSnapshot {
        let transcriptMessages = appState.transcriptMessages(for: task)
        let streamingText = workspaceStreamingText(for: task, transcriptMessages: transcriptMessages)
        let streamingPreview = makeStreamingPreview(for: task, streamingText: streamingText)
        let resultSummary = makeWorkspaceResultSummary(
            for: task,
            transcriptMessages: transcriptMessages,
            streamingText: streamingText
        )
        let currentFocusSummary = makeWorkspaceCurrentFocusSummary(
            for: task,
            streamingText: streamingText,
            resultSummary: resultSummary
        )
        let overviewStatusLine = makeWorkspaceOverviewStatusLine(for: task, resultSummary: resultSummary)
        let shouldShowInspectorLatestAnswer = makeShouldShowInspectorLatestAnswer(
            for: task,
            transcriptMessages: transcriptMessages,
            streamingPreview: streamingPreview,
            resultSummary: resultSummary
        )

        return SelectedTaskDerivedSnapshot(
            taskID: task.taskID,
            currentFocusSummary: currentFocusSummary,
            overviewStatusLine: overviewStatusLine,
            streamingPreview: streamingPreview,
            resultSummary: resultSummary,
            shouldShowInspectorLatestAnswer: shouldShowInspectorLatestAnswer,
            inspectorSummaryValues: makeInspectorSummaryFieldValues(
                for: task,
                currentFocusSummary: currentFocusSummary,
                overviewStatusLine: overviewStatusLine,
                streamingPreview: streamingPreview,
                resultSummary: resultSummary,
                shouldShowResultSummary: shouldShowInspectorLatestAnswer
            )
        )
    }

    private func makeSelectedTaskEntriesSignature(for task: Task) -> SelectedTaskEntriesSignature {
        SelectedTaskEntriesSignature(
            taskID: task.taskID,
            transcriptCount: appState.transcriptMessages(for: task).count,
            pendingCount: appState.pendingOutgoingMessages(for: task).count,
            transcriptDisplayMode: transcriptDisplayMode,
            sessionStatus: task.sessionStatus,
            state: task.state,
            hasStreamingDraft: task.sessionStatus == .running && task.output.isEmpty == false,
            artifactSummary: task.artifact?.summary
        )
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
        let streamingEntry = workspaceStreamingEntry(for: task, transcriptMessages: transcriptMessages)
        if transcriptMessages.isEmpty, task.isPreview {
            return legacyWorkspaceFeedEntries(for: task)
        }
        if transcriptMessages.isEmpty {
            var entries = pendingEntries.isEmpty ? legacyWorkspaceFeedEntries(for: task) : pendingEntries
            if let streamingEntry {
                entries.append(streamingEntry)
                entries = entries.sorted(by: workspaceFeedEntrySort)
            }
            return entries
        }

        let conversationMessages = transcriptMessages.filter { message in
            shouldDisplayMessageInPrimaryWorkspace(message, task: task)
                && task.shouldDisplayMessageInWorkspaceConversation(message)
        }
        let visibleMessages = transcriptMessages.filter { message in
            shouldDisplayMessageInPrimaryWorkspace(message, task: task)
                && task.shouldDisplayMessageInWorkspace(message, mode: transcriptDisplayMode)
        }
        let latestConversationAssistantID = conversationMessages
            .reversed()
            .first(where: { $0.role == .assistant })?
            .id

        var entries = visibleMessages.map { message in
            workspaceFeedEntry(for: message, task: task, latestConversationAssistantID: latestConversationAssistantID)
        }
        entries.append(contentsOf: pendingEntries)
        if let streamingEntry {
            entries.append(streamingEntry)
        }
        entries = entries.sorted(by: workspaceFeedEntrySort)
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

    private func shouldDisplayMessageInPrimaryWorkspace(_ message: HermesConversationMessage, task: Task) -> Bool {
        return true
    }

    private func workspaceEntryBody(_ entry: WorkspaceFeedEntry, task: Task) -> String {
        guard let liveBodyTaskID = entry.liveBodyTaskID, liveBodyTaskID == task.taskID else {
            return entry.body
        }
        return task.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func legacyWorkspaceFeedEntries(for task: Task) -> [WorkspaceFeedEntry] {
        let requestBody = task.requestText ?? task.title
        var entries: [WorkspaceFeedEntry] = [
            WorkspaceFeedEntry(
                id: "task-request-\(task.taskID)",
                title: appState.text(zh: "你交给 Hermes 的任务", en: "You asked Hermes"),
                body: requestBody,
                footer: task.createdAt.formatted(date: .abbreviated, time: .shortened),
                alignment: .trailing,
                background: Color.accentColor.opacity(0.16),
                tint: .accentColor,
                monospaced: false
            )
        ]

        if let resultSummary = workspaceResultSummary(for: task), resultSummary != requestBody {
            entries.append(
                WorkspaceFeedEntry(
                    id: "task-summary-\(task.taskID)",
                    title: task.state == .succeeded
                        ? appState.text(zh: "Hermes 结果", en: "Hermes result")
                        : appState.text(zh: "Hermes 更新", en: "Hermes update"),
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
                    title: appState.text(zh: "结果快照", en: "Result snapshot"),
                    body: appState.systemText(artifact.summary),
                    footer: artifact.keyOutputs.prefix(2).map(appState.systemText).joined(separator: " • "),
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
            title = message.toolName.map { "\(appState.text(zh: "工具", en: "Tool")) · \($0)" } ?? appState.text(zh: "工具输出", en: "Tool output")
            background = Color.secondary.opacity(0.08)
            tint = .secondary
            bubbleStyle = .tool
        case .system:
            title = appState.text(zh: "系统", en: "System")
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
        guard task.sessionStatus == .running, task.output.isEmpty == false else {
            return nil
        }

        return WorkspaceFeedEntry(
            id: "streaming-\(task.taskID)",
            title: appState.text(zh: "Hermes · 草稿", en: "Hermes · draft"),
            body: "",
            footer: appState.text(zh: "正在实时输出 · 还不是最终结果", en: "Streaming live now · not final yet"),
            alignment: .leading,
            background: Color.blue.opacity(0.08),
            tint: .blue,
            monospaced: false,
            showsProgress: true,
            bubbleStyle: .progress,
            liveBodyTaskID: task.taskID,
            isStreamingMarkdown: true
        )
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
            appState.text(zh: "打开“任务进展”标签查看完整执行轨迹", en: "Open the Progress tab for the full execution trail")
        ].compactMap { $0 }

        return WorkspaceFeedEntry(
            id: "progress-activity-\(task.taskID)-\(totalUpdates)",
            title: appState.text(zh: "任务进展", en: "Task progress"),
            body: appState.text(zh: "已捕获 \(totalUpdates) 条来自工具、终端和流式执行细节的底层更新。这些日志会保留在“任务进展”里，而不会混进主对话。", en: "Captured \(totalUpdates) low-level update\(totalUpdates == 1 ? "" : "s") from tools, terminals, and streaming execution details. Those logs stay in Task progress instead of the main conversation."),
            footer: footerParts.joined(separator: " · "),
            alignment: .leading,
            background: Color.secondary.opacity(0.08),
            tint: .secondary,
            monospaced: false,
            bubbleStyle: .tool
        )
    }

    private func workspaceStreamingText(for task: Task, transcriptMessages: [HermesConversationMessage]) -> String? {
        if task.sessionStatus == .running {
            return task.output.isEmpty ? nil : task.output
        }

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
        if let cached = cachedDerivedSnapshot(for: task) {
            return cached.streamingPreview
        }
        guard let streamingText = workspaceStreamingText(for: task, transcriptMessages: appState.transcriptMessages(for: task)) else {
            return nil
        }
        return makeStreamingPreview(for: task, streamingText: streamingText)
    }

    private func workspaceResultSummary(for task: Task) -> String? {
        if let cached = cachedDerivedSnapshot(for: task) {
            return cached.resultSummary
        }

        let transcriptMessages = appState.transcriptMessages(for: task)
        return makeWorkspaceResultSummary(
            for: task,
            transcriptMessages: transcriptMessages,
            streamingText: workspaceStreamingText(for: task, transcriptMessages: transcriptMessages)
        )
    }

    private func workspaceCurrentFocusSummary(for task: Task) -> String {
        if let cached = cachedDerivedSnapshot(for: task) {
            return cached.currentFocusSummary
        }

        let transcriptMessages = appState.transcriptMessages(for: task)
        let streamingText = workspaceStreamingText(for: task, transcriptMessages: transcriptMessages)
        let resultSummary = makeWorkspaceResultSummary(
            for: task,
            transcriptMessages: transcriptMessages,
            streamingText: streamingText
        )
        return makeWorkspaceCurrentFocusSummary(
            for: task,
            streamingText: streamingText,
            resultSummary: resultSummary
        )
    }

    private func makeWorkspaceResultSummary(
        for task: Task,
        transcriptMessages: [HermesConversationMessage],
        streamingText: String?
    ) -> String? {
        if task.sessionStatus == .running {
            return task.runState.progressHint ?? task.latestOutputSummary ?? streamingText
        }

        if task.isPreview,
           let artifactSummary = task.artifact?.summary.trimmingCharacters(in: .whitespacesAndNewlines),
           artifactSummary.isEmpty == false {
            return artifactSummary
        }

        if let lastAssistantMessage = transcriptMessages
            .reversed()
            .first(where: { $0.role == .assistant && task.shouldDisplayMessageInWorkspaceConversation($0) })?
            .displayText,
           lastAssistantMessage.isEmpty == false {
            return lastAssistantMessage
        }

        return streamingText
    }

    private func makeWorkspaceCurrentFocusSummary(
        for task: Task,
        streamingText: String?,
        resultSummary: String?
    ) -> String {
        if task.state == .waitingUser {
            return appState.systemText(task.runState.waitingReason ?? "Waiting for your decision before Hermes can continue.").workspaceSnippet(maxLength: 180)
        }
        if task.state == .failed {
            return appState.systemText(task.runState.failureMessage ?? "Hermes hit an issue and needs recovery.").workspaceSnippet(maxLength: 180)
        }
        if task.sessionStatus == .running {
            if task.runState.observationState != .live,
               let observationStatusLine = task.runState.observationStatusLine,
               observationStatusLine.isEmpty == false {
                return appState.systemText(observationStatusLine).workspaceSnippet(maxLength: 180)
            }
            return appState.systemText(task.runState.phaseLabel).workspaceSnippet(maxLength: 180)
        }
        if task.sessionStatus == .open {
            return appState.text(zh: "当前对话已开放，可直接在下方对话区继续追问或补充上下文。", en: "This conversation is open. Continue in the transcript below with follow-up context.")
                .workspaceSnippet(maxLength: 180)
        }
        if task.sessionStatus == .archived {
            return appState.text(zh: "这次运行已结束，可查看下方回复、文件和执行记录。", en: "This run has ended. Review the reply, files, and execution trail below.")
                .workspaceSnippet(maxLength: 180)
        }
        return (task.requestText ?? appState.systemText(task.currentSummary)).workspaceSnippet(maxLength: 180)
    }

    private func makeWorkspaceOverviewStatusLine(for task: Task, resultSummary _: String?) -> String? {
        if let waitingReason = task.runState.waitingReason, waitingReason.isEmpty == false {
            return appState.systemText(waitingReason)
        }
        if let failureMessage = task.runState.failureMessage, failureMessage.isEmpty == false {
            return appState.systemText(failureMessage)
        }
        if let progressHint = task.runState.progressHint, progressHint.isEmpty == false {
            return appState.systemText(progressHint)
        }
        if let observationStatusLine = task.runState.observationStatusLine, observationStatusLine.isEmpty == false {
            return appState.systemText(observationStatusLine)
        }
        return nil
    }

    private func makeShouldShowInspectorLatestAnswer(
        for task: Task,
        transcriptMessages: [HermesConversationMessage],
        streamingPreview _: String?,
        resultSummary: String?
    ) -> Bool {
        guard let resultSummary, resultSummary.isEmpty == false else {
            return false
        }

        if task.sessionStatus == .running {
            return false
        }

        // When the workspace is using the legacy fallback feed, the center column already shows
        // the latest answer as a bubble-like result snapshot. Do not repeat it again in the
        // inspector.
        if transcriptMessages.isEmpty {
            return false
        }

        let hasVisibleAssistantMessage = transcriptMessages.contains { message in
            message.role == .assistant && task.shouldDisplayMessageInWorkspaceConversation(message)
        }
        return hasVisibleAssistantMessage == false
    }

    private func streamingSummarySource(for task: Task, streamingText: String?) -> String? {
        guard task.sessionStatus == .running else {
            return streamingText
        }
        return task.runState.progressHint ?? task.latestOutputSummary ?? streamingText
    }

    private func makeStreamingPreview(for task: Task, streamingText: String?) -> String? {
        guard let source = streamingSummarySource(for: task, streamingText: streamingText) else {
            return nil
        }
        return source.workspaceSnippet(maxLength: 220)
    }

    private func makeInspectorSummaryFieldValues(
        for task: Task,
        currentFocusSummary: String,
        overviewStatusLine: String?,
        streamingPreview: String?,
        resultSummary: String?,
        shouldShowResultSummary: Bool
    ) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: buildInspectorSummaryFields(
                for: task,
                currentFocusSummary: currentFocusSummary,
                overviewStatusLine: overviewStatusLine,
                streamingPreview: streamingPreview,
                resultSummary: resultSummary,
                shouldShowResultSummary: shouldShowResultSummary
            ).map { ($0.id, $0.value) }
        )
    }

    private func workspaceDisplayTitle(for task: Task) -> String {
        if task.isPreview == false, let requestText = task.requestText, requestText.isEmpty == false {
            return Task.summarizedWorkspaceTitle(from: requestText)
        }
        if Task.isGenericWorkspaceTitle(task.title), let requestText = task.requestText, requestText.isEmpty == false {
            return Task.summarizedWorkspaceTitle(from: requestText)
        }
        return appState.systemText(task.title)
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
            return appState.systemText(statusContextLine)
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
                title: appState.text(zh: "运行状态", en: "Run status"),
                systemImage: "bolt.horizontal.circle",
                tint: .orange,
                events: runStatusEvents,
                emphasizeDetail: false
            ),
            WorkspaceProgressSection(
                title: appState.text(zh: "工具与执行", en: "Tools & execution"),
                systemImage: "hammer",
                tint: .secondary,
                events: executionEvents,
                emphasizeDetail: false
            ),
            WorkspaceProgressSection(
                title: appState.text(zh: "Agent 流", en: "Agent stream"),
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
                        Text(isExpanded ? appState.text(zh: "收起", en: "Show less") : appState.text(zh: "展开", en: "Show more"))
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

    private func inspectorSummaryAllowsCollapse(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return false
        }

        return trimmed.count > 220 || trimmed.contains("\n")
    }

    private func toggleInspectorSummaryExpansion(for summaryID: String) {
        if expandedInspectorSummaryFieldIDs.contains(summaryID) {
            expandedInspectorSummaryFieldIDs.remove(summaryID)
        } else {
            expandedInspectorSummaryFieldIDs.insert(summaryID)
        }
    }

    private func inspectorSummaryFieldValues(for task: Task) -> [String: String] {
        if let cached = cachedDerivedSnapshot(for: task) {
            return cached.inspectorSummaryValues
        }

        let transcriptMessages = appState.transcriptMessages(for: task)
        let streamingText = workspaceStreamingText(for: task, transcriptMessages: transcriptMessages)
        let streamingPreview = streamingText.map { $0.workspaceSnippet(maxLength: 220) }
        let resultSummary = makeWorkspaceResultSummary(
            for: task,
            transcriptMessages: transcriptMessages,
            streamingText: streamingText
        )
        let currentFocusSummary = makeWorkspaceCurrentFocusSummary(
            for: task,
            streamingText: streamingText,
            resultSummary: resultSummary
        )

        return makeInspectorSummaryFieldValues(
            for: task,
            currentFocusSummary: currentFocusSummary,
            overviewStatusLine: makeWorkspaceOverviewStatusLine(for: task, resultSummary: resultSummary),
            streamingPreview: streamingPreview,
            resultSummary: resultSummary,
            shouldShowResultSummary: makeShouldShowInspectorLatestAnswer(
                for: task,
                transcriptMessages: transcriptMessages,
                streamingPreview: streamingPreview,
                resultSummary: resultSummary
            )
        )
    }

    private func inspectorSummaryFields(for task: Task) -> [InspectorSummaryField] {
        if let cached = cachedDerivedSnapshot(for: task) {
            return buildInspectorSummaryFields(
                for: task,
                currentFocusSummary: cached.currentFocusSummary,
                overviewStatusLine: cached.overviewStatusLine,
                streamingPreview: cached.streamingPreview,
                resultSummary: cached.resultSummary,
                shouldShowResultSummary: cached.shouldShowInspectorLatestAnswer
            )
        }

        let transcriptMessages = appState.transcriptMessages(for: task)
        let streamingText = workspaceStreamingText(for: task, transcriptMessages: transcriptMessages)
        let streamingPreview = makeStreamingPreview(for: task, streamingText: streamingText)
        let resultSummary = makeWorkspaceResultSummary(
            for: task,
            transcriptMessages: transcriptMessages,
            streamingText: streamingText
        )
        let currentFocusSummary = makeWorkspaceCurrentFocusSummary(
            for: task,
            streamingText: streamingText,
            resultSummary: resultSummary
        )

        return buildInspectorSummaryFields(
            for: task,
            currentFocusSummary: currentFocusSummary,
            overviewStatusLine: makeWorkspaceOverviewStatusLine(for: task, resultSummary: resultSummary),
            streamingPreview: streamingPreview,
            resultSummary: resultSummary,
            shouldShowResultSummary: makeShouldShowInspectorLatestAnswer(
                for: task,
                transcriptMessages: transcriptMessages,
                streamingPreview: streamingPreview,
                resultSummary: resultSummary
            )
        )
    }

    private func buildInspectorSummaryFields(
        for task: Task,
        currentFocusSummary: String,
        overviewStatusLine: String?,
        streamingPreview: String?,
        resultSummary: String?,
        shouldShowResultSummary: Bool
    ) -> [InspectorSummaryField] {
        var fields: [InspectorSummaryField] = []
        var seenValues: Set<String> = []

        func appendField(id: String, label: String, value: String, allowDuplicate: Bool = false) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return
            }

            let normalizedValue = normalizedInspectorSummaryValue(trimmed)
            if allowDuplicate == false, seenValues.contains(normalizedValue) {
                return
            }

            fields.append(InspectorSummaryField(id: id, label: label, value: trimmed))
            seenValues.insert(normalizedValue)
        }

        appendField(
            id: "task-summary-goal-\(task.taskID)",
            label: appState.text(zh: "目标", en: "Goal"),
            value: task.requestText ?? appState.systemText(task.title),
            allowDuplicate: true
        )
        appendField(
            id: "task-summary-current-\(task.taskID)",
            label: appState.text(zh: "当前", en: "Current"),
            value: currentFocusSummary
        )
        appendField(
            id: "task-summary-phase-\(task.taskID)",
            label: appState.text(zh: "当前阶段", en: "Current phase"),
            value: inspectorPhaseValue(for: task)
        )
        appendField(
            id: "task-summary-focus-\(task.taskID)",
            label: appState.text(zh: "当前重点", en: "Queue focus"),
            value: workspaceQueueFocusTitle(for: task)
        )

        if let overviewStatusLine {
            appendField(
                id: "task-summary-status-\(task.taskID)",
                label: appState.text(zh: "状态", en: "Status"),
                value: overviewStatusLine
            )
        }

        if let sessionBindingSummary = task.sessionBindingSummary {
            appendField(
                id: "task-summary-session-\(task.taskID)",
                label: appState.text(zh: "会话", en: "Session"),
                value: appState.systemText(sessionBindingSummary)
            )
        }

        if let streamingPreview {
            appendField(
                id: "task-summary-streaming-\(task.taskID)",
                label: appState.text(zh: "流式输出", en: "Streaming"),
                value: streamingPreview
            )
        } else if let observationStatusLine = task.runState.observationStatusLine {
            appendField(
                id: "task-summary-feed-\(task.taskID)",
                label: appState.text(zh: "实时流", en: "Live feed"),
                value: appState.systemText(observationStatusLine)
            )
        } else if shouldShowResultSummary, let resultSummary {
            appendField(
                id: "task-summary-result-\(task.taskID)",
                label: task.state == .succeeded
                    ? appState.text(zh: "结果", en: "Result")
                    : appState.text(zh: "最新有效回复", en: "Latest useful answer"),
                value: resultSummary
            )
        }

        return fields
    }

    private func normalizedInspectorSummaryValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private func triggerInspectorSummaryHighlight(for summaryID: String) {
        let token = UUID()
        inspectorSummaryHighlightTokens[summaryID] = token

        _ = withAnimation(.easeOut(duration: 0.12)) {
            highlightedInspectorSummaryFieldIDs.insert(summaryID)
        }

        Swift.Task { @MainActor in
            try? await Swift.Task.sleep(for: .seconds(1.6))
            guard inspectorSummaryHighlightTokens[summaryID] == token else {
                return
            }
            inspectorSummaryHighlightTokens.removeValue(forKey: summaryID)
            _ = withAnimation(.easeOut(duration: 1.4)) {
                highlightedInspectorSummaryFieldIDs.remove(summaryID)
            }
        }
    }

    private func workspaceEventTitle(for event: TaskEvent) -> String {
        switch event.type {
        case .confirm:
            return appState.text(zh: "确认", en: "Approval")
        case .error:
            if let toolName = workspaceToolName(for: event) {
                return appState.text(zh: "\(workspaceToolCategoryTitle(for: toolName))错误", en: "\(workspaceToolCategoryTitle(for: toolName)) error")
            }
            return appState.text(zh: "问题", en: "Issue")
        case .result:
            return appState.text(zh: "结果", en: "Result")
        case .output:
            return appState.text(zh: "输出", en: "Output")
        case .step:
            if let toolName = workspaceToolName(for: event) {
                return workspaceToolCategoryTitle(for: toolName)
            }
            return appState.text(zh: "执行", en: "Execution")
        case .stateChange:
            return appState.text(zh: "运行状态", en: "Run status")
        case .log:
            return appState.text(zh: "思考", en: "Reasoning")
        case .clarify:
            return appState.text(zh: "澄清", en: "Clarification")
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
                return appState.systemText("Started \(displayName)")
            }
            if event.summary.hasPrefix("Completed tool:") {
                return appState.systemText("Completed \(displayName)")
            }
            return displayName
        case .error:
            return appState.text(zh: "\(displayName)失败", en: "\(displayName) failed")
        case .confirm, .result, .output, .stateChange, .log, .clarify:
            return appState.systemText(event.summary)
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
            return appState.text(zh: "终端", en: "Terminal")
        }
        if normalized == "skill_view" || normalized.hasPrefix("skill_") {
            return appState.text(zh: "技能", en: "Skill")
        }
        if normalized.hasPrefix("browser_") {
            return appState.text(zh: "浏览器", en: "Browser")
        }
        if ["read_file", "write_file", "patch", "search_files"].contains(normalized) {
            return appState.text(zh: "文件", en: "Files")
        }
        if normalized == "delegate_task" {
            return appState.text(zh: "委派", en: "Delegation")
        }
        if normalized == "clarify" {
            return appState.text(zh: "澄清", en: "Clarification")
        }
        return appState.text(zh: "工具", en: "Tool")
    }

    private func workspaceDisplayToolName(_ toolName: String) -> String {
        let normalized = toolName.lowercased()

        switch normalized {
        case "terminal":
            return appState.text(zh: "终端", en: "Terminal")
        case "skill_view":
            return appState.text(zh: "技能视图", en: "Skill view")
        case "delegate_task":
            return appState.text(zh: "委派任务", en: "Delegate task")
        case "read_file":
            return appState.text(zh: "读取文件", en: "Read file")
        case "write_file":
            return appState.text(zh: "写入文件", en: "Write file")
        case "search_files":
            return appState.text(zh: "搜索文件", en: "Search files")
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

}

private enum WorkspaceListScope: String, CaseIterable, Identifiable {
    case active
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return HermesDeskL10n.text(zh: "进行中", en: "In Progress")
        case .archive:
            return HermesDeskL10n.text(zh: "归档", en: "Archive")
        }
    }

    var emptyTitle: String {
        switch self {
        case .active:
            return HermesDeskL10n.text(zh: "暂无进行中的任务", en: "No active task")
        case .archive:
            return HermesDeskL10n.text(zh: "暂无归档任务", en: "No archived task")
        }
    }

    var emptyMessage: String {
        switch self {
        case .active:
            return HermesDeskL10n.text(zh: "先在上方选择一个 Agent，再新建任务，就可以在这个工作区里开始工作。", en: "Pick an agent above and create a new task to start working in this workspace.")
        case .archive:
            return HermesDeskL10n.text(zh: "已完成和已停止的任务在适合回看时会出现在这里。", en: "Completed and stopped tasks will land here once they are ready to revisit.")
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
            return HermesDeskL10n.text(zh: "全部", en: "All")
        case .needsInput:
            return HermesDeskL10n.text(zh: "需要处理", en: "Action Required")
        case .running:
            return HermesDeskL10n.text(zh: "进行中", en: "Running")
        case .open:
            return HermesDeskL10n.text(zh: "开放中", en: "Open")
        case .archived:
            return HermesDeskL10n.text(zh: "已归档", en: "Archived")
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
            return HermesDeskL10n.text(zh: "构建", en: "Builder")
        case .reviewer:
            return HermesDeskL10n.text(zh: "审查", en: "Reviewer")
        case .analyst:
            return HermesDeskL10n.text(zh: "分析", en: "Analyst")
        }
    }

    var shortTitle: String {
        switch self {
        case .hermes:
            return "Hermes"
        case .builder:
            return HermesDeskL10n.text(zh: "构建", en: "Build")
        case .reviewer:
            return HermesDeskL10n.text(zh: "审查", en: "Review")
        case .analyst:
            return HermesDeskL10n.text(zh: "分析", en: "Analyze")
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
            return HermesDeskL10n.text(zh: "Hermes 任务", en: "Hermes task")
        case .builder:
            return HermesDeskL10n.text(zh: "用 Hermes 构建", en: "Build with Hermes")
        case .reviewer:
            return HermesDeskL10n.text(zh: "用 Hermes 审查", en: "Review with Hermes")
        case .analyst:
            return HermesDeskL10n.text(zh: "用 Hermes 分析", en: "Analyze with Hermes")
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
    let liveBodyTaskID: Task.ID?
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
        liveBodyTaskID: Task.ID? = nil,
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
        self.liveBodyTaskID = liveBodyTaskID
        self.isStreamingMarkdown = isStreamingMarkdown
    }
}

private struct WorkspaceBubblePalette {
    let top: Color
    let bottom: Color
    let stroke: Color
    let shadow: Color
}

private struct InspectorSummaryField: Identifiable {
    let id: String
    let label: String
    let value: String
}

private struct SelectedTaskDerivedSnapshot {
    let taskID: Task.ID
    let currentFocusSummary: String
    let overviewStatusLine: String?
    let streamingPreview: String?
    let resultSummary: String?
    let shouldShowInspectorLatestAnswer: Bool
    let inspectorSummaryValues: [String: String]
}

private struct SelectedTaskEntriesSignature: Equatable {
    let taskID: Task.ID
    let transcriptCount: Int
    let pendingCount: Int
    let transcriptDisplayMode: HermesWorkspaceTranscriptMode
    let sessionStatus: TaskSessionStatus
    let state: TaskState
    let hasStreamingDraft: Bool
    let artifactSummary: String?
}

private struct SelectedTaskSnapshotKey: Equatable {
    let taskID: Task.ID?
    let updatedAt: Date?
    let state: TaskState?
    let sessionStatus: TaskSessionStatus?
    let runID: String?
    let currentSummary: String?
    let outputCount: Int
    let taskEventCount: Int
    let availableActionCount: Int
    let pendingAction: TaskAction?
    let observationState: RunObservationState?
    let observationMessage: String?
    let artifactSummary: String?
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
    let bodyCount: Int
    let footer: String?
    let showsProgress: Bool
}

private struct WorkspaceFeedAnimationKey: Equatable {
    let taskID: Task.ID
    let entryIDs: [String]
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
        localizedDisplayTitle
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
            return HermesDeskL10n.text(zh: "手动", en: "Manual")
        case .shortcut:
            return HermesDeskL10n.text(zh: "快捷方式", en: "Shortcut")
        case .scheduled:
            return HermesDeskL10n.text(zh: "计划任务", en: "Scheduled")
        case .restored:
            return HermesDeskL10n.text(zh: "已恢复", en: "Restored")
        }
    }
}

private extension TaskAction {
    var displayTitle: String {
        localizedDisplayTitle
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
