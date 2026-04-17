import Foundation
import HermesKit

public extension Task {
    mutating func apply(hermesEvent event: HermesRunEvent, maxStoredEvents: Int = 40) {
        updatedAt = event.timestamp
        runState.lastEventAt = event.timestamp
        if event.type != .messageDelta {
            appendTaskEvent(for: event, maxStoredEvents: maxStoredEvents)
        }

        switch event.type {
        case .messageDelta:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.state = .running
            runState.phaseLabel = "Streaming output"
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
            runState.observationState = .live
            runState.observationMessage = nil
            availableActions = [.stop, .openWorkspace]

            if let delta = event.delta {
                output += delta
            }

            currentSummary = latestOutputSummary?.taskCardSummary() ?? "Streaming output from Hermes"
            runState.progressHint = latestOutputSummary

        case .reasoningAvailable:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.state = .running
            runState.phaseLabel = "Planning"
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
            runState.observationState = .live
            runState.observationMessage = nil
            availableActions = [.stop, .openWorkspace]

            let reasoning = event.reasoning ?? event.timelineDetail ?? event.timelineSummary
            currentSummary = reasoning.taskCardSummary()
            runState.progressHint = reasoning.taskDetailSummary(maxLength: 240)

        case .toolStarted:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.state = .running
            runState.phaseLabel = event.toolName.map { "Running \($0)" } ?? "Running tool"
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
            runState.observationState = .live
            runState.observationMessage = nil
            availableActions = [.stop, .openWorkspace]

            let summary = event.preview?.taskCardSummary()
                ?? event.timelineSummary.taskCardSummary()
            currentSummary = summary
            runState.progressHint = event.preview?.taskDetailSummary(maxLength: 240)

        case .toolCompleted:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.state = .running
            runState.phaseLabel = event.isToolError ? "Tool error" : "Continuing"
            runState.waitingReason = nil
            runState.observationState = .live
            runState.observationMessage = nil
            availableActions = [.stop, .openWorkspace]

            if event.isToolError {
                runState.failureCategory = .toolError
                runState.failureMessage = event.timelineSummary
                currentSummary = event.timelineSummary.taskCardSummary()
            } else {
                runState.failureCategory = nil
                runState.failureMessage = nil
                currentSummary = (event.timelineDetail ?? event.timelineSummary).taskCardSummary()
            }
            runState.progressHint = event.timelineDetail?.taskDetailSummary(maxLength: 240)

        case .approvalRequested:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.state = .waitingUser
            runState.phaseLabel = "Approval requested"
            runState.progressHint = event.command?.taskDetailSummary(maxLength: 240)
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = event.eventDescription ?? "Dangerous command requires approval"
            runState.approvalID = event.approvalID
            runState.observationState = .live
            runState.observationMessage = nil
            availableActions = [.approveOnce, .approveForTask, .reject, .openTerminal, .openWorkspace]
            currentSummary = (event.eventDescription ?? event.command ?? "Approval requested").taskCardSummary()

        case .approvalResolved:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.approvalID = nil
            runState.waitingReason = nil
            runState.progressHint = nil
            runState.observationState = .live
            runState.observationMessage = nil
            if event.decision == "deny" {
                runState.state = .failed
                runState.phaseLabel = "Approval rejected"
                runState.failureCategory = .approvalRejected
                runState.failureMessage = "The approval request was rejected."
                availableActions = [.retry, .openWorkspace]
                currentSummary = "Approval rejected. Review the task before retrying."
            } else {
                runState.state = .running
                runState.phaseLabel = "Approval granted"
                runState.failureCategory = nil
                runState.failureMessage = nil
                availableActions = [.stop, .openWorkspace]
                currentSummary = "Approval granted. Hermes can continue the task."
            }

        case .observationReconnecting:
            runState.observationState = .reconnecting
            runState.observationMessage = event.message ?? "Reconnecting to Hermes live updates."

        case .observationDisconnected:
            runState.observationState = .disconnected
            runState.observationMessage = event.message ?? "Live updates paused after repeated reconnect failures."

        case .runInterrupted:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.state = .cancelled
            runState.phaseLabel = "Stopped"
            runState.progressHint = nil
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
            runState.approvalID = nil
            runState.observationState = .live
            runState.observationMessage = nil
            availableActions = [.openWorkspace]
            currentSummary = (event.message ?? "Run interrupted").taskCardSummary()

        case .runCompleted:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.state = .succeeded
            runState.phaseLabel = "Completed"
            runState.progressHint = nil
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
            runState.approvalID = nil
            runState.observationState = .live
            runState.observationMessage = nil
            availableActions = [.copyResult, .openWorkspace]

            if let output = event.output, output.isEmpty == false, output.count >= self.output.count {
                self.output = output
            }

            let summary = latestOutputSummary?.taskCardSummary() ?? "Hermes completed the task."
            currentSummary = summary
            artifact = Artifact(
                summary: latestOutputSummary ?? summary,
                keyOutputs: event.usage.map { usage in
                    [
                        "Input tokens: \(usage.inputTokens)",
                        "Output tokens: \(usage.outputTokens)",
                        "Total tokens: \(usage.totalTokens)"
                    ]
                } ?? [],
                rawResultReference: runID
            )

        case .runFailed:
            pendingAction = nil
            pendingActionStartedAt = nil
            runState.state = .failed
            runState.phaseLabel = "Run failed"
            runState.progressHint = nil
            runState.failureCategory = .unknownError
            runState.failureMessage = event.failureMessage ?? "Hermes run failed."
            runState.waitingReason = nil
            runState.approvalID = nil
            runState.observationState = .live
            runState.observationMessage = nil
            availableActions = [.retry, .openWorkspace]
            currentSummary = (event.failureMessage ?? "Hermes run failed.").taskCardSummary()
        }
    }

    private mutating func appendTaskEvent(for event: HermesRunEvent, maxStoredEvents: Int) {
        let nextSequence = (taskEvents.last?.seq ?? 0) + 1
        let taskEvent = TaskEvent(
            eventID: "\(taskID)-\(nextSequence)-\(event.type.rawValue)",
            taskID: taskID,
            sessionID: sessionID,
            runID: runID,
            type: event.taskEventType,
            seq: nextSequence,
            timestamp: event.timestamp,
            summary: event.timelineSummary,
            detail: event.timelineDetail,
            capabilitySnapshot: capabilities
        )

        taskEvents.append(taskEvent)
        if taskEvents.count > maxStoredEvents {
            taskEvents.removeFirst(taskEvents.count - maxStoredEvents)
        }
    }
}

private extension HermesRunEvent {
    var taskEventType: EventType {
        switch type {
        case .messageDelta:
            return .output
        case .reasoningAvailable:
            return .log
        case .toolStarted:
            return .step
        case .toolCompleted:
            return isToolError ? .error : .step
        case .approvalRequested, .approvalResolved:
            return .confirm
        case .observationReconnecting, .observationDisconnected, .runInterrupted:
            return .stateChange
        case .runCompleted:
            return .result
        case .runFailed:
            return .error
        }
    }
}

private extension String {
    func taskCardSummary(maxLength: Int = 140) -> String {
        let collapsed = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > maxLength else {
            return collapsed.isEmpty ? "Hermes updated the task." : collapsed
        }

        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    func taskDetailSummary(maxLength: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else {
            return trimmed
        }

        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
