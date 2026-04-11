import Foundation

public struct AgentCapability: Codable, Equatable, Sendable {
    public var canStop: Bool
    public var canRetry: Bool
    public var canPause: Bool
    public var canResume: Bool
    public var canRequestApproval: Bool
    public var canEmitResult: Bool
    public var canOpenWorkspace: Bool

    public init(
        canStop: Bool = true,
        canRetry: Bool = true,
        canPause: Bool = false,
        canResume: Bool = false,
        canRequestApproval: Bool = true,
        canEmitResult: Bool = true,
        canOpenWorkspace: Bool = true
    ) {
        self.canStop = canStop
        self.canRetry = canRetry
        self.canPause = canPause
        self.canResume = canResume
        self.canRequestApproval = canRequestApproval
        self.canEmitResult = canEmitResult
        self.canOpenWorkspace = canOpenWorkspace
    }
}
