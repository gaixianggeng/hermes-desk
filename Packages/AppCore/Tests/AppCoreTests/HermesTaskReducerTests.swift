import Foundation
import XCTest
@testable import AppCore
import HermesKit

final class HermesTaskReducerTests: XCTestCase {
    func testApplyMessageDeltaAccumulatesOutputAndMarksTaskRunning() {
        var task = Task.liveHermesTask(
            title: "Draft release note",
            input: "Summarize the latest changes",
            runID: "run_live_1"
        )

        task.apply(hermesEvent: HermesRunEvent(
            type: .messageDelta,
            runID: "run_live_1",
            timestamp: .now,
            delta: "Hello"
        ))
        task.apply(hermesEvent: HermesRunEvent(
            type: .messageDelta,
            runID: "run_live_1",
            timestamp: .now.addingTimeInterval(1),
            delta: " world"
        ))

        XCTAssertEqual(task.state, .running)
        XCTAssertEqual(task.output, "Hello world")
        XCTAssertEqual(task.runState.phaseLabel, "Streaming output")
        XCTAssertEqual(task.taskEvents.count, 2)
        XCTAssertEqual(task.taskEvents.map(\.type), [.output, .output])
    }

    func testApplyCompletionBuildsArtifactSummaryAndActions() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        var task = Task.liveHermesTask(
            title: "Inspect project",
            input: "Check the repo",
            runID: "run_live_2",
            createdAt: createdAt
        )

        task.apply(hermesEvent: HermesRunEvent(
            type: .runCompleted,
            runID: "run_live_2",
            timestamp: createdAt.addingTimeInterval(5),
            output: "Implemented the requested changes.",
            usage: HermesRunUsage(inputTokens: 10, outputTokens: 20, totalTokens: 30)
        ))

