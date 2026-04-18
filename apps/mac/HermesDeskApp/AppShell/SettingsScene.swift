import AppKit
import SwiftUI

struct SettingsScene: View {
    @EnvironmentObject private var appState: AppStateStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeaderCard

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        languageCard
                        runtimeCard
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        languageCard
                        runtimeCard
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(settingsCanvasBackground)

            Divider()

            DiagnosticsView()
        }
    }

    private var settingsHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.text(zh: "Hermes Desk 设置", en: "Hermes Desk settings"))
                .font(.title2.weight(.semibold))
            Text(appState.text(
                zh: "这里集中放界面层偏好和当前 Agent 对应运行时的概览；更细的健康检查、日志和环境诊断继续放在下面的 Diagnostics 面板里。",
                en: "Keep interface preferences and the selected agent's runtime overview here. Detailed health checks, logs, and environment diagnostics stay in the Diagnostics panel below."
            ))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(settingsCardBackground)
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsSectionTitle(appState.text(zh: "界面语言", en: "Interface language"), systemImage: "globe")

            Picker(appState.text(zh: "界面语言", en: "Interface Language"), selection: $appState.languagePreference) {
                ForEach(HermesDeskLanguagePreference.allCases) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.segmented)

            Text(appState.text(
                zh: "可在“跟随系统 / 简体中文 / English”之间切换。选择中文时，界面会统一显示中文；选择英文时，界面会统一显示英文。",
                en: "Switch between System / 简体中文 / English. Chinese mode shows Chinese consistently, and English mode shows English consistently."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(settingsCardBackground)
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSectionTitle(appState.text(zh: "当前运行时", en: "Current runtime"), systemImage: "server.rack")

            settingsInfoRow(label: appState.text(zh: "当前 Agent", en: "Current agent"), value: appState.selectedAgentDisplayName)
            settingsInfoRow(label: appState.text(zh: "运行时 Profile", en: "Runtime profile"), value: appState.selectedRuntimeProfileDisplayName)
            settingsInfoRow(label: appState.text(zh: "连接状态", en: "Connection status"), value: appState.localizedConnectionTitle)
            settingsInfoRow(label: appState.text(zh: "端点", en: "Endpoint"), value: appState.endpoint.displayName)

            Text(appState.localizedConnectionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(settingsCardBackground)
    }

    private func settingsSectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func settingsInfoRow(label: String, value: String) -> some View {
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

    private var settingsCanvasBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(nsColor: .windowBackgroundColor),
                    Color.black.opacity(0.92)
                ]
                : [
                    Color(red: 0.98, green: 0.97, blue: 0.92),
                    Color(red: 0.96, green: 0.95, blue: 0.89)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var settingsCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06), lineWidth: 1)
            )
    }
}
