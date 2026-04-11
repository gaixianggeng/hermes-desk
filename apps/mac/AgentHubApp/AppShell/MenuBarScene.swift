import AppCore
import AppKit
import SwiftUI

struct MenuBarScene: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppStateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                connectionSummary
                taskSection(title: "Action Required", tasks: appState.inboxTasks, emptyMessage: "Nothing needs approval or retry right now.")
                taskSection(title: "Running", tasks: appState.runningTasks, emptyMessage: "No task is actively running.")
                taskSection(title: "Queued & Paused", tasks: appState.queuedTasks, emptyMessage: "No tasks are waiting to start or resume.")
                taskSection(title: "Recent Results", tasks: Array(appState.recentTasks.prefix(3)), emptyMessage: "No completed results yet.")

                if appState.cancelledTasks.isEmpty == false {
                    taskSection(title: "Stopped", tasks: Array(appState.cancelledTasks.prefix(2)), emptyMessage: "")
                }

                quickActions
            }
            .padding(16)
        }
        .frame(width: 360, height: 560)
        .task {
            await appState.refreshHealth()
        }
    }

    private var connectionSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(appState.connectionState.title, systemImage: appState.menuBarSymbolName)
                .font(.headline)
            Text(appState.connectionState.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(appState.taskFeedSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    countChip(title: "Needs input", value: appState.inboxCount, tint: .orange)
                    countChip(title: "Running", value: appState.runningCount, tint: .blue)
                }
                HStack(spacing: 8) {
                    countChip(title: "Queued", value: appState.queuedCount, tint: .purple)
                    countChip(title: "Results", value: appState.recentCount, tint: .green)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Button {
                revealDashboard()
            } label: {
                Label("Open Dashboard", systemImage: "macwindow")
            }

            Button {
                Swift.Task {
                    await appState.refreshHealth()
                }
            } label: {
                Label(appState.isRefreshing ? "Refreshing…" : "Refresh Hermes Health", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isRefreshing)

            SettingsLink {
                Label("Connection & Diagnostics", systemImage: "stethoscope")
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Agent Hub", systemImage: "power")
            }
        }
    }

    private func taskSection(title: String, tasks: [Task], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if tasks.isEmpty {
                if emptyMessage.isEmpty == false {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(tasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func taskRow(_ task: Task) -> some View {
        Button {
            revealDashboard(selecting: task)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Text(task.runState.phaseLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(task.currentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func revealDashboard(selecting task: Task? = nil) {
        if let task {
            appState.selectTask(task)
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
