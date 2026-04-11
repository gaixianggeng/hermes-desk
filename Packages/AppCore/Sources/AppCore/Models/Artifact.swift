import Foundation

public struct FileReference: Codable, Equatable, Sendable, Identifiable {
    public var path: String

    public init(path: String) {
        self.path = path
    }

    public var id: String { path }
}

public struct Artifact: Codable, Equatable, Sendable {
    public var summary: String
    public var keyOutputs: [String]
    public var files: [FileReference]
    public var diffSummary: String?
    public var nextActions: [String]
    public var rawResultReference: String?

    public init(
        summary: String,
        keyOutputs: [String] = [],
        files: [FileReference] = [],
        diffSummary: String? = nil,
        nextActions: [String] = [],
        rawResultReference: String? = nil
    ) {
        self.summary = summary
        self.keyOutputs = keyOutputs
        self.files = files
        self.diffSummary = diffSummary
        self.nextActions = nextActions
        self.rawResultReference = rawResultReference
    }
}
