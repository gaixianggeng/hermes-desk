import AppKit
import HermesKit
import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppStateStore
    @State private var copyFeedback: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                connectionCard
                taskFeedCard
                supportCard
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.text(zh: "连接与诊断", en: "Connection & Diagnostics"))
                .font(.title2.weight(.semibold))
            Text(appState.text(zh: "用这个面板确认当前选中 Agent 绑定的是哪套运行时配置、本地 API 是否可达，以及出现异常时应该去哪里看日志。", en: "Use this panel to confirm which runtime the selected agent is bound to, whether the local API is reachable, and where to inspect logs when something looks wrong."))
                .foregroundStyle(.secondary)

            if let copyFeedback {
                Label(copyFeedback, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(appState.text(zh: "当前 Hermes 连接", en: "Resolved Hermes connection"), systemImage: "network")

            infoRow(label: appState.text(zh: "当前 Agent", en: "Current agent"), value: appState.selectedAgentDisplayName)
            infoRow(label: appState.text(zh: "运行时 Profile", en: "Runtime profile"), value: appState.selectedRuntimeProfileDisplayName)
            infoRow(label: appState.text(zh: "适配器", en: "Adapter"), value: appState.backendDiagnostics.adapterName)
            infoRow(label: appState.text(zh: "端点", en: "Endpoint"), value: appState.endpoint.displayName)
            infoRow(label: appState.text(zh: "状态", en: "Status"), value: appState.localizedConnectionTitle)
            infoRow(label: appState.text(zh: "说明", en: "Detail"), value: appState.localizedConnectionDetail)
            infoRow(label: appState.text(zh: "Hermes 主目录", en: "Hermes home"), value: appState.backendDiagnostics.hermesHomePath ?? appState.text(zh: "不可用", en: "Unavailable"))
            infoRow(label: appState.text(zh: ".env 路径", en: ".env path"), value: appState.backendDiagnostics.environmentFilePath ?? appState.text(zh: "不可用", en: "Unavailable"))
            infoRow(label: appState.text(zh: "环境文件", en: "Environment file"), value: appState.backendDiagnostics.environmentFileExists ? appState.text(zh: "已找到", en: "Found") : appState.text(zh: "缺失", en: "Missing"))
            infoRow(label: appState.text(zh: "API Key", en: "API key"), value: appState.backendDiagnostics.apiKeyConfigured ? appState.text(zh: "已配置", en: "Configured") : appState.text(zh: "未配置", en: "Not configured"))

            HStack(spacing: 10) {
                Button {
                    Swift.Task {
                        await appState.refreshHealth()
                    }
                } label: {
                    Label(appState.isRefreshing ? appState.text(zh: "刷新中…", en: "Refreshing…") : appState.text(zh: "运行健康检查", en: "Run health check"), systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)

                Button {
                    copyDiagnostics()
                } label: {
                    Label(appState.text(zh: "复制诊断信息", en: "Copy diagnostics"), systemImage: "doc.on.doc")
                }

                Button {
                    reveal(path: appState.backendDiagnostics.hermesHomePath)
                } label: {
                    Label(appState.text(zh: "打开 Agent 运行时目录", en: "Open agent runtime"), systemImage: "folder")
                }
                .disabled(pathExists(appState.backendDiagnostics.hermesHomePath) == false)
            }

            HStack(spacing: 10) {
                Button {
                    reveal(path: appState.backendDiagnostics.environmentFilePath)
                } label: {
                    Label(appState.text(zh: "显示 .env", en: "Reveal .env"), systemImage: "key")
                }
                .disabled(pathExists(appState.backendDiagnostics.environmentFilePath) == false)

                Button {
                    reveal(path: logsDirectoryPath)
                } label: {
                    Label(appState.text(zh: "打开 Agent 日志", en: "Open agent logs"), systemImage: "doc.text.magnifyingglass")
                }
                .disabled(pathExists(logsDirectoryPath) == false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var taskFeedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(appState.text(zh: "任务流快照", en: "Task feed snapshot"), systemImage: "list.bullet.rectangle")

            infoRow(label: appState.text(zh: "实时任务", en: "Live tasks"), value: String(appState.liveTasks.count))
            infoRow(label: appState.text(zh: "示例任务", en: "Preview tasks"), value: String(appState.previewTasks.count))
            infoRow(label: appState.text(zh: "待处理", en: "Needs input"), value: String(appState.inboxCount))
            infoRow(label: appState.text(zh: "进行中", en: "Running"), value: String(appState.runningCount))
            infoRow(label: appState.text(zh: "排队中", en: "Queued"), value: String(appState.queuedCount))
            infoRow(label: appState.text(zh: "结果", en: "Results"), value: String(appState.recentCount))
            infoRow(label: appState.text(zh: "当前选中任务", en: "Selected task"), value: appState.selectedTask?.taskID ?? appState.text(zh: "无", en: "None"))

            Text(appState.taskFeedSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(appState.text(zh: "这个面板能帮你确认什么", en: "What this helps you verify"), systemImage: "stethoscope")

            VStack(alignment: .leading, spacing: 8) {
                bullet(appState.text(zh: "Hermes Desk 当前会把产品层 Agent 绑定到对应的 Hermes 运行时，而不是把 profile 直接暴露成左侧的一级对象。", en: "Hermes Desk binds the product-level agent to the intended Hermes runtime instead of exposing profiles directly as top-level UI objects."))
                bullet(appState.text(zh: "即使脱离 shell 启动，MenuBar App 仍然可以访问 /health 和 /v1/runs。", en: "The MenuBar app can still reach /health and /v1/runs even when launched outside the shell."))
                bullet(appState.text(zh: "当连接异常时，你可以直接跳到 Hermes 主目录和日志，而不是猜测运行时在哪里。", en: "When connectivity breaks, you can jump straight to Hermes home/logs instead of guessing where the runtime lives."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var logsDirectoryPath: String? {
        appState.backendDiagnostics.hermesHomePath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appending(path: "logs", directoryHint: .isDirectory)
                .path
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .padding(.top, 6)
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.diagnosticsSummary, forType: .string)
        copyFeedback = appState.text(zh: "诊断信息已复制", en: "Diagnostics copied")
    }

    private func reveal(path: String?) {
        guard let path, pathExists(path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func pathExists(_ path: String?) -> Bool {
        guard let path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}
