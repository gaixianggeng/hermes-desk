import Foundation

public enum ApprovalSeverity: String, Codable, Sendable, CaseIterable {
    case normal
    case high
    case critical
}

public enum ApprovalStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case approved
    case rejected
    case expired
}

public enum EvidenceType: String, Codable, Sendable, CaseIterable {
    case command
    case patch
    case diffSummary = "diff_summary"
    case pathList = "path_list"
    case rawLogExcerpt = "raw_log_excerpt"
}

public struct EvidenceItem: Codable, Equatable, Sendable, Identifiable {
    public var type: EvidenceType
    public var title: String
    public var content: String

    public init(type: EvidenceType, title: String, content: String) {
        self.type = type
        self.title = title
        self.content = content
    }

    public var id: String {
        "\(type.rawValue)-\(title)"
    }
}

public struct ApprovalOption: Codable, Equatable, Sendable, Identifiable {
    public var action: TaskAction
    public var label: String

    public init(action: TaskAction, label: String) {
        self.action = action
        self.label = label
    }

    public var id: String {
        action.rawValue
    }
}

public struct ApprovalRequest: Codable, Equatable, Sendable, Identifiable {
    public var approvalID: String
    public var taskID: String
    public var severity: ApprovalSeverity
    public var title: String
    public var reason: String
    public var evidence: [EvidenceItem]
    public var options: [ApprovalOption]
    public var timeoutAt: Date?
    public var status: ApprovalStatus
    public var decidedAt: Date?

    public init(
        approvalID: String,
        taskID: String,
        severity: ApprovalSeverity,
        title: String,
        reason: String,
        evidence: [EvidenceItem] = [],
        options: [ApprovalOption] = [],
        timeoutAt: Date? = nil,
        status: ApprovalStatus = .pending,
        decidedAt: Date? = nil
    ) {
        self.approvalID = approvalID
        self.taskID = taskID
        self.severity = severity
        self.title = title
        self.reason = reason
        self.evidence = evidence
        self.options = options
        self.timeoutAt = timeoutAt
        self.status = status
        self.decidedAt = decidedAt
    }

    public var id: String { approvalID }
}
