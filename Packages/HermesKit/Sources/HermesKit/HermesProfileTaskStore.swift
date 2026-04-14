import Foundation
import SQLite3

public struct HermesProfileDescriptor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { profileID }
    public let profileID: String
    public let displayName: String
    public let hermesHomePath: String
    public let environmentFilePath: String
    public let environmentFileExists: Bool

    public init(
        profileID: String,
        displayName: String,
        hermesHomePath: String,
        environmentFilePath: String,
        environmentFileExists: Bool
    ) {
        self.profileID = profileID
        self.displayName = displayName
        self.hermesHomePath = hermesHomePath
        self.environmentFilePath = environmentFilePath
        self.environmentFileExists = environmentFileExists
    }
}

public struct HermesAgentDescriptor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { agentID }
    public let agentID: String
    public let displayName: String
    public let roleSummary: String?
    public let runtimeProfileID: String
    public let runtimeProfile: HermesProfileDescriptor

    public init(
        agentID: String,
        displayName: String,
        roleSummary: String? = nil,
        runtimeProfileID: String,
        runtimeProfile: HermesProfileDescriptor
    ) {
        self.agentID = agentID
        self.displayName = displayName
        self.roleSummary = roleSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nonBlankValue
        self.runtimeProfileID = runtimeProfileID
        self.runtimeProfile = runtimeProfile
    }
}

public struct HermesRootSessionTaskSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(profileID):\(rootSessionID)" }
    public let profileID: String
    public let rootSessionID: String
    public let currentSessionID: String
    public let rootSession: HermesSessionDescriptor
    public let currentSession: HermesSessionDescriptor
    public let lineage: [HermesSessionDescriptor]
    public let initialUserMessage: String?
    public let latestConversationMessage: String?
    public let lastActivityAt: Date?

    public init(
        profileID: String,
        rootSessionID: String,
        currentSessionID: String,
        rootSession: HermesSessionDescriptor,
        currentSession: HermesSessionDescriptor,
        lineage: [HermesSessionDescriptor],
        initialUserMessage: String? = nil,
        latestConversationMessage: String? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.profileID = profileID
        self.rootSessionID = rootSessionID
        self.currentSessionID = currentSessionID
        self.rootSession = rootSession
        self.currentSession = currentSession
        self.lineage = lineage
        self.initialUserMessage = initialUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? initialUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        self.latestConversationMessage = latestConversationMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? latestConversationMessage?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        self.lastActivityAt = lastActivityAt
    }

    public var isArchived: Bool { rootSession.endedAt != nil }

    public var hasConversationContent: Bool {
        initialUserMessage != nil || latestConversationMessage != nil
    }

    public var shouldDisplayInWorkspaceTaskList: Bool {
        let normalizedSource = rootSession.source?.lowercased()
        if normalizedSource == "cron" || normalizedSource == "api_server" {
            return false
        }
        return hasConversationContent
    }
}

public enum HermesProfileDiscovery {
    public static func discoverProfiles(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) -> [HermesProfileDescriptor] {
        let profilesDirectory = homeDirectory
            .appending(path: ".hermes", directoryHint: .isDirectory)
            .appending(path: "profiles", directoryHint: .isDirectory)

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let config = HermesLocalServerConfiguration.discover(processEnvironment: ["HERMES_HOME": url.path])
                return HermesProfileDescriptor(
                    profileID: url.lastPathComponent,
                    displayName: url.lastPathComponent,
                    hermesHomePath: url.path,
                    environmentFilePath: config.environmentFilePath,
                    environmentFileExists: config.environmentFileExists
                )
            }
    }
}

public enum HermesAgentDiscovery {
    public static func discoverAgents(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) -> [HermesAgentDescriptor] {
        HermesProfileDiscovery.discoverProfiles(homeDirectory: homeDirectory).map(makeAgentDescriptor)
    }

