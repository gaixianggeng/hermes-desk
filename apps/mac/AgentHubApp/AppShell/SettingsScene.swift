import HermesKit
import SwiftUI

struct SettingsScene: View {
    @EnvironmentObject private var appState: AppStateStore

    var body: some View {
        Form {
            Section("Adapter") {
                LabeledContent("Current adapter", value: "Hermes")
                LabeledContent("Reachability", value: "Local /health probe")
                LabeledContent("Task list", value: "Preview samples")
            }

            Section("Connection") {
                LabeledContent("Endpoint", value: appState.endpoint.displayName)
                LabeledContent("Status", value: appState.connectionState.title)
                Text(appState.connectionState.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Run health check") {
                    Swift.Task {
                        await appState.refreshHealth()
                    }
                }
                .disabled(appState.isRefreshing)
            }

            Section("Support") {
                Text("Agent Hub can verify the local Hermes endpoint today. Task lists in the menu bar and dashboard are preview samples until Hermes exposes task snapshots.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
