import AppCore
import AppKit
import SwiftUI

struct MenuBarScene: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppStateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionSummary
            if let task = appState.priorityAttentionTask {
                priorityTaskCard(task)
            }
            quickActions
        }
        .padding(16)
        .frame(width: 320)
    }

    private var connectionSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(appState.text(zh: "Hermes Desk 概览", en: "Hermes Desk Overview"), systemImage: appState.menuBarSymbolName)
                    .font(.headline)
                Spacer(minLength: 12)
                Text(appState.localizedConnectionTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(appState.localizedConnectionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let selectedAgent = appState.selectedAgent?.displayName {
                Label(selectedAgent, systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                countChip(title: appState.text(zh: "待处理", en: "Needs input"), value: appState.inboxCount, tint: .orange)
                countChip(title: appState.text(zh: "运行中", en: "Running"), value: appState.runningCount, tint: .blue)
            }

            HStack(spacing: 8) {
                countChip(title: appState.text(zh: "开放中", en: "Open"), value: appState.openCount, tint: .teal)
                countChip(title: appState.text(zh: "已归档", en: "Archived"), value: appState.archivedCount, tint: .green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func priorityTaskCard(_ task: Task) -> some View {
        Button {
            revealDashboard(selecting: task)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(appState.text(zh: "当前焦点", en: "Current Focus"), systemImage: "scope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Text(task.currentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                revealDashboard(selecting: appState.priorityAttentionTask)
            } label: {
                Label(appState.text(zh: "打开主工作区", en: "Open Dashboard"), systemImage: "rectangle.on.rectangle")
            }

            Button {
                Swift.Task {
                    await appState.refreshHealth()
                }
            } label: {
                Label(appState.isRefreshing ? appState.text(zh: "刷新中…", en: "Refreshing…") : appState.text(zh: "刷新连接状态", en: "Refresh Connection"), systemImage: "arrow.clockwise")
            }
            .disabled(appState.isRefreshing)

            if appState.interruptedFeedCount > 0 {
                Button {
                    appState.reconnectInterruptedFeeds()
                } label: {
                    Label(appState.text(zh: "重连中断实时流", en: "Reconnect Interrupted Feeds"), systemImage: "bolt.horizontal.circle")
                }
            }

            SettingsLink {
                Label(appState.text(zh: "设置与诊断", en: "Settings & Diagnostics"), systemImage: "stethoscope")
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(appState.text(zh: "退出 Hermes Desk", en: "Quit Hermes Desk"), systemImage: "power")
            }
        }
    }

    private func revealDashboard(selecting task: Task? = nil) {
        if let task {
            appState.selectTask(task)
        } else if let priorityTask = appState.priorityAttentionTask {
            appState.selectTask(priorityTask)
        } else {
            appState.selectDefaultTaskIfNeeded()
        }

        openWindow(id: WindowRouter.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func countChip(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text("\(title) \(value)")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.15), in: Capsule())
    }
}
