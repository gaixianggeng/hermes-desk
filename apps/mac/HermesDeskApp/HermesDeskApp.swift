import AppCore
import AppKit
import SwiftUI

enum HermesDeskLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "跟随系统"
        case .zhHans:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    var resolved: HermesDeskLanguagePreference {
        switch self {
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("zh") ? .zhHans : .english
        case .zhHans, .english:
            return self
        }
    }
}

enum HermesDeskL10n {
    static let defaultsKey = "hermesDesk.languagePreference"

    static func text(preference: HermesDeskLanguagePreference? = nil, zh: String, en: String) -> String {
        let selected = (preference ?? currentPreference).resolved
        switch selected {
        case .zhHans:
            return zh
        case .english, .system:
            return en
        }
    }

    static func systemText(preference: HermesDeskLanguagePreference? = nil, _ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return raw
        }

        if let translated = exactSystemText(preference: preference, raw: trimmed) {
            return translated
        }
        if let translated = patternedSystemText(preference: preference, raw: trimmed) {
            return translated
        }
        return raw
    }

    static var currentPreference: HermesDeskLanguagePreference {
        HermesDeskLanguagePreference(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? HermesDeskLanguagePreference.system.rawValue) ?? .system
    }

    private static func exactSystemText(preference: HermesDeskLanguagePreference?, raw: String) -> String? {
        switch raw {
        case "Conversation updated", "对话已更新", "对话已更新 / Conversation updated":
            return text(preference: preference, zh: "对话已更新", en: "Conversation updated")
        case "Run finished", "运行已结束", "运行已结束 / Run finished":
            return text(preference: preference, zh: "运行已结束", en: "Run finished")
        case "Streaming output":
            return text(preference: preference, zh: "输出流处理中", en: "Streaming output")
        case "Streaming output from Hermes":
            return text(preference: preference, zh: "Hermes 正在持续输出内容", en: "Streaming output from Hermes")
        case "Planning":
            return text(preference: preference, zh: "规划中", en: "Planning")
        case "Running tool":
            return text(preference: preference, zh: "工具执行中", en: "Running tool")
        case "Tool error":
            return text(preference: preference, zh: "工具错误", en: "Tool error")
        case "Continuing":
            return text(preference: preference, zh: "继续处理中", en: "Continuing")
        case "Approval requested":
            return text(preference: preference, zh: "等待确认", en: "Approval requested")
        case "Dangerous command requires approval":
            return text(preference: preference, zh: "危险命令需要确认", en: "Dangerous command requires approval")
        case "Approval rejected":
            return text(preference: preference, zh: "确认已拒绝", en: "Approval rejected")
        case "The approval request was rejected.":
            return text(preference: preference, zh: "该确认请求已被拒绝。", en: "The approval request was rejected.")
        case "Approval rejected. Review the task before retrying.":
            return text(preference: preference, zh: "确认已拒绝。请先复查任务，再决定是否重试。", en: "Approval rejected. Review the task before retrying.")
        case "Approval granted":
            return text(preference: preference, zh: "确认已通过", en: "Approval granted")
        case "Approval granted for task":
            return text(preference: preference, zh: "本任务确认已通过", en: "Approval granted for task")
        case "Approval granted. Hermes can continue the task.":
            return text(preference: preference, zh: "确认已通过，Hermes 可以继续处理该任务。", en: "Approval granted. Hermes can continue the task.")
        case "Stopped":
            return text(preference: preference, zh: "已停止", en: "Stopped")
        case "Completed":
            return text(preference: preference, zh: "已完成", en: "Completed")
        case "Run failed":
            return text(preference: preference, zh: "运行失败", en: "Run failed")
        case "Hermes run failed.":
            return text(preference: preference, zh: "Hermes 运行失败。", en: "Hermes run failed.")
        case "Run interrupted":
            return text(preference: preference, zh: "运行已中断", en: "Run interrupted")
        case "Run started":
            return text(preference: preference, zh: "运行已开始", en: "Run started")
        case "Connecting to Hermes event stream":
            return text(preference: preference, zh: "正在连接 Hermes 事件流", en: "Connecting to Hermes event stream")
        case "Follow-up queued":
            return text(preference: preference, zh: "追问已排队", en: "Follow-up queued")
        case "Sent a follow-up to Hermes. Waiting for the next run to respond.":
            return text(preference: preference, zh: "已向 Hermes 发送追问，正在等待下一次运行返回结果。", en: "Sent a follow-up to Hermes. Waiting for the next run to respond.")
        case "Retrying":
            return text(preference: preference, zh: "重试中", en: "Retrying")
        case "A replacement run was launched within the current task.":
            return text(preference: preference, zh: "已在当前任务内启动替代运行。", en: "A replacement run was launched within the current task.")
        case "Retry requested. Continue following this task.":
            return text(preference: preference, zh: "已请求重试，继续关注当前任务即可。", en: "Retry requested. Continue following this task.")
        case "Stopping…":
            return text(preference: preference, zh: "停止中…", en: "Stopping…")
        case "Approval decision sent to Hermes. Waiting for the run to continue.":
            return text(preference: preference, zh: "已向 Hermes 发送确认决定，正在等待运行继续。", en: "Approval decision sent to Hermes. Waiting for the run to continue.")
        case "Approval sent for the current task scope.":
            return text(preference: preference, zh: "已为当前任务范围发送批准。", en: "Approval sent for the current task scope.")
        case "Approval sent for one-time execution.":
            return text(preference: preference, zh: "已为单次执行发送批准。", en: "Approval sent for one-time execution.")
        case "Approval sent to Hermes for the current task scope.":
            return text(preference: preference, zh: "已向 Hermes 发送当前任务范围的批准。", en: "Approval sent to Hermes for the current task scope.")
        case "Approval sent to Hermes for one-time execution.":
            return text(preference: preference, zh: "已向 Hermes 发送单次执行的批准。", en: "Approval sent to Hermes for one-time execution.")
        case "Rejection sent to Hermes. Waiting for the task to settle into a failed state.":
            return text(preference: preference, zh: "已向 Hermes 发送拒绝，正在等待任务进入失败状态。", en: "Rejection sent to Hermes. Waiting for the task to settle into a failed state.")
        case "Approval rejection sent. Hermes should stop this risky step.":
            return text(preference: preference, zh: "已发送拒绝确认，Hermes 应该会停止这个高风险步骤。", en: "Approval rejection sent. Hermes should stop this risky step.")
        case "Stop request sent from Hermes Desk. Waiting for Hermes to interrupt the run.":
            return text(preference: preference, zh: "已从 Hermes Desk 发送停止请求，正在等待 Hermes 中断运行。", en: "Stop request sent from Hermes Desk. Waiting for Hermes to interrupt the run.")
        case "Retrying preview task":
            return text(preference: preference, zh: "示例任务重试中", en: "Retrying preview task")
        case "Preview task resumed":
            return text(preference: preference, zh: "示例任务已继续", en: "Preview task resumed")
        case "Paused from task detail":
            return text(preference: preference, zh: "已从任务详情暂停", en: "Paused from task detail")
        case "Stopped from task detail":
            return text(preference: preference, zh: "已从任务详情停止", en: "Stopped from task detail")
        case "Preview task resumed after the approval decision.":
            return text(preference: preference, zh: "确认完成后，示例任务已继续执行。", en: "Preview task resumed after the approval decision.")
        case "Approval recorded. The preview task is back in motion.":
            return text(preference: preference, zh: "确认已记录，示例任务已重新开始执行。", en: "Approval recorded. The preview task is back in motion.")
        case "Preview approval granted for the rest of this sample task.":
            return text(preference: preference, zh: "已为这个示例任务的剩余流程授予批准。", en: "Preview approval granted for the rest of this sample task.")
        case "Preview approval granted once.":
            return text(preference: preference, zh: "已授予一次性的示例批准。", en: "Preview approval granted once.")
        case "Preview retry requested from the task detail panel.":
            return text(preference: preference, zh: "已从任务详情面板请求重试示例任务。", en: "Preview retry requested from the task detail panel.")
        case "Preview task resumed from the paused queue.":
            return text(preference: preference, zh: "示例任务已从暂停队列恢复。", en: "Preview task resumed from the paused queue.")
        case "Paused from Hermes Desk preview controls":
            return text(preference: preference, zh: "已通过 Hermes Desk 示例控件暂停", en: "Paused from Hermes Desk preview controls")
        case "You rejected the preview approval request.":
            return text(preference: preference, zh: "你拒绝了这个示例确认请求。", en: "You rejected the preview approval request.")
        case "Approval rejected. The preview task is blocked until you retry it.":
            return text(preference: preference, zh: "确认已拒绝，示例任务会保持阻塞，直到你重新发起重试。", en: "Approval rejected. The preview task is blocked until you retry it.")
        case "Retry requested. The preview task is running again.":
            return text(preference: preference, zh: "已请求重试，示例任务正在重新运行。", en: "Retry requested. The preview task is running again.")
        case "Resume requested. The preview task is active again.":
            return text(preference: preference, zh: "已请求继续，示例任务重新进入活动状态。", en: "Resume requested. The preview task is active again.")
        case "Pause requested. The preview task is waiting to be resumed.":
            return text(preference: preference, zh: "已请求暂停，示例任务正在等待恢复。", en: "Pause requested. The preview task is waiting to be resumed.")
        case "Stop requested. The preview task has been cancelled.":
            return text(preference: preference, zh: "已请求停止，示例任务已经取消。", en: "Stop requested. The preview task has been cancelled.")
        case "Waiting for your decision before Hermes can continue.":
            return text(preference: preference, zh: "Hermes 需要你的决策后才能继续。", en: "Waiting for your decision before Hermes can continue.")
        case "Hermes hit an issue and needs recovery.":
            return text(preference: preference, zh: "Hermes 遇到问题，需要恢复处理。", en: "Hermes hit an issue and needs recovery.")
        case "Manual reconnect requested from Hermes Desk.":
            return text(preference: preference, zh: "已从 Hermes Desk 手动发起重连。", en: "Manual reconnect requested from Hermes Desk.")
        case "This conversation is still open. Continue chatting with Hermes in the current task.":
            return text(preference: preference, zh: "当前对话仍然开放，可继续在这个任务里与 Hermes 交流。", en: "This conversation is still open. Continue chatting with Hermes in the current task.")
        case "Hermes is working through the task. Detailed tool, terminal, and agent activity stays in Task progress.":
            return text(preference: preference, zh: "Hermes 正在处理这个任务。更细的工具、终端和 Agent 活动会显示在“任务进展”里。", en: "Hermes is working through the task. Detailed tool, terminal, and agent activity stays in Task progress.")
        case "This task has not emitted a structured artifact yet.":
            return text(preference: preference, zh: "这个任务还没有产出结构化结果。", en: "This task has not emitted a structured artifact yet.")
        case "Hermes completed the task.":
            return text(preference: preference, zh: "Hermes 已完成该任务。", en: "Hermes completed the task.")
        case "Hermes updated the task.":
            return text(preference: preference, zh: "Hermes 已更新该任务。", en: "Hermes updated the task.")
        case "Approval sent once — waiting for Hermes to continue.":
            return text(preference: preference, zh: "已发送一次性批准，等待 Hermes 继续。", en: "Approval sent once — waiting for Hermes to continue.")
        case "Task-scope approval sent — waiting for Hermes to continue.":
            return text(preference: preference, zh: "已发送任务范围批准，等待 Hermes 继续。", en: "Task-scope approval sent — waiting for Hermes to continue.")
        case "Rejection sent — waiting for Hermes to stop this step.":
            return text(preference: preference, zh: "已发送拒绝，等待 Hermes 停止这个步骤。", en: "Rejection sent — waiting for Hermes to stop this step.")
        case "Retry requested — launching a replacement run.":
            return text(preference: preference, zh: "已请求重试，正在启动替代运行。", en: "Retry requested — launching a replacement run.")
        case "Stop requested — waiting for Hermes to finish the action.":
            return text(preference: preference, zh: "已请求停止，等待 Hermes 完成当前动作。", en: "Stop requested — waiting for Hermes to finish the action.")
        case "Resume requested — waiting for Hermes to continue.":
            return text(preference: preference, zh: "已请求继续，等待 Hermes 继续。", en: "Resume requested — waiting for Hermes to continue.")
        case "Pause requested — waiting for Hermes to acknowledge it.":
            return text(preference: preference, zh: "已请求暂停，等待 Hermes 确认。", en: "Pause requested — waiting for Hermes to acknowledge it.")
        case "Preview":
            return text(preference: preference, zh: "示例", en: "Preview")
        case "Preview sample":
            return text(preference: preference, zh: "示例任务", en: "Preview sample")
        case "Live Hermes run":
            return text(preference: preference, zh: "实时 Hermes 运行", en: "Live Hermes run")
        case "Preview: review risky git cleanup":
            return text(preference: preference, zh: "示例：审查高风险 Git 清理", en: "Preview: review risky git cleanup")
        case "Preview: recover failing build loop":
            return text(preference: preference, zh: "示例：恢复失败的构建循环", en: "Preview: recover failing build loop")
        case "Preview: map menu bar UI to task model":
            return text(preference: preference, zh: "示例：将菜单栏 UI 映射到任务模型", en: "Preview: map menu bar UI to task model")
        case "Preview: prepare task detail panel":
            return text(preference: preference, zh: "示例：准备任务详情面板", en: "Preview: prepare task detail panel")
        case "Preview: review dashboard copy updates":
            return text(preference: preference, zh: "示例：审查仪表盘文案更新", en: "Preview: review dashboard copy updates")
        case "Preview: bootstrap Hermes Desk skeleton":
            return text(preference: preference, zh: "示例：初始化 Hermes Desk 骨架", en: "Preview: bootstrap Hermes Desk skeleton")
        case "Preview: discarded onboarding draft":
            return text(preference: preference, zh: "示例：已废弃的入门草稿", en: "Preview: discarded onboarding draft")
        case "Sample approval request for a destructive shell command while live Hermes task feeds are unavailable.":
            return text(preference: preference, zh: "示例确认请求：在实时 Hermes 任务流不可用时，对一个破坏性 shell 命令进行审批。", en: "Sample approval request for a destructive shell command while live Hermes task feeds are unavailable.")
        case "Destructive shell command":
            return text(preference: preference, zh: "破坏性 shell 命令", en: "Destructive shell command")
        case "Sample failed run kept in the inbox so retry and investigation flows can be reviewed.":
            return text(preference: preference, zh: "示例失败运行保留在待处理列表中，用来审查重试和排障流程。", en: "Sample failed run kept in the inbox so retry and investigation flows can be reviewed.")
        case "Build failed":
            return text(preference: preference, zh: "构建失败", en: "Build failed")
        case "Swift build exited with a non-zero status.":
            return text(preference: preference, zh: "Swift 构建以非零状态码退出。", en: "Swift build exited with a non-zero status.")
        case "Sample active work used to demonstrate in-progress cards and task detail routing.":
            return text(preference: preference, zh: "示例进行中任务，用来展示执行中的卡片和任务详情路由。", en: "Sample active work used to demonstrate in-progress cards and task detail routing.")
        case "Reviewing SwiftUI files":
            return text(preference: preference, zh: "正在审查 SwiftUI 文件", en: "Reviewing SwiftUI files")
        case "Inspecting the app shell structure":
            return text(preference: preference, zh: "正在检查应用外壳结构", en: "Inspecting the app shell structure")
        case "Sample queued work waiting behind the active task.":
            return text(preference: preference, zh: "示例排队任务，正在等待当前活跃任务完成。", en: "Sample queued work waiting behind the active task.")
        case "Queued":
            return text(preference: preference, zh: "排队中", en: "Queued")
        case "Sample paused task waiting for a content review before it resumes.":
            return text(preference: preference, zh: "示例暂停任务，正在等待内容审查后继续。", en: "Sample paused task waiting for a content review before it resumes.")
        case "Paused for review":
            return text(preference: preference, zh: "等待审查中", en: "Paused for review")
        case "Copy review":
            return text(preference: preference, zh: "文案审查", en: "Copy review")
        case "Sample completed task kept here to show how reusable results will look.":
            return text(preference: preference, zh: "示例已完成任务保留在这里，用来展示可复用结果的呈现方式。", en: "Sample completed task kept here to show how reusable results will look.")
        case "Generated project scaffolding and shared package boundaries.":
            return text(preference: preference, zh: "已生成项目脚手架和共享包边界。", en: "Generated project scaffolding and shared package boundaries.")
        case "XcodeGen config":
            return text(preference: preference, zh: "XcodeGen 配置", en: "XcodeGen config")
        case "AppCore models":
            return text(preference: preference, zh: "AppCore 模型", en: "AppCore models")
        case "Hermes health stub":
            return text(preference: preference, zh: "Hermes 健康检查桩", en: "Hermes health stub")
        case "Review the generated project in Xcode":
            return text(preference: preference, zh: "在 Xcode 里检查生成后的项目", en: "Review the generated project in Xcode")
        case "Compare the preview result shape with the upcoming Hermes task feed":
            return text(preference: preference, zh: "把预览结果结构与即将接入的 Hermes 任务流进行对比", en: "Compare the preview result shape with the upcoming Hermes task feed")
        case "Sample cancelled task kept separate from completed results.":
            return text(preference: preference, zh: "示例已取消任务单独保留，不与已完成结果混在一起。", en: "Sample cancelled task kept separate from completed results.")
        case "Cancelled":
            return text(preference: preference, zh: "已取消", en: "Cancelled")
        case "System":
            return text(preference: preference, zh: "系统", en: "System")
        case "Hermes":
            return "Hermes"
        case "Tool output":
            return text(preference: preference, zh: "工具输出", en: "Tool output")
        case "Restoring the live Hermes feed after Hermes Desk launch.":
            return text(preference: preference, zh: "Hermes Desk 启动后，正在恢复 Hermes 实时任务流。", en: "Restoring the live Hermes feed after Hermes Desk launch.")
        case "Hermes is back online. Restoring the live task feed.":
            return text(preference: preference, zh: "Hermes 已恢复在线，正在重建实时任务流。", en: "Hermes is back online. Restoring the live task feed.")
        case "Enter a task for Hermes before starting the run.":
            return text(preference: preference, zh: "请先输入要交给 Hermes 的任务，再开始运行。", en: "Enter a task for Hermes before starting the run.")
        case "Hermes is already starting another task.":
            return text(preference: preference, zh: "Hermes 正在启动另一个任务。", en: "Hermes is already starting another task.")
        case "The current agent runtime is missing API_SERVER_KEY, so Hermes Desk cannot send runs yet.":
            return text(preference: preference, zh: "当前 Agent 运行时缺少 API_SERVER_KEY，所以 Hermes Desk 还不能发起运行。", en: "The current agent runtime is missing API_SERVER_KEY, so Hermes Desk cannot send runs yet.")
        case "Only conversations created by Hermes Desk can continue inside this app.":
            return text(preference: preference, zh: "只有由 Hermes Desk 创建的对话才能在这个应用里继续。", en: "Only conversations created by Hermes Desk can continue inside this app.")
        case "Live Hermes resume is not wired in Hermes Desk yet.":
            return text(preference: preference, zh: "Hermes Desk 暂时还不支持实时 Hermes 任务的继续操作。", en: "Live Hermes resume is not wired in Hermes Desk yet.")
        case "Live Hermes pause is not wired in Hermes Desk yet.":
            return text(preference: preference, zh: "Hermes Desk 暂时还不支持实时 Hermes 任务的暂停操作。", en: "Live Hermes pause is not wired in Hermes Desk yet.")
        case "Hermes has not confirmed the approval yet. Reconnect the live feed or reopen the task timeline before deciding whether to send it again.":
            return text(preference: preference, zh: "Hermes 还没有确认这次批准。请先重连实时流或重新打开任务时间线，再决定是否重复发送。", en: "Hermes has not confirmed the approval yet. Reconnect the live feed or reopen the task timeline before deciding whether to send it again.")
        case "Hermes has not confirmed the rejection yet. Reconnect the live feed or reopen the task timeline before retrying the rejection.":
            return text(preference: preference, zh: "Hermes 还没有确认这次拒绝。请先重连实时流或重新打开任务时间线，再重试拒绝操作。", en: "Hermes has not confirmed the rejection yet. Reconnect the live feed or reopen the task timeline before retrying the rejection.")
        case "Hermes has not confirmed the replacement run yet. Refresh or retry again if no new run appears.":
            return text(preference: preference, zh: "Hermes 还没有确认替代运行。若还没看到新的运行，请刷新或再次重试。", en: "Hermes has not confirmed the replacement run yet. Refresh or retry again if no new run appears.")
        case "Hermes has not confirmed the stop request yet. Refresh the task timeline before sending another stop.":
            return text(preference: preference, zh: "Hermes 还没有确认停止请求。再次发送停止前，请先刷新任务时间线。", en: "Hermes has not confirmed the stop request yet. Refresh the task timeline before sending another stop.")
        case "Hermes has not confirmed the stop request yet and the live feed is interrupted. Reconnect the feed before retrying.":
            return text(preference: preference, zh: "Hermes 还没有确认停止请求，而且实时流已经中断。请先重连实时流，再决定是否重试。", en: "Hermes has not confirmed the stop request yet and the live feed is interrupted. Reconnect the feed before retrying.")
        case "Hermes has not confirmed the last action yet.":
            return text(preference: preference, zh: "Hermes 还没有确认上一个操作。", en: "Hermes has not confirmed the last action yet.")
        case "Reconnecting to Hermes live updates.":
            return text(preference: preference, zh: "正在重新连接 Hermes 实时更新。", en: "Reconnecting to Hermes live updates.")
        case "Live updates paused after repeated reconnect failures.":
            return text(preference: preference, zh: "多次重连失败后，实时更新已暂停。", en: "Live updates paused after repeated reconnect failures.")
        case "Open terminal":
            return text(preference: preference, zh: "打开终端", en: "Open terminal")
        case "Open workspace":
            return text(preference: preference, zh: "打开工作区", en: "Open workspace")
        case "Copy result":
            return text(preference: preference, zh: "复制结果", en: "Copy result")
        case "allow once":
            return text(preference: preference, zh: "允许一次", en: "allow once")
        case "allow task":
            return text(preference: preference, zh: "允许整个任务", en: "allow task")
        case "reject":
            return text(preference: preference, zh: "拒绝", en: "reject")
        case "retry":
            return text(preference: preference, zh: "重试", en: "retry")
        case "stop":
            return text(preference: preference, zh: "停止", en: "stop")
        case "resume":
            return text(preference: preference, zh: "继续", en: "resume")
        case "pause":
            return text(preference: preference, zh: "暂停", en: "pause")
        case "open terminal":
            return text(preference: preference, zh: "打开终端", en: "open terminal")
        case "open workspace":
            return text(preference: preference, zh: "打开工作区", en: "open workspace")
        case "copy result":
            return text(preference: preference, zh: "复制结果", en: "copy result")
        default:
            return nil
        }
    }

    private static func patternedSystemText(preference: HermesDeskLanguagePreference?, raw: String) -> String? {
        if let suffix = raw.remainder(after: "Running ") {
            return text(preference: preference, zh: "正在运行 \(suffix)", en: "Running \(suffix)")
        }
        if let suffix = raw.remainder(after: "Checking ") {
            return text(preference: preference, zh: "正在检查 \(suffix)", en: "Checking \(suffix)")
        }
        if let suffix = raw.remainder(after: "Started ") {
            return text(preference: preference, zh: "已开始 \(suffix)", en: "Started \(suffix)")
        }
        if let suffix = raw.remainder(after: "Completed ") {
            return text(preference: preference, zh: "已完成 \(suffix)", en: "Completed \(suffix)")
        }
        if let suffix = raw.remainder(after: "Tool · ") {
            return "\(text(preference: preference, zh: "工具", en: "Tool")) · \(suffix)"
        }
        if let suffix = raw.remainder(after: "Reconnecting to Hermes live updates") {
            return text(preference: preference, zh: "正在重新连接 Hermes 实时更新\(suffix)", en: "Reconnecting to Hermes live updates\(suffix)")
        }
        if let suffix = raw.remainder(after: "Live updates paused after ") {
            return text(preference: preference, zh: "实时更新在 \(suffix) 后已暂停", en: "Live updates paused after \(suffix)")
        }
        if let suffix = raw.remainder(after: "Live updates paused after repeated reconnect failures") {
            return text(preference: preference, zh: "多次重连失败后，实时更新已暂停\(suffix)", en: "Live updates paused after repeated reconnect failures\(suffix)")
        }
        if let suffix = raw.remainder(after: "Reconnecting "), suffix.contains(" interrupted live feed") {
            let zhSuffix = suffix
                .replacingOccurrences(of: " interrupted live feeds.", with: " 个中断实时流。")
                .replacingOccurrences(of: " interrupted live feed.", with: " 个中断实时流。")
                .replacingOccurrences(of: " interrupted live feeds", with: " 个中断实时流")
                .replacingOccurrences(of: " interrupted live feed", with: " 个中断实时流")
            return text(preference: preference, zh: "正在重连 \(zhSuffix)", en: "Reconnecting \(suffix)")
        }
        if let suffix = raw.remainder(after: "Reconnecting ") {
            return text(preference: preference, zh: "正在重连 \(suffix)", en: "Reconnecting \(suffix)")
        }
        if let suffix = raw.remainder(after: "Hermes Desk stopped waiting on ") {
            return text(preference: preference, zh: "Hermes Desk 已停止等待 \(systemText(preference: preference, suffix))", en: "Hermes Desk stopped waiting on \(suffix)")
        }
        if let suffix = raw.remainder(after: "🔁 Replacement run: ") {
            return "🔁 \(text(preference: preference, zh: "替代运行", en: "Replacement run")): \(suffix)"
        }
        if let suffix = raw.remainder(after: "↩️ Retried from: ") {
            return "↩️ \(text(preference: preference, zh: "重试来源", en: "Retried from")): \(suffix)"
        }
        if let suffix = raw.remainder(after: "🟠 ") {
            return "🟠 \(systemText(preference: preference, suffix))"
        }
        if let suffix = raw.remainder(after: "🔌 ") {
            return "🔌 \(systemText(preference: preference, suffix))"
        }
        if raw.hasPrefix("Current: "), let rootRange = raw.range(of: " · Root: ") {
            let current = String(raw[raw.index(raw.startIndex, offsetBy: 9)..<rootRange.lowerBound])
            let root = String(raw[rootRange.upperBound...])
            return text(preference: preference, zh: "当前：\(current) · 根会话：\(root)", en: "Current: \(current) · Root: \(root)")
        }
        if let suffix = raw.remainder(after: "Current: ") {
            return text(preference: preference, zh: "当前：\(suffix)", en: "Current: \(suffix)")
        }
        if let suffix = raw.remainder(after: "Input tokens: ") {
            return text(preference: preference, zh: "输入令牌：\(suffix)", en: "Input tokens: \(suffix)")
        }
        if let suffix = raw.remainder(after: "Output tokens: ") {
            return text(preference: preference, zh: "输出令牌：\(suffix)", en: "Output tokens: \(suffix)")
        }
        if let suffix = raw.remainder(after: "Total tokens: ") {
            return text(preference: preference, zh: "总令牌：\(suffix)", en: "Total tokens: \(suffix)")
        }
        return nil
    }
}