    static func makeAgentDescriptor(profile: HermesProfileDescriptor) -> HermesAgentDescriptor {
        let rootURL = URL(fileURLWithPath: profile.hermesHomePath, isDirectory: true)
        let soulMarkdown = try? String(contentsOf: rootURL.appending(path: "SOUL.md"), encoding: .utf8)
        let configYAML = try? String(contentsOf: rootURL.appending(path: "config.yaml"), encoding: .utf8)
        let displayName = extractDisplayName(from: soulMarkdown) ?? profile.displayName
        let roleSummary = extractRoleSummary(from: soulMarkdown, configYAML: configYAML)

        return HermesAgentDescriptor(
            agentID: profile.profileID,
            displayName: displayName,
            roleSummary: roleSummary,
            runtimeProfileID: profile.profileID,
            runtimeProfile: profile
        )
    }

    static func extractDisplayName(from soulMarkdown: String?) -> String? {
        guard let firstLine = soulMarkdown?
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.isEmpty == false }) else {
            return nil
        }

        if let quoted = firstCapture(in: firstLine, pattern: "「([^」]+)」") {
            return quoted.nonBlankValue
        }

        if firstLine.hasPrefix("You are ") {
            return segment(from: String(firstLine.dropFirst("You are ".count)))
        }

        if firstLine.hasPrefix("你是") {
            return segment(from: String(firstLine.dropFirst("你是".count)))
        }

        return nil
    }

    static func extractRoleSummary(from soulMarkdown: String?, configYAML: String?) -> String? {
        if let systemPrompt = extractSystemPrompt(from: configYAML) {
            return systemPrompt.workspaceSummary(maxLength: 88)
        }

        guard let firstLine = soulMarkdown?
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.isEmpty == false }) else {
            return nil
        }

        return firstLine.workspaceSummary(maxLength: 88)
    }

    private static func extractSystemPrompt(from configYAML: String?) -> String? {
        guard let configYAML, let prompt = firstCapture(
            in: configYAML,
            pattern: #"(?m)^\s*system_prompt:\s*(.+)$"#
        ) else {
            return nil
        }

        return prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .nonBlankValue
    }

    private static func segment(from rawValue: String) -> String? {
        let separators = ["，", ",", "。", ".", "：", ":"]
        let boundary = separators
            .compactMap { rawValue.range(of: $0)?.lowerBound }
            .min() ?? rawValue.endIndex
        let candidate = rawValue[..<boundary]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return candidate.nonBlankValue
    }

    private static func firstCapture(in value: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let fullRange = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, range: fullRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }
}

public struct HermesProfileTaskStore: Sendable {
    public let profile: HermesProfileDescriptor
    private let transcriptStore: HermesLocalTranscriptStore

    public init(profile: HermesProfileDescriptor) {
        self.profile = profile
        self.transcriptStore = HermesLocalTranscriptStore(
            stateDBPath: URL(fileURLWithPath: profile.hermesHomePath, isDirectory: true)
                .appending(path: "state.db")
                .path
        )
    }

    public func fetchRootSessionTasks() throws -> [HermesRootSessionTaskSnapshot] {
        try transcriptStore.withReadOnlyDatabase { database in
            let rootSessions = try fetchRootSessionDescriptors(database: database)
            return try rootSessions.map { rootSession in
                let currentSessionID = try transcriptStore.fetchLatestDescendantSessionID(
                    anchorSessionID: rootSession.sessionID,
                    database: database
                ) ?? rootSession.sessionID
                let currentSession = try transcriptStore.fetchSessionDescriptor(
                    sessionID: currentSessionID,
                    database: database
                ) ?? rootSession
                let lineage = try transcriptStore.fetchLineage(to: currentSessionID, database: database)
                return HermesRootSessionTaskSnapshot(
                    profileID: profile.profileID,
                    rootSessionID: rootSession.sessionID,
                    currentSessionID: currentSessionID,
                    rootSession: rootSession,
                    currentSession: currentSession,
                    lineage: lineage,
                    initialUserMessage: try fetchInitialUserMessage(rootSessionID: rootSession.sessionID, database: database),
                    latestConversationMessage: try fetchLatestConversationMessage(sessionIDs: lineage.map(\.sessionID), database: database),
                    lastActivityAt: try fetchLastActivityAt(sessionIDs: lineage.map(\.sessionID), database: database) ?? currentSession.endedAt ?? currentSession.startedAt ?? rootSession.startedAt
                )
            }
            .sorted {
                ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
            }
        }
    }

