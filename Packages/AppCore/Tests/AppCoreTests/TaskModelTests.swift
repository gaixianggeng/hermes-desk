import Foundation
import XCTest
@testable import AppCore

final class TaskModelTests: XCTestCase {
    func testSortedForOverviewPrioritizesPendingWork() {
        let now = Date()
        let tasks = [
            makeTask(id: "recent", state: .succeeded, updatedAt: now.addingTimeInterval(-300)),
            makeTask(id: "running", state: .running, updatedAt: now.addingTimeInterval(-60)),
            makeTask(id: "failed", state: .failed, updatedAt: now.addingTimeInterval(-120)),
            makeTask(id: "waiting", state: .waitingUser, updatedAt: now)
        ]

        let sortedIDs = tasks.sortedForOverview().map(\.taskID)

        XCTAssertEqual(sortedIDs, ["waiting", "failed", "running", "recent"])
    }

    func testTaskStateTerminalFlagMatchesProtocolExpectations() {
        XCTAssertTrue(TaskState.succeeded.isTerminal)
        XCTAssertTrue(TaskState.failed.isTerminal)
        XCTAssertTrue(TaskState.cancelled.isTerminal)
        XCTAssertFalse(TaskState.running.isTerminal)
        XCTAssertFalse(TaskState.waitingUser.isTerminal)
    }

    func testSortedForOverviewKeepsQueuedWorkAheadOfResultsAndCancelledLast() {
        let now = Date()
        let tasks = [
            makeTask(id: "cancelled", state: .cancelled, updatedAt: now.addingTimeInterval(-30)),
            makeTask(id: "succeeded", state: .succeeded, updatedAt: now.addingTimeInterval(-60)),
            makeTask(id: "paused", state: .paused, updatedAt: now.addingTimeInterval(-90)),
            makeTask(id: "queued", state: .queued, updatedAt: now)
        ]

        let sortedIDs = tasks.sortedForOverview().map(\.taskID)

        XCTAssertEqual(sortedIDs, ["queued", "paused", "succeeded", "cancelled"])
    }

    func testSortedForOverviewPrioritizesLiveTasksAheadOfPreviewSamplesWithinSameState() {
        let now = Date()
        let tasks = [
            makeTask(id: "preview-running", state: .running, updatedAt: now, isPreview: true),
            makeTask(id: "live-running", state: .running, updatedAt: now.addingTimeInterval(-60), isPreview: false)
        ]

        let sortedIDs = tasks.sortedForOverview().map(\.taskID)

        XCTAssertEqual(sortedIDs, ["live-running", "preview-running"])
    }

    private func makeTask(id: String, state: TaskState, updatedAt: Date, isPreview: Bool = false) -> Task {
        Task(
            taskID: id,
            title: id,
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            currentSummary: "summary",
            runState: RunState(
                state: state,
                phaseLabel: "phase",
                lastEventAt: updatedAt
            ),
            isPreview: isPreview
        )
    }
}
