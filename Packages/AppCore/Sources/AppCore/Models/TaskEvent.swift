import Foundation

public enum EventType: String, Codable, Sendable, CaseIterable {
    case stateChange = "state_change"
    case output
    case step
    case confirm
    case error
    case result
    case log
    case clarify
}

public struct TaskEvent: Codable, Equatable, Sendable, Identifiable {
    public var eventID: String
    public var taskID: String
    public var sessionID: String?
    public var runID: String?
    public var type: EventType
    public var seq: Int
    public var timestamp: Date
    public var summary: String
    public var detail: String?
    public var capabilitySnapshot: AgentCapability

    public init(
        eventID: String,
        taskID: String,
        sessionID: String? = nil,
        runID: String? = nil,
        type: EventType,
        seq: Int,
        timestamp: Date,
        summary: String,
        detail: String? = nil,
        capabilitySnapshot: AgentCapability = AgentCapability()
    ) {
        self.eventID = eventID
        self.taskID = taskID
        self.sessionID = sessionID
        self.runID = runID
        self.type = type
        self.seq = seq
        self.timestamp = timestamp
        self.summary = summary
        self.detail = detail
        self.capabilitySnapshot = capabilitySnapshot
    }

    public var id: String { eventID }
}
