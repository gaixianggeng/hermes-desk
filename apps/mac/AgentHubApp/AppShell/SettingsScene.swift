import HermesKit
import SwiftUI

struct SettingsScene: View {
    @EnvironmentObject private var appState: AppStateStore

    var body: some View {
        Form {
            Section("Adapter") {
                LabeledContent("Current adapter", value: "Hermes")
                LabeledContent("Reachability", value: "Local /health + /v1/runs")
                LabeledContent("Task list", value: "Live Hermes runs + preview samples")
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
                Text("Agent Hub now starts live Hermes runs from the dashboard and streams their events into task detail. Preview tasks remain available as sample shells around the live task feed.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
