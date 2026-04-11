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
}
