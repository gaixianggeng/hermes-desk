import SwiftUI

struct SettingsScene: View {
    @EnvironmentObject private var appState: AppStateStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(appState.text(zh: "界面语言", en: "Interface Language"))
                    .font(.headline)
                Picker(appState.text(zh: "界面语言", en: "Interface Language"), selection: $appState.languagePreference) {
                    ForEach(HermesDeskLanguagePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Text(appState.text(zh: "可在“跟随系统 / 简体中文 / English”之间切换，便于后续继续扩展多语言。", en: "Switch between System / 简体中文 / English. This keeps the app ready for broader localization later."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)

            Divider()

            DiagnosticsView()
        }
    }
}