        XCTAssertEqual(task.state, .succeeded)
        XCTAssertEqual(task.currentSummary, "Implemented the requested changes.")
        XCTAssertEqual(task.artifact?.summary, "Implemented the requested changes.")
        XCTAssertEqual(task.artifact?.keyOutputs, [
            "Input tokens: 10",
            "Output tokens: 20",
            "Total tokens: 30"
        ])
        XCTAssertEqual(task.availableActions, [.copyResult, .openWorkspace])
        XCTAssertEqual(task.taskEvents.last?.type, .result)
    }

    func testApplyFailureCapturesErrorStateAndRetryAction() {
        var task = Task.liveHermesTask(
            title: "Inspect project",
            input: "Check the repo",
            runID: "run_live_3"
        )

        task.apply(hermesEvent: HermesRunEvent(
            type: .runFailed,
            runID: "run_live_3",
            timestamp: .now,
            failureMessage: "Hermes lost access to the workspace."
        ))

        XCTAssertEqual(task.state, .failed)
        XCTAssertEqual(task.runState.failureMessage, "Hermes lost access to the workspace.")
        XCTAssertEqual(task.availableActions, [.retry, .openWorkspace])
        XCTAssertEqual(task.taskEvents.last?.type, .error)
    }

    func testApplyApprovalRequestedMovesTaskIntoWaitingUserState() {
        var task = Task.liveHermesTask(
            title: "Inspect project",
            input: "Check the repo",
            runID: "run_live_approval"
        )

        task.apply(hermesEvent: HermesRunEvent(
            type: .approvalRequested,
            runID: "run_live_approval",
            timestamp: .now,
            approvalID: "approval_1",
            command: "rm -rf /tmp/demo",
            eventDescription: "Dangerous command",
            allowPermanent: true
        ))

        XCTAssertEqual(task.state, .waitingUser)
        XCTAssertEqual(task.runState.phaseLabel, "Approval requested")
        XCTAssertEqual(task.runState.waitingReason, "Dangerous command")
        XCTAssertEqual(task.runState.approvalID, "approval_1")
        XCTAssertEqual(task.availableActions, [.approveOnce, .approveForTask, .reject, .openTerminal, .openWorkspace])
        XCTAssertEqual(task.taskEvents.last?.type, .confirm)
    }

    func testApplyApprovalResolvedReturnsTaskToRunningState() {
        var task = Task.liveHermesTask(
            title: "Inspect project",
            input: "Check the repo",
            runID: "run_live_approval"
        )
        task.runState.state = .waitingUser
        task.runState.phaseLabel = "Approval requested"
        task.runState.waitingReason = "Dangerous command"
        task.runState.approvalID = "approval_1"
        task.availableActions = [.approveOnce, .approveForTask, .reject, .openTerminal, .openWorkspace]

        task.apply(hermesEvent: HermesRunEvent(
            type: .approvalResolved,
            runID: "run_live_approval",
            timestamp: .now,
            approvalID: "approval_1",
            decision: "once"
        ))

        XCTAssertEqual(task.state, .running)
        XCTAssertEqual(task.runState.phaseLabel, "Approval granted")
        XCTAssertNil(task.runState.approvalID)
        XCTAssertEqual(task.availableActions, [.stop, .openWorkspace])
        XCTAssertEqual(task.taskEvents.last?.type, .confirm)
    }

    func testApplyRunInterruptedMarksTaskCancelled() {
        var task = Task.liveHermesTask(
            title: "Inspect project",
            input: "Check the repo",
            runID: "run_live_interrupt"
        )

        task.apply(hermesEvent: HermesRunEvent(
            type: .runInterrupted,
            runID: "run_live_interrupt",
            timestamp: .now,
            message: "Stop requested via API server"
        ))

        XCTAssertEqual(task.state, .cancelled)
        XCTAssertEqual(task.runState.phaseLabel, "Stopped")
        XCTAssertEqual(task.currentSummary, "Stop requested via API server")
        XCTAssertEqual(task.taskEvents.last?.type, .stateChange)
    }

    func testApplyObservationReconnectingKeepsRunAliveAndShowsReconnectMessage() {
        var task = Task.liveHermesTask(
            title: "Inspect project",
            input: "Check the repo",
            runID: "run_live_stream"
        )
        task.runState.state = .running
        task.runState.phaseLabel = "Streaming output"

        task.apply(hermesEvent: HermesRunEvent(
            type: .observationReconnecting,
            runID: "run_live_stream",
            timestamp: .now,
            message: "Reconnecting to Hermes live updates (attempt 1 of 3)."
        ))

        XCTAssertEqual(task.state, .running)
        XCTAssertEqual(task.runState.observationState, .reconnecting)
        XCTAssertEqual(task.runState.observationMessage, "Reconnecting to Hermes live updates (attempt 1 of 3).")
        XCTAssertEqual(task.statusContextLine, "🟠 Reconnecting to Hermes live updates (attempt 1 of 3).")
        XCTAssertEqual(task.taskEvents.last?.type, .stateChange)
    }

    func testApplyObservationDisconnectedDoesNotConvertRunIntoFailure() {
        var task = Task.liveHermesTask(
            title: "Inspect project",
            input: "Check the repo",
            runID: "run_live_stream"
        )
        task.runState.state = .waitingUser
        task.runState.phaseLabel = "Approval requested"
        task.runState.waitingReason = "Dangerous command"
        task.runState.approvalID = "approval_1"

        task.apply(hermesEvent: HermesRunEvent(
            type: .observationDisconnected,
            runID: "run_live_stream",
            timestamp: .now,
            message: "Live updates paused after repeated reconnect failures."
        ))

        XCTAssertEqual(task.state, .waitingUser)
        XCTAssertEqual(task.runState.observationState, .disconnected)
        XCTAssertEqual(task.runState.observationMessage, "Live updates paused after repeated reconnect failures.")
        XCTAssertEqual(task.runState.approvalID, "approval_1")
        XCTAssertEqual(task.taskEvents.last?.type, .stateChange)
    }
}
