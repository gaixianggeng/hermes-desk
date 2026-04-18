import AppCore
import SwiftUI

struct ConfirmationCardView: View {
    @EnvironmentObject private var appState: AppStateStore
    let task: Task
    let feedback: String?
    let isActionEnabled: (TaskAction) -> Bool
    let performAction: (TaskAction) -> Void

    private var approvalActions: [TaskAction] {
        task.availableActions.filter { action in
            switch action {
            case .approveOnce, .approveForTask, .reject, .openTerminal, .openWorkspace:
                return true
            default:
                return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appState.text(zh: "需要确认", en: "Approval required"), systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(appState.systemText(task.runState.waitingReason ?? task.currentSummary))
                .font(.subheadline.weight(.medium))

            Text(appState.text(zh: "请在这里判断任务是否应该继续。示例任务可用于 dogfooding；真实 Hermes 运行现在也会直接通过 Hermes Desk 下发确认决策。", en: "Use this card to decide whether the task should continue. Preview tasks stay fully interactive for dogfooding, and live Hermes runs now send approval decisions directly through Hermes Desk."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(appState.text(zh: "证据", en: "Evidence"))
                    .font(.subheadline.weight(.semibold))
                Text(task.latestOutputSummary ?? appState.systemText(task.currentSummary))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let feedback {
                Text(appState.systemText(feedback))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(approvalActions, id: \.rawValue) { action in
                    actionButton(action)
                }
            }

            if task.isPreview == false, approvalActions.contains(where: { isActionEnabled($0) == false }) {
                Text(appState.text(zh: "部分确认按钮暂时不可用，因为当前运行仍在等待 Hermes 处理上一个动作，或者确认令牌已经失效。", en: "Some approval controls are temporarily unavailable because this run is waiting on Hermes to settle the previous action or the approval token is no longer valid."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func actionButton(_ action: TaskAction) -> some View {
        let button = Button {
            performAction(action)
        } label: {
            Label(action.confirmationLabel, systemImage: action.confirmationSymbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isActionEnabled(action) == false)

        switch action {
        case .approveOnce, .approveForTask:
            button.buttonStyle(.borderedProminent)
        case .reject, .openTerminal, .openWorkspace:
            button.buttonStyle(.bordered)
        default:
            button.buttonStyle(.plain)
        }
    }
}

private extension TaskAction {
    var confirmationLabel: String {
        switch self {
        case .approveOnce:
            return HermesDeskL10n.text(zh: "允许一次", en: "Allow once")
        case .approveForTask:
            return HermesDeskL10n.text(zh: "本任务允许", en: "Allow for task")
        case .reject:
            return HermesDeskL10n.text(zh: "拒绝", en: "Reject")
        case .openTerminal:
            return HermesDeskL10n.text(zh: "打开终端", en: "Open terminal")
        case .openWorkspace:
            return HermesDeskL10n.text(zh: "打开工作区", en: "Open workspace")
        default:
            return rawValue
        }
    }

    var confirmationSymbol: String {
        switch self {
        case .approveOnce, .approveForTask:
            return "checkmark.circle.fill"
        case .reject:
            return "xmark.circle.fill"
        case .openTerminal:
            return "terminal.fill"
        case .openWorkspace:
            return "folder.fill"
        default:
            return "circle"
        }
    }

}