private extension String {
    func remainder(after prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}

@main
struct HermesDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppStateStore()

    var body: some Scene {
        Window(appState.text(zh: "Hermes Desk", en: "Hermes Desk"), id: WindowRouter.mainWindowID) {
            DashboardView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1_120, height: 700)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarScene()
                .environmentObject(appState)
        } label: {
            MenuBarStatusLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsScene()
                .environmentObject(appState)
                .frame(width: 540, height: 360)
        }
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var appState: AppStateStore

    var body: some View {
        HStack(spacing: 6) {
            signalDot(color: appState.menuBarConnectionSignal.color)
            Image(systemName: appState.menuBarSymbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            prioritySignal
        }
        .padding(.horizontal, 2)
        .help(appState.menuBarStatusHelpText)
    }

    @ViewBuilder
    private var prioritySignal: some View {
        if let count = appState.menuBarPrioritySignal.count, count > 0 {
            HStack(spacing: 4) {
                signalDot(color: appState.menuBarPrioritySignal.color)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        } else {
            signalDot(color: appState.menuBarPrioritySignal.color)
        }
    }

    private func signalDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.65), lineWidth: 0.6)
            }
            .shadow(color: color.opacity(0.45), radius: 1.6)
    }
}

private struct MenuBarSignal {
    var color: Color
    var label: String
    var count: Int?
}

