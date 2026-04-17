import Foundation

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
