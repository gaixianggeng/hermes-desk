import Foundation
import HermesKit

public extension Task {
    mutating func apply(hermesEvent event: HermesRunEvent, maxStoredEvents: Int = 40) {
        updatedAt = event.timestamp
        runState.lastEventAt = event.timestamp
        appendTaskEvent(for: event, maxStoredEvents: maxStoredEvents)

        switch event.type {
        case .messageDelta:
            runState.state = .running
            runState.phaseLabel = "Streaming output"
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
            availableActions = [.stop, .openWorkspace]

            if let delta = event.delta {
                output += delta
            }

            currentSummary = latestOutputSummary?.taskCardSummary() ?? "Streaming output from Hermes"
            runState.progressHint = latestOutputSummary

        case .reasoningAvailable:
            runState.state = .running
            runState.phaseLabel = "Planning"
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
            availableActions = [.stop, .openWorkspace]

            let reasoning = event.reasoning ?? event.timelineDetail ?? event.timelineSummary
            currentSummary = reasoning.taskCardSummary()
            runState.progressHint = reasoning.taskDetailSummary(maxLength: 240)

        case .toolStarted:
            runState.state = .running
            runState.phaseLabel = event.toolName.map { "Running \($0)" } ?? "Running tool"
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
            availableActions = [.stop, .openWorkspace]

            let summary = event.preview?.taskCardSummary()
                ?? event.timelineSummary.taskCardSummary()
            currentSummary = summary
            runState.progressHint = event.preview?.taskDetailSummary(maxLength: 240)

        case .toolCompleted:
            runState.state = .running
            runState.phaseLabel = event.isToolError ? "Tool error" : "Continuing"
            runState.waitingReason = nil
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

        case .runCompleted:
            runState.state = .succeeded
            runState.phaseLabel = "Completed"
            runState.progressHint = nil
            runState.failureCategory = nil
            runState.failureMessage = nil
            runState.waitingReason = nil
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
            runState.state = .failed
            runState.phaseLabel = "Run failed"
            runState.progressHint = nil
            runState.failureCategory = .unknownError
            runState.failureMessage = event.failureMessage ?? "Hermes run failed."
            runState.waitingReason = nil
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