    private func fetchRootSessionDescriptors(database: OpaquePointer) throws -> [HermesSessionDescriptor] {
        let sql = """
        SELECT id, parent_session_id, title, source, started_at, ended_at
        FROM sessions
        WHERE parent_session_id IS NULL
        ORDER BY started_at DESC, id DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HermesLocalTranscriptStoreError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var results: [HermesSessionDescriptor] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(
                HermesSessionDescriptor(
                    sessionID: text(at: 0, statement: statement),
                    parentSessionID: optionalText(at: 1, statement: statement),
                    title: optionalText(at: 2, statement: statement),
                    source: optionalText(at: 3, statement: statement),
                    startedAt: optionalDate(at: 4, statement: statement),
                    endedAt: optionalDate(at: 5, statement: statement)
                )
            )
        }
        return results
    }

    private func fetchInitialUserMessage(rootSessionID: String, database: OpaquePointer) throws -> String? {
        let sql = """
        SELECT COALESCE(content, '')
        FROM messages
        WHERE session_id = ? AND role = 'user'
        ORDER BY timestamp ASC, id ASC
        LIMIT 1
        """
        return try fetchSingleString(sql: sql, parameter: rootSessionID, database: database)
    }

    private func fetchLatestConversationMessage(sessionIDs: [String], database: OpaquePointer) throws -> String? {
        guard sessionIDs.isEmpty == false else { return nil }
        let placeholders = Array(repeating: "?", count: sessionIDs.count).joined(separator: ",")
        let sql = """
        SELECT COALESCE(content, '')
        FROM messages
        WHERE session_id IN (\(placeholders))
          AND role IN ('user', 'assistant')
          AND TRIM(COALESCE(content, '')) != ''
        ORDER BY timestamp DESC, id DESC
        LIMIT 1
        """
        return try fetchSingleString(sql: sql, parameters: sessionIDs, database: database)
    }

    private func fetchLastActivityAt(sessionIDs: [String], database: OpaquePointer) throws -> Date? {
        guard sessionIDs.isEmpty == false else { return nil }
        let placeholders = Array(repeating: "?", count: sessionIDs.count).joined(separator: ",")
        let sql = """
        SELECT MAX(timestamp)
        FROM messages
        WHERE session_id IN (\(placeholders))
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HermesLocalTranscriptStoreError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, sessionID) in sessionIDs.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), sessionID, -1, localTransientSQLiteDestructor)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
    }

    private func fetchSingleString(sql: String, parameter: String, database: OpaquePointer) throws -> String? {
        try fetchSingleString(sql: sql, parameters: [parameter], database: database)
    }

    private func fetchSingleString(sql: String, parameters: [String], database: OpaquePointer) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HermesLocalTranscriptStoreError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, parameter) in parameters.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), parameter, -1, localTransientSQLiteDestructor)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return optionalText(at: 0, statement: statement)
    }

    private func text(at index: Int32, statement: OpaquePointer) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: cString)
    }

    private func optionalText(at index: Int32, statement: OpaquePointer) -> String? {
        let value = text(at: index, statement: statement)
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func optionalDate(at index: Int32, statement: OpaquePointer) -> Date? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }
}

private let localTransientSQLiteDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    func workspaceSummary(maxLength: Int) -> String {
        let collapsed = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > maxLength else {
            return collapsed
        }

        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var nonBlankValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
