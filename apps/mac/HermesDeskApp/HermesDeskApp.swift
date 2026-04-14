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

    static var currentPreference: HermesDeskLanguagePreference {
        HermesDeskLanguagePreference(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? HermesDeskLanguagePreference.system.rawValue) ?? .system
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
