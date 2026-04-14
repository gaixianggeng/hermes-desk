import AppCore
import SwiftUI

struct FailurePanelView: View {
    @EnvironmentObject private var appState: AppStateStore
    let task: Task
    let feedback: String?
    let isActionEnabled: (TaskAction) -> Bool
    let performAction: (TaskAction) -> Void

    private var recoveryActions: [TaskAction] {
        task.availableActions.filter { action in
            switch action {
            case .retry, .openTerminal, .openWorkspace, .copyResult:
                return true
            default:
                return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appState.text(zh: "失败恢复", en: "Failure recovery"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text(task.runState.failureMessage ?? task.currentSummary)
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: appState.text(zh: "失败类型", en: "Failure type"), value: task.runState.failureCategory?.localizedDisplayTitle ?? appState.text(zh: "未知", en: "Unknown"))
                if let waitingReason = task.runState.waitingReason {
                    infoRow(label: appState.text(zh: "阻塞原因", en: "Blocked on"), value: waitingReason)
                }
                infoRow(label: appState.text(zh: "建议下一步", en: "Recommended next step"), value: recoveryRecommendation)
            }

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                SettingsLink {
                    Label(appState.text(zh: "打开诊断", en: "Open diagnostics"), systemImage: "stethoscope")
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(recoveryActions, id: \.rawValue) { action in
                    actionButton(action)
                }
            }

            if task.isPreview == false, recoveryActions.contains(where: { isActionEnabled($0) == false }) {
                Text(appState.text(zh: "部分 Hermes 恢复动作在 Hermes Desk 里暂时仍是只读。你可以先在这里查看诊断和上下文，必要时再回 Hermes 完成恢复。", en: "Some live Hermes recovery actions are still read-only in Hermes Desk. Use diagnostics/context here, then finish recovery in Hermes when necessary."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recoveryRecommendation: String {
        switch task.runState.failureCategory {
        case .connectionError:
            return appState.text(zh: "优先检查该 Agent 绑定的运行时配置、接口地址和日志。", en: "Check the selected agent runtime, endpoint, and logs first.")
        case .toolError:
            return appState.text(zh: "先查看最近上下文，修好底层命令后再重试。", en: "Open the latest context, then retry once the underlying command is fixed.")
        case .approvalRejected:
            return appState.text(zh: "先复查风险步骤，再决定是否以更安全的方案继续。", en: "Review the risky step, then retry only if the task should continue with a safer plan.")
        case .approvalExpired:
            return appState.text(zh: "重新打开任务上下文，并做一次新的确认决策。", en: "Re-open the task context and make a fresh approval decision.")
        case .validationError:
            return appState.text(zh: "修正提示词或任务输入后再重试。", en: "Fix the prompt or task inputs, then retry.")
        case .dependencyError:
            return appState.text(zh: "重新运行前先检查工作区和日志。", en: "Inspect workspace/logs before re-running.")
        case .unknownError, .none:
            return appState.text(zh: "重试前先查看诊断和最近事件。", en: "Inspect diagnostics and the latest events before retrying.")
        }
    }

    @ViewBuilder
    private func actionButton(_ action: TaskAction) -> some View {
        let button = Button {
            performAction(action)
        } label: {
            Label(action.failureLabel, systemImage: action.failureSymbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isActionEnabled(action) == false)

        switch action {
        case .retry:
            button.buttonStyle(.borderedProminent)
        case .openTerminal, .openWorkspace, .copyResult:
            button.buttonStyle(.bordered)
        default:
            button.buttonStyle(.plain)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

private extension TaskAction {
    var failureLabel: String {
        switch self {
        case .retry:
            return HermesDeskL10n.text(zh: "重试", en: "Retry")
        case .openTerminal:
            return HermesDeskL10n.text(zh: "打开终端", en: "Open terminal")
        case .openWorkspace:
            return HermesDeskL10n.text(zh: "打开工作区", en: "Open workspace")
        case .copyResult:
            return HermesDeskL10n.text(zh: "复制结果", en: "Copy result")
        default:
            return rawValue
        }
    }

    var failureSymbol: String {
        switch self {
        case .retry:
            return "arrow.clockwise.circle.fill"
        case .openTerminal:
            return "terminal.fill"
        case .openWorkspace:
            return "folder.fill"
        case .copyResult:
            return "doc.on.doc.fill"
        default:
            return "circle"
        }
    }
}

private extension FailureCategory {
    var displayTitle: String {
        switch self {
        case .connectionError:
            return "Connection issue"
        case .toolError:
            return "Tool error"
        case .approvalRejected:
            return "Approval rejected"
        case .approvalExpired:
            return "Approval expired"
        case .validationError:
            return "Validation error"
        case .dependencyError:
            return "Dependency issue"
        case .unknownError:
            return "Unknown error"
        }
    }
}