private extension AppStateStore {
    var menuBarConnectionSignal: MenuBarSignal {
        switch connectionState {
        case .online:
            return MenuBarSignal(color: .green, label: text(zh: "Hermes 在线", en: "Hermes online"), count: nil)
        case .starting:
            return MenuBarSignal(color: .yellow, label: text(zh: "正在检查 Hermes", en: "Checking Hermes"), count: nil)
        case .disconnected:
            return MenuBarSignal(color: .red, label: text(zh: "Hermes 离线", en: "Hermes offline"), count: nil)
        case .configurationError:
            return MenuBarSignal(color: .red, label: text(zh: "Hermes 配置异常", en: "Hermes misconfigured"), count: nil)
        }
    }

    var menuBarPrioritySignal: MenuBarSignal {
        let liveFailedCount = liveTasks.filter { $0.state == .failed }.count
        let liveApprovalCount = liveTasks.filter { $0.state == .waitingUser }.count
        let liveRunningCount = liveTasks.filter { $0.state == .running }.count
        let liveRecentCount = liveTasks.filter { $0.state == .succeeded }.count

        if liveFailedCount > 0 {
            return MenuBarSignal(color: .red, label: text(zh: "\(liveFailedCount) 个失败", en: "\(liveFailedCount) failed"), count: liveFailedCount)
        }
        if liveApprovalCount > 0 {
            return MenuBarSignal(color: .orange, label: text(zh: "\(liveApprovalCount) 个待确认", en: "\(liveApprovalCount) need approval"), count: liveApprovalCount)
        }
        if interruptedFeedCount > 0 {
            return MenuBarSignal(color: .blue, label: text(zh: "\(interruptedFeedCount) 个待重连", en: "\(interruptedFeedCount) reconnecting"), count: interruptedFeedCount)
        }
        if liveRunningCount > 0 {
            return MenuBarSignal(color: .green, label: text(zh: "\(liveRunningCount) 个进行中", en: "\(liveRunningCount) running"), count: liveRunningCount)
        }
        if liveRecentCount > 0 {
            return MenuBarSignal(color: .secondary, label: text(zh: "\(liveRecentCount) 个已完成", en: "\(liveRecentCount) completed"), count: liveRecentCount)
        }
        return MenuBarSignal(color: .secondary.opacity(0.75), label: text(zh: "当前没有进行中的任务", en: "No live work"), count: nil)
    }

    var menuBarStatusHelpText: String {
        text(
            zh: "左灯：\(menuBarConnectionSignal.label)｜右灯：\(menuBarPrioritySignal.label)。点击后可跳到最高优先级任务。",
            en: "Left signal: \(menuBarConnectionSignal.label) | Right signal: \(menuBarPrioritySignal.label). Click to open the highest-priority task."
        )
    }
}
